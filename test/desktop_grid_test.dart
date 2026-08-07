import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/desktop_grid.dart';
import 'package:graceful_shell/desktop/desktop_icon.dart';
import 'package:graceful_shell/desktop/desktop_layout.dart';
import 'package:graceful_shell/desktop/desktop_store.dart';
import 'package:graceful_shell/scopes.dart';

const Size _surface = Size(400, 300);

void main() {
  late Directory dir;
  late File fileA;
  late File fileB;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('gs_desktop_grid_test');
    fileA = File('${dir.path}/a.txt')..writeAsStringSync('a');
    fileB = File('${dir.path}/b.txt')..writeAsStringSync('b');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// A store seeded in memory. No [ConfigStore] on purpose: it loads
  /// asynchronously from disk, and a real I/O completion never lands inside
  /// `testWidgets`' fake-async zone. Persistence is covered by
  /// `desktop_store_test.dart`, which is a plain `test`.
  DesktopStore openStore() {
    final store = DesktopStore.forTesting()
      ..seed(DesktopConfig(
        enabled: true,
        cellWidth: 100,
        cellHeight: 100,
        spacing: 0,
        padding: 0,
        items: [
          DesktopItem(
              kind: DesktopItemKind.file, target: fileA.path, column: 0, row: 0),
          DesktopItem(
              kind: DesktopItemKind.file, target: fileB.path, column: 1, row: 0),
        ],
      ));
    addTearDown(store.dispose);
    return store;
  }

  /// Pumps the layer the way the background surface does — no
  /// PanelWindowManager, so nothing here can reach a popup path.
  Future<void> pumpGrid(
    WidgetTester tester,
    DesktopStore store, {
    void Function(DesktopItem item)? onOpen,
    void Function(DesktopItem item, Offset position)? onItemMenu,
    void Function(GridCell cell, Offset position)? onEmptyMenu,
    Map<String, PanelConfig> panels = const {},
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 14),
          child: ThemeScope(
            theme: const ThemeConfig(),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: _surface.width,
                height: _surface.height,
                child: DesktopLayer(
                  store: store,
                  panels: panels,
                  onOpen: onOpen,
                  onItemMenu: onItemMenu,
                  onEmptyMenu: onEmptyMenu,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder tileFor(File file) => find.byWidgetPredicate(
      (w) => w is DesktopIconTile && w.item.target == file.path);

  group('layout', () {
    test('the geometry under test is 4 columns by 3 rows', () {
      final g = computeGridGeometry(
        _surface,
        const DesktopConfig(
            cellWidth: 100, cellHeight: 100, spacing: 0, padding: 0),
      );
      expect((g.columns, g.rows), (4, 3));
    });

    testWidgets('draws one tile per item at the cell rect', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);

      expect(find.byType(DesktopIconTile), findsNWidgets(2));
      expect(tester.getTopLeft(tileFor(fileA)), Offset.zero);
      expect(tester.getTopLeft(tileFor(fileB)), const Offset(100, 0));
    });

    // The background surface spans the full output, under the bars, so an icon
    // in the top-left would otherwise sit behind a top panel.
    testWidgets('insets the grid by the panel exclusive zones', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store, panels: const {
        'top': PanelConfig(anchor: 'top', height: 40),
      });
      expect(tester.getTopLeft(tileFor(fileA)), const Offset(0, 40));
    });
  });

  group('selection', () {
    testWidgets('a single click selects, and empty space clears it',
        (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);

      // pumpAndSettle, not pump: onDoubleTap leaves a ~300ms recognizer timer
      // pending, and testWidgets fails the test if one outlives the tree.
      await tester.tap(tileFor(fileA));
      await tester.pumpAndSettle();
      expect(store.selectedTarget, fileA.path);
      expect(
        tester.widget<DesktopIconTile>(tileFor(fileA)).selected,
        isTrue,
      );

      // Bottom-right corner: past both icons, so this is bare desktop.
      await tester.tapAt(const Offset(350, 250));
      await tester.pumpAndSettle();
      expect(store.selectedTarget, isNull);
    });

    testWidgets('clicking a second icon moves the selection', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);

      await tester.tap(tileFor(fileA));
      await tester.pumpAndSettle();
      await tester.tap(tileFor(fileB));
      await tester.pumpAndSettle();

      expect(store.selectedTarget, fileB.path);
      expect(tester.widget<DesktopIconTile>(tileFor(fileA)).selected, isFalse);
      expect(tester.widget<DesktopIconTile>(tileFor(fileB)).selected, isTrue);
    });

    // onTap waits out the double-tap window once onDoubleTap is registered, so
    // selection is painted on tap *down* instead.
    testWidgets('selection lands on tap down, not after the double-tap window',
        (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);

      final gesture = await tester.startGesture(tester.getCenter(tileFor(fileA)));
      await tester.pump();
      expect(store.selectedTarget, fileA.path);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('opening', () {
    testWidgets('a double click opens the item', (tester) async {
      final store = openStore();
      final opened = <String>[];
      await pumpGrid(tester, store, onOpen: (item) => opened.add(item.target));

      await tester.tap(tileFor(fileB));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(tileFor(fileB));
      await tester.pumpAndSettle();

      expect(opened, [fileB.path]);
    });

    testWidgets('a single click does not open anything', (tester) async {
      final store = openStore();
      final opened = <String>[];
      await pumpGrid(tester, store, onOpen: (item) => opened.add(item.target));

      await tester.tap(tileFor(fileA));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
    });
  });

  group('grid lines', () {
    // The desktop is a wallpaper the rest of the time; the lines exist only to
    // show where a dragged icon will land.
    testWidgets('are absent at rest and present during a drag', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);
      expect(find.byType(CustomPaint), findsNothing);

      store.beginDrag(fileA.path);
      await tester.pump();
      expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is DesktopGridLines),
        findsOneWidget,
      );

      store.endDrag();
      await tester.pump();
      expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is DesktopGridLines),
        findsNothing,
      );
    });
  });

  group('drag', () {
    testWidgets('dropping on empty space moves the icon there', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);

      await tester.drag(tileFor(fileA), const Offset(200, 100));
      await tester.pumpAndSettle();

      final a = store.items.firstWhere((i) => i.target == fileA.path);
      expect((a.column, a.row), (2, 1));
      expect(store.isDragging, isFalse);
    });

    testWidgets('dropping on another icon swaps the two', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);

      // A is at (0,0), B at (1,0): drag A one cell right, onto B.
      await tester.drag(tileFor(fileA), const Offset(100, 0));
      await tester.pumpAndSettle();

      final a = store.items.firstWhere((i) => i.target == fileA.path);
      final b = store.items.firstWhere((i) => i.target == fileB.path);
      expect((a.column, a.row), (1, 0));
      expect((b.column, b.row), (0, 0));
    });
  });

  group('context menus', () {
    testWidgets('right-clicking an item reports it and selects it',
        (tester) async {
      final store = openStore();
      DesktopItem? menuItem;
      await pumpGrid(tester, store, onItemMenu: (item, _) => menuItem = item);

      final gesture =
          await tester.startGesture(tester.getCenter(tileFor(fileB)),
              buttons: kSecondaryButton);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(menuItem?.target, fileB.path);
      expect(store.selectedTarget, fileB.path);
    });

    testWidgets('right-clicking empty space reports the cell under the cursor',
        (tester) async {
      final store = openStore();
      GridCell? cell;
      await pumpGrid(tester, store, onEmptyMenu: (c, _) => cell = c);

      final gesture = await tester.startGesture(const Offset(350, 250),
          buttons: kSecondaryButton);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(cell, (column: 3, row: 2));
    });
  });

  group('rename in place', () {
    testWidgets('swaps the tile for an editor seeded with the current name',
        (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);

      store.beginRename(fileA.path);
      await tester.pump();

      expect(tileFor(fileA), findsNothing);
      expect(find.byType(DesktopRenameField), findsOneWidget);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.controller.text, 'a.txt');
      // Selected whole, because renaming usually means replacing.
      expect(field.controller.selection.baseOffset, 0);
      expect(field.controller.selection.extentOffset, 'a.txt'.length);

      store.cancelRename();
      await tester.pumpAndSettle();
    });

    // The background surface is created keyboardMode: none, so without this the
    // field would never see a key event.
    testWidgets('asks the host for the keyboard only while renaming',
        (tester) async {
      final store = openStore();
      final requests = <bool>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 14),
            child: ThemeScope(
              theme: const ThemeConfig(),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: _surface.width,
                  height: _surface.height,
                  child: DesktopLayer(
                    store: store,
                    onKeyboardRequested: requests.add,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(requests, isEmpty);

      store.beginRename(fileA.path);
      await tester.pump();
      expect(requests, [true]);

      store.commitRename(fileA.path, 'Renamed');
      await tester.pumpAndSettle();
      expect(requests, [true, false]);
    });

    testWidgets('Enter commits and Escape cancels', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);

      store.beginRename(fileA.path);
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'Shopping list');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(store.renamingTarget, isNull);
      expect(
        store.items.firstWhere((i) => i.target == fileA.path).label,
        'Shopping list',
      );
      expect(find.text('Shopping list'), findsOneWidget);

      store.beginRename(fileA.path);
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'Discarded');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(store.renamingTarget, isNull);
      expect(
        store.items.firstWhere((i) => i.target == fileA.path).label,
        'Shopping list',
      );
    });

    // The only route back to the derived name once an item has been renamed.
    testWidgets('an empty name clears the override', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);

      store.commitRename(fileA.path, 'Temporary');
      await tester.pump();

      store.beginRename(fileA.path);
      await tester.pump();
      await tester.enterText(find.byType(EditableText), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        store.items.firstWhere((i) => i.target == fileA.path).label,
        isNull,
      );
      expect(find.text('a.txt'), findsOneWidget);
    });
  });

  group('missing targets', () {
    // Silently dropping an icon because a network mount was offline would lose
    // the user's arrangement.
    testWidgets('a deleted target is dimmed, not removed', (tester) async {
      final store = openStore();
      fileA.deleteSync();
      await pumpGrid(tester, store);

      expect(find.byType(DesktopIconTile), findsNWidgets(2));
      expect(tester.widget<DesktopIconTile>(tileFor(fileA)).missing, isTrue);
      expect(tester.widget<DesktopIconTile>(tileFor(fileB)).missing, isFalse);
    });
  });
}
