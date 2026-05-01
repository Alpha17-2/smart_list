import 'dart:async';

import 'package:flutter/foundation.dart';

import '../cache/cache_key.dart';
import '../cache/cache_store.dart';
import '../cache/memory_cache_store.dart';
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
/// Concerns are split into pluggable collaborators:
///
/// * [SmartListPaginationStrategy] decides the next request shape.
/// * [SmartListCacheStore] persists / retrieves page responses.
/// * [RetryPolicy] decides when to retry transient failures.
/// * [Debouncer] coalesces rapid search input.
/// * [RequestToken] guards against stale (race-condition) responses.
///
/// All collaborators are injected and replaceable, so the controller stays
/// free of concrete dependencies on any particular cache, retry, or
/// pagination scheme.
class SmartListController<T> extends ValueNotifier<SmartListState<T>> {
  // ─── Injected collaborators ──────────────────────────────────────────────

  final SmartListFetcher<T> _fetcher;
  final PaginationStrategyBuilder<T> _strategyBuilder;
  final SmartListCacheStore<T>? _cache;
  final RetryPolicy _retryPolicy;
  final Debouncer _searchDebouncer;
  final UniqueKeyExtractor<T>? _uniqueKey;
  final bool _useCache;

  // ─── Internal bookkeeping ────────────────────────────────────────────────

  late SmartListPaginationStrategy<T> _normalStrategy;
  SmartListPaginationStrategy<T>? _searchStrategy;

  /// Items captured when a search begins, restored on `clearSearch`.
  List<T>? _preSearchItems;
  bool? _preSearchHasReachedEnd;

  /// The most recent page response per phase — used for "next request"
  /// computation.
  SmartListPage<T>? _lastNormalPage;
  SmartListPage<T>? _lastSearchPage;

  final RequestToken _requestToken = RequestToken();

  /// One-shot flag — when `true`, the next call to [_fetchNext] skips the
  /// cache *read* (but still writes the fresh response). Set by [refresh] so
  /// pull-to-refresh always reaches the network. Cleared after the fetch
  /// consumes it, so subsequent paginations resume normal cache behaviour.
  bool _bypassCacheReadOnce = false;

  bool _disposed = false;

  // ─── Construction ────────────────────────────────────────────────────────

  /// Build a controller from explicit collaborators.
  ///
  /// Prefer [SmartListController.simple] for the common case.
  SmartListController({
    required SmartListFetcher<T> fetcher,
    required PaginationStrategyBuilder<T> strategyBuilder,
    SmartListCacheStore<T>? cache,
    RetryPolicy? retryPolicy,
    Duration searchDebounce = const Duration(milliseconds: 300),
    UniqueKeyExtractor<T>? uniqueKey,
    bool enableCache = true,
  })  : _fetcher = fetcher,
        _strategyBuilder = strategyBuilder,
        _cache = enableCache ? (cache ?? MemoryCacheStore<T>()) : null,
        _retryPolicy = retryPolicy ?? RetryPolicy(),
        _searchDebouncer = Debouncer(delay: searchDebounce),
        _uniqueKey = uniqueKey,
        _useCache = enableCache,
        super(SmartListState<T>.initial()) {
    _normalStrategy = _strategyBuilder();
  }

  /// Defaults to page-based pagination of [pageSize], a 5-minute in-memory
  /// cache, and the standard retry policy.
  factory SmartListController.simple({
    required SmartListFetcher<T> fetcher,
    int pageSize = 20,
    UniqueKeyExtractor<T>? uniqueKey,
    bool enableCache = true,
  }) {
    return SmartListController<T>(
      fetcher: fetcher,
      strategyBuilder: () => PagePaginationStrategy<T>(pageSize: pageSize),
      uniqueKey: uniqueKey,
      enableCache: enableCache,
    );
  }

  // ─── Public surface ──────────────────────────────────────────────────────

  /// Load the very first page (or no-op if items are already present).
  ///
  /// Pass `force: true` to discard any current state and fetch fresh.
  Future<void> loadInitial({bool force = false}) async {
    if (_disposed) return;
    if (!force && value.items.isNotEmpty) return;
    await _startFetchSequence(reason: _FetchReason.initial);
  }

  /// Fetch the next page. No-op if a fetch is already in flight, the list
  /// has reached its end, or no initial load has happened yet.
  Future<void> loadNextPage() async {
    if (_disposed) return;
    final s = value;
    if (s.isBusy) return;
    if (s.hasReachedEnd) return;
    if (s.phase == SmartListPhase.initial) {
      // Treat this as the initial load.
      return loadInitial();
    }
    await _fetchNext();
  }

  /// Pull-to-refresh — keeps existing items visible while the new first page
  /// is fetched, then atomically replaces.
  ///
  /// By default the cache *read* is bypassed (typical pull-to-refresh
  /// expectation: always go to network). The fresh response is still
  /// *written* to the cache, overwriting any stale entry. Pass
  /// `bypassCache: false` to permit serving the refresh from cache —
  /// useful for cheap "redo" calls where stale data is acceptable.
  Future<void> refresh({bool bypassCache = true}) async {
    if (_disposed) return;
    _bypassCacheReadOnce = bypassCache;
    await _startFetchSequence(reason: _FetchReason.refresh);
  }

  /// Begin a search. Empty/whitespace queries are treated as `clearSearch`.
  /// Calls are debounced — rapid typing produces a single fetch.
  void search(String query) {
    if (_disposed) return;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clearSearch();
      return;
    }
    _searchDebouncer.run(() => _runSearch(trimmed));
  }

  /// Cancel any in-flight search, restore the pre-search items, and resume
  /// normal browsing from where it left off.
  void clearSearch() {
    if (_disposed) return;
    _searchDebouncer.cancel();
    if (!value.isSearchActive && _preSearchItems == null) return;

    // Supersede any in-flight search request.
    _requestToken.issue();

    final restoredItems = _preSearchItems ?? const [];
    final restoredEnd = _preSearchHasReachedEnd ?? false;
    _preSearchItems = null;
    _preSearchHasReachedEnd = null;
    _searchStrategy = null;
    _lastSearchPage = null;

    value = value.copyWith(
      items: List<T>.unmodifiable(restoredItems),
      phase: SmartListPhase.success,
      hasReachedEnd: restoredEnd,
      clearError: true,
      clearStackTrace: true,
      clearQuery: true,
    );
  }

  /// Replace filters and re-fetch from page 1. Pass an empty map to clear.
  Future<void> applyFilters(Map<String, dynamic> filters) async {
    if (_disposed) return;
    if (mapEquals(filters, value.filters)) return;
    value = value.copyWith(filters: Map.unmodifiable(filters));
    await _startFetchSequence(reason: _FetchReason.filtersChanged);
  }

  // ─── Real-time mutations ─────────────────────────────────────────────────

  /// Prepend an item (e.g. a freshly-arrived chat message).
  void insertAtTop(T item) {
    if (_disposed) return;
    value = value.copyWith(
      items: List<T>.unmodifiable(<T>[item, ...value.items]),
    );
  }

  /// Insert at an arbitrary index. Out-of-range indices are clamped.
  void insertAtIndex(int index, T item) {
    if (_disposed) return;
    final next = List<T>.of(value.items);
    final i = index.clamp(0, next.length);
    next.insert(i, item);
    value = value.copyWith(items: List<T>.unmodifiable(next));
  }

  /// Remove all items matching [test].
  void removeWhere(bool Function(T item) test) {
    if (_disposed) return;
    final next = List<T>.of(value.items)..removeWhere(test);
    value = value.copyWith(items: List<T>.unmodifiable(next));
  }

  /// Replace all items matching [test] with the result of [update].
  void updateWhere(bool Function(T item) test, T Function(T item) update) {
    if (_disposed) return;
    final next = <T>[
      for (final item in value.items) test(item) ? update(item) : item,
    ];
    value = value.copyWith(items: List<T>.unmodifiable(next));
  }

  /// Drop all in-memory state and start fresh on the next `loadInitial`.
  void reset() {
    if (_disposed) return;
    _requestToken.issue();
    _searchDebouncer.cancel();
    _normalStrategy.reset();
    _searchStrategy = null;
    _preSearchItems = null;
    _preSearchHasReachedEnd = null;
    _lastNormalPage = null;
    _lastSearchPage = null;
    value = SmartListState<T>.initial();
  }

  /// Drop the entire cache (if any). Does not change the visible state.
  void clearCache() => _cache?.clear();

  // ─── Internal: fetch flow ────────────────────────────────────────────────

  Future<void> _runSearch(String query) async {
    // First-time entry into search mode → snapshot the current list so we
    // can restore on `clearSearch`.
    if (!value.isSearchActive) {
      _preSearchItems = List<T>.of(value.items);
      _preSearchHasReachedEnd = value.hasReachedEnd;
    }
    _searchStrategy = _strategyBuilder();
    _lastSearchPage = null;
    value = value.copyWith(
      query: query,
      items: const [],
      phase: SmartListPhase.loading,
      hasReachedEnd: false,
      clearError: true,
      clearStackTrace: true,
      retryAttempt: 0,
    );
    await _fetchNext();
  }

  Future<void> _startFetchSequence({required _FetchReason reason}) async {
    final keepItems = reason == _FetchReason.refresh && value.items.isNotEmpty;
    final phase =
        keepItems ? SmartListPhase.refreshing : SmartListPhase.loading;

    if (value.isSearchActive) {
      _searchStrategy?.reset();
      _searchStrategy ??= _strategyBuilder();
      _lastSearchPage = null;
    } else {
      _normalStrategy.reset();
      _lastNormalPage = null;
    }

    value = value.copyWith(
      items: keepItems ? value.items : const [],
      phase: phase,
      hasReachedEnd: false,
      clearError: true,
      clearStackTrace: true,
      retryAttempt: 0,
    );
    await _fetchNext();
  }

  Future<void> _fetchNext() async {
    final isSearch = value.isSearchActive;
    final strategy = isSearch ? _searchStrategy! : _normalStrategy;
    final lastPage = isSearch ? _lastSearchPage : _lastNormalPage;
    final isFirstPage = lastPage == null;

    final SmartListPageRequest? request = isFirstPage
        ? strategy.initialRequest(query: value.query, filters: value.filters)
        : strategy.nextRequest(
            lastPage,
            query: value.query,
            filters: value.filters,
          );

    if (request == null) {
      // No more pages.
      value = value.copyWith(
        phase: SmartListPhase.success,
        hasReachedEnd: true,
      );
      return;
    }

    // Mark loadingMore phase if we already have items and this is not a
    // refresh (refresh preserves the refreshing phase).
    if (value.items.isNotEmpty &&
        value.phase != SmartListPhase.refreshing &&
        value.phase != SmartListPhase.loading) {
      value = value.copyWith(phase: SmartListPhase.loadingMore);
    }

    final token = _requestToken.issue();

    final cacheKey = SmartListCacheKey(
      query: request.query,
      filters: request.filters,
      page: request.page,
      cursor: request.cursor,
    );

    // Cache hit fast-path. `_bypassCacheReadOnce` is consumed here so the
    // bypass only applies to this single fetch; subsequent paginations
    // resume using the cache normally.
    final shouldReadCache = _useCache && !_bypassCacheReadOnce;
    _bypassCacheReadOnce = false;
    final cached = shouldReadCache ? _cache?.read(cacheKey) : null;
    if (cached != null) {
      _applyPage(
        cached,
        isSearch: isSearch,
        token: token,
        replace: isFirstPage,
      );
      return;
    }

    try {
      final page = await _retryPolicy.run<SmartListPage<T>>(
        () => _fetcher(request),
        onRetry: (attempt, _) {
          if (_requestToken.isCurrent(token)) {
            value = value.copyWith(retryAttempt: attempt);
          }
        },
      );

      if (!_requestToken.isCurrent(token)) {
        // Superseded by a newer request; discard silently.
        return;
      }

      if (_useCache) _cache?.write(cacheKey, page);
      _applyPage(
        page,
        isSearch: isSearch,
        token: token,
        replace: isFirstPage,
      );
    } catch (e, st) {
      if (e is SmartListCancelledException) return;
      if (!_requestToken.isCurrent(token)) return;
      value = value.copyWith(
        phase: SmartListPhase.error,
        error: e,
        stackTrace: st,
      );
    }
  }

  void _applyPage(
    SmartListPage<T> page, {
    required bool isSearch,
    required int token,
    required bool replace,
  }) {
    if (!_requestToken.isCurrent(token)) return;

    if (isSearch) {
      _lastSearchPage = page;
    } else {
      _lastNormalPage = page;
    }

    final strategy = isSearch ? _searchStrategy! : _normalStrategy;
    final reachedEnd = strategy.isExhausted(page);

    // First page of a fresh sequence (initial / refresh / new search) atomically
    // replaces the visible list. Subsequent pages append (with dedupe).
    final merged = replace
        ? _mergeItems(const [], page.items)
        : _mergeItems(value.items, page.items);

    value = value.copyWith(
      items: List<T>.unmodifiable(merged),
      phase: SmartListPhase.success,
      hasReachedEnd: reachedEnd,
      clearError: true,
      clearStackTrace: true,
      retryAttempt: 0,
    );
  }

  /// Merge new page items into existing items, deduplicating by [_uniqueKey]
  /// when configured. Preserves order: existing first, new appended.
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

  // ─── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    _searchDebouncer.dispose();
    super.dispose();
  }
}

enum _FetchReason { initial, refresh, filtersChanged }
