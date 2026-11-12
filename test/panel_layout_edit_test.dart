import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/panel_layout_edit.dart';

void main() {
  group('the list arithmetic', () {
    test('removes the module at its index, and only if it is still there', () {
      const modules = ['clock', 'battery', 'clock'];
      expect(withModuleRemoved(modules, 2, 'clock'), ['clock', 'battery']);
      // A stale index naming a different module leaves the list alone.
      expect(withModuleRemoved(modules, 1, 'clock'), same(modules));
      expect(withModuleRemoved(modules, 5, 'clock'), same(modules));
    });

    test('inserts at an index, clamped to the list', () {
      expect(withModuleInserted(['a', 'b'], 1, 'x'), ['a', 'x', 'b']);
      expect(withModuleInserted(['a', 'b'], 9, 'x'), ['a', 'b', 'x']);
      expect(withModuleInserted(const [], 0, 'x'), ['x']);
    });

    test('a reorder of what was built keeps a dropped module in place', () {
      // `ws` is Miracle-only and was not built, so the bar showed a, b, c.
      final out = withShownReordered(['a', 'ws', 'b', 'c'], [0, 2, 3], [
        2,
        0,
        1,
      ]);
      expect(out, ['c', 'ws', 'a', 'b']);
    });

    test('a click is read as thirds of the bar', () {
      expect(panelSlotAt(10, 300), 'left');
      expect(panelSlotAt(150, 300), 'center');
      expect(panelSlotAt(299, 300), 'right');
      expect(panelSlotLabel('left', vertical: true), 'Top');
      expect(panelSlotLabel('right', vertical: false), 'Right');
    });

    test('offers what the bar does not hold, by title', () {
      final keys = addableModules(
        const LayoutConfig(left: ['clock'], center: [], right: []),
        miracleUnsupported: false,
        titleOf: (key) => key,
        registered: ['weather', 'clock', 'battery'],
      );
      expect(keys, ['battery', 'weather']);
    });
  });

  group('writing to the config', () {
    late Directory tempDir;
    late String path;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('panel_layout_edit');
      path = '${tempDir.path}/config.toml';
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('a removal writes only its section', () async {
      await File(path).writeAsString('''
[panels.top]
anchor = "top"

[panels.top.layout]
left = ["workspaces"]
right = ["battery", "clock"]
''');
      final store = await ConfigStore.loadFrom(path);
      addTearDown(store.dispose);
      removePanelModule(
        store,
        panel: 'top',
        slot: 'right',
        index: 0,
        key: 'battery',
      );
      expect(store.getList<String>(['panels', 'top', 'layout', 'right']), [
        'clock',
      ]);
      expect(store.getList<String>(['panels', 'top', 'layout', 'left']), [
        'workspaces',
      ]);
      expect(store.get<Object>(['panels', 'top', 'layout', 'center']), isNull);
    });

    test('a panel showing the defaults keeps the other two sections', () async {
      await File(path).writeAsString('''
[panels.top]
anchor = "top"
''');
      final store = await ConfigStore.loadFrom(path);
      addTearDown(store.dispose);
      insertPanelModule(store, panel: 'top', slot: 'center', key: 'clock');
      final layout = storedPanelLayout(store, 'top');
      const defaults = LayoutConfig();
      expect(layout.left, defaults.left);
      expect(layout.center, [...defaults.center, 'clock']);
      expect(layout.right, defaults.right);
    });

    test('an insert lands beside the module it was asked from', () async {
      await File(path).writeAsString('''
[panels.top.layout]
right = ["battery", "clock"]
''');
      final store = await ConfigStore.loadFrom(path);
      addTearDown(store.dispose);
      insertPanelModule(
        store,
        panel: 'top',
        slot: 'right',
        key: 'weather',
        index: 1,
      );
      expect(store.getList<String>(['panels', 'top', 'layout', 'right']), [
        'battery',
        'weather',
        'clock',
      ]);
    });

    test('a drop is written once, and not over a layout that moved', () async {
      await File(path).writeAsString('''
[panels.top.layout]
right = ["battery", "clock", "system"]
''');
      final store = await ConfigStore.loadFrom(path);
      addTearDown(store.dispose);
      var notifies = 0;
      store.addListener(() => notifies++);

      reorderPanelSlot(
        store,
        panel: 'top',
        slot: 'right',
        built: const ['battery', 'clock', 'system'],
        shown: const [0, 1, 2],
        order: const [1, 0, 2],
      );
      expect(notifies, 1);
      expect(store.getList<String>(['panels', 'top', 'layout', 'right']), [
        'clock',
        'battery',
        'system',
      ]);

      // Built from the layout before that drop: nothing is written.
      reorderPanelSlot(
        store,
        panel: 'top',
        slot: 'right',
        built: const ['battery', 'clock', 'system'],
        shown: const [0, 1, 2],
        order: const [2, 1, 0],
      );
      expect(notifies, 1);
    });
  });
}
