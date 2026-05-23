# Changelog

All notable changes to this package are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 — 2026-05-24

A correctness, concurrency, and performance sweep based on a full
code review. 28 issues addressed across the controller, widget,
caching, and pagination layers. Two breaking changes — both narrow,
both with clear migration paths.

### ⚠️ Breaking

- **`SmartListController` no longer extends `ValueNotifier`.** It now
  extends `ChangeNotifier` and `implements ValueListenable<SmartListState<T>>`.
  - **Still works:** reading `controller.value` (or the new alias
    `controller.state`); subscribing via
    `ValueListenableBuilder(valueListenable: controller, ...)`.
  - **No longer compiles:** `controller.value = X` from external
    code. External writes were a footgun — they bypassed the
    controller's internal bookkeeping. Use the mutation APIs
    (`insertAtTop`, `applyFilters`, `refresh`, `reset`, etc.) instead.

- **`SmartListController(...)` no longer accepts `enableCache:`.**
  The full constructor now takes a single `cache:` parameter:
  - `cache: null` (or omitted) → no cache.
  - `cache: someStore` → use that store.

  Migration: drop any `enableCache: false`; add an explicit
  `cache: MemoryCacheStore<T>()` if you previously relied on the
  implicit default. `SmartListController.simple` still accepts
  `enableCache: true` for the common case — no migration needed
  there.

### Added

- `insertAtBottom(item)` — companion to `insertAtTop`; appends to
  the end of the data list. Documented `reverse: true` semantics
  for chat-style layouts.
- `loadMoreErrorBuilder` slot on `SmartListView` for inline
  pagination-error footers. Defaults to a compact "Failed to
  load more / Retry" row instead of the full-screen error widget.
- `SmartListController.state` — alias for `controller.value`,
  readable shorthand outside `ValueListenableBuilder` contexts.

### Fixed — correctness

- **Equality / hashCode contract** for `SmartListState` and
  `SmartListCacheKey`. Previously hashed `filters.entries`;
  `MapEntry` has no value-equality, so equal filter maps produced
  different hashes — silently breaking cache lookups.
- **Separator off-by-one** in `SmartListView` — the divider between
  the last two real items was being suppressed along with the
  intended footer-slot suppression.
- **`SmartListPage.empty().totalCount`** is now `null` (unknown)
  instead of `0` (server reported zero).

### Fixed — concurrency

- **`RetryPolicy.run` now honours cancellation.** New `shouldContinue`
  callback aborts the retry chain via `SmartListCancelledException`.
  The controller wires it to `!_disposed && token.isCurrent`, so
  retries no longer continue past dispose or stomp on superseded
  requests. `onRetry` also guards against post-dispose mutations.
- **Cache-bypass intent is now per-call**, not a controller-wide
  flag. Concurrent fetches can no longer steal each other's bypass.
- **`applyFilters` emits a single coherent state transition**
  instead of flashing `{new filters, old phase, old items}` first.
- **Pending debounced searches are cancelled** when `refresh()` /
  `loadInitial(force: true)` / `applyFilters()` fires, so a stale
  search can't re-enter search mode after the reset.
- **Concurrent `loadNextPage()` calls are serialized** via an
  internal lock — extra callers await the in-flight result and
  return without firing a duplicate fetch.

### Fixed — widget / UI

- **Pull-to-refresh works on every placeholder state** (loading /
  error / empty). Placeholders are now wrapped in a viewport-tall
  scrollable so the `RefreshIndicator` always has a target.
- **`Debouncer(Duration.zero)` always schedules asynchronously**
  (previously fired synchronously, which could trigger
  "setState called during build" when invoked from a build pass).
- **Internal `ScrollController` is not resurrected after dispose**
  — the lazy getter returns `null` instead of leaking a fresh one.
- **`clearSearch` preserves real-time edits made during search.**
  `insertAtTop`, `removeWhere`, and `updateWhere` mutations now
  replay against the pre-search snapshot so they survive the
  restore. `insertAtIndex` is unchanged (positional, no semantic
  mapping) and that exclusion is documented.

### Performance

- **`List<T>.unmodifiable(...)` → `UnmodifiableListView<T>(...)`** in
  the controller. Same immutability contract, zero-copy wrap.
  Microbenchmarked at **~400× faster** for a 10k-item list
  (see `test/benchmark_test.dart`).
- **`_mergeItems` is now O(M)** instead of O(N + M) per page. The
  dedupe seen-set is persisted per phase and reset on fresh
  sequences.
- **Split-rebuild for `SmartListView`.** The populated `ListView`
  body is extracted into a dedicated widget passed via
  `ValueListenableBuilder`'s `child:` slot. It subscribes to the
  controller independently and only `setState`s when `items`,
  `phase`, or `error` actually change — filtering out
  query / filters / `retryAttempt` notifications. Benchmarked: a
  refresh cycle triggers **~50% fewer `itemBuilder` calls**
  (the `refreshing` transition preserves the items reference and
  no longer rebuilds the body); retry chains with N attempts skip
  N body rebuilds entirely.
- **Scroll-end handler bails when `maxScrollExtent <= 0`** — short
  lists no longer fire `loadNextPage` on every metric change.

### Docs

- `README.md`: dropped the inaccurate "two lines" tagline;
  documented the 5-minute default cache TTL; clarified that
  `SmartListController.simple` is page-pagination only.
- `CHANGELOG.md`: corrected the "56 tests" / `LLD.md` references
  in 0.0.1.
- Dartdoc clarifications on `refresh()`-during-search,
  `clearSearch` stale-pagination, `applyFilters({})` no-op
  semantics, `SmartListPage.items` immutability contract, stale
  cache-write behaviour, and reverse-mode `insertAtTop`.

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
