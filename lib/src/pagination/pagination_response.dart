import 'package:flutter/foundation.dart';

/// Result of a single page fetch, returned by the user's fetcher.
///
/// At minimum, callers must return [items]. The optional fields help the
/// controller decide whether more pages exist:
///
/// * [nextCursor] — for cursor-based pagination; `null` signals end-of-list.
/// * [hasMore] — explicit override; takes precedence when provided.
///
/// If neither is provided, the controller falls back to the heuristic
/// "received fewer items than the requested page size → end of list".
@immutable
class SmartListPage<T> {
  /// The items for this page.
  final List<T> items;

  /// Cursor to pass on the next request. `null` indicates end-of-list when
  /// using cursor-based pagination.
  final String? nextCursor;

  /// Explicit "are there more pages" signal. When non-null, this overrides
  /// any inference from [items.length] or [nextCursor].
  final bool? hasMore;

  /// Total count, when known. Purely informational; not used for paging.
  final int? totalCount;

  const SmartListPage({
    required this.items,
    this.nextCursor,
    this.hasMore,
    this.totalCount,
  });

  /// Convenience for an explicitly-empty terminal page.
  const SmartListPage.empty()
      : items = const [],
        nextCursor = null,
        hasMore = false,
        totalCount = 0;
}
