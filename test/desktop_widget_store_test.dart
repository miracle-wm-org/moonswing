import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/desktop/desktop_layout.dart';
import 'package:moonswing/desktop/desktop_store.dart';
import 'package:toml/toml.dart';

/// A 3x2 grid, so "full" is reachable and a 2x1 widget is a third of it.
final DesktopGridGeometry _grid = computeGridGeometry(
  const Size(300, 200),
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

const GridSpan _min = (columns: 2, rows: 1);
const GridSpan _max = (columns: 3, rows: 2);

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('gs_desktop_widget_store_test');
    path = '${dir.path}/config.toml';
    File(path).writeAsStringSync('''
theme = "glassy"

[desktop]
enabled = true
cell_width = 100
cell_height = 100
spacing = 0
padding = 0

[[desktop.items]]
kind = "file"
target = "/tmp/a.txt"
column = 0
row = 0

[[desktop.widgets]]
id = "media_player"
type = "media_player"
column = 1
row = 1
column_span = 2
row_span = 1
''');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<(DesktopStore, ConfigStore)> open() async {
    final config = await ConfigStore.loadFrom(path);
    final store = DesktopStore.forTesting()..start(config: config);
    addTearDown(() {
      store.dispose();
      config.dispose();
    });
    return (store, config);
  }

  Future<List<Map<String, dynamic>>> tablesOnDisk(String key) async {
    final doc = await TomlDocument.load(path);
    final desktop = doc.toMap()['desktop'];
    if (desktop is! Map) return [];
    final list = desktop[key];
    if (list is! List) return [];
    return list.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  group('start', () {
    test('reads the widgets from the config', () async {
      final (store, _) = await open();
      expect(store.widgets.single.id, 'media_player');
      expect(store.widgets.single.columnSpan, 2);
      expect(store.blockedCells, {
        (column: 1, row: 1),
        (column: 2, row: 1),
      });
    });
  });

  group('addWidget', () {
    test('places it and writes it back', () async {
      final (store, config) = await open();
      store.addWidget(_widget('second', column: 0, row: 0), _grid);
      await config.flush();

      final onDisk = await tablesOnDisk('widgets');
      expect(onDisk.map((w) => w['id']), ['media_player', 'second']);
      expect(onDisk.last['column_span'], 2);
    });

    test('displaces the icons underneath, in a single commit', () async {
      final (store, config) = await open();
      var notifications = 0;
      store.addListener(() => notifications++);

      // The icon lives at (0,0), which this widget is about to cover.
      store.addWidget(_widget('second'), _grid);

      expect(notifications, 1);
      expect(store.items.single.column == 0 && store.items.single.row == 0,
          isFalse);
      await config.flush();
      final items = await tablesOnDisk('items');
      expect(items.single['row'] == 0 && items.single['column'] == 0, isFalse);
    });

    test('ignores a duplicate id', () async {
      final (store, _) = await open();
      store.addWidget(_widget('media_player', row: 0), _grid);
      expect(store.widgets, hasLength(1));
      expect(store.widgets.single.row, 1);
    });
  });

  group('moveWidget', () {
    test('moves and persists', () async {
      final (store, config) = await open();
      store.moveWidget('media_player', (column: 0, row: 0), _grid);
      await config.flush();
      expect((await tablesOnDisk('widgets')).single['row'], 0);
    });

    test('a refused move writes nothing', () async {
      final (store, config) = await open();
      store.addWidget(_widget('second', column: 0, row: 0), _grid);
      await config.flush();
      final before = await tablesOnDisk('widgets');

      // Straight onto the widget that is already there.
      store.moveWidget('media_player', (column: 0, row: 0), _grid);
      await config.flush();
      expect(await tablesOnDisk('widgets'), before);
    });
  });

  group('resizeWidget', () {
    test('clamps to the type limits and persists', () async {
      final (store, config) = await open();
      store.resizeWidget(
        'media_player',
        (column: 0, row: 0, columnSpan: 9, rowSpan: 9),
        _grid,
        minSpan: _min,
        maxSpan: _max,
      );
      await config.flush();
      final onDisk = (await tablesOnDisk('widgets')).single;
      expect(onDisk['column_span'], 3);
      expect(onDisk['row_span'], 2);
    });

    test('a resize that swallows an icon displaces it', () async {
      final (store, _) = await open();
      store.resizeWidget(
        'media_player',
        (column: 0, row: 0, columnSpan: 3, rowSpan: 2),
        _grid,
        minSpan: _min,
        maxSpan: _max,
      );
      // The grid is entirely covered, so the icon has nowhere to go and is
      // left where it is rather than lost.
      expect(store.items.single.target, '/tmp/a.txt');
      expect(store.widgets.single.columnSpan, 3);
    });
  });

  group('removeWidget', () {
    test('drops it from the config and clears its chrome', () async {
      final (store, config) = await open();
      store.selectWidget('media_player');
      store.removeWidget('media_player');
      expect(store.widgets, isEmpty);
      expect(store.selectedWidget, isNull);
      await config.flush();
      expect(await tablesOnDisk('widgets'), isEmpty);
    });

    test('an unknown id writes nothing', () async {
      final (store, _) = await open();
      var notifications = 0;
      store.addListener(() => notifications++);
      store.removeWidget('nope');
      expect(notifications, 0);
    });
  });

  group('organize', () {
    // The headline rule: organize compacts icons and leaves widgets alone.
    test('never moves a widget, and flows icons around it', () async {
      final (store, _) = await open();
      store.organize(_grid);
      expect(store.widgets.single.column, 1);
      expect(store.widgets.single.row, 1);
      final item = store.items.single;
      final cell = (column: item.column, row: item.row);
      expect(store.blockedCells.contains(cell), isFalse);
    });
  });

  group('selection', () {
    test('selecting a widget clears the icon selection, and the reverse',
        () async {
      final (store, _) = await open();
      store.select('/tmp/a.txt');
      store.selectWidget('media_player');
      expect(store.selectedTargets, isEmpty);
      expect(store.selectedWidget, 'media_player');

      store.select('/tmp/a.txt');
      expect(store.selectedWidget, isNull);
    });

    test('a click on bare desktop clears both', () async {
      final (store, _) = await open();
      store.selectWidget('media_player');
      store.select(null);
      expect(store.selectedWidget, isNull);
      expect(store.selectedTargets, isEmpty);
    });

    test('widget drag state notifies but never writes', () async {
      final (store, config) = await open();
      final before = await tablesOnDisk('widgets');
      var notifications = 0;
      store.addListener(() => notifications++);

      store.beginWidgetDrag('media_player');
      expect(store.isDragging, isTrue);
      store.endWidgetDrag();
      expect(store.isDragging, isFalse);

      expect(notifications, 2);
      await config.flush();
      expect(await tablesOnDisk('widgets'), before);
    });
  });

  group('external edits', () {
    test('a widget removed under a selection drops the selection', () async {
      final (store, config) = await open();
      store.selectWidget('media_player');
      config.set(['desktop', 'widgets'], <Map<String, dynamic>>[]);
      expect(store.widgets, isEmpty);
      expect(store.selectedWidget, isNull);
    });
  });
}
