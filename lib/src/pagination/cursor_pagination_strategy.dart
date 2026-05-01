import 'pagination_request.dart';
import 'pagination_response.dart';
import 'pagination_strategy.dart';

/// Cursor (token) based pagination — the API hands back an opaque
/// `nextCursor` string, which the client passes to fetch the next page.
class CursorPaginationStrategy<T> implements SmartListPaginationStrategy<T> {
  @override
  final int pageSize;

  String? _nextCursor;
  int _nextPage = 1;

  /// Create a cursor strategy with the given [pageSize] hint (default 20).
  CursorPaginationStrategy({this.pageSize = 20});

  @override
  SmartListPageRequest initialRequest({
    String? query,
    Map<String, dynamic> filters = const {},
  }) {
    _nextCursor = null;
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
    Map<String, dynamic> filters = const {},
  }) {
    if (isExhausted(previousResponse)) return null;
    _nextCursor = previousResponse.nextCursor;
    _nextPage += 1;
    return SmartListPageRequest(
      page: _nextPage,
      pageSize: pageSize,
      cursor: _nextCursor,
      offset: 0,
      query: query,
      filters: filters,
    );
  }

  @override
  void reset() {
    _nextCursor = null;
    _nextPage = 1;
  }

  @override
  bool isExhausted(SmartListPage<T> response) {
    if (response.hasMore != null) return !response.hasMore!;
    // Cursor APIs typically signal end via `nextCursor == null`.
    return response.nextCursor == null;
  }
}
