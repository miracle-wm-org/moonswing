import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/overlay/sticky_notes/overview_actions.dart';
import 'package:moonswing/overlay/sticky_notes/sticky_note.dart';
import 'package:moonswing/overlay/sticky_notes/sticky_note_layer.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_store.dart';

import 'tap_target.dart';

/// The panel these tests lay the notes around: 800×500, centred on a
/// 1600×1000 output until the offset moves it.
Size _cardSize(Size surface) => const Size(800, 500);

void main() {
  late TodoStore store;
  late ValueNotifier<Offset> offset;
  late GlobalKey<StickyNoteLayerState> layer;
  late int released;
  final now = DateTime(2026, 10, 20, 9);

  Future<void> pump(WidgetTester tester, {List<NoteItem> notes = const []}) {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store = TodoStore.forTesting(notes: notes, now: () => now, inMemory: true);
    addTearDown(store.dispose);
    offset = ValueNotifier(Offset.zero);
    addTearDown(offset.dispose);
    layer = GlobalKey();
    released = 0;
    return tester.pumpWidget(
      ThemeScope(
        theme: const ThemeConfig(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextEditingShortcuts(
            child: StickyNoteLayer(
              key: layer,
              offset: offset,
              cardSizeFor: _cardSize,
              opacity: kAlwaysCompleteAnimation,
              reserved: [overviewActionBarRect(1)],
              onKeyboardReleased: () => released++,
              store: store,
            ),
          ),
        ),
      ),
    );
  }

  Rect noteRect(WidgetTester tester) => tester.getRect(find.byType(StickyNote));

  Future<void> rightClick(WidgetTester tester, Offset at) async {
    await tester.tapAt(
      at,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
  }

  testWidgets('a new note lands beside the panel and takes the keyboard', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(StickyNote), findsNothing);

    final id = layer.currentState!.addNote()!;
    await tester.pump();

    final note = store.note(id)!;
    expect(note.placement.isPlaced, isTrue);
    expect(note.placement.size, StickySize.medium);
    // Left of the panel (whose left edge is at 400), level with its top.
    expect(noteRect(tester), const Rect.fromLTWH(164, 250, 220, 220));
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);

    // A second goes under the first rather than on top of it.
    layer.currentState!.addNote();
    await tester.pump();
    final rects = [
      for (final e in find.byType(StickyNote).evaluate())
        tester.getRect(find.byWidget(e.widget)),
    ];
    expect(rects[0].overlaps(rects[1]), isFalse);
  });

  testWidgets('what is written is saved after a pause, and on Escape', (
    tester,
  ) async {
    await pump(tester);
    final id = layer.currentState!.addNote()!;
    await tester.pump();

    await tester.enterText(find.byType(EditableText), 'buy milk');
    expect(store.note(id)!.body, '');
    await tester.pump(kStickyCommitDelay);
    expect(store.note(id)!.body, 'buy milk');

    await tester.enterText(find.byType(EditableText), 'buy oat milk');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(store.note(id)!.body, 'buy oat milk');
    expect(released, 1, reason: 'the keyboard goes back to the overview');
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isFalse);
  });

  testWidgets('the menu recolours, resizes and removes', (tester) async {
    await pump(tester);
    final id = layer.currentState!.addNote()!;
    await tester.pump();
    expect(layer.currentState!.dismissMenu(), isFalse);

    await rightClick(tester, noteRect(tester).center);
    await tester.tap(find.text('Colour'));
    await tester.pump();
    await tester.tap(find.text('Pink'));
    await tester.pump();
    expect(store.note(id)!.placement.color, StickyColor.pink);
    expect(find.text('Colour'), findsNothing, reason: 'a choice closes it');

    await rightClick(tester, noteRect(tester).center);
    await tester.tap(find.text('Text size'));
    await tester.pump();
    await tester.tap(find.text('Large'));
    await tester.pump();
    expect(store.note(id)!.placement.size, StickySize.large);
    expect(noteRect(tester).size, const Size(220, 220));
    final writing = tester.widget<EditableText>(find.byType(EditableText));
    expect(writing.style.fontSize, stickyFontSize(StickySize.large));

    // Escape's half: the overview asks before closing.
    await rightClick(tester, noteRect(tester).center);
    expect(find.text('Remove note'), findsOneWidget);
    expect(layer.currentState!.dismissMenu(), isTrue);
    await tester.pump();
    expect(find.text('Remove note'), findsNothing);

    await rightClick(tester, noteRect(tester).center);
    await tester.tap(find.text('Remove note'));
    await tester.pump();
    expect(store.notes, isEmpty);
    expect(find.byType(StickyNote), findsNothing);
  });

  testWidgets('a click off the menu closes it and changes nothing', (
    tester,
  ) async {
    await pump(tester);
    final id = layer.currentState!.addNote()!;
    await tester.pump();
    final before = store.note(id);
    await rightClick(tester, noteRect(tester).center);
    await tester.tapAt(const Offset(1500, 900));
    await tester.pump();
    expect(find.text('Remove note'), findsNothing);
    expect(store.note(id), before);
  });

  testWidgets('a note is dragged by its grip, and follows the panel', (
    tester,
  ) async {
    await pump(tester);
    final id = layer.currentState!.addNote()!;
    await tester.pump();
    final start = noteRect(tester);
    final before = store.note(id)!.placement;

    final mouse = await tester.startGesture(
      start.topCenter + const Offset(0, kStickyGripHeight / 2),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 10; i++) {
      await mouse.moveBy(const Offset(10, 5));
      await tester.pump();
    }
    // Moved on screen, not yet in the store.
    expect(noteRect(tester).topLeft, start.topLeft + const Offset(100, 50));
    expect(store.note(id)!.placement, before);
    await mouse.up();
    await tester.pump();
    final after = store.note(id)!.placement;
    expect(after.dx, before.dx! + 100);
    expect(after.dy, before.dy! + 50);
    expect(noteRect(tester).topLeft, start.topLeft + const Offset(100, 50));

    // The panel moves; the note goes with it, with nothing written.
    offset.value = const Offset(-60, 40);
    await tester.pump();
    expect(noteRect(tester).topLeft, start.topLeft + const Offset(40, 90));
    expect(store.note(id)!.placement, after);
  });

  testWidgets('a drag past the edge leaves no dead travel', (tester) async {
    await pump(tester);
    layer.currentState!.addNote();
    await tester.pump();
    final start = noteRect(tester);
    final mouse = await tester.startGesture(
      start.topCenter + const Offset(0, kStickyGripHeight / 2),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(-20, 0));
    await tester.pump();
    await mouse.moveBy(Offset(-start.left - 200, 0));
    await tester.pump();
    expect(noteRect(tester).left, 0);
    await mouse.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(noteRect(tester).left, 30);
    await mouse.up();
  });

  testWidgets('a note with no place is given one', (tester) async {
    await pump(
      tester,
      notes: [
        NoteItem(
          id: 'old',
          title: '',
          body: 'from an old backup',
          created: now,
          updated: now,
        ),
      ],
    );
    await tester.pump();
    final placement = store.note('old')!.placement;
    expect(placement.isPlaced, isTrue);
    expect(
      noteRect(tester).overlaps(const Rect.fromLTWH(400, 250, 800, 500)),
      isFalse,
    );
  });

  testWidgets('nothing animates at rest', (tester) async {
    await pump(tester);
    layer.currentState!.addNote();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('the corner button fires from every corner', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      ThemeScope(
        theme: const ThemeConfig(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: OverviewActionBar(
              actions: [
                OverviewAction(
                  icon: FontAwesomeIcons.noteSticky,
                  label: 'New note',
                  onTap: () => taps++,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tapEveryCorner(tester, find.byType(HoverRegion));
    expect(taps, 4);
  });
}
