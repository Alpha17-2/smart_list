import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_list/smart_list.dart';

void main() {
  group('Debouncer', () {
    test('coalesces rapid calls into one', () {
      fakeAsync((async) {
        final d = Debouncer(delay: const Duration(milliseconds: 100));
        var count = 0;
        d.run(() => count++);
        d.run(() => count++);
        d.run(() => count++);
        async.elapse(const Duration(milliseconds: 150));
        expect(count, 1);
        d.dispose();
      });
    });

    test('cancel prevents firing', () {
      fakeAsync((async) {
        final d = Debouncer(delay: const Duration(milliseconds: 100));
        var fired = false;
        d.run(() => fired = true);
        d.cancel();
        async.elapse(const Duration(milliseconds: 200));
        expect(fired, isFalse);
        d.dispose();
      });
    });

    test('zero delay still defers to the next microtask (#19)', () {
      // Pre-fix: Duration.zero fired the action synchronously, which made
      // it unsafe to call `debouncer.run` from inside a Flutter build —
      // any state mutation would trigger 'setState called during build'.
      // Post-fix: even a zero delay schedules through a Timer.
      fakeAsync((async) {
        final d = Debouncer(delay: Duration.zero);
        var fired = false;
        d.run(() => fired = true);
        expect(fired, isFalse, reason: 'must not run synchronously');
        async.elapse(const Duration(milliseconds: 1));
        expect(fired, isTrue);
        d.dispose();
      });
    });
  });

  group('RequestToken', () {
    test('issued tokens are monotonic', () {
      final t = RequestToken();
      final a = t.issue();
      final b = t.issue();
      expect(b > a, isTrue);
      expect(t.isCurrent(b), isTrue);
      expect(t.isCurrent(a), isFalse);
    });
  });

  group('RetryPolicy', () {
    test('retries until success within maxAttempts', () async {
      final policy = RetryPolicy(
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 1),
      );
      var calls = 0;
      final result = await policy.run<String>(() async {
        calls++;
        if (calls < 3) throw TimeoutException('flaky');
        return 'ok';
      });
      expect(result, 'ok');
      expect(calls, 3);
    });

    test('does not retry StateError by default', () async {
      final policy = RetryPolicy(
        maxAttempts: 5,
        baseDelay: const Duration(milliseconds: 1),
      );
      var calls = 0;
      await expectLater(
        policy.run<int>(() async {
          calls++;
          throw StateError('not transient');
        }),
        throwsA(isA<StateError>()),
      );
      expect(calls, 1);
    });

    test('retries TimeoutException by default', () async {
      final policy = RetryPolicy(
        maxAttempts: 2,
        baseDelay: const Duration(milliseconds: 1),
      );
      expect(policy.shouldRetry(TimeoutException('x'), 1), isTrue);
    });

    test('rethrows after maxAttempts', () async {
      final policy = RetryPolicy(
        maxAttempts: 2,
        baseDelay: const Duration(milliseconds: 1),
      );
      var calls = 0;
      await expectLater(
        policy.run<int>(() async {
          calls++;
          throw TimeoutException('always');
        }),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 2);
    });

    test('shouldRetry predicate is honoured', () async {
      final policy = RetryPolicy(
        maxAttempts: 5,
        baseDelay: const Duration(milliseconds: 1),
        shouldRetry: (e) => e is FormatException,
      );
      var calls = 0;
      await expectLater(
        policy.run<int>(() async {
          calls++;
          throw StateError('not retryable');
        }),
        throwsA(isA<StateError>()),
      );
      expect(calls, 1);
    });

    test('RetryPolicy.aggressive retries any error', () {
      final p = RetryPolicy.aggressive();
      expect(p.shouldRetry(StateError('x'), 1), isTrue);
    });

    test('RetryPolicy.none disables retries', () {
      final p = RetryPolicy.none();
      expect(p.shouldRetry(Exception('x'), 1), isFalse);
    });
  });
}
