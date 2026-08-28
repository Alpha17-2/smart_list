import 'pagination_request.dart';
import 'pagination_response.dart';
import 'pagination_strategy.dart';

/// Cursor (token) based pagination — the API hands back an opaque
/// `nextCursor` string, which the client passes to fetch the next page.
class CursorPaginationStrategy<T> implements SmartListPaginationStrategy<T> {
  @override
  final int pageSize;

  int _nextPage = 1;

  /// Create a cursor strategy with the given [pageSize] hint (default 20).
  CursorPaginationStrategy({this.pageSize = 20});

  @override
  SmartListPageRequest initialRequest({
    String? query,
    Map<String, Object?> filters = const {},
  }) {
    _nextPage = 1;
    return SmartListPageRequest(
      page: _nextPage,
      pageSize: pageSize,
      cursor: null,
      offset: 0,
      query: query,
      filters: filters,
    );
  }

  @override
  SmartListPageRequest? nextRequest(
    SmartListPage<T> previousResponse, {
    String? query,
    Map<String, Object?> filters = const {},
  }) {
    if (isExhausted(previousResponse)) return null;
    return SmartListPageRequest(
      page: _nextPage,
      pageSize: pageSize,
      cursor: previousResponse.nextCursor,
      offset: 0,
      query: query,
      filters: filters,
    );
  }

  @override
  void commit(SmartListPageRequest request, SmartListPage<T> response) {
    _nextPage = request.page + 1;
  }

  @override
  void reset() {
    _nextPage = 1;
  }

  @override
  bool isExhausted(SmartListPage<T> response) {
    // Explicit "no more" always wins. `hasMore: true` without a cursor cannot
    // be followed (repeating cursor: null would re-fetch page 1 forever).
    if (response.hasMore == false) return true;
    return response.nextCursor == null;
  }
}
