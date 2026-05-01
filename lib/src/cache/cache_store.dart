import '../pagination/pagination_response.dart';
import 'cache_key.dart';

/// Abstract cache store. Implementations may be in-memory, on-disk, or
/// remote — the controller never needs to know.
abstract class SmartListCacheStore<T> {
  /// Read a cached page if it exists and has not expired.
  SmartListPage<T>? read(SmartListCacheKey key);

  /// Persist a page response.
  void write(SmartListCacheKey key, SmartListPage<T> page);

  /// Drop a single entry.
  void invalidate(SmartListCacheKey key);

  /// Drop every entry whose [SmartListCacheKey.query] equals [query].
  /// Pass `null` to invalidate the "no-search" entries.
  void invalidateQuery(String? query);

  /// Drop everything.
  void clear();
}
