import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/desktop_grid.dart';
import 'package:graceful_shell/desktop/desktop_icon.dart';
import 'package:graceful_shell/desktop/desktop_layout.dart';
import 'package:graceful_shell/desktop/desktop_store.dart';
import 'package:graceful_shell/desktop/widgets/desktop_widget.dart';
import 'package:graceful_shell/desktop/widgets/desktop_widget_frame.dart';
import 'package:graceful_shell/scopes.dart';

/// 400x300 of 100px cells: a 4x3 grid whose pixel maths is its coordinates
/// times 100.
const Size _surface = Size(400, 300);

/// A stand-in for the media player, so this file tests the *framework* rather
/// than any one widget. Registered per test and cleared afterwards — the
/// registry is process-global.
final DesktopWidgetSpec _spec = DesktopWidgetSpec(
  type: 'fake',
  name: 'Fake widget',
  icon: FontAwesomeIcons.shapes,
  minSpan: (columns: 2, rows: 1),
  maxSpan: (columns: 4, rows: 3),
  builder: (context, widget) => Text('fake ${widget.span.columns}x'
      '${widget.span.rows}'),
);

DesktopWidgetItem _widget({
  String id = 'fake',
  String type = 'fake',
  int column = 0,
  int row = 0,
  int columnSpan = 2,
  int rowSpan = 1,
}) =>
    DesktopWidgetItem(
      id: id,
      type: type,
      column: column,
      row: row,
      columnSpan: columnSpan,
      rowSpan: rowSpan,
    );

void main() {
  setUp(() => DesktopWidgetRegistry.register(_spec));
  tearDown(DesktopWidgetRegistry.clear);

  DesktopStore openStore({
    List<DesktopWidgetItem> widgets = const [],
    List<DesktopItem> items = const [],
  }) {
    final store = DesktopStore.forTesting()
      ..seed(DesktopConfig(
        enabled: true,
        cellWidth: 100,
        cellHeight: 100,
        spacing: 0,
        padding: 0,
        items: items,
        widgets: widgets,
      ));
    addTearDown(store.dispose);
    return store;
  }

  Future<DesktopGridGeometry> pumpGrid(
    WidgetTester tester,
    DesktopStore store, {
    void Function(DesktopWidgetItem widget, Offset position)? onWidgetMenu,
  }) async {
    late DesktopGridGeometry geometry;
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
                  onWidgetMenu: onWidgetMenu,
                  onGeometry: (g) => geometry = g,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return geometry;
  }

  Finder gripFor(DesktopWidgetCorner corner) => find.byWidgetPredicate(
        (w) => w is DesktopWidgetResizeGrip && w.corner == corner,
      );

  group('rendering', () {
    testWidgets('draws a registered widget at its span', (tester) async {
      final store = openStore(widgets: [_widget()]);
      await pumpGrid(tester, store);

      expect(find.text('fake 2x1'), findsOneWidget);
      final rect = tester.getRect(find.byType(DesktopWidgetFrame));
      expect(rect.left, 0);
      expect(rect.width, 200);
      expect(rect.height, 100);
    });

    testWidgets('clamps a span the type no longer allows', (tester) async {
      // Authored at 6 wide; the spec's maximum is 4. The config is left alone
      // and the *render* is clamped.
      final store = openStore(widgets: [_widget(columnSpan: 6)]);
      await pumpGrid(tester, store);
      expect(find.text('fake 4x1'), findsOneWidget);
      expect(store.widgets.single.columnSpan, 6);
    });

    // The entry stays in the config, so there is still something to right-click
    // and remove — and an upgrade brings the real widget straight back.
    testWidgets('an unknown type is a placeholder, not a hole', (tester) async {
      final store = openStore(widgets: [_widget(type: 'from_the_future')]);
      await pumpGrid(tester, store);
      expect(find.textContaining('Unknown widget'), findsOneWidget);
    });

    testWidgets('an icon is never rendered under a widget', (tester) async {
      final store = openStore(
        widgets: [_widget()],
        items: const [
          DesktopItem(kind: DesktopItemKind.file, target: '/tmp/a.txt'),
        ],
      );
      final geometry = await pumpGrid(tester, store);

      final tile = tester.getRect(find.byType(DesktopIconTile));
      expect(
        cellsOfArea((column: 0, row: 0, columnSpan: 2, rowSpan: 1))
            .contains(nearestCell(geometry, tile.center)),
        isFalse,
      );
      // Render-only: the config still has the icon where its owner put it.
      expect((store.items.single.column, store.items.single.row), (0, 0));
    });
  });

  group('drag', () {
    testWidgets('moves the widget to the cell it was dropped on',
        (tester) async {
      final store = openStore(widgets: [_widget()]);
      await pumpGrid(tester, store);

      await tester.drag(find.byType(DesktopWidgetFrame), const Offset(100, 100));
      await tester.pumpAndSettle();

      expect((store.widgets.single.column, store.widgets.single.row), (1, 1));
      expect(store.draggingWidget, isNull);
    });

    testWidgets('lights the grid lines while it is in flight', (tester) async {
      final store = openStore(widgets: [_widget()]);
      await pumpGrid(tester, store);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(DesktopWidgetFrame)),
      );
      await gesture.moveBy(const Offset(60, 60));
      await tester.pump();

      expect(store.isDragging, isTrue);
      expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is DesktopGridLines),
        findsOneWidget,
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.isDragging, isFalse);
    });

    testWidgets('a drop onto another widget is refused', (tester) async {
      final store = openStore(widgets: [
        _widget(),
        _widget(id: 'other', row: 1),
      ]);
      await pumpGrid(tester, store);

      await tester.drag(find.text('fake 2x1').first, const Offset(0, 100));
      await tester.pumpAndSettle();

      expect(store.widgets.first.row, 0);
      expect(store.widgets.last.row, 1);
    });
  });

  group('resize', () {
    testWidgets('the grips appear once the widget is selected',
        (tester) async {
      final store = openStore(widgets: [_widget()]);
      await pumpGrid(tester, store);
      expect(gripFor(DesktopWidgetCorner.bottomRight), findsNothing);

      store.selectWidget('fake');
      await tester.pump();
      expect(find.byType(DesktopWidgetResizeGrip), findsNWidgets(4));
    });

    testWidgets('dragging the bottom-right grip grows the span',
        (tester) async {
      final store = openStore(widgets: [_widget()]);
      await pumpGrid(tester, store);
      store.selectWidget('fake');
      await tester.pump();

      await tester.drag(
        gripFor(DesktopWidgetCorner.bottomRight),
        const Offset(100, 100),
      );
      await tester.pumpAndSettle();

      final widget = store.widgets.single;
      expect((widget.column, widget.row), (0, 0));
      expect((widget.columnSpan, widget.rowSpan), (3, 2));
    });

    testWidgets('dragging the top-left grip moves the corner, not the widget',
        (tester) async {
      final store = openStore(widgets: [_widget(column: 1, row: 1)]);
      await pumpGrid(tester, store);
      store.selectWidget('fake');
      await tester.pump();

      await tester.drag(
        gripFor(DesktopWidgetCorner.topLeft),
        const Offset(-100, -100),
      );
      await tester.pumpAndSettle();

      final widget = store.widgets.single;
      expect((widget.column, widget.row), (0, 0));
      expect((widget.columnSpan, widget.rowSpan), (3, 2));
    });

    // The minimum is the type's, and it holds the *dragged* corner: a widget
    // that slid out from under the pointer at the limit would be unusable.
    testWidgets('cannot be dragged below the type minimum', (tester) async {
      final store = openStore(widgets: [_widget(columnSpan: 3)]);
      await pumpGrid(tester, store);
      store.selectWidget('fake');
      await tester.pump();

      await tester.drag(
        gripFor(DesktopWidgetCorner.bottomRight),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();

      final widget = store.widgets.single;
      expect(widget.columnSpan, 2);
      expect(widget.column, 0);
    });
  });

  group('widget content', () {
    // The claim the media player's transport buttons rest on: a card that is
    // draggable from anywhere still lets its own controls take a tap. The
    // parent pan and the child tap share an arena, and a press that does not
    // move resolves to the tap.
    testWidgets('a control inside a widget takes the tap, not the drag',
        (tester) async {
      var taps = 0;
      DesktopWidgetRegistry.register(
        DesktopWidgetSpec(
          type: 'fake',
          name: 'Fake widget',
          icon: FontAwesomeIcons.shapes,
          minSpan: (columns: 2, rows: 1),
          maxSpan: (columns: 4, rows: 3),
          builder: (context, widget) => Center(
            child: GestureDetector(
              onTap: () => taps++,
              child: const Text('press me'),
            ),
          ),
        ),
      );

      final store = openStore(widgets: [_widget()]);
      await pumpGrid(tester, store);

      await tester.tap(find.text('press me'));
      await tester.pump();

      expect(taps, 1);
      expect((store.widgets.single.column, store.widgets.single.row), (0, 0));
    });

    testWidgets('dragging from the control still moves the widget',
        (tester) async {
      var taps = 0;
      DesktopWidgetRegistry.register(
        DesktopWidgetSpec(
          type: 'fake',
          name: 'Fake widget',
          icon: FontAwesomeIcons.shapes,
          minSpan: (columns: 2, rows: 1),
          maxSpan: (columns: 4, rows: 3),
          builder: (context, widget) => Center(
            child: GestureDetector(
              onTap: () => taps++,
              child: const Text('press me'),
            ),
          ),
        ),
      );

      final store = openStore(widgets: [_widget()]);
      await pumpGrid(tester, store);

      await tester.drag(find.text('press me'), const Offset(0, 100));
      await tester.pumpAndSettle();

      expect(taps, 0);
      expect(store.widgets.single.row, 1);
    });
  });

  group('context menu', () {
    testWidgets('right-clicking a widget reports it and selects it',
        (tester) async {
      DesktopWidgetItem? reported;
      final store = openStore(widgets: [_widget()]);
      await pumpGrid(tester, store, onWidgetMenu: (w, _) => reported = w);

      final centre = tester.getCenter(find.byType(DesktopWidgetFrame));
      final gesture =
          await tester.startGesture(centre, buttons: kSecondaryButton);
      await gesture.up();
      await tester.pump();

      expect(reported?.id, 'fake');
      expect(store.selectedWidget, 'fake');
    });
  });
}
