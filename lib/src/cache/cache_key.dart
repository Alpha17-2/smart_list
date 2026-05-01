import 'package:flutter/foundation.dart';

/// Composite key used to scope cache entries by query + filters + page.
///
/// Two requests with the same query/filters/page produce equal keys —
/// suitable for use as a `Map` key.
@immutable
class SmartListCacheKey {
  final String? query;
  final Map<String, dynamic> filters;
  final int page;
  final String? cursor;

  const SmartListCacheKey({
    this.query,
    this.filters = const {},
    required this.page,
    this.cursor,
  });

  @override
  bool operator ==(Object other) =>
      other is SmartListCacheKey &&
      other.query == query &&
      other.page == page &&
      other.cursor == cursor &&
      mapEquals(other.filters, filters);

  @override
  int get hashCode => Object.hash(
        query,
        page,
        cursor,
        Object.hashAllUnordered(filters.entries),
      );

  @override
  String toString() =>
      'SmartListCacheKey(query: $query, page: $page, cursor: $cursor, filters: $filters)';
}
