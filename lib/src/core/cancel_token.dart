import 'smart_list_exception.dart';

/// Cooperative cancellation signal passed into every [SmartListFetcher] call.
///
/// The controller cancels the active token when a newer request supersedes it
/// (refresh, search, filters, dispose). Fetchers should call [throwIfCancelled]
/// after awaits, or subscribe via [onCancel] to abort HTTP clients.
class SmartListCancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  /// `true` once this token has been cancelled.
  bool get isCancelled => _cancelled;

  /// Throws [SmartListCancelledException] if this token is cancelled.
  void throwIfCancelled() {
    if (_cancelled) {
      throw const SmartListCancelledException();
    }
  }

  /// Invoke [callback] when [cancel] runs. No-op if already cancelled —
  /// [callback] is invoked immediately in that case.
  void onCancel(void Function() callback) {
    if (_cancelled) {
      callback();
      return;
    }
    _listeners.add(callback);
  }

  /// Mark this token cancelled. Idempotent.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }
}
