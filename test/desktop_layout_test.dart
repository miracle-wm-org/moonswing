import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/desktop_layout.dart';

/// A grid whose arithmetic is easy to do in your head: 100px cells, no spacing,
/// no padding, so cell (c, r) is exactly at (100c, 100r).
const DesktopConfig _plain = DesktopConfig(
  enabled: true,
  cellWidth: 100,
  cellHeight: 100,
  spacing: 0,
  padding: 0,
);

DesktopItem _item(String target, int column, int row) => DesktopItem(
      kind: DesktopItemKind.file,
      target: target,
      column: column,
      row: row,
    );

void main() {
  group('panelInsetsFor', () {
    test('applies each panel to the edge its anchor names', () {
      final insets = panelInsetsFor(const {
        'top': PanelConfig(anchor: 'top', height: 32),
        'bottom': PanelConfig(anchor: 'bottom', height: 40),
        'left': PanelConfig(anchor: 'left', height: 48),
        'right': PanelConfig(anchor: 'right', height: 56),
      }, 0);
      expect(insets, const EdgeInsets.fromLTRB(48, 32, 56, 40));
    });

    // Per wlr-layer-shell the exclusive zone includes the margin, so a floating
    // bar reserves height + margin and the grid must clear both.
    test('adds the theme panel margin to each panel it insets', () {
      final insets = panelInsetsFor(
        const {'top': PanelConfig(anchor: 'top', height: 32)},
        8,
      );
      expect(insets.top, 40);
    });

    test('two panels on the same edge stack', () {
      final insets = panelInsetsFor(const {
        'a': PanelConfig(anchor: 'top', height: 32),
        'b': PanelConfig(anchor: 'top', height: 24),
      }, 0);
      expect(insets.top, 56);
    });

    test('no panels means no inset', () {
      expect(panelInsetsFor(const {}, 8), EdgeInsets.zero);
    });
  });

  group('computeGridGeometry', () {
    test('derives column and row counts from the surface', () {
      final g = computeGridGeometry(const Size(1000, 500), _plain);
      expect(g.columns, 10);
      expect(g.rows, 5);
      expect(g.capacity, 50);
    });

    // N cells occupy N*pitch - spacing, so the last cell needs no trailing gap.
    test('the trailing cell needs no spacing after it', () {
      const config = DesktopConfig(cellWidth: 100, spacing: 10, padding: 0);
      // 3 columns need 100+10+100+10+100 = 320, not 330.
      final g = computeGridGeometry(const Size(320, 1000), config);
      expect(g.columns, 3);
      expect(computeGridGeometry(const Size(319, 1000), config).columns, 2);
    });

    test('insets and padding both shrink the usable area and move the origin',
        () {
      const config = DesktopConfig(
        cellWidth: 100,
        cellHeight: 100,
        spacing: 0,
        padding: 20,
      );
      final g = computeGridGeometry(
        const Size(1000, 500),
        config,
        insets: const EdgeInsets.fromLTRB(0, 100, 0, 0),
      );
      // Width 1000 - 2*20 = 960 -> 9 columns; height 500 - 100 - 40 = 360 -> 3.
      expect(g.columns, 9);
      expect(g.rows, 3);
      expect(g.origin, const Offset(20, 120));
    });

    // A grid with no cells has no valid drop target and every placement helper
    // would return null forever.
    test('never yields a grid with zero cells', () {
      final g = computeGridGeometry(const Size(1, 1), _plain);
      expect(g.columns, 1);
      expect(g.rows, 1);
    });

    test('cellRect steps by cell size plus spacing', () {
      const config = DesktopConfig(
        cellWidth: 100,
        cellHeight: 80,
        spacing: 10,
        padding: 5,
      );
      final g = computeGridGeometry(const Size(2000, 2000), config);
      expect(g.cellRect(0, 0), const Rect.fromLTWH(5, 5, 100, 80));
      expect(g.cellRect(2, 3), const Rect.fromLTWH(225, 275, 100, 80));
    });
  });

  group('cellAt', () {
    final g = computeGridGeometry(const Size(1000, 500), _plain);

    test('resolves a point inside a cell', () {
      expect(cellAt(g, const Offset(150, 250)), (column: 1, row: 2));
      expect(cellAt(g, const Offset(0, 0)), (column: 0, row: 0));
    });

    test('returns null outside the grid', () {
      expect(cellAt(g, const Offset(-1, 10)), isNull);
      expect(cellAt(g, const Offset(10, -1)), isNull);
      expect(cellAt(g, const Offset(1200, 10)), isNull);
      expect(cellAt(g, const Offset(10, 700)), isNull);
    });

    test('returns null in the gutter between cells', () {
      const spaced = DesktopConfig(
        cellWidth: 100,
        cellHeight: 100,
        spacing: 20,
        padding: 0,
      );
      final gapped = computeGridGeometry(const Size(1000, 1000), spaced);
      expect(cellAt(gapped, const Offset(110, 50)), isNull);
      expect(cellAt(gapped, const Offset(50, 110)), isNull);
      expect(cellAt(gapped, const Offset(130, 50)), (column: 1, row: 0));
    });
  });

  group('nearestCell', () {
    final g = computeGridGeometry(const Size(1000, 500), _plain);

    test('is total: clamps at every edge and beyond every corner', () {
      expect(nearestCell(g, const Offset(-500, -500)), (column: 0, row: 0));
      expect(nearestCell(g, const Offset(9999, 9999)), (column: 9, row: 4));
      expect(nearestCell(g, const Offset(-500, 250)), (column: 0, row: 2));
      expect(nearestCell(g, const Offset(9999, 250)), (column: 9, row: 2));
    });

    test('agrees with cellAt for points inside a cell', () {
      expect(nearestCell(g, const Offset(350, 150)), (column: 3, row: 1));
    });
  });

  group('firstFreeCell', () {
    final g = computeGridGeometry(const Size(300, 200), _plain); // 3x2

    test('flows down a column before moving across', () {
      expect(firstFreeCell(g, {}), (column: 0, row: 0));
      expect(
        firstFreeCell(g, {(column: 0, row: 0)}),
        (column: 0, row: 1),
      );
      expect(
        firstFreeCell(g, {(column: 0, row: 0), (column: 0, row: 1)}),
        (column: 1, row: 0),
      );
    });

    test('returns null when the grid is full', () {
      final all = <GridCell>{
        for (var c = 0; c < g.columns; c++)
          for (var r = 0; r < g.rows; r++) (column: c, row: r),
      };
      expect(firstFreeCell(g, all), isNull);
    });
  });

  group('nearestFreeCell', () {
    final g = computeGridGeometry(const Size(1000, 500), _plain);

    test('returns the preferred cell when it is free', () {
      expect(
        nearestFreeCell(g, {}, (column: 4, row: 2)),
        (column: 4, row: 2),
      );
    });

    test('is deterministic around an occupied preferred cell', () {
      const preferred = (column: 4, row: 2);
      final result = nearestFreeCell(g, {preferred}, preferred);
      // Distance 1 in all four directions; column-major tie-break picks the
      // lowest column, then the lowest row.
      expect(result, (column: 3, row: 2));
      expect(nearestFreeCell(g, {preferred}, preferred), result);
    });

    test('an out-of-range preference still lands inside the grid', () {
      final result = nearestFreeCell(g, {}, (column: 99, row: 99))!;
      expect(g.contains(result), isTrue);
      expect(result, (column: 9, row: 4));
    });

    test('returns null when the grid is full', () {
      final all = <GridCell>{
        for (var c = 0; c < g.columns; c++)
          for (var r = 0; r < g.rows; r++) (column: c, row: r),
      };
      expect(nearestFreeCell(g, all, (column: 0, row: 0)), isNull);
    });
  });

  group('moveItemTo', () {
    test('moves into a free cell', () {
      final items = [_item('/a', 0, 0), _item('/b', 1, 1)];
      final moved = moveItemTo(items, '/a', (column: 2, row: 2));
      final a = moved.firstWhere((i) => i.target == '/a');
      expect((a.column, a.row), (2, 2));
      expect(moved, hasLength(2));
    });

    // The headline behaviour: dropping one icon on another must not stack them.
    test('swaps with the occupant, moving both', () {
      final items = [_item('/a', 0, 0), _item('/b', 3, 1)];
      final moved = moveItemTo(items, '/a', (column: 3, row: 1));
      final a = moved.firstWhere((i) => i.target == '/a');
      final b = moved.firstWhere((i) => i.target == '/b');
      expect((a.column, a.row), (3, 1));
      expect((b.column, b.row), (0, 0));
    });

    // Callers skip the config write on an identical instance, so a drag that
    // ends where it started must cost nothing.
    test('returns the identical list for a no-op move', () {
      final items = [_item('/a', 2, 2)];
      expect(identical(moveItemTo(items, '/a', (column: 2, row: 2)), items),
          isTrue);
    });

    test('returns the identical list for an unknown target', () {
      final items = [_item('/a', 0, 0)];
      expect(
          identical(moveItemTo(items, '/nope', (column: 1, row: 1)), items),
          isTrue);
    });

    test('does not mutate the input list', () {
      final items = [_item('/a', 0, 0), _item('/b', 1, 0)];
      moveItemTo(items, '/a', (column: 1, row: 0));
      expect(items[0].column, 0);
      expect(items[1].column, 1);
    });
  });

  group('placeItem', () {
    final g = computeGridGeometry(const Size(300, 200), _plain); // 3x2

    test('honours the requested cell when it is free', () {
      final placed = placeItem([_item('/a', 0, 0)], _item('/b', 2, 1), g);
      final b = placed.firstWhere((i) => i.target == '/b');
      expect((b.column, b.row), (2, 1));
    });

    test('never displaces: an occupied request lands nearby instead', () {
      final items = [_item('/a', 0, 0)];
      final placed = placeItem(items, _item('/b', 0, 0), g);
      final a = placed.firstWhere((i) => i.target == '/a');
      final b = placed.firstWhere((i) => i.target == '/b');
      expect((a.column, a.row), (0, 0));
      expect((b.column, b.row), isNot((0, 0)));
    });

    test('ignores a target that is already pinned', () {
      final items = [_item('/a', 0, 0)];
      expect(identical(placeItem(items, _item('/a', 2, 1), g), items), isTrue);
    });

    test('returns the list unchanged when the grid is full', () {
      final full = [
        for (var c = 0; c < g.columns; c++)
          for (var r = 0; r < g.rows; r++) _item('/$c-$r', c, r),
      ];
      expect(identical(placeItem(full, _item('/new', 0, 0), g), full), isTrue);
    });
  });

  group('organizeItems', () {
    final g = computeGridGeometry(const Size(300, 200), _plain); // 3 cols, 2 rows

    test('compacts column-major, preserving reading order', () {
      final items = [
        _item('/c', 2, 1),
        _item('/a', 0, 0),
        _item('/b', 1, 0),
      ];
      final organized = organizeItems(items, g);
      Map<String, (int, int)> cells() => {
            for (final i in organized) i.target: (i.column, i.row),
          };
      // Column-major on a 2-row grid: the second item fills down to (0, 1)
      // before the third starts a new column.
      expect(cells()['/a'], (0, 0));
      expect(cells()['/b'], (0, 1));
      expect(cells()['/c'], (1, 0));
    });

    test('is idempotent', () {
      final items = [
        _item('/c', 2, 1),
        _item('/a', 0, 0),
        _item('/b', 1, 0),
      ];
      final once = organizeItems(items, g);
      final twice = organizeItems(once, g);
      expect(
        twice.map((i) => (i.target, i.column, i.row)),
        once.map((i) => (i.target, i.column, i.row)),
      );
    });

    // Losing a pinned icon to a resize would be unforgivable, so overflow flows
    // into further columns rather than being dropped.
    test('keeps every item even past capacity', () {
      final items = [for (var i = 0; i < 10; i++) _item('/$i', 0, i)];
      final organized = organizeItems(items, g);
      expect(organized, hasLength(10));
      expect(organized.map((i) => i.target).toSet(), hasLength(10));
    });

    test('breaks ties on document order, not sort instability', () {
      final items = [
        _item('/second', 0, 0),
        _item('/first', 0, 0),
      ];
      final organized = organizeItems(items, g);
      expect(organized.first.target, '/second');
    });
  });

  group('reflowIntoGrid', () {
    final g = computeGridGeometry(const Size(300, 200), _plain); // 3x2

    test('returns the identical list when everything already fits', () {
      final items = [_item('/a', 0, 0), _item('/b', 2, 1)];
      expect(identical(reflowIntoGrid(items, g), items), isTrue);
    });

    // The same item list renders on a 4K and a 1080p monitor; a cell the small
    // one does not have must still show its icon.
    test('pulls an out-of-range item into a free cell without colliding', () {
      final items = [_item('/a', 0, 0), _item('/stray', 20, 0)];
      final reflowed = reflowIntoGrid(items, g);
      final stray = reflowed.firstWhere((i) => i.target == '/stray');
      expect(g.contains((column: stray.column, row: stray.row)), isTrue);
      expect((stray.column, stray.row), isNot((0, 0)));
      expect(reflowed, hasLength(2));
    });

    test('does not mutate the input, so the authored cell survives', () {
      final items = [_item('/stray', 20, 0)];
      reflowIntoGrid(items, g);
      expect(items.single.column, 20);
    });

    test('keeps a stray when there is nowhere to put it', () {
      final full = [
        for (var c = 0; c < g.columns; c++)
          for (var r = 0; r < g.rows; r++) _item('/$c-$r', c, r),
      ];
      final reflowed = reflowIntoGrid([...full, _item('/stray', 9, 9)], g);
      expect(reflowed, hasLength(full.length + 1));
    });
  });
}
