import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/modules/dock.dart';

void main() {
  group('dockDropIndex', () {
    test('snaps to the nearest slot', () {
      expect(dockDropIndex(0, 32, 4), 0);
      expect(dockDropIndex(15, 32, 4), 0);
      expect(dockDropIndex(17, 32, 4), 1);
      expect(dockDropIndex(64, 32, 4), 2);
    });

    test('clamps to the ends', () {
      expect(dockDropIndex(-500, 32, 4), 0);
      expect(dockDropIndex(500, 32, 4), 3);
    });

    test('is a no-op for a degenerate row', () {
      expect(dockDropIndex(99, 32, 1), 0);
      expect(dockDropIndex(99, 0, 4), 0);
    });
  });

  group('moveDockItem', () {
    test('shifts the rest along', () {
      expect(moveDockItem(['a', 'b', 'c', 'd'], 0, 2), ['b', 'c', 'a', 'd']);
      expect(moveDockItem(['a', 'b', 'c', 'd'], 3, 1), ['a', 'd', 'b', 'c']);
    });

    test('leaves the list alone when the slot is unchanged', () {
      expect(moveDockItem(['a', 'b', 'c'], 1, 1), ['a', 'b', 'c']);
    });

    test('does not mutate its input', () {
      final items = ['a', 'b', 'c'];
      moveDockItem(items, 0, 2);
      expect(items, ['a', 'b', 'c']);
    });
  });

  group('mergeDockOrder', () {
    test('applies the new order when every id resolved', () {
      expect(
        mergeDockOrder(['a', 'b', 'c'], ['c', 'a', 'b']),
        ['c', 'a', 'b'],
      );
    });

    test('pins unresolved ids to their original index', () {
      // 'gone' never renders, so the user could not have moved it.
      expect(
        mergeDockOrder(['a', 'gone', 'b', 'c'], ['c', 'b', 'a']),
        ['c', 'gone', 'b', 'a'],
      );
      expect(
        mergeDockOrder(['gone', 'a', 'b'], ['b', 'a']),
        ['gone', 'b', 'a'],
      );
    });

    test('falls back to the new order when the counts disagree', () {
      // A stale config read (an id added or dropped mid-gesture) must not
      // produce a list with holes.
      expect(mergeDockOrder(['a', 'b'], ['a', 'b', 'c']), ['a', 'b', 'c']);
    });
  });
}
