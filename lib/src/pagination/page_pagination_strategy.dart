import 'pagination_request.dart';
import 'pagination_response.dart';
import 'pagination_strategy.dart';

/// Page-number based pagination (e.g. `?page=1&size=20`).
class PagePaginationStrategy<T> implements SmartListPaginationStrategy<T> {
  @override
  final int pageSize;

  /// Page number to use for the very first request. Most APIs use 1; some use 0.
  final int initialPage;

  int _nextPage;

  PagePaginationStrategy({this.pageSize = 20, this.initialPage = 1})
      : _nextPage = initialPage;

  SmartListPageRequest _requestFor({
    required int page,
    String? query,
    Map<String, Object?> filters = const {},
  }) {
    return SmartListPageRequest(
      page: page,
      pageSize: pageSize,
      offset: (page - initialPage) * pageSize,
      query: query,
      filters: filters,
    );
  }

  @override
  SmartListPageRequest initialRequest({
    String? query,
    Map<String, Object?> filters = const {},
  }) {
    _nextPage = initialPage;
    return _requestFor(page: _nextPage, query: query, filters: filters);
  }

  @override
  SmartListPageRequest? nextRequest(
    SmartListPage<T> previousResponse, {
    String? query,
    Map<String, Object?> filters = const {},
  }) {
    if (isExhausted(previousResponse)) return null;
    return _requestFor(page: _nextPage, query: query, filters: filters);
  }

  @override
  void commit(SmartListPageRequest request, SmartListPage<T> response) {
    _nextPage = request.page + 1;
  }

  @override
  void reset() => _nextPage = initialPage;

  @override
  bool isExhausted(SmartListPage<T> response) {
    if (response.hasMore != null) return !response.hasMore!;
    return response.items.length < pageSize;
  }
}
