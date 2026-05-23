import 'dart:async';
import 'dart:math' as math;

import '../core/smart_list_exception.dart';

/// Decides whether a thrown error is worth retrying, and with what backoff.
///
/// Default behaviour: up to 3 attempts (initial + 2 retries), exponential
/// backoff starting at 200ms with jitter, retry on every error. Override
/// [shouldRetry] to scope retries to specific transient failures
/// (e.g. network timeouts, 5xx responses).
class RetryPolicy {
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final bool Function(Object error)? _shouldRetry;
  final math.Random _rng;

  RetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 200),
    this.maxDelay = const Duration(seconds: 5),
    bool Function(Object error)? shouldRetry,
    math.Random? rng,
  })  : _shouldRetry = shouldRetry,
        _rng = rng ?? math.Random();

  /// Disable retries entirely.
  factory RetryPolicy.none() => RetryPolicy(maxAttempts: 1);

  /// Whether the policy permits another attempt for [error] after
  /// [attemptsSoFar] attempts have already been made.
  bool shouldRetry(Object error, int attemptsSoFar) {
    if (attemptsSoFar >= maxAttempts) return false;
    return _shouldRetry?.call(error) ?? true;
  }

  /// Backoff delay before the next attempt (1-based).
  Duration backoffFor(int nextAttempt) {
    final exp = math.pow(2, nextAttempt - 1).toInt();
    final raw = baseDelay * exp;
    final capped = raw > maxDelay ? maxDelay : raw;
    // Add up to 25% jitter to avoid thundering herd.
    final jitterMs = (_rng.nextDouble() * capped.inMilliseconds * 0.25).toInt();
    return capped + Duration(milliseconds: jitterMs);
  }

  /// Run [action] under this retry policy. Calls [onRetry] before each retry
  /// attempt (1-based attempt counter) so the controller can surface retry
  /// state to the UI.
  ///
  /// If [shouldContinue] is supplied, it is consulted before every attempt
  /// and again after each backoff sleep. Returning `false` aborts the loop
  /// with a [SmartListCancelledException] instead of retrying — this lets
  /// callers cancel an in-flight retry chain when the request is superseded
  /// or the owning controller is disposed.
  Future<R> run<R>(
    Future<R> Function() action, {
    void Function(int attempt, Object error)? onRetry,
    bool Function()? shouldContinue,
  }) async {
    var attempt = 0;
    while (true) {
      if (shouldContinue != null && !shouldContinue()) {
        throw const SmartListCancelledException('retry aborted');
      }
      attempt++;
      try {
        return await action();
      } catch (e) {
        if (e is SmartListCancelledException) rethrow;
        if (!shouldRetry(e, attempt)) rethrow;
        if (shouldContinue != null && !shouldContinue()) {
          throw const SmartListCancelledException('retry aborted');
        }
        onRetry?.call(attempt, e);
        await Future<void>.delayed(backoffFor(attempt));
      }
    }
  }
}
