import '../pagination/pagination_response.dart';
import 'cache_key.dart';
import 'cache_store.dart';

class _CacheEntry<T> {
  final SmartListPage<T> page;
  final DateTime expiresAt;
  _CacheEntry(this.page, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Simple in-memory cache store with TTL-based invalidation and an optional
/// LRU bound. Suitable for typical session-scoped use; persistence can be
/// added later via a [SmartListCacheStore] implementation that wraps Hive,
/// SQLite, etc.
class MemoryCacheStore<T> implements SmartListCacheStore<T> {
  /// Time-to-live for each cached page.
  final Duration ttl;

  /// Maximum number of entries before the oldest is evicted. `null` disables.
  final int? maxEntries;

  /// Injected clock for deterministic testing. Defaults to `DateTime.now`.
  final DateTime Function() _clock;

  // LinkedHashMap preserves insertion order — we use that as LRU order
  // by re-inserting on read.
  final Map<SmartListCacheKey, _CacheEntry<T>> _entries =
      <SmartListCacheKey, _CacheEntry<T>>{};

  MemoryCacheStore({
    this.ttl = const Duration(minutes: 5),
    this.maxEntries = 64,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  @override
  SmartListPage<T>? read(SmartListCacheKey key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (_clock().isAfter(entry.expiresAt)) {
      _entries.remove(key);
      return null;
    }
    // Touch LRU.
    _entries.remove(key);
    _entries[key] = entry;
    return entry.page;
  }

  @override
  void write(SmartListCacheKey key, SmartListPage<T> page) {
    _entries.remove(key);
    _entries[key] = _CacheEntry<T>(page, _clock().add(ttl));
    if (maxEntries != null && _entries.length > maxEntries!) {
      // Evict least-recently-used (head of insertion order).
      final firstKey = _entries.keys.first;
      _entries.remove(firstKey);
    }
  }

  @override
  void invalidate(SmartListCacheKey key) => _entries.remove(key);

  @override
  void invalidateQuery(String? query) {
    _entries.removeWhere((k, _) => k.query == query);
  }

  @override
  void clear() => _entries.clear();

  /// Number of entries currently cached. Exposed for tests / diagnostics.
  int get length => _entries.length;
}
