import 'package:flutter_test/flutter_test.dart';
import 'package:smart_list/smart_list.dart';

void main() {
  group('PagePaginationStrategy', () {
    test('initialRequest starts at page 1 by default', () {
      final s = PagePaginationStrategy<int>(pageSize: 10);
      final req = s.initialRequest();
      expect(req.page, 1);
      expect(req.pageSize, 10);
      expect(req.offset, 0);
    });

    test('respects custom initialPage', () {
      final s = PagePaginationStrategy<int>(pageSize: 10, initialPage: 0);
      expect(s.initialRequest().page, 0);
    });

    test('nextRequest increments page when more available', () {
      final s = PagePaginationStrategy<int>(pageSize: 3);
      s.initialRequest();
      final next = s.nextRequest(
        SmartListPage<int>(items: const [1, 2, 3], hasMore: true),
      );
      expect(next, isNotNull);
      expect(next!.page, 2);
      expect(next.offset, 3);
    });

    test('nextRequest returns null when short page is received', () {
      final s = PagePaginationStrategy<int>(pageSize: 5);
      s.initialRequest();
      // Only 2 of 5 items returned → end of list.
      final next = s.nextRequest(
        SmartListPage<int>(items: const [1, 2]),
      );
      expect(next, isNull);
    });

    test('hasMore=false short-circuits even on full page', () {
      final s = PagePaginationStrategy<int>(pageSize: 3);
      s.initialRequest();
      final next = s.nextRequest(
        SmartListPage<int>(items: const [1, 2, 3], hasMore: false),
      );
      expect(next, isNull);
    });

    test('reset returns to initialPage', () {
      final s = PagePaginationStrategy<int>(pageSize: 3, initialPage: 1);
      s.initialRequest();
      s.nextRequest(SmartListPage<int>(items: const [1, 2, 3], hasMore: true));
      s.reset();
      expect(s.initialRequest().page, 1);
    });
  });

  group('CursorPaginationStrategy', () {
    test('initial request has no cursor', () {
      final s = CursorPaginationStrategy<int>();
      expect(s.initialRequest().cursor, isNull);
    });

    test('next request uses prior nextCursor', () {
      final s = CursorPaginationStrategy<int>(pageSize: 5);
      s.initialRequest();
      final next = s.nextRequest(
        SmartListPage<int>(items: const [1, 2], nextCursor: 'cursor-2'),
      );
      expect(next, isNotNull);
      expect(next!.cursor, 'cursor-2');
      expect(next.page, 2);
    });

    test('null nextCursor signals end-of-list', () {
      final s = CursorPaginationStrategy<int>();
      s.initialRequest();
      final next = s.nextRequest(
        SmartListPage<int>(items: const [1, 2], nextCursor: null),
      );
      expect(next, isNull);
    });

    test('explicit hasMore=true overrides null cursor', () {
      final s = CursorPaginationStrategy<int>();
      s.initialRequest();
      final next = s.nextRequest(
        SmartListPage<int>(items: const [1], hasMore: true, nextCursor: null),
      );
      expect(next, isNotNull);
    });
  });

  group('OffsetPaginationStrategy', () {
    test('offsets advance by items.length', () {
      final s = OffsetPaginationStrategy<int>(pageSize: 4);
      s.initialRequest();
      final next = s.nextRequest(
        SmartListPage<int>(items: const [1, 2, 3, 4], hasMore: true),
      );
      expect(next!.offset, 4);
      final next2 = s.nextRequest(
        SmartListPage<int>(items: const [5, 6, 7, 8], hasMore: true),
      );
      expect(next2!.offset, 8);
    });

    test('empty page ends pagination', () {
      final s = OffsetPaginationStrategy<int>(pageSize: 4);
      s.initialRequest();
      expect(
        s.nextRequest(SmartListPage<int>(items: const [])),
        isNull,
      );
    });
  });
}
