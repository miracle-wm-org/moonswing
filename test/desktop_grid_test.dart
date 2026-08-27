import 'dart:io';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryButton;
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
  /// WindowManager, so nothing here can reach a popup path.
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
      expect(store.selectedTargets, {fileA.path});
      expect(
        tester.widget<DesktopIconTile>(tileFor(fileA)).selected,
        isTrue,
      );

      // Bottom-right corner: past both icons, so this is bare desktop.
      await tester.tapAt(const Offset(350, 250));
      await tester.pumpAndSettle();
      expect(store.selectedTargets, isEmpty);
    });

    testWidgets('clicking a second icon moves the selection', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);

      await tester.tap(tileFor(fileA));
      await tester.pumpAndSettle();
      await tester.tap(tileFor(fileB));
      await tester.pumpAndSettle();

      expect(store.selectedTargets, {fileB.path});
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
      expect(store.selectedTargets, {fileA.path});
      await gesture.up();
      await tester.pumpAndSettle();
    });

    // Pressing to *drag* a group must not throw the group away first, so
    // pointer-down leaves an already-selected icon's selection alone.
    testWidgets('pressing a member of a multi-selection does not collapse it',
        (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);
      store.selectAll([fileA.path, fileB.path]);
      await tester.pump();

      final gesture = await tester.startGesture(tester.getCenter(tileFor(fileA)));
      await tester.pump();
      expect(store.selectedTargets, {fileA.path, fileB.path});
      await gesture.up();
      await tester.pumpAndSettle();
    });

    // ...and the completed tap is what narrows it back down, so a user can get
    // to one icon without first clicking bare desktop.
    testWidgets('clicking a member of a multi-selection collapses onto it',
        (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);
      store.selectAll([fileA.path, fileB.path]);
      await tester.pump();

      await tester.tap(tileFor(fileA));
      // Past kDoubleTapTimeout: with onDoubleTap registered the tap recognizer
      // only wins the arena once the double-tap window has closed, which is the
      // documented cost of collapsing on the *completed* tap.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(store.selectedTargets, {fileA.path});
    });
  });

  group('band select', () {
    /// Drags a marquee from [from] to [to] in steps, so the intermediate
    /// updates actually run — `tester.drag` sends a single move event.
    Future<TestGesture> band(
      WidgetTester tester,
      Offset from,
      Offset to, {
      int steps = 4,
    }) async {
      final gesture = await tester.startGesture(from);
      for (var i = 1; i <= steps; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / steps)!);
        await tester.pump();
      }
      return gesture;
    }

    testWidgets('selects every icon the box touches', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);

      // From bare desktop at the bottom right up across both icons.
      final gesture = await band(tester, const Offset(350, 250), const Offset(50, 50));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(store.selectedTargets, {fileA.path, fileB.path});
      expect(tester.widget<DesktopIconTile>(tileFor(fileA)).selected, isTrue);
      expect(tester.widget<DesktopIconTile>(tileFor(fileB)).selected, isTrue);
    });

    testWidgets('the box is drawn only while the drag is in flight',
        (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);
      expect(find.byType(DesktopSelectionBand), findsNothing);

      final gesture = await band(tester, const Offset(350, 250), const Offset(50, 50));
      expect(find.byType(DesktopSelectionBand), findsOneWidget);
      expect(
        tester.getRect(find.byType(DesktopSelectionBand)),
        const Rect.fromLTRB(50, 50, 350, 250),
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(DesktopSelectionBand), findsNothing);
    });

    // The lines exist to show where an *icon* will land, so a marquee must not
    // begin a drag.
    testWidgets('does not light the grid lines', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);

      final gesture = await band(tester, const Offset(350, 250), const Offset(50, 50));
      expect(store.isDragging, isFalse);
      expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is DesktopGridLines),
        findsNothing,
      );

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a new band replaces the previous selection', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);
      store.selectAll([fileA.path, fileB.path]);
      await tester.pump();

      // Starts on bare cell (2,1) — a press on a tile would drag it instead —
      // and reaches only into B's cell (1,0).
      final gesture = await band(tester, const Offset(250, 150), const Offset(150, 50));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(store.selectedTargets, {fileB.path});
    });

    testWidgets('a band over bare desktop clears the selection', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);
      store.select(fileA.path);
      await tester.pump();

      final gesture = await band(tester, const Offset(210, 110), const Offset(390, 290));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(store.selectedTargets, isEmpty);
    });

    // The band used to be two `setState` fields, so every pointer move rebuilt
    // the whole layer — two grid reflows, every tile, and every widget card —
    // to move one translucent rect. It is a notifier now, and this is what says
    // so: the tile widgets are the *same instances* across a band move, which
    // they could not be if their parent had rebuilt.
    testWidgets('moving the band rebuilds nothing but the band',
        (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);
      final before = tester.widget<DesktopIconTile>(tileFor(fileA));

      // Entirely within the bottom-right quadrant, so no icon is crossed and
      // the store never notifies — a band that *does* cross one has to rebuild
      // the tiles it just highlighted.
      final gesture = await tester.startGesture(const Offset(390, 290));
      await gesture.moveTo(const Offset(350, 250));
      await tester.pump();
      await gesture.moveTo(const Offset(320, 220));
      await tester.pump();

      expect(find.byType(DesktopSelectionBand), findsOneWidget);
      expect(
        tester.getRect(find.byType(DesktopSelectionBand)),
        const Rect.fromLTRB(320, 220, 390, 290),
      );
      expect(
        identical(tester.widget<DesktopIconTile>(tileFor(fileA)), before),
        isTrue,
        reason: 'a band move must not rebuild the icons it is not touching',
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(DesktopSelectionBand), findsNothing);
    });

    // The pan recognizer is primary-button only, so the empty-space menu is
    // still reachable by dragging off a right-press.
    testWidgets('a right-drag does not band', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);

      final gesture = await tester.startGesture(const Offset(350, 250),
          buttons: kSecondaryButton);
      await gesture.moveTo(const Offset(50, 50));
      await tester.pump();
      expect(find.byType(DesktopSelectionBand), findsNothing);
      expect(store.selectedTargets, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a plain click on bare desktop still clears a multi-selection',
        (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);
      store.selectAll([fileA.path, fileB.path]);
      await tester.pump();

      await tester.tapAt(const Offset(350, 250));
      await tester.pumpAndSettle();
      expect(store.selectedTargets, isEmpty);
    });
  });

  // Everything a pointer does while it is moving, and what it is allowed to
  // cost. The band's own tests above drive a *touch* pointer, which is what let
  // the expensive half of this hide: `MouseRegion` fires enter and exit with the
  // button held down (`RendererBinding.dispatchEvent` re-runs the hit test for
  // every `PointerMoveEvent` so that it does), so a marquee dragged with a real
  // mouse rebuilt the whole layer twice for every icon it passed over — every
  // tile and every widget card, whose builders measure their own text — on top
  // of once more for every icon that entered or left the box.
  group('pointer cost', () {
    /// A mouse pointer parked off the grid, so a `moveTo` is a real hover.
    Future<TestGesture> mouse(WidgetTester tester) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(600, 500));
      addTearDown(() => gesture.removePointer());
      await tester.pump();
      return gesture;
    }

    testWidgets('hovering an icon rebuilds that icon and nothing else',
        (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);
      final otherBefore = tester.widget<DesktopIconTile>(tileFor(fileB));

      final gesture = await mouse(tester);
      await gesture.moveTo(const Offset(50, 50));
      await tester.pump();

      expect(tester.widget<DesktopIconTile>(tileFor(fileA)).hovered, isTrue);
      expect(
        identical(tester.widget<DesktopIconTile>(tileFor(fileB)), otherBefore),
        isTrue,
        reason: 'hover is the hovered tile\'s own state, not the layer\'s',
      );
    });

    testWidgets('a band crossing an icon rebuilds that icon and nothing else',
        (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);
      final otherBefore = tester.widget<DesktopIconTile>(tileFor(fileB));

      // Down column 0 only: the box reaches into A's cell and stops short of
      // B's, and the pointer passes over A on the way, so this is the hover and
      // the selection arriving together — which is what a real drag does.
      final gesture = await mouse(tester);
      await gesture.down(const Offset(10, 250));
      await tester.pump();
      for (final y in [200.0, 150.0, 100.0, 50.0]) {
        await gesture.moveTo(Offset(90, y));
        await tester.pump();
      }

      expect(store.selectedTargets, {fileA.path});
      expect(tester.widget<DesktopIconTile>(tileFor(fileA)).selected, isTrue);
      expect(
        identical(tester.widget<DesktopIconTile>(tileFor(fileB)), otherBefore),
        isTrue,
        reason: 'a selection change must rebuild only the tiles it moved',
      );

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

  group('multi drag', () {
    testWidgets('dragging a member moves the whole selection', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);
      store.selectAll([fileA.path, fileB.path]);
      await tester.pump();

      // A is at (0,0) and B at (1,0); one cell down moves both.
      await tester.drag(tileFor(fileA), const Offset(0, 100));
      await tester.pumpAndSettle();

      final a = store.items.firstWhere((i) => i.target == fileA.path);
      final b = store.items.firstWhere((i) => i.target == fileB.path);
      expect((a.column, a.row), (0, 1));
      expect((b.column, b.row), (1, 1));
    });

    testWidgets('dragging an unselected icon selects it and moves it alone',
        (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);
      store.select(fileA.path);
      await tester.pump();

      await tester.drag(tileFor(fileB), const Offset(0, 100));
      await tester.pumpAndSettle();

      final a = store.items.firstWhere((i) => i.target == fileA.path);
      final b = store.items.firstWhere((i) => i.target == fileB.path);
      expect(store.selectedTargets, {fileB.path});
      expect((a.column, a.row), (0, 0));
      expect((b.column, b.row), (1, 1));
    });

    // One ghost per member, holding its relative cell, so the group keeps its
    // shape under the cursor. Two tiles plus two ghosts.
    testWidgets('draws a ghost for every member of the group', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store);
      store.selectAll([fileA.path, fileB.path]);
      await tester.pump();

      final gesture = await tester.startGesture(tester.getCenter(tileFor(fileA)));
      await gesture.moveBy(const Offset(0, 100));
      await tester.pump();
      expect(find.byType(DesktopIconTile), findsNWidgets(4));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(DesktopIconTile), findsNWidgets(2));
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
      expect(store.selectedTargets, {fileB.path});
    });

    // The menu acts on the selection, so right-clicking inside one must not
    // silently shrink it to the icon under the cursor.
    testWidgets('right-clicking a member keeps the whole selection',
        (tester) async {
      final store = openStore();
      DesktopItem? menuItem;
      await pumpGrid(tester, store, onItemMenu: (item, _) => menuItem = item);
      store.selectAll([fileA.path, fileB.path]);
      await tester.pump();

      final gesture =
          await tester.startGesture(tester.getCenter(tileFor(fileA)),
              buttons: kSecondaryButton);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(menuItem?.target, fileA.path);
      expect(store.selectedTargets, {fileA.path, fileB.path});
    });

    testWidgets('right-clicking a non-member narrows onto it', (tester) async {
      final store = openStore();
      await pumpGrid(tester, store, onItemMenu: (_, __) {});
      store.select(fileA.path);
      await tester.pump();

      final gesture =
          await tester.startGesture(tester.getCenter(tileFor(fileB)),
              buttons: kSecondaryButton);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(store.selectedTargets, {fileB.path});
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
