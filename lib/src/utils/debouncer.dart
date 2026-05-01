import 'dart:async';

/// Coalesces rapid successive calls into a single delayed invocation.
///
/// Used internally by the search pipeline so that typing "abc" only fires
/// one fetch (for "abc") rather than three (for "a", "ab", "abc").
///
/// Each call to [run] cancels the previous pending call.
class Debouncer {
  /// Delay applied to each scheduled action before it fires.
  final Duration delay;
  Timer? _timer;

  /// Create a debouncer that waits [delay] (default 300 ms) between the most
  /// recent [run] call and the eventual invocation of the action.
  Debouncer({this.delay = const Duration(milliseconds: 300)});

  /// Schedule [action] to run after [delay], cancelling any previously
  /// scheduled action.
  void run(void Function() action) {
    _timer?.cancel();
    if (delay == Duration.zero) {
      action();
      return;
    }
    _timer = Timer(delay, action);
  }

  /// Cancel any pending action. Safe to call when nothing is pending.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// `true` if an action is scheduled but not yet fired.
  bool get isPending => _timer?.isActive ?? false;

  /// Release internal resources. The instance must not be reused after this.
  void dispose() => cancel();
}
