# SmartList

> Paginated, searchable Flutter lists with retries, cache, and cancelable fetches.
> Use `SmartListView`, or `SmartListSliver` inside a `CustomScrollView`.

[![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.0%2B-0175C2?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg)]()

---

## Why SmartList?

If you've ever built a list screen in Flutter, you've probably written the same boilerplate again and again:

- Load more when the user scrolls near the bottom.
- Debounce the search box so we don't hit the API on every keystroke.
- Show a spinner the first time, a small spinner at the bottom afterwards
- What if the user pulls to refresh while a search is loading?
- What if a slow response comes back *after* a faster one?

Every list screen ends up reinventing this. **SmartList does it once, properly, and lets you focus on your UI.**

---

## What you get

| Feature | What it means |
|---|---|
| 📄 **Pagination** | Page-based, cursor-based, or offset-based — pick one, swap any time |
| 🔍 **Search** | Built-in debouncing, automatic cancellation, restores previous list when you clear |
| ⬇️ **Pull-to-refresh** | One flag — `enableRefresh: true` |
| 🎨 **UI states** | Loading, empty, error, search-empty — all customisable, sensible defaults out of the box |
| 💾 **Caching** | In-memory TTL/LRU; `listId` when sharing a store; disk via `SmartListCacheStore` (see `example/`) |
| 🔁 **Auto-retry** | Transient I/O/timeouts by default; `RetryPolicy.aggressive()` retries everything |
| 🛡️ **Race-safe** | Request tokens plus **cancel tokens** so superseded HTTP work can stop |
| 🧹 **No duplicates** | Optional `uniqueKey` on pages and local inserts |
| 🪶 **Tiny** | Core depends on Flutter only |

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  smart_list: ^1.0.0
```

Then run:

```bash
flutter pub get
```

---

## A note on the examples

> `SmartList` is **generic over any type `T`** — bring your own model class.
> The examples below use `Post`, `Message`, `Product`, and `User` as stand-ins
> for *your* domain types. Anywhere you see one of those, mentally substitute
> your own class.

---

## Quickstart

```dart
import 'package:smart_list/smart_list.dart';

final controller = SmartListController<Post>.simple(
  fetcher: (req, cancel) async {
    final items = await api.getPosts(req.page);
    cancel.throwIfCancelled();
    return SmartListPage(items: items);
  },
);

SmartListView<Post>(
  controller: controller,
  itemBuilder: (context, post, index) => ListTile(title: Text(post.title)),
);
```

That's it. You now have a list with infinite scroll, pull-to-refresh, loading/empty/error states, and an in-memory cache (5-minute TTL by default — pass your own `MemoryCacheStore(ttl: …)` or a custom `SmartListCacheStore` via the full constructor to tune it).

For `CustomScrollView`, use `SmartListSliver` in `slivers:` (wrap the scroll view in `RefreshIndicator` yourself).

---

## Adding search

```dart
TextField(
  onChanged: controller.search,        // built-in debounce
  decoration: InputDecoration(hintText: 'Search…'),
);

// Anywhere later:
controller.clearSearch();              // restores the original list
```

The fetcher receives the query through `req.query` — handle it however your API expects.

---

## Customising the UI

Every state has a sensible default and is overridable. (Example below uses `Product` — your own model class.)

```dart
SmartListView<Product>(
  controller: controller,
  itemBuilder: (_, product, __) => ProductCard(product),

  loadingBuilder:    (_) => MyShimmerSkeleton(),
  emptyBuilder:      (_) => Center(child: Text('No products in stock')),
  searchEmptyBuilder:(_, q) => Text('Nothing matches "$q"'),
  errorBuilder:      (_, err, retry) => MyErrorWidget(err, onRetry: retry),
  loadingMoreBuilder:(_) => MySmallSpinner(),

  separatorBuilder: (_, __) => const Divider(height: 1),
  loadMoreThreshold: 300,                // start prefetching 300px before the bottom
  enableRefresh: true,
);
```

Need *complete* control? Skip `SmartListView` and use the controller directly — it implements `ValueListenable`, so it works with any UI you like:

```dart
ValueListenableBuilder<SmartListState<Product>>(
  valueListenable: controller,
  builder: (context, state, _) {
    if (state.isInitialLoading) return MyCustomSkeleton();
    return CustomScrollView(slivers: [...]);
  },
);
```

---

## Pagination styles

`SmartListController.simple` hard-codes page-based pagination. To use cursor or offset, build the controller with the full constructor and supply a `strategyBuilder`:

```dart
SmartListController<MyItem>(
  fetcher: myFetcher,
  strategyBuilder: () => CursorPaginationStrategy<MyItem>(pageSize: 20),
);
```

Available strategies:

```dart
// Page-based: ?page=1&size=20  (this is the default in `.simple`)
PagePaginationStrategy<MyItem>(pageSize: 20)

// Cursor-based: ?cursor=xyz
CursorPaginationStrategy<MyItem>(pageSize: 20)

// Offset-based: ?offset=40&limit=20
OffsetPaginationStrategy<MyItem>(pageSize: 20)
```

Use the full constructor when you want a non-default strategy:

```dart
SmartListController<MyItem>(
  fetcher: api.fetch,
  strategyBuilder: () => CursorPaginationStrategy<MyItem>(pageSize: 30),
);
```

---

## Real-time updates

Got a new chat message? An item that changed? Mutate the list directly — no refetch needed:

```dart
// In a chat screen with `SmartListController<Message>`:
controller.insertAtTop(newMessage);
controller.insertAtIndex(3, replyMessage);
controller.updateWhere((m) => m.id == 7, (m) => m.copyWith(read: true));
controller.removeWhere((m) => m.archived);
```

---

## Filters

Re-fetch with new filters in one call:

```dart
controller.applyFilters({'status': 'open', 'category': 'food'});
```

Pass an empty map to clear them. The fetcher gets them through `req.filters`.

---

## Plays well with every state-management library

`SmartListController` is a `ChangeNotifier` that implements `ValueListenable` — Provider, Riverpod, GetX, BLoC, and `setState` all consume it without an adapter. The only rule: dispose it when its scope dies.

```dart
// Provider
ChangeNotifierProvider(create: (_) => SmartListController.simple(...));

// Riverpod
final ctrlProvider = Provider.autoDispose((ref) {
  final c = SmartListController.simple(...);
  ref.onDispose(c.dispose);
  return c;
});

// GetX
class HomeController extends GetxController {
  final list = SmartListController.simple(...);
  @override void onClose() { list.dispose(); super.onClose(); }
}
```

---

## What the controller exposes

```dart
controller.loadInitial();            // first load (no-op if already loaded)
controller.loadNextPage();           // fetch next page
controller.refresh();                // pull-to-refresh (skips cache by default)
controller.refresh(bypassCache: false); // allow cache reuse on refresh
controller.search('flutter');        // debounced search
controller.clearSearch();            // restore pre-search list
controller.applyFilters({...});      // change filters & refetch
controller.insertAtTop(item);
controller.insertAtBottom(item);
controller.insertAtIndex(i, item);
controller.updateWhere(test, fn);
controller.removeWhere(test);
controller.reset();                  // wipe state
controller.clearCache();
controller.value;                    // current SmartListState<T>
controller.state;                    // alias for value
controller.addListener(() => …);     // it's a ChangeNotifier
```

---

## The state object

`SmartListState<T>` is what your UI reacts to:

```dart
state.items           // List<T> — what to render
state.phase           // SmartListPhase — initial / loading / loadingMore / refreshing / success / error
state.isInitialLoading
state.isLoadingMore
state.isRefreshing
state.hasError
state.error           // Object?
state.isEmpty
state.isSearchActive
state.isSearchEmpty
state.hasReachedEnd
state.query           // active search query
state.filters
```

It's immutable — every change produces a new instance. Equality is value-based, so you can drop it straight into `BlocBuilder`, `Selector`, etc.

---

## Try the example

A full working demo lives in `example/`:

```bash
cd example
flutter run
```

It shows ListView + search, a sliver/cursor tab, cancel-aware delayed fetches, and a copy-paste `JsonFileCacheStore` in `example/lib/json_file_cache_store.dart`.

---

## Extending pagination / cache

Prefer `extends SmartListPaginationStrategy` (and default methods on the cache store) so new APIs are not breaking. `implements` must re-declare every member including `commit`.

Filters are `Map<String, Object?>`.

Post-1.0 (not in this package yet): hybrid local+remote search, DevTools overlay.

---

## License

MIT — use it freely in commercial and open-source projects.
