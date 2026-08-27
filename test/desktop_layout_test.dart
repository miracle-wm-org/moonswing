import 'dart:math' as math;

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

  group('targetsInRect', () {
    final g = computeGridGeometry(const Size(300, 200), _plain); // 3x2
    final items = [_item('/a', 0, 0), _item('/b', 1, 0), _item('/c', 0, 1)];

    test('catches every cell the band touches', () {
      expect(
        targetsInRect(items, g, const Rect.fromLTRB(50, 50, 150, 150)),
        {'/a', '/b', '/c'},
      );
    });

    test('ignores cells the band does not reach', () {
      expect(
        targetsInRect(items, g, const Rect.fromLTRB(210, 10, 290, 90)),
        isEmpty,
      );
    });

    // A band is built with Rect.fromPoints, so a drag up and to the left is the
    // same rect as the drag back down and to the right.
    test('is direction-agnostic once the rect is normalized', () {
      final forward = Rect.fromPoints(const Offset(50, 50), const Offset(150, 150));
      final backward = Rect.fromPoints(const Offset(150, 150), const Offset(50, 50));
      expect(
        targetsInRect(items, g, backward),
        targetsInRect(items, g, forward),
      );
    });

    // What makes a plain click on bare desktop still clear the selection: the
    // press produces a band of no area before the pan is even recognized.
    test('a zero-area band catches nothing', () {
      expect(
        targetsInRect(items, g, Rect.fromPoints(const Offset(50, 50), const Offset(50, 50))),
        isEmpty,
      );
    });

    // Overlap is strict, so a band that stops exactly on a cell boundary has
    // not touched the cell beyond it.
    test('a band that only touches a cell edge does not catch it', () {
      expect(
        targetsInRect(items, g, const Rect.fromLTRB(100, 0, 200, 100)),
        {'/b'},
      );
    });

    // The band must select what is on screen, which for an off-grid item is
    // wherever the reflow seated it.
    test('measured against the rendered list, a stray is caught where drawn', () {
      final authored = [_item('/a', 0, 0), _item('/stray', 20, 0)];
      const whole = Rect.fromLTRB(0, 0, 300, 200);
      expect(targetsInRect(authored, g, whole), {'/a'});
      expect(
        targetsInRect(reflowIntoGrid(authored, g), g, whole),
        {'/a', '/stray'},
      );
    });
  });

  group('DesktopBandIndex', () {
    // The one that matters: the index is a *narrowing* of the scan it replaced,
    // so it has to answer identically on every band, not merely on the ones
    // somebody thought to write down. Randomised over off-grid cells (which
    // `reflowIntoGrid` leaves behind on a full grid), fractional geometries,
    // and bands aligned exactly to a cell edge — which is where the strict
    // `Rect.overlaps` semantics live.
    test('agrees with a brute-force scan on every band', () {
      final random = math.Random(20260827);
      Set<String> scan(
        List<DesktopItem> items,
        DesktopGridGeometry g,
        Rect rect,
      ) {
        if (rect.isEmpty) return const {};
        return {
          for (final item in items)
            if (g.cellRect(item.column, item.row).overlaps(rect)) item.target,
        };
      }

      for (var trial = 0; trial < 300; trial++) {
        final config = DesktopConfig(
          cellWidth: const [32.0, 96.0, 137.5][random.nextInt(3)],
          cellHeight: const [32.0, 96.0, 137.5][random.nextInt(3)],
          spacing: const [0.0, 7.5, 12.0][random.nextInt(3)],
          padding: const [0.0, 13.25, 24.0][random.nextInt(3)],
        );
        final g = computeGridGeometry(const Size(1280, 800), config);
        final items = [
          for (var i = 0; i < random.nextInt(40); i++)
            _item('/t$i', random.nextInt(28) - 3, random.nextInt(17) - 2),
        ];
        final index = DesktopBandIndex(items, g);

        for (var query = 0; query < 12; query++) {
          final Rect rect;
          if (query.isEven) {
            // Aligned to the grid, so edges land exactly on cell boundaries.
            final left = g.origin.dx + (random.nextInt(14) - 2) * g.columnPitch;
            final top = g.origin.dy + (random.nextInt(14) - 2) * g.rowPitch;
            rect = Rect.fromLTRB(
              left,
              top,
              left + [0.0, g.cellSize.width, g.columnPitch * 3][query % 3],
              top + [0.0, g.cellSize.height, g.rowPitch * 2][query % 3],
            );
          } else {
            final left = random.nextDouble() * 1600 - 200;
            final top = random.nextDouble() * 1100 - 200;
            rect = Rect.fromLTRB(
              left,
              top,
              left + random.nextDouble() * 900,
              top + random.nextDouble() * 700,
            );
          }
          expect(
            index.targetsIn(rect),
            scan(items, g, rect),
            reason: 'trial $trial, query $query, rect $rect',
          );
        }
      }
    });

    // The whole point: a band's hit test costs what it selects, not what the
    // desktop holds. A scan would examine every one of these ten thousand
    // icons on every pointer move.
    test('examines what the band crosses, not what the desktop holds', () {
      final g = computeGridGeometry(const Size(1000, 500), _plain); // 10x5
      // Far more items than cells, so most are off-grid strays — the case a
      // scan is worst at and an index has to stay indifferent to.
      final items = [
        for (var i = 0; i < 10000; i++) _item('/t$i', i % 500, i ~/ 500),
      ];
      final index = DesktopBandIndex(items, g);

      // A band over the first two cells of the first column.
      final hits = index.targetsIn(const Rect.fromLTRB(10, 10, 90, 190));
      expect(hits, {'/t0', '/t500'});
      expect(index.seatsExamined, lessThan(8));
    });

    test('a stray outside the grid is answered exactly, not clamped in', () {
      final g = computeGridGeometry(const Size(300, 200), _plain); // 3x2
      final index = DesktopBandIndex(
        [_item('/a', 0, 0), _item('/stray', 20, 0)],
        g,
      );
      expect(index.targetsIn(const Rect.fromLTRB(0, 0, 300, 200)), {'/a'});
      // Where it is actually drawn, two thousand pixels off the right edge.
      expect(
        index.targetsIn(const Rect.fromLTRB(1990, 0, 2100, 100)),
        {'/stray'},
      );
    });

    // A hand-built geometry can have no pitch to divide by; the fallback is the
    // scan, not a crash out of a pointer handler.
    test('a degenerate geometry falls back rather than dividing by zero', () {
      const g = DesktopGridGeometry(
        columns: 2,
        rows: 2,
        cellSize: Size.zero,
        spacing: 0,
        origin: Offset.zero,
      );
      final index = DesktopBandIndex([_item('/a', 0, 0)], g);
      // A zero-sized cell overlaps nothing, but the query still answers.
      expect(index.targetsIn(const Rect.fromLTRB(0, 0, 100, 100)), isEmpty);
    });

    test('an empty desktop answers without touching the arithmetic', () {
      final g = computeGridGeometry(const Size(300, 200), _plain);
      final index = DesktopBandIndex(const [], g);
      expect(index.isEmpty, isTrue);
      expect(index.targetsIn(const Rect.fromLTRB(0, 0, 300, 200)), isEmpty);
      expect(index.seatsExamined, 0);
    });
  });

  group('moveItemsBy', () {
    final g = computeGridGeometry(const Size(300, 200), _plain); // 3x2

    test('translates the whole group', () {
      final items = [_item('/a', 0, 0), _item('/b', 1, 0)];
      final next = moveItemsBy(items, {'/a', '/b'}, 1, 1, g);
      expect((next[0].column, next[0].row), (1, 1));
      expect((next[1].column, next[1].row), (2, 1));
    });

    // N=1 has to stay exactly what moveItemTo does, or dropping one icon on
    // another would stop swapping.
    test('with one target it reproduces the swap', () {
      final items = [_item('/a', 0, 0), _item('/b', 1, 0)];
      final next = moveItemsBy(items, {'/a'}, 1, 0, g);
      expect((next[0].column, next[0].row), (1, 0));
      expect((next[1].column, next[1].row), (0, 0));
    });

    test('displaces a bystander into a cell the group vacated', () {
      final items = [_item('/a', 0, 0), _item('/b', 0, 1), _item('/c', 1, 0)];
      final next = moveItemsBy(items, {'/a', '/b'}, 1, 0, g);
      final byTarget = {for (final i in next) i.target: (i.column, i.row)};
      expect(byTarget['/a'], (1, 0));
      expect(byTarget['/b'], (1, 1));
      expect(byTarget['/c'], (0, 0));
    });

    // The group slides along the edge rather than piling into it, so the
    // arrangement survives an overshoot.
    test('clamps the group rigidly at the edge', () {
      final items = [_item('/a', 0, 0), _item('/b', 1, 0)];
      final next = moveItemsBy(items, {'/a', '/b'}, 5, 0, g);
      expect((next[0].column, next[0].row), (1, 0));
      expect((next[1].column, next[1].row), (2, 0));
    });

    test('returns the identical list when the delta clamps to zero', () {
      final items = [_item('/a', 0, 0), _item('/b', 1, 0)];
      expect(identical(moveItemsBy(items, {'/a', '/b'}, -3, 0, g), items), isTrue);
    });

    test('returns the identical list for a zero delta', () {
      final items = [_item('/a', 0, 0)];
      expect(identical(moveItemsBy(items, {'/a'}, 0, 0, g), items), isTrue);
    });

    test('returns the identical list when no target matches', () {
      final items = [_item('/a', 0, 0)];
      expect(identical(moveItemsBy(items, {'/nope'}, 1, 0, g), items), isTrue);
    });

    // A group wider than the grid inverts the clamp range, which num.clamp
    // asserts on.
    test('a group wider than the grid does not throw', () {
      final items = [_item('/a', 0, 0), _item('/b', 5, 0)];
      expect(() => moveItemsBy(items, {'/a', '/b'}, 1, 0, g), returnsNormally);
    });

    test('does not mutate the input list', () {
      final items = [_item('/a', 0, 0), _item('/b', 1, 0)];
      moveItemsBy(items, {'/a', '/b'}, 1, 1, g);
      expect((items[0].column, items[0].row), (0, 0));
    });
  });
}
