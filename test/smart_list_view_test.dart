import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_list/smart_list.dart';

Future<SmartListPage<int>> _source(SmartListPageRequest req, SmartListCancelToken cancel) async {
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
    Future<SmartListPage<int>> slowSource(SmartListPageRequest req, SmartListCancelToken cancel) async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return _source(req, cancel);
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
    Future<SmartListPage<int>> emptySrc(SmartListPageRequest _, SmartListCancelToken cancel) async =>
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
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.physics, isA<AlwaysScrollableScrollPhysics>());
    c.dispose();
  });

  testWidgets('renders error state with retry button', (tester) async {
    var calls = 0;
    Future<SmartListPage<int>> failingSrc(SmartListPageRequest _, SmartListCancelToken cancel) async {
      calls++;
      if (calls == 1) throw StateError('boom');
      return const SmartListPage(items: [1, 2, 3], hasMore: false);
    }

    final c = SmartListController<int>(
      fetcher: failingSrc,
      strategyBuilder: () => PagePaginationStrategy<int>(pageSize: 10),
      retryPolicy: RetryPolicy.none(),
      enableCache: false,
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
    Future<SmartListPage<int>> src(SmartListPageRequest req, SmartListCancelToken cancel) async {
      if (req.query == null) {
        return SmartListPage<int>(items: const [1, 2, 3], hasMore: false);
      }
      return const SmartListPage(items: [], hasMore: false);
    }

    final c = SmartListController<int>(
      fetcher: src,
      strategyBuilder: () => PagePaginationStrategy<int>(pageSize: 10),
      searchDebounce: Duration.zero,
      enableCache: false,
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

  testWidgets('SmartListSliver loads items in a CustomScrollView',
      (tester) async {
    final c = SmartListController<int>.simple(
      fetcher: _source,
      pageSize: 10,
      enableCache: false,
    );
    await tester.pumpWidget(
      _wrap(
        CustomScrollView(
          slivers: [
            SmartListSliver<int>(
              controller: c,
              itemBuilder: (_, item, __) => Text('s-$item'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('s-1'), findsOneWidget);
    c.dispose();
  });
}
