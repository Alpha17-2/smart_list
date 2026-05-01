import '../pagination/pagination_request.dart';
import '../pagination/pagination_response.dart';

/// Signature for a user-supplied page fetcher.
///
/// The controller calls this once per page with a fully-populated
/// [SmartListPageRequest] and expects a [SmartListPage] back. Implementations
/// should respect cancellation cooperatively where possible (e.g. by
/// checking `Future.any` against a cancellation signal), but the controller
/// also guards against stale responses internally via a request token.
typedef SmartListFetcher<T> = Future<SmartListPage<T>> Function(
  SmartListPageRequest request,
);

/// Optional unique-key extractor used for deduplication across pages.
typedef UniqueKeyExtractor<T> = Object Function(T item);
