import 'package:flutter_test/flutter_test.dart';
import 'package:smart_list/smart_list.dart';

void main() {
  group('SmartListState', () {
    test('initial state has no items and is in initial phase', () {
      final s = SmartListState<int>.initial();
      expect(s.items, isEmpty);
      expect(s.phase, SmartListPhase.initial);
      expect(s.hasError, isFalse);
      expect(s.isInitialLoading, isFalse);
    });

    test('isInitialLoading only true when loading + empty', () {
      final empty = SmartListState<int>(phase: SmartListPhase.loading);
      final populated = SmartListState<int>(
        items: const [1],
        phase: SmartListPhase.loading,
      );
      expect(empty.isInitialLoading, isTrue);
      expect(populated.isInitialLoading, isFalse);
    });

    test('isEmpty only after a successful fetch', () {
      final loading = SmartListState<int>(phase: SmartListPhase.loading);
      final success = SmartListState<int>(phase: SmartListPhase.success);
      expect(loading.isEmpty, isFalse);
      expect(success.isEmpty, isTrue);
    });

    test('isSearchActive ignores empty query', () {
      expect(SmartListState<int>(query: '').isSearchActive, isFalse);
      expect(SmartListState<int>(query: 'foo').isSearchActive, isTrue);
    });

    test('isSearchEmpty requires both empty success and active query', () {
      final s1 = SmartListState<int>(
        phase: SmartListPhase.success,
        query: 'no-match',
      );
      final s2 = SmartListState<int>(
        phase: SmartListPhase.success,
        query: 'no-match',
        items: const [1],
      );
      expect(s1.isSearchEmpty, isTrue);
      expect(s2.isSearchEmpty, isFalse);
    });

    test('copyWith clearError drops the error', () {
      final s = SmartListState<int>(
        phase: SmartListPhase.error,
        error: 'boom',
      );
      final cleared = s.copyWith(clearError: true);
      expect(cleared.error, isNull);
    });

    test('copyWith clearQuery drops the query', () {
      final s = SmartListState<int>(query: 'foo');
      expect(s.copyWith(clearQuery: true).query, isNull);
    });

    test('equality compares items, phase, query, filters', () {
      final a = SmartListState<int>(items: const [1, 2], query: 'q');
      final b = SmartListState<int>(items: const [1, 2], query: 'q');
      final c = SmartListState<int>(items: const [1, 3], query: 'q');
      expect(a, b);
      expect(a == c, isFalse);
    });
  });
}
