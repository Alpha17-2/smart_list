import 'package:flutter_test/flutter_test.dart';
import 'package:smart_list/src/widgets/load_more_gate.dart';

void main() {
  test('fires once when entering the threshold zone', () {
    final g = LoadMoreGate();
    expect(g.shouldLoadMore(500, 240), isFalse);
    expect(g.shouldLoadMore(200, 240), isTrue);
    expect(g.shouldLoadMore(100, 240), isFalse);
    expect(g.shouldLoadMore(50, 240), isFalse);
  });

  test('fires again after leaving and re-entering the zone', () {
    final g = LoadMoreGate();
    expect(g.shouldLoadMore(100, 240), isTrue);
    expect(g.shouldLoadMore(400, 240), isFalse);
    expect(g.shouldLoadMore(100, 240), isTrue);
  });
}
