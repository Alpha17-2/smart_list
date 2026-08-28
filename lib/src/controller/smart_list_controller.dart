import 'dart:async';
import 'dart:collection' show UnmodifiableListView;

import 'package:flutter/foundation.dart';

import '../cache/cache_key.dart';
import '../cache/cache_store.dart';
import '../cache/memory_cache_store.dart';
import '../core/cancel_token.dart';
import '../core/smart_list_exception.dart';
import '../core/smart_list_phase.dart';
import '../core/smart_list_state.dart';
import '../core/typedefs.dart';
import '../pagination/page_pagination_strategy.dart';
import '../pagination/pagination_request.dart';
import '../pagination/pagination_response.dart';
import '../pagination/pagination_strategy.dart';
import '../utils/debouncer.dart';
import '../utils/request_token.dart';
import '../utils/retry_policy.dart';

/// Factory that builds a fresh pagination strategy. The controller uses
/// this to create independent strategy instances for normal browsing vs.
/// active searches.
typedef PaginationStrategyBuilder<T> = SmartListPaginationStrategy<T>
    Function();

/// Central orchestrator for a paginated, searchable, cached list.
///
/// `SmartListController` is a [ChangeNotifier] that implements
/// [ValueListenable] of [SmartListState], so widgets can subscribe via
/// `ValueListenableBuilder(valueListenable: controller, ...)` exactly as
/// before. The state is exposed read-only through [value] (or the alias
/// [state]) — there is no public setter, so external code cannot corrupt
/// the controller's internal bookkeeping by writing to `controller.value`.
///
/// Cache is a fetch snapshot, not a live store: local mutations invalidate
/// the current query+filters scope so a later cache read cannot resurrect
/// stale pages.
///
/// Concerns are split into pluggable collaborators:
///
/// * [SmartListPaginationStrategy] decides the next request shape.
/// * [SmartListCacheStore] persists / retrieves page responses.
/// * [RetryPolicy] decides when to retry transient failures.
/// * [Debouncer] coalesces rapid search input.
/// * [RequestToken] guards against stale (race-condition) responses.
class SmartListController<T> extends ChangeNotifier
    implements ValueListenable<SmartListState<T>> {
  final SmartListFetcher<T> _fetcher;
  final PaginationStrategyBuilder<T> _strategyBuilder;
  final SmartListCacheStore<T>? _cache;
  final RetryPolicy _retryPolicy;
  final Debouncer _searchDebouncer;
  final UniqueKeyExtractor<T>? _uniqueKey;
  final bool _useCache;

  /// Isolates cache entries when multiple controllers share a store.
  final Object listId;

  SmartListState<T> _state;

  /// The current state snapshot. Implements [ValueListenable] so widgets
  /// can subscribe via `ValueListenableBuilder(valueListenable: controller)`.
  @override
  SmartListState<T> get value => _state;

  /// Alias for [value]. Provided for readability when the controller is
  /// used outside a `ValueListenableBuilder`.
  SmartListState<T> get state => _state;

  void _set(SmartListState<T> next) {
    if (identical(_state, next) || _disposed) return;
    _state = next;
    notifyListeners();
  }

  late SmartListPaginationStrategy<T> _normalStrategy;
  SmartListPaginationStrategy<T>? _searchStrategy;

  List<T>? _preSearchItems;
  bool? _preSearchHasReachedEnd;
  Map<String, Object?>? _preSearchFilters;

  SmartListPage<T>? _lastNormalPage;
  SmartListPage<T>? _lastSearchPage;

  /// Persistent dedupe set per phase. Keyed by [_uniqueKey] outputs so that
  /// appending a page costs O(M) (new items) instead of O(N + M).
  Set<Object>? _normalSeen;
  Set<Object>? _searchSeen;

  final RequestToken _requestToken = RequestToken();
  SmartListCancelToken? _fetchCancel;

  /// Serializes pagination so two `loadNextPage()` calls that slip past the
  /// `isBusy` snapshot cannot both append a page.
  Future<void>? _paginationLock;

  SmartListPageRequest? _failedRequest;
  bool _disposed = false;

  /// Build a controller from explicit collaborators.
  ///
  /// Prefer [SmartListController.simple] for the common case.
  /// Pass [cache] to enable caching (`null` means no cache).
  SmartListController({
    required SmartListFetcher<T> fetcher,
    required PaginationStrategyBuilder<T> strategyBuilder,
    SmartListCacheStore<T>? cache,
    RetryPolicy? retryPolicy,
    Duration searchDebounce = const Duration(milliseconds: 300),
    UniqueKeyExtractor<T>? uniqueKey,
    Object? listId,
  })  : _fetcher = fetcher,
        _strategyBuilder = strategyBuilder,
        _cache = cache,
        _retryPolicy = retryPolicy ?? RetryPolicy(),
        _searchDebouncer = Debouncer(delay: searchDebounce),
        _uniqueKey = uniqueKey,
        _useCache = cache != null,
        listId = listId ?? Object(),
        _state = SmartListState<T>.initial() {
    _normalStrategy = _strategyBuilder();
  }

  /// Defaults to page-based pagination of [pageSize], a 5-minute in-memory
  /// cache, and the standard retry policy.
  factory SmartListController.simple({
    required SmartListFetcher<T> fetcher,
    int pageSize = 20,
    UniqueKeyExtractor<T>? uniqueKey,
    bool enableCache = true,
    Object? listId,
  }) {
    return SmartListController<T>(
      fetcher: fetcher,
      strategyBuilder: () => PagePaginationStrategy<T>(pageSize: pageSize),
      uniqueKey: uniqueKey,
      cache: enableCache ? MemoryCacheStore<T>() : null,
      listId: listId,
    );
  }

  Future<void> loadInitial({bool force = false}) async {
    if (_disposed) return;
    if (!force && value.items.isNotEmpty) return;
    await _startFetchSequence(reason: _FetchReason.initial);
  }

  /// Fetch the next page. Concurrent callers serialize on an internal lock.
  Future<void> loadNextPage() async {
    if (_disposed) return;

    final inflight = _paginationLock;
    if (inflight != null) {
      await inflight;
      return;
    }

    final s = value;
    if (s.hasReachedEnd) return;
    if (s.phase == SmartListPhase.initial) {
      return loadInitial();
    }
    if (s.isBusy) return;

    final completer = Completer<void>();
    _paginationLock = completer.future;
    try {
      await _fetchNext();
    } finally {
      _paginationLock = null;
      completer.complete();
    }
  }

  /// Pull-to-refresh. By default the cache *read* is bypassed. The fresh
  /// response is still *written* to the cache.
  ///
  /// When a search is active, [refresh] re-fetches the *search results*
  /// only. Call [clearSearch] first to refresh the underlying list.
  Future<void> refresh({bool bypassCache = true}) async {
    if (_disposed) return;
    await _startFetchSequence(
      reason: _FetchReason.refresh,
      bypassCache: bypassCache,
    );
  }

  void search(String query) {
    if (_disposed) return;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clearSearch();
      return;
    }
    _searchDebouncer.run(() => _runSearch(trimmed));
  }

  /// Restore the pre-search snapshot. Mutations during search
  /// ([insertAtTop], [insertAtBottom], [removeWhere], [updateWhere]) are
  /// replayed onto that snapshot.
  ///
  /// If filters changed during search, browse is refetched instead of
  /// restoring a stale snapshot.
  void clearSearch() {
    if (_disposed) return;
    _searchDebouncer.cancel();
    if (!value.isSearchActive && _preSearchItems == null) return;

    _supersedeInFlight();
    _failedRequest = null;

    final filtersChangedDuringSearch = _preSearchFilters != null &&
        !mapEquals(_preSearchFilters, value.filters);

    _searchStrategy = null;
    _lastSearchPage = null;
    _searchSeen = null;

    if (filtersChangedDuringSearch) {
      _preSearchItems = null;
      _preSearchHasReachedEnd = null;
      _preSearchFilters = null;
      _set(
        value.copyWith(
          phase: SmartListPhase.loading,
          items: const [],
          hasReachedEnd: false,
          clearError: true,
          clearStackTrace: true,
          clearQuery: true,
          retryAttempt: 0,
        ),
      );
      _startFetchSequence(reason: _FetchReason.filtersChanged);
      return;
    }

    final restoredItems = _preSearchItems ?? const [];
    final restoredEnd = _preSearchHasReachedEnd ?? false;
    _preSearchItems = null;
    _preSearchHasReachedEnd = null;
    _preSearchFilters = null;

    _set(
      value.copyWith(
        items: UnmodifiableListView<T>(restoredItems),
        phase: SmartListPhase.success,
        hasReachedEnd: restoredEnd,
        clearError: true,
        clearStackTrace: true,
        clearQuery: true,
      ),
    );
  }

  /// Replace filters and re-fetch from page 1.
  ///
  /// The filter swap is applied as part of the loading transition so
  /// listeners observe one consistent notification.
  Future<void> applyFilters(Map<String, Object?> filters) async {
    if (_disposed) return;
    if (mapEquals(filters, value.filters)) return;
    await _startFetchSequence(
      reason: _FetchReason.filtersChanged,
      filters: Map<String, Object?>.unmodifiable(filters),
    );
  }

  /// Prepend an item. When [uniqueKey] is set, an existing item with the
  /// same key is dropped first. Replayed onto the pre-search snapshot.
  void insertAtTop(T item) {
    if (_disposed) return;
    final next = _insertDeduped(value.items, item, 0);
    _invalidateMutationCache();
    _set(value.copyWith(items: UnmodifiableListView<T>(next)));
    if (_preSearchItems != null) {
      _preSearchItems = _insertDeduped(_preSearchItems!, item, 0);
    }
  }

  /// Append an item. Same uniqueKey / snapshot rules as [insertAtTop].
  void insertAtBottom(T item) {
    if (_disposed) return;
    final next = _insertDeduped(value.items, item, value.items.length);
    _invalidateMutationCache();
    _set(value.copyWith(items: UnmodifiableListView<T>(next)));
    if (_preSearchItems != null) {
      _preSearchItems =
          _insertDeduped(_preSearchItems!, item, _preSearchItems!.length);
    }
  }

  /// Insert at an arbitrary index. Not replayed against the pre-search
  /// snapshot (the index is only meaningful for the visible list).
  void insertAtIndex(int index, T item) {
    if (_disposed) return;
    final next = _insertDeduped(value.items, item, index);
    _invalidateMutationCache();
    _set(value.copyWith(items: UnmodifiableListView<T>(next)));
  }

  void removeWhere(bool Function(T item) test) {
    if (_disposed) return;
    final next = List<T>.of(value.items)..removeWhere(test);
    _invalidateMutationCache();
    _set(value.copyWith(items: UnmodifiableListView<T>(next)));
    if (_preSearchItems != null) {
      _preSearchItems = List<T>.of(_preSearchItems!)..removeWhere(test);
    }
  }

  void updateWhere(bool Function(T item) test, T Function(T item) update) {
    if (_disposed) return;
    final next = <T>[
      for (final item in value.items) test(item) ? update(item) : item,
    ];
    _invalidateMutationCache();
    _set(value.copyWith(items: UnmodifiableListView<T>(next)));
    if (_preSearchItems != null) {
      _preSearchItems = <T>[
        for (final item in _preSearchItems!) test(item) ? update(item) : item,
      ];
    }
  }

  void reset() {
    if (_disposed) return;
    _supersedeInFlight();
    _searchDebouncer.cancel();
    _normalStrategy.reset();
    _searchStrategy = null;
    _preSearchItems = null;
    _preSearchHasReachedEnd = null;
    _preSearchFilters = null;
    _lastNormalPage = null;
    _lastSearchPage = null;
    _normalSeen = null;
    _searchSeen = null;
    _failedRequest = null;
    _set(SmartListState<T>.initial());
  }

  void clearCache() => _cache?.clear();

  Future<void> _runSearch(String query) async {
    if (_disposed) return;
    if (!value.isSearchActive) {
      _preSearchItems = List<T>.of(value.items);
      _preSearchHasReachedEnd = value.hasReachedEnd;
      _preSearchFilters = Map<String, Object?>.of(value.filters);
    }
    _failedRequest = null;
    _searchStrategy = _strategyBuilder();
    _lastSearchPage = null;
    _set(
      value.copyWith(
        query: query,
        phase: SmartListPhase.loading,
        hasReachedEnd: false,
        clearError: true,
        clearStackTrace: true,
        retryAttempt: 0,
      ),
    );
    await _fetchNext();
  }

  Future<void> _startFetchSequence({
    required _FetchReason reason,
    bool bypassCache = false,
    Map<String, Object?>? filters,
  }) async {
    if (_disposed) return;
    _searchDebouncer.cancel();
    _failedRequest = null;

    final keepItems = reason == _FetchReason.refresh && value.items.isNotEmpty;
    final phase =
        keepItems ? SmartListPhase.refreshing : SmartListPhase.loading;

    if (reason == _FetchReason.refresh && bypassCache) {
      _invalidateCurrentScope();
    }

    if (value.isSearchActive) {
      _searchStrategy?.reset();
      _searchStrategy ??= _strategyBuilder();
      _lastSearchPage = null;
    } else {
      _normalStrategy.reset();
      _lastNormalPage = null;
    }

    _set(
      value.copyWith(
        items: keepItems ? value.items : const [],
        phase: phase,
        hasReachedEnd: false,
        filters: filters,
        clearError: true,
        clearStackTrace: true,
        retryAttempt: 0,
      ),
    );
    await _fetchNext(bypassCache: bypassCache);
  }

  Future<void> _fetchNext({bool bypassCache = false}) async {
    if (_disposed) return;
    final isSearch = value.isSearchActive;
    final strategy = isSearch ? _searchStrategy! : _normalStrategy;
    final lastPage = isSearch ? _lastSearchPage : _lastNormalPage;
    final isFirstPage = lastPage == null;

    final SmartListPageRequest? request = _failedRequest ??
        (isFirstPage
            ? strategy.initialRequest(
                query: value.query,
                filters: value.filters,
              )
            : strategy.nextRequest(
                lastPage,
                query: value.query,
                filters: value.filters,
              ));

    if (request == null) {
      _set(
        value.copyWith(
          phase: SmartListPhase.success,
          hasReachedEnd: true,
        ),
      );
      return;
    }

    if (value.items.isNotEmpty &&
        value.phase != SmartListPhase.refreshing &&
        value.phase != SmartListPhase.loading) {
      _set(value.copyWith(phase: SmartListPhase.loadingMore));
    }

    _supersedeInFlight();
    final cancel = SmartListCancelToken();
    _fetchCancel = cancel;
    final token = _requestToken.issue();

    final cacheKey = SmartListCacheKey(
      listId: listId,
      query: request.query,
      filters: request.filters,
      page: request.page,
      cursor: request.cursor,
    );

    final shouldReadCache = _useCache && !bypassCache;
    final cached = shouldReadCache ? _cache?.read(cacheKey) : null;
    if (cached != null) {
      _applyPage(
        cached,
        request: request,
        isSearch: isSearch,
        token: token,
        replace: isFirstPage,
      );
      return;
    }

    try {
      final page = await _retryPolicy.run<SmartListPage<T>>(
        () => _fetcher(request, cancel),
        onRetry: (attempt, _) {
          if (_disposed) return;
          if (cancel.isCancelled) return;
          if (!_requestToken.isCurrent(token)) return;
          _set(value.copyWith(retryAttempt: attempt));
        },
        shouldContinue: () =>
            !_disposed &&
            !cancel.isCancelled &&
            _requestToken.isCurrent(token),
      );

      if (_disposed) return;
      if (cancel.isCancelled || !_requestToken.isCurrent(token)) return;

      if (_useCache) _cache?.write(cacheKey, page);
      _applyPage(
        page,
        request: request,
        isSearch: isSearch,
        token: token,
        replace: isFirstPage,
      );
    } on SmartListCancelledException {
      return;
    } catch (e, st) {
      if (_disposed) return;
      if (!_requestToken.isCurrent(token)) return;
      _failedRequest = request;
      _set(
        value.copyWith(
          phase: SmartListPhase.error,
          error: e,
          stackTrace: st,
        ),
      );
    }
  }

  void _applyPage(
    SmartListPage<T> page, {
    required SmartListPageRequest request,
    required bool isSearch,
    required int token,
    required bool replace,
  }) {
    if (_disposed) return;
    if (!_requestToken.isCurrent(token)) return;

    if (isSearch) {
      _lastSearchPage = page;
    } else {
      _lastNormalPage = page;
    }

    final strategy = isSearch ? _searchStrategy! : _normalStrategy;
    strategy.commit(request, page);
    _failedRequest = null;
    final reachedEnd = strategy.isExhausted(page);

    if (replace) {
      if (isSearch) {
        _searchSeen = _uniqueKey == null ? null : <Object>{};
      } else {
        _normalSeen = _uniqueKey == null ? null : <Object>{};
      }
    }
    final merged = replace
        ? _mergeItems(const [], page.items, isSearch: isSearch)
        : _mergeItems(value.items, page.items, isSearch: isSearch);

    _set(
      value.copyWith(
        items: UnmodifiableListView<T>(merged),
        phase: SmartListPhase.success,
        hasReachedEnd: reachedEnd,
        clearError: true,
        clearStackTrace: true,
        retryAttempt: 0,
      ),
    );
  }

  List<T> _insertDeduped(List<T> source, T item, int index) {
    final next = List<T>.of(source);
    if (_uniqueKey != null) {
      final extract = _uniqueKey!;
      final key = extract(item);
      next.removeWhere((e) => extract(e) == key);
    }
    final i = index.clamp(0, next.length);
    next.insert(i, item);
    return next;
  }

  List<T> _mergeItems(
    List<T> existing,
    List<T> incoming, {
    required bool isSearch,
  }) {
    final extract = _uniqueKey;
    if (extract == null) {
      return <T>[...existing, ...incoming];
    }
    final seen = isSearch ? _searchSeen! : _normalSeen!;
    final out = <T>[...existing];
    for (final item in incoming) {
      if (seen.add(extract(item))) out.add(item);
    }
    return out;
  }

  void _invalidateCurrentScope() {
    _cache?.invalidateScope(
      listId: listId,
      query: value.query,
      filters: value.filters,
    );
  }

  void _invalidateMutationCache() => _invalidateCurrentScope();

  void _supersedeInFlight() {
    _fetchCancel?.cancel();
    _requestToken.issue();
  }

  @override
  void dispose() {
    _disposed = true;
    _supersedeInFlight();
    _failedRequest = null;
    _searchDebouncer.dispose();
    super.dispose();
  }
}

enum _FetchReason { initial, refresh, filtersChanged }
