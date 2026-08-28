# Changelog

All notable changes to this package are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.0.0 — 2026-08-29

First stable API. Core still depends only on Flutter.

### Breaking
- `SmartListFetcher` now receives `SmartListCancelToken` as the second argument.
- Filters are `Map<String, Object?>` (`SmartListFilters`).
- Default `RetryPolicy` retries only transient errors (timeouts / typical I/O type names), not every `Exception`. Use `RetryPolicy.aggressive()` for the old behaviour.
- `SmartListCacheKey` includes optional `listId`; `invalidateScope` accepts `listId`.

### Added
- `SmartListCancelToken` — cooperative cancel on refresh/search/dispose.
- `SmartListSliver` for `CustomScrollView`.
- `listId` on `SmartListController` for shared cache stores.
- Load-more fires on threshold **crossing**, not every scroll notification.
- `uniqueKey` applies to inserts; mutations invalidate the current cache scope.
- Search keeps previous items visible while a search fetch is in flight (`isSearchLoading`).
- Example `JsonFileCacheStore` (not a core dependency).

### Changed
- Cache is documented as a fetch snapshot, not a live store.

## 0.0.2 — 2026-08-28

### Fixed
- Pagination strategies now **peek** the next request and **commit** only after
  a successful apply, so a failed "load more" retries the same page instead of
  skipping it. The controller also reuses `_failedRequest` for custom
  strategies that still mutate in `nextRequest`.
- Bypass `refresh()` invalidates the current query+filters cache scope so later
  pages cannot mix with a freshly fetched page 1. Added
  `SmartListCacheStore.invalidateScope`.
- Disposing the controller during an in-flight fetch no longer notifies a
  disposed `ValueNotifier`.
- Cursor paging treats `hasMore: true` with a null `nextCursor` as end-of-list
  (avoids re-requesting page 1 forever).
- `clearSearch()` after `applyFilters()` during a search refetches the browse
  list instead of restoring a stale snapshot.
- Empty / error / loading states are wrapped in a scrollable so pull-to-refresh
  works when `enableRefresh` is true.

### Added
- `SmartListPaginationStrategy.commit` (default no-op; built-ins implement it).
- `SmartListCacheStore.invalidateScope`.

## 0.0.1 — 2026-05-02

Initial release. A unified, production-ready abstraction for paginated,
searchable, cached lists in Flutter.

### Added

#### Controller & state
- `SmartListController<T>` extending `ValueNotifier<SmartListState<T>>` —
  drop-in compatible with `setState`, Provider, Riverpod, GetX, and BLoC
  with no adapter.
- Immutable `SmartListState<T>` with derived booleans
  (`isInitialLoading`, `isLoadingMore`, `isRefreshing`, `hasError`,
  `isEmpty`, `isSearchActive`, `isSearchEmpty`, `hasReachedEnd`).
- `SmartListPhase` enum: `initial` / `loading` / `loadingMore` /
  `refreshing` / `success` / `error`.
- Public API: `loadInitial({force})`, `loadNextPage()`,
  `refresh({bypassCache})`, `search(query)`, `clearSearch()`,
  `applyFilters(filters)`, `insertAtTop`, `insertAtIndex`,
  `removeWhere`, `updateWhere`, `reset()`, `clearCache()`.
- Race-condition guard via `RequestToken` — superseded responses are
  silently discarded; old slow responses can never overwrite newer state.
- Pre-search snapshot / restore: `clearSearch()` returns the user to
  exactly where they were before searching.

#### Pagination (strategy pattern)
- `SmartListPaginationStrategy<T>` interface.
- `PagePaginationStrategy<T>` — `?page=N&size=M` (default in `.simple`).
- `CursorPaginationStrategy<T>` — opaque-cursor APIs.
- `OffsetPaginationStrategy<T>` — `?offset=N&limit=M`.
- End-of-list inference: explicit `hasMore` → strategy-specific signal
  (null cursor / short page / empty page).

#### Cache
- `SmartListCacheStore<T>` abstract interface (in-memory today; pluggable
  for disk / network caches).
- `MemoryCacheStore<T>` with TTL expiry, optional LRU eviction
  (`maxEntries`), and an injectable clock for deterministic testing.
- Composite `SmartListCacheKey` keyed on query + filters + page + cursor.
- `refresh()` bypasses the cache *read* by default while still *writing*
  the fresh response — opt out with `refresh(bypassCache: false)`.

#### Resilience utilities
- `Debouncer` — coalesces rapid search keystrokes into a single fetch.
- `RetryPolicy` — exponential backoff with jitter, configurable
  `maxAttempts` and `shouldRetry` predicate; `RetryPolicy.none()` factory.
- `RequestToken` — monotonically increasing token for race-condition guards.

#### Widget layer
- `SmartListView<T>` composing `ListView.separated`, `RefreshIndicator`,
  and `NotificationListener` — auto-pagination via `loadMoreThreshold`.
- Builder slots: `itemBuilder`, `separatorBuilder`, `loadingBuilder`,
  `loadingMoreBuilder`, `emptyBuilder`, `searchEmptyBuilder`,
  `errorBuilder`, `footerBuilder` (generic `SmartListFooterBuilder<T>` —
  preserves item-type safety).
- `DefaultSmartListStates` — sensible Material 3 defaults for every state.
- `mounted` + controller-identity guards on the post-frame initial-load
  callback; controller swaps handled via `didUpdateWidget`.

#### Real-time updates & deduplication
- `insertAtTop` / `insertAtIndex` for prepend / arbitrary insert.
- `updateWhere` / `removeWhere` for bulk mutations.
- Optional `uniqueKey` extractor — collapses duplicates across pages.

#### Filters
- `applyFilters(Map<String, dynamic>)` — re-fetches from page 1; no-op when
  filters are unchanged. Filters are propagated to the fetcher via
  `SmartListPageRequest.filters`.

#### Documentation & examples
- Comprehensive Dart-doc comments on every public symbol.
- `README.md` with quickstart, customisation guide, pagination styles,
  state-management interop examples, and full API reference.
- `LLD.md` — low-level design document covering architecture, sequence
  diagrams, edge-case handling, and extension points.
- `example/` app demonstrating pagination, debounced search,
  pull-to-refresh, simulated transient failures with auto-retry, and a
  custom empty-state builder.

#### Testing
- 56 tests covering controller flow, pagination strategies, cache
  semantics, debouncer, retry policy, request token, state derivations,
  and widget UI states.
