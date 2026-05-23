# Changelog

All notable changes to this package are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 — 2026-05-24

### Breaking changes

- **`SmartListController` no longer extends `ValueNotifier`.** It now
  extends `ChangeNotifier` and implements
  `ValueListenable<SmartListState<T>>`. Reads via `controller.value`
  (or the new alias `controller.state`) still work; subscribing via
  `ValueListenableBuilder(valueListenable: controller, ...)` still
  works. The breaking part: `controller.value = X` no longer compiles
  — external code can no longer corrupt internal bookkeeping by
  writing the state directly. Use the mutation APIs (`insertAtTop`,
  `applyFilters`, `refresh`, `reset`, etc.) instead.

- **`SmartListController(...)` no longer accepts `enableCache:`.**
  The full constructor now takes a single `cache:` parameter:
  - `cache: null` (or omitted) → no cache.
  - `cache: someStore` → use that store.

  Anyone previously using `enableCache: false` should drop the line;
  anyone relying on the implicit default cache should add
  `cache: MemoryCacheStore<T>()` explicitly. The convenience factory
  `SmartListController.simple` still accepts `enableCache: true` for
  the common case.

### Fixed

A full sweep of correctness, concurrency, ergonomics, and
documentation issues identified during code review. Highlights:

- hashCode/equals contract for `SmartListState` and `SmartListCacheKey`
  (no more silent cache misses).
- `RetryPolicy.run` honours cancellation and is safe across dispose.
- `_bypassCacheReadOnce` race fixed by threading bypass per-call.
- `SmartListView` separator off-by-one corrected.
- Pending debounced searches are cancelled on `refresh` /
  `loadInitial(force)` / `applyFilters`.
- `applyFilters` emits a single coherent state transition instead of
  flashing an intermediate snapshot.
- Concurrent `loadNextPage` calls are now serialized; the same page
  cannot be appended twice.
- Scroll handler skips notifications fired before the list has any
  scrollable extent.
- `_mergeItems` runs in O(M) (persisted seen-set per phase).
- New `loadMoreErrorBuilder` slot — inline pagination errors are no
  longer rendered with the full-screen error widget.
- Pull-to-refresh works on every placeholder state (loading / error
  / empty) via a viewport-tall scrollable wrapper.
- `Debouncer(Duration.zero)` now schedules asynchronously so callers
  can invoke `run` from inside a build pass safely.
- `clearSearch` preserves `insertAtTop` / `removeWhere` /
  `updateWhere` mutations made while a search was active.
- New `insertAtBottom` method; reverse-list (chat) semantics
  documented.
- `SmartListPage.empty()` sets `totalCount: null` (unknown), not 0.
- README and CHANGELOG inaccuracies corrected.
- `List<T>.unmodifiable(...)` calls in the controller replaced with
  `UnmodifiableListView<T>(...)` — same immutability contract, no
  per-call copy. Microbenchmarked at ~400× faster for a 10k-item
  list (see `test/benchmark_test.dart`).

### Deferred

- Per-notification `ValueListenableBuilder` rebuild of the entire
  `ListView` subtree (~1 `itemBuilder` call per visible item per
  state change) is documented but unaddressed. The microbenchmark
  in `test/benchmark_test.dart` quantifies the cost. Mitigation
  options today: wrap your `itemBuilder` widgets in
  `RepaintBoundary`, return `const` widgets where possible. A
  proper fix (split-rebuild via separate items-only `Listenable`)
  is tracked as a follow-up.

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
- `example/` app demonstrating pagination, debounced search,
  pull-to-refresh, simulated transient failures with auto-retry, and a
  custom empty-state builder.

#### Testing
- Tests covering controller flow, pagination strategies, cache
  semantics, debouncer, retry policy, request token, state derivations,
  and widget UI states.
