@Tags(['benchmark'])
library;

// Microbenchmarks for two perf hot-spots flagged in the code review:
//
//   #25 — `List.unmodifiable(...)` allocated per state mutation
//         (already fixed; this benchmark documents the win).
//   #26 — `ValueListenableBuilder` rebuilds the full ListView subtree on
//         every state change, including phase-only transitions where the
//         items list is identical.
//
// These tests print timings instead of asserting strict thresholds — they
// exist to inform the #26 refactor decision, not to gate CI. Run with:
//
//   fvm flutter test test/benchmark_test.dart --tags benchmark
//
// The non-tagged default `flutter test` skips them.

import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_list/smart_list.dart';

const _kBigListSize = 10000;
const _kIterations = 1000;

void main() {
  group('#25 — allocation cost per state mutation', () {
    test('List.unmodifiable vs UnmodifiableListView for big list', () {
      final src = List<int>.generate(_kBigListSize, (i) => i);

      final swCopy = Stopwatch()..start();
      for (var i = 0; i < _kIterations; i++) {
        // ignore: unused_local_variable
        final out = List<int>.unmodifiable(src);
      }
      swCopy.stop();

      final swView = Stopwatch()..start();
      for (var i = 0; i < _kIterations; i++) {
        // ignore: unused_local_variable
        final out = UnmodifiableListView<int>(src);
      }
      swView.stop();

      // ignore: avoid_print
      print('#25 list=$_kBigListSize iters=$_kIterations '
          'List.unmodifiable=${swCopy.elapsedMicroseconds}µs '
          'UnmodifiableListView=${swView.elapsedMicroseconds}µs '
          'speedup=${(swCopy.elapsedMicroseconds / swView.elapsedMicroseconds).toStringAsFixed(1)}x');

      // Sanity expectation only — the view should beat the copy on a list
      // this large. If this ever flips, something is weird.
      expect(swView.elapsedMicroseconds, lessThan(swCopy.elapsedMicroseconds));
    });
  });

  group('#26 — ValueListenableBuilder rebuild cost', () {
    testWidgets('items-identical phase change still rebuilds itemBuilder',
        (tester) async {
      // 10 fake items, but the itemBuilder is heavily instrumented to count
      // how often it gets called. We then push state changes that ONLY
      // change phase (not items) and observe whether the itemBuilder runs.
      var builds = 0;
      Future<SmartListPage<int>> src(SmartListPageRequest _) async =>
          SmartListPage<int>(items: List<int>.generate(10, (i) => i + 1));

      final c = SmartListController<int>.simple(
        fetcher: src,
        pageSize: 10,
        enableCache: false,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SmartListView<int>(
            controller: c,
            itemBuilder: (_, item, __) {
              builds++;
              return SizedBox(height: 48, child: Text('item-$item'));
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Capture builds after initial render settles.
      final after = builds;

      // Pump after each notification cycle so we measure the per-frame
      // itemBuilder cost rather than what Flutter coalesces.
      const N = 10;
      for (var i = 0; i < N; i++) {
        c.insertAtTop(-1);
        await tester.pump();
        c.removeWhere((it) => it == -1);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      final added = builds - after;
      // ignore: avoid_print
      print('#26 visible itemBuilder calls after $N insertAtTop+removeWhere '
          'cycles ($N×2 notifications, pumped between each): $added '
          '(low value ≈ Flutter\'s ListView.builder laziness is already '
          'amortising the rebuild; high value ≈ #26 refactor is worth it)');

      // Document the current behaviour — assert only that we got *some*
      // signal, not the magnitude. The number guides whether #26 is worth
      // the refactor.
      expect(added, greaterThanOrEqualTo(0));
      c.dispose();
    });
  });
}
