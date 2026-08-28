import 'pagination_request.dart';
import 'pagination_response.dart';

/// Abstract pagination strategy.
///
/// A strategy owns the bookkeeping required to translate "fetch the next
/// page" into a concrete [SmartListPageRequest]. The controller is agnostic
/// to the specific strategy — adding a new pagination scheme is a matter of
/// implementing this class, not modifying the controller.
///
/// Strategies are stateful (they remember where they left off) and must be
/// cheap to [reset] when a fresh fetch sequence begins (refresh, search, or
/// filter change).
///
/// Prefer **extending** this class so new default methods stay source-compatible.
/// `implements` requires re-implementing every member, including [commit].
abstract class SmartListPaginationStrategy<T> {
  /// Page size hint passed to every request. Strategies may use this both to
  /// build requests and to infer end-of-list when explicit signals are absent.
  int get pageSize;

  /// Build the request for the very first page in a fresh sequence.
  SmartListPageRequest initialRequest({
    String? query,
    Map<String, Object?> filters = const {},
  });

  /// Build the request for the next page given the previous response, or
  /// return `null` if no further pages are available.
  ///
  /// The default end-of-list heuristic is "received fewer than [pageSize]
  /// items"; strategies may override this with their own signals.
  SmartListPageRequest? nextRequest(
    SmartListPage<T> previousResponse, {
    String? query,
    Map<String, Object?> filters = const {},
  });

  /// Reset to the initial position. Called on refresh, new search, or when
  /// filters change.
  void reset();

  /// Whether the strategy considers itself exhausted given the last response.
  /// The controller uses this to populate `state.hasReachedEnd`.
  bool isExhausted(SmartListPage<T> response);

  /// Advance internal bookkeeping after a page was successfully applied.
  ///
  /// [initialRequest] / [nextRequest] must be side-effect free peeks: calling
  /// them twice with the same inputs must yield the same request. Built-in
  /// strategies commit only here so a failed fetch can be retried without
  /// skipping a page. Default is a no-op so user-defined strategies compile
  /// unchanged.
  void commit(SmartListPageRequest request, SmartListPage<T> response) {}
}
