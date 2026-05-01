/// Sentinel error raised internally when an in-flight request is superseded
/// by a newer one (e.g. user types a new query while the old one is still
/// pending). Callers normally never see this — the controller swallows it.
class SmartListCancelledException implements Exception {
  final String reason;
  const SmartListCancelledException([this.reason = 'cancelled']);

  @override
  String toString() => 'SmartListCancelledException: $reason';
}
