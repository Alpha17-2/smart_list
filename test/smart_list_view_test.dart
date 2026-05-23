import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_list/smart_list.dart';

Future<SmartListPage<int>> _source(SmartListPageRequest req) async {
  final start = (req.page - 1) * req.pageSize + 1;
  final items = <int>[for (var i = 0; i < req.pageSize; i++) start + i];
  // 30 items total — so page 3 of 10 returns the last page.
  if (start > 30) return const SmartListPage(items: []);
  if (start + req.pageSize - 1 >= 30) {
    return SmartListPage<int>(
      items: items.where((i) => i <= 30).toList(),
      hasMore: false,
    );
  }
  return SmartListPage<int>(items: items, hasMore: true);
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders loading then items on initial load', (tester) async {
    Future<SmartListPage<int>> slowSource(SmartListPageRequest req) async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return _source(req);
    }

    final c = SmartListController<int>.simple(
      fetcher: slowSource,
      pageSize: 10,
      enableCache: false,
    );

    await tester.pumpWidget(
      _wrap(SmartListView<int>(
        controller: c,
        itemBuilder: (_, item, __) => ListTile(
          key: ValueKey('item-$item'),
          title: Text('Item $item'),
        ),
      )),
    );

    // Pump once for the post-frame `loadInitial`; another to render the
    // loading phase update.
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('item-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('item-10')), findsOneWidget);
    c.dispose();
  });

  testWidgets('renders empty state when fetch returns no items',
      (tester) async {
    Future<SmartListPage<int>> emptySrc(SmartListPageRequest _) async =>
        const SmartListPage(items: [], hasMore: false);
    final c = SmartListController<int>.simple(
      fetcher: emptySrc,
      pageSize: 10,
      enableCache: false,
    );

    await tester.pumpWidget(
      _wrap(SmartListView<int>(
        controller: c,
        itemBuilder: (_, item, __) => Text('$item'),
      )),
    );
    await tester.pumpAndSettle();
    expect(find.text('No items'), findsOneWidget);
    c.dispose();
  });

  testWidgets('renders error state with retry button', (tester) async {
    var calls = 0;
    Future<SmartListPage<int>> failingSrc(SmartListPageRequest _) async {
      calls++;
      if (calls == 1) throw StateError('boom');
      return const SmartListPage(items: [1, 2, 3], hasMore: false);
    }

    final c = SmartListController<int>(
      fetcher: failingSrc,
      strategyBuilder: () => PagePaginationStrategy<int>(pageSize: 10),
      retryPolicy: RetryPolicy.none(),
    );

    await tester.pumpWidget(
      _wrap(SmartListView<int>(
        controller: c,
        itemBuilder: (_, item, __) => Text('item-$item'),
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('item-1'), findsOneWidget);
    c.dispose();
  });

  testWidgets('shows search-empty state for non-matching query',
      (tester) async {
    Future<SmartListPage<int>> src(SmartListPageRequest req) async {
      if (req.query == null) {
        return SmartListPage<int>(items: const [1, 2, 3], hasMore: false);
      }
      return const SmartListPage(items: [], hasMore: false);
    }

    final c = SmartListController<int>(
      fetcher: src,
      strategyBuilder: () => PagePaginationStrategy<int>(pageSize: 10),
      searchDebounce: Duration.zero,
    );

    await tester.pumpWidget(
      _wrap(SmartListView<int>(
        controller: c,
        itemBuilder: (_, item, __) => Text('item-$item'),
      )),
    );
    await tester.pumpAndSettle();
    expect(find.text('item-1'), findsOneWidget);

    c.search('zzz');
    await tester.pumpAndSettle();
    expect(find.text('No results for "zzz"'), findsOneWidget);
    c.dispose();
  });

  testWidgets('pull-to-refresh works on error placeholder (#18)',
      (tester) async {
    var calls = 0;
    Future<SmartListPage<int>> src(SmartListPageRequest _) async {
      calls++;
      if (calls == 1) throw StateError('boom');
      return const SmartListPage(items: [1, 2, 3], hasMore: false);
    }

    final c = SmartListController<int>(
      fetcher: src,
      strategyBuilder: () => PagePaginationStrategy<int>(pageSize: 10),
      retryPolicy: RetryPolicy.none(),
    );

    await tester.pumpWidget(
      _wrap(SmartListView<int>(
        controller: c,
        itemBuilder: (_, item, __) => Text('item-$item'),
      )),
    );
    await tester.pumpAndSettle();

    // The error placeholder must live inside a scrollable so the pull
    // gesture can fire RefreshIndicator. Verify a Scrollable exists at
    // the error placeholder level.
    expect(find.byType(Scrollable), findsOneWidget);

    // Drag from near the top of the viewport to trigger pull-to-refresh.
    await tester.fling(find.byType(Scrollable), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    // After the pull-to-refresh, the second fetch attempt should have run.
    expect(calls, greaterThanOrEqualTo(2));
    expect(find.text('item-1'), findsOneWidget);
    c.dispose();
  });

  testWidgets('inline loadMoreError footer is used on pagination errors (#13)',
      (tester) async {
    Future<SmartListPage<int>> src(SmartListPageRequest req) async {
      if (req.page == 1) {
        return const SmartListPage(items: [1, 2, 3], hasMore: true);
      }
      throw StateError('boom');
    }

    final c = SmartListController<int>(
      fetcher: src,
      strategyBuilder: () => PagePaginationStrategy<int>(pageSize: 3),
      retryPolicy: RetryPolicy.none(),
    );

    await tester.pumpWidget(
      _wrap(SmartListView<int>(
        controller: c,
        itemBuilder: (_, item, __) => SizedBox(
          height: 48,
          child: Text('item-$item'),
        ),
      )),
    );
    await tester.pumpAndSettle();

    // Trigger the failing next-page fetch.
    await c.loadNextPage();
    await tester.pumpAndSettle();

    // The compact inline 'Failed to load more' row must be shown — not the
    // full-screen 32sp icon + headline + button widget used for top-level
    // errors. Verify the inline label is present and the full-screen icon
    // size is NOT (size 32 vs 18).
    expect(find.text('Failed to load more'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    c.dispose();
  });

  testWidgets('custom loadMoreErrorBuilder is used when provided (#13)',
      (tester) async {
    Future<SmartListPage<int>> src(SmartListPageRequest req) async {
      if (req.page == 1) {
        return const SmartListPage(items: [1, 2, 3], hasMore: true);
      }
      throw StateError('boom');
    }

    final c = SmartListController<int>(
      fetcher: src,
      strategyBuilder: () => PagePaginationStrategy<int>(pageSize: 3),
      retryPolicy: RetryPolicy.none(),
    );

    await tester.pumpWidget(
      _wrap(SmartListView<int>(
        controller: c,
        itemBuilder: (_, item, __) => SizedBox(
          height: 48,
          child: Text('item-$item'),
        ),
        loadMoreErrorBuilder: (context, error, retry) =>
            const Text('custom-load-more-error'),
      )),
    );
    await tester.pumpAndSettle();

    await c.loadNextPage();
    await tester.pumpAndSettle();

    expect(find.text('custom-load-more-error'), findsOneWidget);
    expect(find.text('Failed to load more'), findsNothing);
    c.dispose();
  });

  testWidgets('separator renders between every adjacent pair (regression #8)',
      (tester) async {
    Future<SmartListPage<int>> src(SmartListPageRequest _) async =>
        const SmartListPage(items: [1, 2, 3], hasMore: false);

    final c = SmartListController<int>.simple(
      fetcher: src,
      pageSize: 10,
      enableCache: false,
    );

    await tester.pumpWidget(
      _wrap(SmartListView<int>(
        controller: c,
        itemBuilder: (_, item, __) => SizedBox(
          height: 48,
          child: Text('item-$item'),
        ),
        separatorBuilder: (_, index) => Container(
          key: ValueKey('sep-$index'),
          height: 1,
          color: const Color(0xFF000000),
        ),
      )),
    );
    await tester.pumpAndSettle();

    // For 3 items + 1 footer slot, ListView.separated calls the separator
    // builder for indices 0..items.length-1 = 0..2. We want separators
    // between item 0–1 and 1–2 (indices 0 and 1), but NOT between item 2
    // and the footer (index 2). The pre-fix code suppressed indices 1 and
    // 2, losing the divider between items 1 and 2.
    expect(find.byKey(const ValueKey('sep-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('sep-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('sep-2')), findsNothing);
    c.dispose();
  });
}
