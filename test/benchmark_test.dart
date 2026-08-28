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
    testWidgets('items-changing mutations rebuild itemBuilder (baseline)',
        (tester) async {
      // Every mutation changes the items reference, so the body MUST
      // rebuild. This benchmark is the unavoidable baseline — used to
      // confirm the optimisation doesn't *regress* this case.
      var builds = 0;
      Future<SmartListPage<int>> src(
        SmartListPageRequest _,
        SmartListCancelToken cancel,
      ) async =>
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
      final after = builds;

      const N = 10;
      for (var i = 0; i < N; i++) {
        c.insertAtTop(-1);
        await tester.pump();
        c.removeWhere((it) => it == -1);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // ignore: avoid_print
      print('#26 baseline (items change every notification): '
          '${builds - after} itemBuilder calls across $N×2 mutations');
      c.dispose();
    });

    testWidgets('items-unchanged notifications no longer rebuild itemBuilder',
        (tester) async {
      // The #26 win: notifications that don't change the items reference
      // (e.g. the `refreshing` phase transition during pull-to-refresh,
      // which is fired with items=value.items — same reference) should
      // not rebuild the body subtree. Pre-fix: every notification rebuilt
      // every visible item. Post-fix: `_SmartListBody._onControllerChange`
      // sees `identical(_items, s.items)` and skips setState.
      //
      // We trigger 10 refresh cycles. Each refresh fires:
      //   1. Refreshing transition: items reference UNCHANGED → filtered.
      //   2. Success after fetch: items reference CHANGES → body rebuilds.
      // So we expect ~N (≈ 10) body rebuilds, each painting ~10 items =
      // ~100 itemBuilder calls. Pre-fix would be ~2N rebuilds = ~200 calls.
      var builds = 0;
      Future<SmartListPage<int>> src(
        SmartListPageRequest _,
        SmartListCancelToken cancel,
      ) async =>
          SmartListPage<int>(items: List<int>.generate(10, (i) => i + 1));

      final c = SmartListController<int>.simple(
        fetcher: src,
        pageSize: 10,
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
      final after = builds;

      const N = 10;
      for (var i = 0; i < N; i++) {
        await c.refresh();
        await tester.pumpAndSettle();
      }

      final added = builds - after;
      // ignore: avoid_print
      print('#26 items-unchanged scenario: $added itemBuilder calls across '
          '$N refresh cycles '
          '(pre-fix would be ~2×$N×10 = ${2 * N * 10}; post-fix should '
          'be roughly half that since the `refreshing` transition is '
          'filtered out as items-unchanged)');

      // Pre-fix bound (loose): every notification triggers a full rebuild
      // of all visible items → 2 notifications × N cycles × ~10 visible
      // = ~200. Post-fix bound: only the success notifications survive
      // → ~100. Assert we're meaningfully under the pre-fix bound.
      expect(added, lessThan(2 * N * 10),
          reason: 'post-fix: items-unchanged notifications must not '
              'rebuild the body subtree');
      c.dispose();
    });
  });
}
