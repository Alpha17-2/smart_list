import 'pagination_request.dart';
import 'pagination_response.dart';
import 'pagination_strategy.dart';

/// Offset / limit based pagination (e.g. `?offset=40&limit=20`).
class OffsetPaginationStrategy<T> implements SmartListPaginationStrategy<T> {
  @override
  final int pageSize;

  int _nextOffset = 0;
  int _nextPage = 1;

  OffsetPaginationStrategy({this.pageSize = 20});

  @override
  SmartListPageRequest initialRequest({
    String? query,
    Map<String, Object?> filters = const {},
  }) {
    _nextOffset = 0;
    _nextPage = 1;
    return SmartListPageRequest(
      page: _nextPage,
      pageSize: pageSize,
      offset: _nextOffset,
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
      offset: _nextOffset,
      query: query,
      filters: filters,
    );
  }

  @override
  void commit(SmartListPageRequest request, SmartListPage<T> response) {
    _nextOffset = request.offset + response.items.length;
    _nextPage = request.page + 1;
  }

  @override
  void reset() {
    _nextOffset = 0;
    _nextPage = 1;
  }

  @override
  bool isExhausted(SmartListPage<T> response) {
    if (response.hasMore != null) return !response.hasMore!;
    if (response.items.isEmpty) return true;
    return response.items.length < pageSize;
  }
}
