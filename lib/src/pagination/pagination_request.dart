import 'package:flutter/foundation.dart';

/// Parameters passed to a user-supplied fetcher for each page request.
///
/// All pagination strategies (page / cursor / offset) populate this same
/// shape so the fetcher signature stays uniform; strategies differ only in
/// which fields are meaningful.
@immutable
class SmartListPageRequest {
  /// 1-based page index. Always populated; useful even for cursor APIs as a
  /// "which page-call are we on" counter.
  final int page;

  /// Requested page size. Strategies may use this to compute offsets or to
  /// infer end-of-list when the response is short.
  final int pageSize;

  /// Cursor returned from the previous page, or `null` for the first page.
  /// Used by cursor-based APIs.
  final String? cursor;

  /// Offset to read from. Used by offset-based APIs. Always populated.
  final int offset;

  /// The active search query, or `null` if no search is in progress.
  final String? query;

  /// User-applied filters, scoped to the request.
  final Map<String, dynamic> filters;

  const SmartListPageRequest({
    required this.page,
    required this.pageSize,
    this.cursor,
    this.offset = 0,
    this.query,
    this.filters = const {},
  });

  @override
  String toString() =>
      'SmartListPageRequest(page: $page, pageSize: $pageSize, '
      'cursor: $cursor, offset: $offset, query: $query, filters: $filters)';
}
