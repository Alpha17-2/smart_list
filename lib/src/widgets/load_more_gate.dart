/// Fires once when remaining distance first enters the prefetch zone.
class LoadMoreGate {
  double? _lastRemaining;

  bool shouldLoadMore(double remaining, double threshold) {
    final last = _lastRemaining;
    _lastRemaining = remaining;
    if (remaining > threshold) return false;
    if (last != null && last <= threshold) return false;
    return true;
  }

  void reset() => _lastRemaining = null;
}
