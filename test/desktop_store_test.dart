import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/desktop/desktop_layout.dart';
import 'package:graceful_shell/desktop/desktop_store.dart';
import 'package:toml/toml.dart';

/// A 3-column, 2-row grid, so "full" is reachable in a test.
final DesktopGridGeometry _grid = computeGridGeometry(
  const Size(300, 200),
  const DesktopConfig(cellWidth: 100, cellHeight: 100, spacing: 0, padding: 0),
);

DesktopItem _item(String target, {int column = 0, int row = 0}) => DesktopItem(
      kind: DesktopItemKind.file,
      target: target,
      column: column,
      row: row,
    );

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('gs_desktop_store_test');
    path = '${dir.path}/config.toml';
    File(path).writeAsStringSync('''
theme = "graceful"

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

[[desktop.items]]
kind = "file"
target = "/tmp/b.txt"
column = 1
row = 0
''');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// A store bound to the temp config, torn down with the test.
  Future<(DesktopStore, ConfigStore)> open() async {
    final config = await ConfigStore.loadFrom(path);
    final store = DesktopStore.forTesting()..start(config: config);
    addTearDown(() {
      store.dispose();
      config.dispose();
    });
    return (store, config);
  }

  /// The `[[desktop.items]]` tables as they currently sit on disk.
  Future<List<Map<String, dynamic>>> itemsOnDisk() async {
    final doc = await TomlDocument.load(path);
    final desktop = doc.toMap()['desktop'];
    if (desktop is! Map) return [];
    final items = desktop['items'];
    if (items is! List) return [];
    return items.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  group('start', () {
    test('reads the grid and items from the config', () async {
      final (store, _) = await open();
      expect(store.enabled, isTrue);
      expect(store.config.cellWidth, 100);
      expect(store.items.map((i) => i.target), ['/tmp/a.txt', '/tmp/b.txt']);
    });

    test('an unbound store is an empty disabled grid, not a crash', () {
      final store = DesktopStore.forTesting()..start();
      addTearDown(store.dispose);
      expect(store.enabled, isFalse);
      expect(store.items, isEmpty);
    });
  });

  group('ephemeral state', () {
    // Selection changes on every click. If it reached ConfigStore it would
    // rebuild every panel on every monitor and write to disk each time.
    test('select, drag and rename notify but never write', () async {
      final (store, config) = await open();
      var notifications = 0;
      store.addListener(() => notifications++);

      final before = await itemsOnDisk();

      store.select('/tmp/a.txt');
      store.beginDrag('/tmp/a.txt');
      store.endDrag();
      store.beginRename('/tmp/a.txt');
      store.cancelRename();

      expect(notifications, 5);
      await config.flush();
      expect(await itemsOnDisk(), before);
    });

    test('repeated identical calls do not notify', () async {
      final (store, _) = await open();
      store.select('/tmp/a.txt');
      var notifications = 0;
      store.addListener(() => notifications++);
      store.select('/tmp/a.txt');
      expect(notifications, 0);
    });

    test('isDragging is what makes the grid lines visible', () async {
      final (store, _) = await open();
      expect(store.isDragging, isFalse);
      store.beginDrag('/tmp/a.txt');
      expect(store.isDragging, isTrue);
      store.endDrag();
      expect(store.isDragging, isFalse);
    });

    test('renaming an item also selects it, and only it', () async {
      final (store, _) = await open();
      store.selectAll(['/tmp/a.txt', '/tmp/b.txt']);
      store.beginRename('/tmp/b.txt');
      expect(store.selectedTargets, {'/tmp/b.txt'});
    });

    // The rubber band calls selectAll on every pan update, and this store is
    // watched by every monitor's desktop surface.
    test('selectAll notifies once and never writes', () async {
      final (store, config) = await open();
      var notifications = 0;
      store.addListener(() => notifications++);
      final before = await itemsOnDisk();

      store.selectAll(['/tmp/a.txt', '/tmp/b.txt']);

      expect(notifications, 1);
      expect(store.selectedTargets, {'/tmp/a.txt', '/tmp/b.txt'});
      await config.flush();
      expect(await itemsOnDisk(), before);
    });

    test('selectAll with an unchanged set does not notify', () async {
      final (store, _) = await open();
      store.selectAll(['/tmp/a.txt', '/tmp/b.txt']);
      var notifications = 0;
      store.addListener(() => notifications++);
      // Same set, different order.
      store.selectAll(['/tmp/b.txt', '/tmp/a.txt']);
      expect(notifications, 0);
    });

    test('select replaces a multi-selection with one target', () async {
      final (store, _) = await open();
      store.selectAll(['/tmp/a.txt', '/tmp/b.txt']);
      store.select('/tmp/a.txt');
      expect(store.selectedTargets, {'/tmp/a.txt'});
      expect(store.isSelected('/tmp/b.txt'), isFalse);
      store.select(null);
      expect(store.selectedTargets, isEmpty);
    });

    // The selection is handed out read-only so a caller cannot widen it behind
    // the store's back and skip the notification.
    test('selectedTargets cannot be mutated by a caller', () async {
      final (store, _) = await open();
      store.select('/tmp/a.txt');
      expect(
        () => store.selectedTargets.add('/tmp/b.txt'),
        throwsUnsupportedError,
      );
    });
  });

  group('moveTo', () {
    test('persists the new cell', () async {
      final (store, config) = await open();
      store.moveTo('/tmp/a.txt', (column: 2, row: 1));
      await config.flush();

      final onDisk = await itemsOnDisk();
      final a = onDisk.firstWhere((m) => m['target'] == '/tmp/a.txt');
      expect(a['column'], 2);
      expect(a['row'], 1);
    });

    // Dropping one icon onto another must move both, never stack them.
    test('swaps with the occupant', () async {
      final (store, config) = await open();
      store.moveTo('/tmp/a.txt', (column: 1, row: 0));
      await config.flush();

      final onDisk = await itemsOnDisk();
      final a = onDisk.firstWhere((m) => m['target'] == '/tmp/a.txt');
      final b = onDisk.firstWhere((m) => m['target'] == '/tmp/b.txt');
      expect((a['column'], a['row']), (1, 0));
      expect((b['column'], b['row']), (0, 0));
    });

    // A drag that ends where it started must cost nothing.
    test('a no-op move writes nothing and does not notify', () async {
      final (store, _) = await open();
      var notifications = 0;
      store.addListener(() => notifications++);
      store.moveTo('/tmp/a.txt', (column: 0, row: 0));
      expect(notifications, 0);
    });

    test('the in-memory list updates synchronously, before the write', () async {
      final (store, _) = await open();
      store.moveTo('/tmp/a.txt', (column: 2, row: 1));
      final a = store.items.firstWhere((i) => i.target == '/tmp/a.txt');
      expect((a.column, a.row), (2, 1));
    });
  });

  group('addItem / removeItem', () {
    test('adds at the requested cell and persists', () async {
      final (store, config) = await open();
      store.addItem(_item('/tmp/c.txt', column: 2, row: 1), _grid);
      await config.flush();

      final onDisk = await itemsOnDisk();
      expect(onDisk, hasLength(3));
      final c = onDisk.firstWhere((m) => m['target'] == '/tmp/c.txt');
      expect((c['column'], c['row']), (2, 1));
    });

    test('never displaces: an occupied request lands elsewhere', () async {
      final (store, _) = await open();
      store.addItem(_item('/tmp/c.txt'), _grid);
      final a = store.items.firstWhere((i) => i.target == '/tmp/a.txt');
      final c = store.items.firstWhere((i) => i.target == '/tmp/c.txt');
      expect((a.column, a.row), (0, 0));
      expect((c.column, c.row), isNot((0, 0)));
    });

    test('a duplicate target is ignored', () async {
      final (store, _) = await open();
      var notifications = 0;
      store.addListener(() => notifications++);
      store.addItem(_item('/tmp/a.txt', column: 2, row: 1), _grid);
      expect(notifications, 0);
      expect(store.items, hasLength(2));
    });

    test('removing clears any chrome pointing at it', () async {
      final (store, config) = await open();
      store.select('/tmp/a.txt');
      store.beginRename('/tmp/a.txt');
      store.removeItem('/tmp/a.txt');

      expect(store.selectedTargets, isEmpty);
      expect(store.renamingTarget, isNull);
      await config.flush();
      expect((await itemsOnDisk()).map((m) => m['target']), ['/tmp/b.txt']);
    });

    test('removing an unknown target does nothing', () async {
      final (store, _) = await open();
      var notifications = 0;
      store.addListener(() => notifications++);
      store.removeItem('/tmp/nope.txt');
      expect(notifications, 0);
    });

    // Each _commit is a ConfigStore.set, whose notification is synchronous and
    // rebuilds every panel on every monitor — so a five-icon selection must not
    // be five of them.
    test('removeItems writes once for the whole selection', () async {
      final (store, config) = await open();
      store.selectAll(['/tmp/a.txt', '/tmp/b.txt']);
      var notifications = 0;
      store.addListener(() => notifications++);

      store.removeItems(store.selectedTargets);

      expect(notifications, 1);
      expect(store.selectedTargets, isEmpty);
      await config.flush();
      expect(await itemsOnDisk(), isEmpty);
    });

    test('removeItems keeps the survivors selected', () async {
      final (store, _) = await open();
      store.selectAll(['/tmp/a.txt', '/tmp/b.txt']);
      store.removeItems(['/tmp/a.txt']);
      expect(store.selectedTargets, {'/tmp/b.txt'});
    });

    test('removeItems with nothing pinned does not notify', () async {
      final (store, _) = await open();
      var notifications = 0;
      store.addListener(() => notifications++);
      store.removeItems(['/tmp/nope.txt', '/tmp/also-nope.txt']);
      expect(notifications, 0);
    });
  });

  group('moveGroupBy', () {
    test('persists every member of the group', () async {
      final (store, config) = await open();
      store.moveGroupBy({'/tmp/a.txt', '/tmp/b.txt'}, 0, 1, _grid);
      await config.flush();

      final onDisk = await itemsOnDisk();
      final a = onDisk.firstWhere((m) => m['target'] == '/tmp/a.txt');
      final b = onDisk.firstWhere((m) => m['target'] == '/tmp/b.txt');
      expect((a['column'], a['row']), (0, 1));
      expect((b['column'], b['row']), (1, 1));
    });

    test('a group move that clamps to zero writes nothing', () async {
      final (store, _) = await open();
      var notifications = 0;
      store.addListener(() => notifications++);
      store.moveGroupBy({'/tmp/a.txt', '/tmp/b.txt'}, -2, 0, _grid);
      expect(notifications, 0);
    });
  });

  group('commitRename', () {
    test('persists the label and ends the rename', () async {
      final (store, config) = await open();
      store.beginRename('/tmp/a.txt');
      store.commitRename('/tmp/a.txt', '  Notes  ');

      expect(store.renamingTarget, isNull);
      await config.flush();
      final a = (await itemsOnDisk())
          .firstWhere((m) => m['target'] == '/tmp/a.txt');
      expect(a['label'], 'Notes');
    });

    // The only route back to the desktop entry's own name once renamed.
    test('an empty label clears the override rather than storing it', () async {
      final (store, config) = await open();
      store.commitRename('/tmp/a.txt', 'Notes');
      store.commitRename('/tmp/a.txt', '   ');
      await config.flush();

      final a = (await itemsOnDisk())
          .firstWhere((m) => m['target'] == '/tmp/a.txt');
      expect(a.containsKey('label'), isFalse);
      expect(
        store.items.firstWhere((i) => i.target == '/tmp/a.txt').label,
        isNull,
      );
    });
  });

  group('organize', () {
    test('compacts and persists', () async {
      final (store, config) = await open();
      store.moveTo('/tmp/b.txt', (column: 2, row: 1));
      store.organize(_grid);
      await config.flush();

      final onDisk = await itemsOnDisk();
      final cells = {for (final m in onDisk) m['target']: (m['column'], m['row'])};
      expect(cells['/tmp/a.txt'], (0, 0));
      expect(cells['/tmp/b.txt'], (0, 1));
    });

    test('is a no-op on an already-organized grid', () async {
      final (store, _) = await open();
      store.organize(_grid);
      var notifications = 0;
      store.addListener(() => notifications++);
      store.organize(_grid);
      expect(notifications, 0);
    });
  });

  group('config listener', () {
    // The listener fires on every keystroke anywhere in the settings UI.
    test('an unrelated config write does not notify', () async {
      final (store, config) = await open();
      var notifications = 0;
      store.addListener(() => notifications++);
      config.set(['theme'], 'glassy');
      expect(notifications, 0);
    });

    test('an unrelated write leaves items and selection alone', () async {
      final (store, config) = await open();
      store.select('/tmp/a.txt');
      config.set(['theme'], 'glassy');
      expect(store.selectedTargets, {'/tmp/a.txt'});
      expect(store.items.map((i) => i.target), ['/tmp/a.txt', '/tmp/b.txt']);
    });

    test('an external edit to the grid is picked up', () async {
      final (store, config) = await open();
      config.set(['desktop', 'cell_width'], 140);
      expect(store.config.cellWidth, 140);
    });

    test('an item removed out from under a selection clears it', () async {
      final (store, config) = await open();
      store.select('/tmp/b.txt');
      config.set(['desktop', 'items'], [
        {'kind': 'file', 'target': '/tmp/a.txt', 'column': 0, 'row': 0},
      ]);
      expect(store.selectedTargets, isEmpty);
    });

    // Only the vanished target goes: an external edit must not drop the icons
    // that are still there out of the selection.
    test('an external removal prunes only the target that vanished', () async {
      final (store, config) = await open();
      store.selectAll(['/tmp/a.txt', '/tmp/b.txt']);
      config.set(['desktop', 'items'], [
        {'kind': 'file', 'target': '/tmp/a.txt', 'column': 0, 'row': 0},
      ]);
      expect(store.selectedTargets, {'/tmp/a.txt'});
    });
  });

  group('persistence', () {
    test('survives a flush and a reload', () async {
      final (store, config) = await open();
      store.moveTo('/tmp/a.txt', (column: 2, row: 1));
      store.commitRename('/tmp/b.txt', 'Beta');
      await config.flush();

      final reopened = await ConfigStore.loadFrom(path);
      final reloaded = DesktopStore.forTesting()..start(config: reopened);
      addTearDown(() {
        reloaded.dispose();
        reopened.dispose();
      });

      final a = reloaded.items.firstWhere((i) => i.target == '/tmp/a.txt');
      final b = reloaded.items.firstWhere((i) => i.target == '/tmp/b.txt');
      expect((a.column, a.row), (2, 1));
      expect(b.label, 'Beta');
    });

    test('setGrid writes every geometry key', () async {
      final (store, config) = await open();
      store.setGrid(const DesktopConfig(
        enabled: true,
        cellWidth: 120,
        cellHeight: 110,
        spacing: 4,
        padding: 6,
        iconSize: 64,
        showLabels: false,
      ));
      await config.flush();

      final doc = await TomlDocument.load(path);
      final desktop = (doc.toMap()['desktop'] as Map).cast<String, dynamic>();
      expect(desktop['cell_width'], 120);
      expect(desktop['cell_height'], 110);
      expect(desktop['spacing'], 4);
      expect(desktop['padding'], 6);
      expect(desktop['icon_size'], 64);
      expect(desktop['show_labels'], isFalse);
      // The items are untouched by a geometry edit.
      expect(await itemsOnDisk(), hasLength(2));
    });
  });
}
