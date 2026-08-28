import 'dart:async';
import 'dart:math' as math;

import '../core/smart_list_exception.dart';

/// Decides whether a thrown error is worth retrying, and with what backoff.
///
/// Default: up to 3 attempts, exponential backoff starting at 200ms with
/// jitter, retry only on [isTransient] errors (timeouts and typical I/O
/// failures). Pass [shouldRetry] to override. Use [RetryPolicy.aggressive]
/// to restore retry-on-every-error. HTTP 4xx mapping is the caller's job via
/// a custom [shouldRetry] predicate.
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

  /// Retry every error (the 0.0.1 default). Prefer the standard constructor
  /// unless you intentionally want that behaviour.
  factory RetryPolicy.aggressive({
    int maxAttempts = 3,
    Duration baseDelay = const Duration(milliseconds: 200),
    Duration maxDelay = const Duration(seconds: 5),
    math.Random? rng,
  }) {
    return RetryPolicy(
      maxAttempts: maxAttempts,
      baseDelay: baseDelay,
      maxDelay: maxDelay,
      shouldRetry: (_) => true,
      rng: rng,
    );
  }

  /// Heuristic for network-style transients without importing `dart:io`
  /// (keeps the package web-safe).
  static bool isTransient(Object error) {
    if (error is TimeoutException) return true;
    final type = error.runtimeType.toString();
    return type == 'SocketException' ||
        type == 'HttpException' ||
        type == 'HandshakeException' ||
        type == 'TlsException' ||
        type == 'OSError' ||
        type == 'ClientException';
  }

  /// Whether the policy permits another attempt for [error] after
  /// [attemptsSoFar] attempts have already been made.
  bool shouldRetry(Object error, int attemptsSoFar) {
    if (error is SmartListCancelledException) return false;
    if (attemptsSoFar >= maxAttempts) return false;
    if (_shouldRetry != null) return _shouldRetry!(error);
    return isTransient(error);
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
