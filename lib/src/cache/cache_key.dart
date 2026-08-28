import 'package:flutter/foundation.dart';

/// Composite key used to scope cache entries by list + query + filters + page.
///
/// Two requests with the same [listId]/query/filters/page produce equal keys —
/// suitable for use as a `Map` key. Use a distinct [listId] per list when
/// sharing a [SmartListCacheStore] across controllers.
@immutable
class SmartListCacheKey {
  /// Isolates entries when multiple lists share a store. `null` is valid
  /// for a store used by a single controller.
  final Object? listId;

  final String? query;
  final Map<String, Object?> filters;
  final int page;
  final String? cursor;

  const SmartListCacheKey({
    this.listId,
    this.query,
    this.filters = const {},
    required this.page,
    this.cursor,
  });

  @override
  bool operator ==(Object other) =>
      other is SmartListCacheKey &&
      other.listId == listId &&
      other.query == query &&
      other.page == page &&
      other.cursor == cursor &&
      mapEquals(other.filters, filters);

  @override
  int get hashCode => Object.hash(
        listId,
        query,
        page,
        cursor,
        Object.hashAllUnordered(
          filters.keys.map((k) => Object.hash(k, filters[k])),
        ),
      );

  @override
  String toString() =>
      'SmartListCacheKey(listId: $listId, query: $query, page: $page, cursor: $cursor, filters: $filters)';
}
