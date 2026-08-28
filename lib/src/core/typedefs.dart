import '../pagination/pagination_request.dart';
import '../pagination/pagination_response.dart';
import 'cancel_token.dart';

/// Signature for a user-supplied page fetcher.
///
/// The controller calls this once per page with a fully-populated
/// [SmartListPageRequest] and a [SmartListCancelToken]. After each `await`,
/// call `cancel.throwIfCancelled()` (or abort your HTTP client from
/// `cancel.onCancel`) so superseded work stops promptly.
typedef SmartListFetcher<T> = Future<SmartListPage<T>> Function(
  SmartListPageRequest request,
  SmartListCancelToken cancel,
);

/// Optional unique-key extractor used for deduplication across pages
/// and local inserts.
typedef UniqueKeyExtractor<T> = Object Function(T item);

/// Filter map carried on requests, state, and cache keys.
typedef SmartListFilters = Map<String, Object?>;
