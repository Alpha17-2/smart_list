import 'dart:async';

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
/// `SmartListController` extends [ValueNotifier] so widgets can listen for
/// state changes via the standard Flutter mechanisms
/// ([ValueListenableBuilder], `context.watch`, etc.) without pulling in any
/// third-party state-management library. The contained [SmartListState] is
/// always immutable; mutations replace the value rather than mutating it.
///
/// Cache is a fetch snapshot, not a live store: local mutations invalidate
/// the current query+filters scope so a later cache read cannot resurrect
/// stale pages.
class SmartListController<T> extends ValueNotifier<SmartListState<T>> {
  final SmartListFetcher<T> _fetcher;
  final PaginationStrategyBuilder<T> _strategyBuilder;
  final SmartListCacheStore<T>? _cache;
  final RetryPolicy _retryPolicy;
  final Debouncer _searchDebouncer;
  final UniqueKeyExtractor<T>? _uniqueKey;
  final bool _useCache;

  /// Isolates cache entries when multiple controllers share a store.
  final Object listId;

  late SmartListPaginationStrategy<T> _normalStrategy;
  SmartListPaginationStrategy<T>? _searchStrategy;

  List<T>? _preSearchItems;
  bool? _preSearchHasReachedEnd;
  Map<String, Object?>? _preSearchFilters;

  SmartListPage<T>? _lastNormalPage;
  SmartListPage<T>? _lastSearchPage;

  final RequestToken _requestToken = RequestToken();
  SmartListCancelToken? _fetchCancel;

  bool _bypassCacheReadOnce = false;
  SmartListPageRequest? _failedRequest;
  bool _disposed = false;

  SmartListController({
    required SmartListFetcher<T> fetcher,
    required PaginationStrategyBuilder<T> strategyBuilder,
    SmartListCacheStore<T>? cache,
    RetryPolicy? retryPolicy,
    Duration searchDebounce = const Duration(milliseconds: 300),
    UniqueKeyExtractor<T>? uniqueKey,
    bool enableCache = true,
    Object? listId,
  })  : _fetcher = fetcher,
        _strategyBuilder = strategyBuilder,
        _cache = enableCache ? (cache ?? MemoryCacheStore<T>()) : null,
        _retryPolicy = retryPolicy ?? RetryPolicy(),
        _searchDebouncer = Debouncer(delay: searchDebounce),
        _uniqueKey = uniqueKey,
        _useCache = enableCache,
        listId = listId ?? Object(),
        super(SmartListState<T>.initial()) {
    _normalStrategy = _strategyBuilder();
  }

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
      enableCache: enableCache,
      listId: listId,
    );
  }

  Future<void> loadInitial({bool force = false}) async {
    if (_disposed) return;
    if (!force && value.items.isNotEmpty) return;
    await _startFetchSequence(reason: _FetchReason.initial);
  }

  Future<void> loadNextPage() async {
    if (_disposed) return;
    final s = value;
    if (s.isBusy) return;
    if (s.hasReachedEnd) return;
    if (s.phase == SmartListPhase.initial) {
      return loadInitial();
    }
    await _fetchNext();
  }

  Future<void> refresh({bool bypassCache = true}) async {
    if (_disposed) return;
    _bypassCacheReadOnce = bypassCache;
    await _startFetchSequence(reason: _FetchReason.refresh);
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

    if (filtersChangedDuringSearch) {
      _preSearchItems = null;
      _preSearchHasReachedEnd = null;
      _preSearchFilters = null;
      _emit(
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

    _emit(
      value.copyWith(
        items: List<T>.unmodifiable(restoredItems),
        phase: SmartListPhase.success,
        hasReachedEnd: restoredEnd,
        clearError: true,
        clearStackTrace: true,
        clearQuery: true,
      ),
    );
  }

  Future<void> applyFilters(Map<String, Object?> filters) async {
    if (_disposed) return;
    if (mapEquals(filters, value.filters)) return;
    _emit(value.copyWith(filters: Map.unmodifiable(filters)));
    await _startFetchSequence(reason: _FetchReason.filtersChanged);
  }

  void insertAtTop(T item) {
    if (_disposed) return;
    final next = _insertDeduped(item, 0);
    _invalidateMutationCache();
    _emit(value.copyWith(items: List<T>.unmodifiable(next)));
  }

  void insertAtIndex(int index, T item) {
    if (_disposed) return;
    final next = List<T>.of(value.items);
    if (_uniqueKey != null) {
      final extract = _uniqueKey!;
      final key = extract(item);
      next.removeWhere((e) => extract(e) == key);
    }
    final i = index.clamp(0, next.length);
    next.insert(i, item);
    _invalidateMutationCache();
    _emit(value.copyWith(items: List<T>.unmodifiable(next)));
  }

  void removeWhere(bool Function(T item) test) {
    if (_disposed) return;
    final next = List<T>.of(value.items)..removeWhere(test);
    _invalidateMutationCache();
    _emit(value.copyWith(items: List<T>.unmodifiable(next)));
  }

  void updateWhere(bool Function(T item) test, T Function(T item) update) {
    if (_disposed) return;
    final next = <T>[
      for (final item in value.items) test(item) ? update(item) : item,
    ];
    _invalidateMutationCache();
    _emit(value.copyWith(items: List<T>.unmodifiable(next)));
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
    _failedRequest = null;
    _emit(SmartListState<T>.initial());
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
    _emit(
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

  Future<void> _startFetchSequence({required _FetchReason reason}) async {
    if (_disposed) return;
    _failedRequest = null;

    final keepItems = reason == _FetchReason.refresh && value.items.isNotEmpty;
    final phase =
        keepItems ? SmartListPhase.refreshing : SmartListPhase.loading;

    if (reason == _FetchReason.refresh && _bypassCacheReadOnce) {
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

    _emit(
      value.copyWith(
        items: keepItems ? value.items : const [],
        phase: phase,
        hasReachedEnd: false,
        clearError: true,
        clearStackTrace: true,
        retryAttempt: 0,
      ),
    );
    await _fetchNext();
  }

  Future<void> _fetchNext() async {
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
      _emit(
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
      _emit(value.copyWith(phase: SmartListPhase.loadingMore));
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

    final shouldReadCache = _useCache && !_bypassCacheReadOnce;
    _bypassCacheReadOnce = false;
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
          if (_requestToken.isCurrent(token)) {
            _emit(value.copyWith(retryAttempt: attempt));
          }
        },
      );

      if (_disposed) return;
      cancel.throwIfCancelled();
      if (!_requestToken.isCurrent(token)) return;

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
      _emit(
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

    final merged = replace
        ? _mergeItems(const [], page.items)
        : _mergeItems(value.items, page.items);

    _emit(
      value.copyWith(
        items: List<T>.unmodifiable(merged),
        phase: SmartListPhase.success,
        hasReachedEnd: reachedEnd,
        clearError: true,
        clearStackTrace: true,
        retryAttempt: 0,
      ),
    );
  }

  List<T> _insertDeduped(T item, int index) {
    final next = List<T>.of(value.items);
    if (_uniqueKey != null) {
      final extract = _uniqueKey!;
      final key = extract(item);
      next.removeWhere((e) => extract(e) == key);
    }
    final i = index.clamp(0, next.length);
    next.insert(i, item);
    return next;
  }

  List<T> _mergeItems(List<T> existing, List<T> incoming) {
    final extract = _uniqueKey;
    if (extract == null) {
      return <T>[...existing, ...incoming];
    }
    final seen = <Object>{for (final item in existing) extract(item)};
    final out = <T>[...existing];
    for (final item in incoming) {
      final key = extract(item);
      if (seen.add(key)) out.add(item);
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

  void _emit(SmartListState<T> next) {
    if (_disposed) return;
    value = next;
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
