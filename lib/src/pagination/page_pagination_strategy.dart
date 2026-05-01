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

  @override
  SmartListPageRequest initialRequest({
    String? query,
    Map<String, dynamic> filters = const {},
  }) {
    _nextPage = initialPage;
    final req = SmartListPageRequest(
      page: _nextPage,
      pageSize: pageSize,
      offset: 0,
      query: query,
      filters: filters,
    );
    _nextPage += 1;
    return req;
  }

  @override
  SmartListPageRequest? nextRequest(
    SmartListPage<T> previousResponse, {
    String? query,
    Map<String, dynamic> filters = const {},
  }) {
    if (isExhausted(previousResponse)) return null;
    final page = _nextPage;
    final req = SmartListPageRequest(
      page: page,
      pageSize: pageSize,
      offset: (page - initialPage) * pageSize,
      query: query,
      filters: filters,
    );
    _nextPage += 1;
    return req;
  }

  @override
  void reset() => _nextPage = initialPage;

  @override
  bool isExhausted(SmartListPage<T> response) {
    if (response.hasMore != null) return !response.hasMore!;
    return response.items.length < pageSize;
  }
}
