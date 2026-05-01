/// The lifecycle phase of a [SmartListController].
///
/// Phases are mutually exclusive — at any moment the controller is in
/// exactly one of these states. Boolean conveniences derived from the
/// phase live on `SmartListState` (e.g. `isInitialLoading`, `hasError`).
enum SmartListPhase {
  /// No fetch has been requested yet.
  initial,

  /// First-page (or first-search-page) load is in flight and the visible
  /// list is currently empty.
  loading,

  /// A subsequent page is being fetched while existing items remain visible.
  loadingMore,

  /// A pull-to-refresh is in flight while existing items remain visible.
  refreshing,

  /// The most recent fetch completed successfully.
  success,

  /// The most recent fetch failed.
  error,
}
