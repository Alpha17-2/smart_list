import 'package:flutter_test/flutter_test.dart';
import 'package:smart_list/smart_list.dart';

void main() {
  group('MemoryCacheStore', () {
    test('write/read round-trips a page', () {
      final store = MemoryCacheStore<int>();
      const key = SmartListCacheKey(page: 1);
      store.write(key, SmartListPage<int>(items: const [1, 2, 3]));
      expect(store.read(key)!.items, [1, 2, 3]);
    });

    test('returns null and evicts on TTL expiry', () {
      var now = DateTime(2025, 1, 1, 12, 0, 0);
      final store = MemoryCacheStore<int>(
        ttl: const Duration(seconds: 30),
        clock: () => now,
      );
      const key = SmartListCacheKey(page: 1);
      store.write(key, SmartListPage<int>(items: const [1]));
      now = now.add(const Duration(seconds: 31));
      expect(store.read(key), isNull);
      expect(store.length, 0);
    });

    test('LRU eviction at maxEntries', () {
      final store = MemoryCacheStore<int>(maxEntries: 2);
      const k1 = SmartListCacheKey(page: 1);
      const k2 = SmartListCacheKey(page: 2);
      const k3 = SmartListCacheKey(page: 3);
      store.write(k1, SmartListPage<int>(items: const [1]));
      store.write(k2, SmartListPage<int>(items: const [2]));
      // Touch k1 so it becomes most-recently-used.
      store.read(k1);
      store.write(k3, SmartListPage<int>(items: const [3]));
      expect(store.read(k1), isNotNull);
      expect(store.read(k2), isNull, reason: 'k2 should be evicted (LRU)');
      expect(store.read(k3), isNotNull);
    });

    test('invalidateQuery scopes to a single query', () {
      final store = MemoryCacheStore<int>();
      store.write(
        const SmartListCacheKey(query: 'a', page: 1),
        SmartListPage<int>(items: const [1]),
      );
      store.write(
        const SmartListCacheKey(query: 'b', page: 1),
        SmartListPage<int>(items: const [2]),
      );
      store.invalidateQuery('a');
      expect(store.read(const SmartListCacheKey(query: 'a', page: 1)), isNull);
      expect(
        store.read(const SmartListCacheKey(query: 'b', page: 1)),
        isNotNull,
      );
    });

    test('invalidateScope matches query and filters', () {
      final store = MemoryCacheStore<int>();
      final open = <String, dynamic>{'status': 'open'};
      final closed = <String, dynamic>{'status': 'closed'};
      store.write(
        SmartListCacheKey(page: 1, filters: open),
        SmartListPage<int>(items: const [1]),
      );
      store.write(
        SmartListCacheKey(page: 2, filters: open),
        SmartListPage<int>(items: const [2]),
      );
      store.write(
        SmartListCacheKey(page: 1, filters: closed),
        SmartListPage<int>(items: const [3]),
      );
      store.invalidateScope(filters: open);
      expect(store.length, 1);
      expect(
        store.read(SmartListCacheKey(page: 1, filters: open)),
        isNull,
      );
      expect(
        store.read(SmartListCacheKey(page: 2, filters: open)),
        isNull,
      );
      expect(
        store.read(SmartListCacheKey(page: 1, filters: closed))!.items,
        [3],
      );
    });

    test('clear empties the store', () {
      final store = MemoryCacheStore<int>();
      store.write(
        const SmartListCacheKey(page: 1),
        SmartListPage<int>(items: const [1]),
      );
      store.clear();
      expect(store.length, 0);
    });

    test('cache keys with different listIds are distinct', () {
      const k1 = SmartListCacheKey(listId: 'a', page: 1);
      const k2 = SmartListCacheKey(listId: 'b', page: 1);
      expect(k1 == k2, isFalse);
    });
  });
}
