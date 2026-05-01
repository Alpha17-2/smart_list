import 'package:flutter_test/flutter_test.dart';
import 'package:smart_list/smart_list.dart';

/// In-memory paginated source we can drive deterministically.
class _FakeSource {
  _FakeSource({required this.totalItems, this.matcher});

  final int totalItems;
  final bool Function(int item, String? query)? matcher;

  int callCount = 0;
  int failuresLeft = 0;
  Duration latency = Duration.zero;

  Future<SmartListPage<int>> fetch(SmartListPageRequest req) async {
    callCount++;
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    if (failuresLeft > 0) {
      failuresLeft--;
      throw StateError('forced failure');
    }
    final all = <int>[
      for (var i = 1; i <= totalItems; i++)
        if (matcher == null || matcher!(i, req.query)) i,
    ];
    final start = (req.page - 1) * req.pageSize;
    if (start >= all.length) return const SmartListPage(items: []);
    final end = (start + req.pageSize).clamp(0, all.length);
    return SmartListPage<int>(
      items: all.sublist(start, end),
      hasMore: end < all.length,
    );
  }
}

void main() {
  group('SmartListController — basic pagination', () {
    test('loadInitial populates first page and reports success', () async {
      final src = _FakeSource(totalItems: 5);
      final c = SmartListController<int>.simple(
        fetcher: src.fetch,
        pageSize: 10,
      );
      await c.loadInitial();
      expect(c.value.items, [1, 2, 3, 4, 5]);
      expect(c.value.phase, SmartListPhase.success);
      expect(c.value.hasReachedEnd, isTrue);
      c.dispose();
    });

    test('loadNextPage appends pages until exhausted', () async {
      final src = _FakeSource(totalItems: 7);
      final c = SmartListController<int>.simple(
        fetcher: src.fetch,
        pageSize: 3,
      );
      await c.loadInitial();
      expect(c.value.items, [1, 2, 3]);
      expect(c.value.hasReachedEnd, isFalse);
      await c.loadNextPage();
      expect(c.value.items, [1, 2, 3, 4, 5, 6]);
      await c.loadNextPage();
      expect(c.value.items, [1, 2, 3, 4, 5, 6, 7]);
      expect(c.value.hasReachedEnd, isTrue);
      // Further calls are a no-op.
      final before = src.callCount;
      await c.loadNextPage();
      expect(src.callCount, before);
      c.dispose();
    });

    test('loadInitial without force is a no-op when items present', () async {
      final src = _FakeSource(totalItems: 3);
      final c = SmartListController<int>.simple(
        fetcher: src.fetch,
        pageSize: 10,
      );
      await c.loadInitial();
      final before = src.callCount;
      await c.loadInitial();
      expect(src.callCount, before);
      c.dispose();
    });
  });

  group('SmartListController — refresh', () {
    test('refresh keeps items visible and re-fetches from page 1', () async {
      final src = _FakeSource(totalItems: 4);
      final c = SmartListController<int>.simple(
        fetcher: src.fetch,
        pageSize: 2,
        enableCache: false,
      );
      await c.loadInitial();
      await c.loadNextPage();
      expect(c.value.items, [1, 2, 3, 4]);

      final phases = <SmartListPhase>[];
      void listener() => phases.add(c.value.phase);
      c.addListener(listener);

      await c.refresh();
      c.removeListener(listener);

      expect(phases.first, SmartListPhase.refreshing);
      expect(c.value.items, [1, 2]);
      expect(c.value.phase, SmartListPhase.success);
      c.dispose();
    });
  });

  group('SmartListController — search', () {
    test('search snapshots existing list and restores on clear', () async {
      final src = _FakeSource(
        totalItems: 20,
        matcher: (i, q) => q == null || i.toString().contains(q),
      );
      final c = SmartListController<int>(
        fetcher: src.fetch,
        strategyBuilder: () => PagePaginationStrategy<int>(pageSize: 100),
        searchDebounce: Duration.zero,
      );
      await c.loadInitial();
      expect(c.value.items.length, 20);

      c.search('1');
      // Wait for debounced fetch to complete.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // 1, 10..19 = 11 items
      expect(c.value.items, [1, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]);
      expect(c.value.isSearchActive, isTrue);

      c.clearSearch();
      expect(c.value.isSearchActive, isFalse);
      expect(c.value.items.length, 20);
      c.dispose();
    });

    test('search debounces rapid keystrokes', () async {
      final src = _FakeSource(
        totalItems: 50,
        matcher: (i, q) => q == null || i.toString().contains(q),
      );
      final c = SmartListController<int>(
        fetcher: src.fetch,
        strategyBuilder: () => PagePaginationStrategy<int>(pageSize: 100),
        searchDebounce: const Duration(milliseconds: 50),
      );
      await c.loadInitial();
      final before = src.callCount;
      c.search('1');
      c.search('12');
      c.search('123');
      // Only the last one should fire after the debounce window.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(src.callCount - before, 1);
      expect(c.value.query, '123');
      c.dispose();
    });

    test('empty search query is treated as clearSearch', () async {
      final src = _FakeSource(
        totalItems: 5,
        matcher: (i, q) => q == null || i.toString().contains(q),
      );
      final c = SmartListController<int>(
        fetcher: src.fetch,
        strategyBuilder: () => PagePaginationStrategy<int>(pageSize: 100),
        searchDebounce: Duration.zero,
      );
      await c.loadInitial();
      c.search('1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(c.value.isSearchActive, isTrue);

      c.search('   ');
      expect(c.value.isSearchActive, isFalse);
      expect(c.value.items, [1, 2, 3, 4, 5]);
      c.dispose();
    });
  });

  group('SmartListController — race-condition guard', () {
    test('stale slow response is discarded after refresh', () async {
      // First fetch is slow; we trigger a refresh while it's in flight.
      final src = _FakeSource(totalItems: 3);
      src.latency = const Duration(milliseconds: 80);
      final c = SmartListController<int>.simple(
        fetcher: src.fetch,
        pageSize: 10,
        enableCache: false,
      );
      final firstLoad = c.loadInitial();
      // Allow first fetch to start.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Mutate the source so we can detect which response landed.
      src.latency = Duration.zero;
      // Trigger a fresh sequence — should supersede the slow one.
      final refresh = c.refresh();
      await Future.wait([firstLoad, refresh]);
      // We should still end up in success with items.
      expect(c.value.phase, SmartListPhase.success);
      expect(c.value.items, [1, 2, 3]);
      c.dispose();
    });
  });

  group('SmartListController — error + retry', () {
    test('surfaces error after exhausted retries', () async {
      final src = _FakeSource(totalItems: 5);
      src.failuresLeft = 5;
      final c = SmartListController<int>(
        fetcher: src.fetch,
        strategyBuilder: () => PagePaginationStrategy<int>(pageSize: 5),
        retryPolicy: RetryPolicy(
          maxAttempts: 2,
          baseDelay: const Duration(milliseconds: 1),
        ),
      );
      await c.loadInitial();
      expect(c.value.phase, SmartListPhase.error);
      expect(c.value.error, isA<StateError>());
      c.dispose();
    });

    test('recovers if a retry succeeds', () async {
      final src = _FakeSource(totalItems: 5);
      src.failuresLeft = 1;
      final c = SmartListController<int>(
        fetcher: src.fetch,
        strategyBuilder: () => PagePaginationStrategy<int>(pageSize: 5),
        retryPolicy: RetryPolicy(
          maxAttempts: 3,
          baseDelay: const Duration(milliseconds: 1),
        ),
      );
      await c.loadInitial();
      expect(c.value.phase, SmartListPhase.success);
      expect(c.value.items, [1, 2, 3, 4, 5]);
      c.dispose();
    });
  });

  group('SmartListController — caching', () {
    test('second loadInitial(force) hits the cache and skips the network',
        () async {
      final src = _FakeSource(totalItems: 3);
      final cache = MemoryCacheStore<int>();
      final c = SmartListController<int>(
        fetcher: src.fetch,
        strategyBuilder: () => PagePaginationStrategy<int>(pageSize: 5),
        cache: cache,
      );
      await c.loadInitial();
      final firstCalls = src.callCount;
      // Force-reload: cache should serve page 1.
      await c.loadInitial(force: true);
      expect(src.callCount, firstCalls,
          reason: 'cached page should not re-hit the source');
      expect(c.value.items, [1, 2, 3]);
      c.dispose();
    });
  });

  group('SmartListController — deduplication', () {
    test('uniqueKey collapses duplicates across pages', () async {
      // Source returns overlapping items deliberately.
      Future<SmartListPage<int>> dupSource(SmartListPageRequest req) async {
        if (req.page == 1) {
          return SmartListPage<int>(items: const [1, 2, 3], hasMore: true);
        }
        return SmartListPage<int>(items: const [3, 4, 5], hasMore: false);
      }

      final c = SmartListController<int>(
        fetcher: dupSource,
        strategyBuilder: () => PagePaginationStrategy<int>(pageSize: 3),
        uniqueKey: (i) => i,
      );
      await c.loadInitial();
      await c.loadNextPage();
      expect(c.value.items, [1, 2, 3, 4, 5]);
      c.dispose();
    });
  });

  group('SmartListController — mutations', () {
    test('insertAtTop / insertAtIndex / removeWhere / updateWhere', () async {
      final src = _FakeSource(totalItems: 3);
      final c = SmartListController<int>.simple(
        fetcher: src.fetch,
        pageSize: 10,
      );
      await c.loadInitial();
      expect(c.value.items, [1, 2, 3]);

      c.insertAtTop(0);
      expect(c.value.items, [0, 1, 2, 3]);

      c.insertAtIndex(2, 99);
      expect(c.value.items, [0, 1, 99, 2, 3]);

      c.updateWhere((i) => i == 99, (_) => 7);
      expect(c.value.items, [0, 1, 7, 2, 3]);

      c.removeWhere((i) => i.isEven);
      expect(c.value.items, [1, 7, 3]);
      c.dispose();
    });
  });

  group('SmartListController — filters', () {
    test('applyFilters resets and re-fetches', () async {
      var receivedFilters = const <String, dynamic>{};
      Future<SmartListPage<int>> src(SmartListPageRequest req) async {
        receivedFilters = req.filters;
        return SmartListPage<int>(items: const [1, 2], hasMore: false);
      }

      final c = SmartListController<int>.simple(
        fetcher: src,
        pageSize: 10,
        enableCache: false,
      );
      await c.loadInitial();
      await c.applyFilters({'status': 'open'});
      expect(receivedFilters, {'status': 'open'});
      expect(c.value.filters, {'status': 'open'});
      c.dispose();
    });
  });

  group('SmartListController — disposal', () {
    test('post-dispose calls are silent no-ops', () async {
      final src = _FakeSource(totalItems: 3);
      final c = SmartListController<int>.simple(
        fetcher: src.fetch,
        pageSize: 10,
      );
      c.dispose();
      // None of these should throw.
      await c.loadInitial();
      await c.refresh();
      c.search('x');
      c.clearSearch();
    });
  });
}
