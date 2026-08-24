import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/desktop_layout.dart';

/// A 4x3 grid of 100px cells with no spacing or padding, so a cell's pixel
/// rect is its coordinates times 100 and the arithmetic is checkable by eye.
final DesktopGridGeometry _grid = computeGridGeometry(
  const Size(400, 300),
  const DesktopConfig(cellWidth: 100, cellHeight: 100, spacing: 0, padding: 0),
);

DesktopWidgetItem _widget(
  String id, {
  int column = 0,
  int row = 0,
  int columnSpan = 2,
  int rowSpan = 1,
}) =>
    DesktopWidgetItem(
      id: id,
      type: 'media_player',
      column: column,
      row: row,
      columnSpan: columnSpan,
      rowSpan: rowSpan,
    );

DesktopItem _item(String target, {int column = 0, int row = 0}) => DesktopItem(
      kind: DesktopItemKind.file,
      target: target,
      column: column,
      row: row,
    );

const GridSpan _min = (columns: 2, rows: 1);
const GridSpan _max = (columns: 4, rows: 3);

void main() {
  group('geometry', () {
    test('a span swallows the gutters it crosses', () {
      final spaced = computeGridGeometry(
        const Size(400, 300),
        const DesktopConfig(
          cellWidth: 90,
          cellHeight: 90,
          spacing: 10,
          padding: 0,
        ),
      );
      // Two 90px cells plus the one 10px gap between them: the widget is one
      // surface, not two tiles that happen to touch.
      final rect = spaced.areaRect(
        (column: 0, row: 0, columnSpan: 2, rowSpan: 1),
      );
      expect(rect, const Rect.fromLTWH(0, 0, 190, 90));
    });

    test('containsArea rejects a span that runs off the edge', () {
      expect(
        _grid.containsArea((column: 2, row: 0, columnSpan: 2, rowSpan: 1)),
        isTrue,
      );
      expect(
        _grid.containsArea((column: 3, row: 0, columnSpan: 2, rowSpan: 1)),
        isFalse,
      );
      expect(
        _grid.containsArea((column: 0, row: 2, columnSpan: 1, rowSpan: 2)),
        isFalse,
      );
    });

    test('cellsOfArea enumerates the rectangle', () {
      expect(
        cellsOfArea((column: 1, row: 1, columnSpan: 2, rowSpan: 2)),
        {
          (column: 1, row: 1),
          (column: 1, row: 2),
          (column: 2, row: 1),
          (column: 2, row: 2),
        },
      );
    });

    test('widgetCells can ignore one widget, which is what makes a move legal',
        () {
      final widgets = [_widget('a'), _widget('b', column: 2)];
      expect(widgetCells(widgets).length, 4);
      expect(widgetCells(widgets, ignoreId: 'a'), {
        (column: 2, row: 0),
        (column: 3, row: 0),
      });
    });
  });

  group('placement', () {
    test('nearestFreeArea takes the wanted area when it is free', () {
      final area = nearestFreeArea(
        (column: 1, row: 1, columnSpan: 2, rowSpan: 1),
        _grid,
        const {},
      );
      expect(area, (column: 1, row: 1, columnSpan: 2, rowSpan: 1));
    });

    test('nearestFreeArea slides off an occupied one, ties column-major', () {
      final occupied = widgetCells([_widget('a')]);
      final area = nearestFreeArea(
        (column: 0, row: 0, columnSpan: 2, rowSpan: 1),
        _grid,
        occupied,
      );
      expect(area, (column: 0, row: 1, columnSpan: 2, rowSpan: 1));
    });

    test('nearestFreeArea shrinks a span too big for the grid', () {
      final area = nearestFreeArea(
        (column: 0, row: 0, columnSpan: 9, rowSpan: 9),
        _grid,
        const {},
      );
      expect(area, (column: 0, row: 0, columnSpan: 4, rowSpan: 3));
    });

    test('nearestFreeArea answers null when nothing of that size fits', () {
      final occupied = {
        for (var c = 0; c < 4; c++)
          for (var r = 0; r < 3; r++) (column: c, row: r),
      };
      expect(
        nearestFreeArea(
          (column: 0, row: 0, columnSpan: 2, rowSpan: 1),
          _grid,
          occupied,
        ),
        isNull,
      );
    });

    test('placeWidget appends, and refuses a duplicate id', () {
      final placed = placeWidget(const [], _widget('a'), _grid);
      expect(placed.single.id, 'a');
      expect(
        identical(placeWidget(placed, _widget('a', row: 2), _grid), placed),
        isTrue,
      );
    });

    test('placeWidget puts a second widget beside the first', () {
      var widgets = placeWidget(const [], _widget('a'), _grid);
      widgets = placeWidget(widgets, _widget('b'), _grid);
      expect(widgets.last.row, 1);
      expect(widgets.last.column, 0);
    });
  });

  group('moveWidgetTo', () {
    test('moves and clamps into the grid', () {
      final widgets = moveWidgetTo(
        [_widget('a')],
        'a',
        (column: 3, row: 2),
        _grid,
      );
      // A 2x1 cannot start in the last column: the clamp keeps it on screen
      // rather than letting half of it fall off.
      expect(widgets.single.column, 2);
      expect(widgets.single.row, 2);
    });

    test('refuses a move onto another widget, with no write', () {
      final widgets = [_widget('a'), _widget('b', row: 1)];
      expect(
        identical(moveWidgetTo(widgets, 'b', (column: 0, row: 0), _grid),
            widgets),
        isTrue,
      );
    });

    test('a move to the cell it already holds is a no-op', () {
      final widgets = [_widget('a')];
      expect(
        identical(moveWidgetTo(widgets, 'a', (column: 0, row: 0), _grid),
            widgets),
        isTrue,
      );
    });
  });

  group('resizeWidgetTo', () {
    test('clamps the span to the type limits', () {
      final widgets = resizeWidgetTo(
        [_widget('a')],
        'a',
        (column: 0, row: 0, columnSpan: 1, rowSpan: 9),
        _grid,
        minSpan: _min,
        maxSpan: _max,
      );
      expect(widgets.single.columnSpan, 2);
      expect(widgets.single.rowSpan, 3);
    });

    test('carries the origin, so a top-left drag moves the corner', () {
      final widgets = resizeWidgetTo(
        [_widget('a', column: 2, row: 2)],
        'a',
        (column: 1, row: 1, columnSpan: 3, rowSpan: 2),
        _grid,
        minSpan: _min,
        maxSpan: _max,
      );
      expect(widgets.single.column, 1);
      expect(widgets.single.row, 1);
      expect(widgets.single.columnSpan, 3);
    });

    test('refuses a resize that would swallow another widget', () {
      final widgets = [_widget('a'), _widget('b', column: 2)];
      expect(
        identical(
          resizeWidgetTo(
            widgets,
            'a',
            (column: 0, row: 0, columnSpan: 4, rowSpan: 1),
            _grid,
            minSpan: _min,
            maxSpan: _max,
          ),
          widgets,
        ),
        isTrue,
      );
    });
  });

  group('reflowWidgetsIntoGrid', () {
    test('leaves a fitting layout identical', () {
      final widgets = [_widget('a'), _widget('b', row: 1)];
      expect(identical(reflowWidgetsIntoGrid(widgets, _grid), widgets), isTrue);
    });

    test('pulls an off-grid widget in and shrinks an oversized one', () {
      final small = computeGridGeometry(
        const Size(200, 200),
        const DesktopConfig(
          cellWidth: 100,
          cellHeight: 100,
          spacing: 0,
          padding: 0,
        ),
      );
      final reflowed = reflowWidgetsIntoGrid(
        [_widget('a', column: 3, row: 2, columnSpan: 3, rowSpan: 1)],
        small,
      );
      // Clamped rather than re-flowed to the origin: the widget stays as near
      // the corner the user put it in as the smaller grid allows.
      expect(reflowed.single.column, 0);
      expect(reflowed.single.row, 1);
      expect(reflowed.single.columnSpan, 2);
    });

    // Render-only, exactly as `reflowIntoGrid` is: the authored area has to
    // survive plugging the big monitor back in.
    test('does not touch the input list', () {
      final widgets = [_widget('a', column: 9)];
      reflowWidgetsIntoGrid(widgets, _grid);
      expect(widgets.single.column, 9);
    });
  });

  group('icons and widgets together', () {
    test('organize flows icons around a widget rather than under it', () {
      final blocked = widgetCells([_widget('a')]);
      final organized = organizeItems(
        [_item('/1'), _item('/2', row: 1), _item('/3', row: 2)],
        _grid,
        blocked: blocked,
      );
      // Column 0 rows 1 and 2 are free; the widget owns (0,0) and (1,0).
      expect(
        organized.map((i) => (i.column, i.row)),
        [(0, 1), (0, 2), (1, 1)],
      );
    });

    test('organize with no widgets is unchanged', () {
      final organized = organizeItems([_item('/1', column: 2)], _grid);
      expect(organized.single.column, 0);
      expect(organized.single.row, 0);
    });

    test('reflowIntoGrid treats a widget cell as out of range', () {
      final items = [_item('/1'), _item('/2', column: 1)];
      final reflowed = reflowIntoGrid(
        items,
        _grid,
        blocked: widgetCells([_widget('a')]),
      );
      expect(reflowed.every((i) => i.row > 0 || i.column > 1), isTrue);
      // Config untouched: the icon comes back when the widget moves away.
      expect(items.first.row, 0);
    });

    test('a drop onto a widget is refused rather than redirected', () {
      final items = [_item('/1', column: 3)];
      expect(
        identical(
          moveItemTo(
            items,
            '/1',
            (column: 0, row: 0),
            blocked: widgetCells([_widget('a')]),
          ),
          items,
        ),
        isTrue,
      );
    });

    test('a group drop onto a widget is refused whole', () {
      final items = [_item('/1', row: 2), _item('/2', column: 1, row: 2)];
      expect(
        identical(
          moveItemsBy(
            items,
            {'/1', '/2'},
            0,
            -2,
            _grid,
            blocked: widgetCells([_widget('a')]),
          ),
          items,
        ),
        isTrue,
      );
    });

    test('placeItem never lands on a widget', () {
      final placed = placeItem(
        const [],
        _item('/1'),
        _grid,
        blocked: widgetCells([_widget('a')]),
      );
      expect(placed.single.column == 0 && placed.single.row == 0, isFalse);
    });
  });

  group('displaceItemsFrom', () {
    test('moves the icons under a widget out, and nothing else', () {
      final items = [_item('/under'), _item('/beside', column: 3)];
      final moved = displaceItemsFrom(
        items,
        (column: 0, row: 0, columnSpan: 2, rowSpan: 1),
        _grid,
      );
      expect(moved.first.column == 0 && moved.first.row == 0, isFalse);
      expect((moved.last.column, moved.last.row), (3, 0));
    });

    test('is a no-op when nothing is under the area', () {
      final items = [_item('/1', row: 2)];
      expect(
        identical(
          displaceItemsFrom(
            items,
            (column: 0, row: 0, columnSpan: 2, rowSpan: 1),
            _grid,
          ),
          items,
        ),
        isTrue,
      );
    });

    test('never pushes a displaced icon under another widget', () {
      final other = _widget('b', column: 0, row: 1);
      final items = [_item('/under')];
      final moved = displaceItemsFrom(
        items,
        (column: 0, row: 0, columnSpan: 2, rowSpan: 1),
        _grid,
        blocked: widgetCells([other]),
      );
      final cell = (column: moved.single.column, row: moved.single.row);
      expect(cellsOfArea(areaOf(other)).contains(cell), isFalse);
    });

    test('an icon with nowhere to go is left where it is, not lost', () {
      final tiny = computeGridGeometry(
        const Size(200, 100),
        const DesktopConfig(
          cellWidth: 100,
          cellHeight: 100,
          spacing: 0,
          padding: 0,
        ),
      );
      final items = [_item('/under')];
      final moved = displaceItemsFrom(
        items,
        (column: 0, row: 0, columnSpan: 2, rowSpan: 1),
        tiny,
      );
      expect(moved.single.target, '/under');
    });
  });

  group('nextDesktopWidgetId', () {
    test('is the bare type, then -2, -3…', () {
      expect(nextDesktopWidgetId(const [], 'media_player'), 'media_player');
      expect(
        nextDesktopWidgetId([_widget('media_player')], 'media_player'),
        'media_player-2',
      );
      expect(
        nextDesktopWidgetId(
          [_widget('media_player'), _widget('media_player-2')],
          'media_player',
        ),
        'media_player-3',
      );
    });
  });
}
