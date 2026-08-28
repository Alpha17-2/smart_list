/// Raised when a fetch is superseded or the controller is disposed.
///
/// Fetchers should throw this from [SmartListCancelToken.throwIfCancelled]
/// after an `await`. The controller swallows it and does not enter `error`.
class SmartListCancelledException implements Exception {
  final String reason;
  const SmartListCancelledException([this.reason = 'cancelled']);

  @override
  String toString() => 'SmartListCancelledException: $reason';
}
