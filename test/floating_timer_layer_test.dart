import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/overlay/sticky_notes/floating_timer_layer.dart';
import 'package:moonswing/overlay/sticky_notes/overview_actions.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/timers/timer_sound.dart';
import 'package:moonswing/timers/timer_store.dart';

/// The panel these tests lay the timers around: 800×500, centred on a
/// 1600×1000 output until the offset moves it.
Size _cardSize(Size surface) => const Size(800, 500);

const Rect _panel = Rect.fromLTWH(400, 250, 800, 500);

void main() {
  late TimersStore store;
  late TimerSoundStore sound;
  late ValueNotifier<Offset> offset;
  late GlobalKey<FloatingTimerLayerState> layer;
  late int released;
  late int menusOpened;
  late DateTime clock;

  Future<void> pump(WidgetTester tester, {List<Rect> reserved = const []}) {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    clock = DateTime(2026, 10, 21, 9);
    // Hand-driven: no ticker behind the test zone.
    store = TimersStore.forTesting(now: () => clock);
    addTearDown(store.dispose);
    sound = TimerSoundStore.forTesting();
    addTearDown(sound.dispose);
    offset = ValueNotifier(Offset.zero);
    addTearDown(offset.dispose);
    layer = GlobalKey();
    released = 0;
    menusOpened = 0;
    return tester.pumpWidget(
      ThemeScope(
        theme: const ThemeConfig(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextEditingShortcuts(
            child: FloatingTimerLayer(
              key: layer,
              offset: offset,
              cardSizeFor: _cardSize,
              opacity: kAlwaysCompleteAnimation,
              reserved: () => [overviewActionBarRect(3), ...reserved],
              onKeyboardReleased: () => released++,
              onMenuOpened: () => menusOpened++,
              store: store,
              sound: sound,
            ),
          ),
        ),
      ),
    );
  }

  List<Rect> cards(WidgetTester tester) => [
    for (final e in find.byType(FloatingTimer).evaluate())
      tester.getRect(find.byWidget(e.widget)),
  ];

  Future<void> rightClick(WidgetTester tester, Offset at) async {
    await tester.tapAt(
      at,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
  }

  testWidgets('a new stopwatch lands beside the panel, clear of the rest', (
    tester,
  ) async {
    // A note already left of the panel, level with its top.
    const note = Rect.fromLTWH(164, 250, 220, 220);
    await pump(tester, reserved: [note]);
    expect(find.byType(FloatingTimer), findsNothing);

    final id = layer.currentState!.startStopwatch();
    await tester.pump();
    await tester.pump();

    expect(store.placeOf(id), isNotNull);
    final rect = cards(tester).single;
    expect(rect.size, kFloatingTimerSize);
    expect(rect.overlaps(_panel), isFalse);
    expect(rect.overlaps(note), isFalse);
    expect(rect.overlaps(overviewActionBarRect(3)), isFalse);
    expect(find.text('Stopwatch'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(layer.currentState!.occupied, [rect]);

    // A second goes beside the first rather than on top of it.
    layer.currentState!.startStopwatch();
    await tester.pump();
    await tester.pump();
    final both = cards(tester);
    expect(both, hasLength(2));
    expect(both[0].overlaps(both[1]), isFalse);
  });

  testWidgets('the readout follows the store', (tester) async {
    await pump(tester);
    layer.currentState!.startStopwatch();
    await tester.pump();
    await tester.pump();

    clock = clock.add(const Duration(minutes: 1, seconds: 5));
    store.tick();
    await tester.pump();
    expect(find.text('01:05'), findsOneWidget);
  });

  testWidgets('the composer opens under the button, starts, and lets go', (
    tester,
  ) async {
    await pump(tester);
    final button = overviewActionRect(1);
    layer.currentState!.openComposer(button);
    await tester.pump();
    expect(menusOpened, 1);

    final start = find.text('Start timer');
    expect(start, findsOneWidget);
    // The field has the keyboard, so a length is typed straight in.
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
    expect(
      tester.getTopLeft(find.byType(EditableText)).dy,
      greaterThan(button.bottom),
    );

    await tester.enterText(find.byType(EditableText), '2:30');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();

    expect(store.entries.single.total, const Duration(minutes: 2, seconds: 30));
    expect(find.text('Start timer'), findsNothing, reason: 'it closes');
    expect(released, 1, reason: 'the keyboard goes back to the overview');
    expect(find.text('02:30'), findsOneWidget);
    expect(find.text('Timer · 02:30'), findsOneWidget);
  });

  testWidgets('the composer closes on Escape and on a click off it', (
    tester,
  ) async {
    await pump(tester);
    expect(layer.currentState!.dismissMenu(), isFalse);

    layer.currentState!.openComposer(overviewActionRect(1));
    await tester.pump();
    // Escape's half: the overview asks before closing.
    expect(layer.currentState!.dismissMenu(), isTrue);
    await tester.pump();
    expect(find.text('Start timer'), findsNothing);
    expect(released, 1);

    layer.currentState!.openComposer(overviewActionRect(1));
    await tester.pump();
    await tester.tapAt(const Offset(1500, 900));
    await tester.pump();
    expect(find.text('Start timer'), findsNothing);
    expect(store.isEmpty, isTrue);
    expect(released, 2);
  });

  testWidgets('the menu pauses, resumes, resets and removes', (tester) async {
    await pump(tester);
    final id = store.startTimer(const Duration(minutes: 5));
    await tester.pump();
    await tester.pump();
    Offset centre() => cards(tester).single.center;

    clock = clock.add(const Duration(minutes: 1));
    await rightClick(tester, centre());
    expect(menusOpened, 1);
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(store.entry(id)!.running, isFalse);
    expect(find.text('Pause'), findsNothing, reason: 'a choice closes it');
    expect(find.text('Timer · 05:00 · Paused'), findsOneWidget);
    expect(find.text('04:00'), findsOneWidget);

    await rightClick(tester, centre());
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(find.text('05:00'), findsOneWidget);

    await rightClick(tester, centre());
    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(store.entry(id)!.running, isTrue);

    await rightClick(tester, centre());
    await tester.tap(find.text('Remove timer'));
    await tester.pump();
    expect(store.isEmpty, isTrue);
    expect(find.byType(FloatingTimer), findsNothing);
  });

  testWidgets('a finished countdown offers a restart', (tester) async {
    await pump(tester);
    final id = store.startTimer(const Duration(minutes: 1));
    await tester.pump();
    await tester.pump();
    clock = clock.add(const Duration(minutes: 2));
    store.tick();
    await tester.pump();
    expect(store.entry(id)!.finished, isTrue);

    await rightClick(tester, cards(tester).single.center);
    expect(find.text('Resume'), findsNothing);
    await tester.tap(find.text('Restart'));
    await tester.pump();
    expect(store.entry(id)!.running, isTrue);
    expect(store.entry(id)!.finished, isFalse);
  });

  testWidgets('a stopwatch says what it removes', (tester) async {
    await pump(tester);
    layer.currentState!.startStopwatch();
    await tester.pump();
    await tester.pump();
    await rightClick(tester, cards(tester).single.center);
    expect(find.text('Remove stopwatch'), findsOneWidget);
    // A click off the menu closes it and changes nothing.
    await tester.tapAt(const Offset(1500, 900));
    await tester.pump();
    expect(find.text('Remove stopwatch'), findsNothing);
    expect(store.length, 1);
  });

  testWidgets('a card is dragged anywhere on it, and follows the panel', (
    tester,
  ) async {
    await pump(tester);
    final id = layer.currentState!.startStopwatch();
    await tester.pump();
    await tester.pump();
    final start = cards(tester).single;
    final before = store.placeOf(id)!;

    final mouse = await tester.startGesture(
      start.bottomRight - const Offset(4, 4),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 10; i++) {
      await mouse.moveBy(const Offset(10, 5));
      await tester.pump();
    }
    // Moved on screen, not yet in the store.
    expect(cards(tester).single.topLeft, start.topLeft + const Offset(100, 50));
    expect(store.placeOf(id), before);
    await mouse.up();
    await tester.pump();
    expect(store.placeOf(id), before + const Offset(100, 50));
    expect(cards(tester).single.topLeft, start.topLeft + const Offset(100, 50));

    // The panel moves; the card goes with it, with nothing written.
    offset.value = const Offset(-60, 40);
    await tester.pump();
    expect(cards(tester).single.topLeft, start.topLeft + const Offset(40, 90));
    expect(store.placeOf(id), before + const Offset(100, 50));
  });

  testWidgets('a drag past the edge leaves no dead travel', (tester) async {
    await pump(tester);
    layer.currentState!.startStopwatch();
    await tester.pump();
    await tester.pump();
    final start = cards(tester).single;
    final mouse = await tester.startGesture(
      start.center,
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(-20, 0));
    await tester.pump();
    await mouse.moveBy(Offset(-start.left - 200, 0));
    await tester.pump();
    expect(cards(tester).single.left, 0);
    await mouse.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(cards(tester).single.left, 30);
    await mouse.up();
  });

  testWidgets('a place outlives the layer, as the overview is reopened', (
    tester,
  ) async {
    await pump(tester);
    final id = layer.currentState!.startStopwatch();
    await tester.pump();
    await tester.pump();
    final first = cards(tester).single;

    await tester.pumpWidget(const SizedBox());
    expect(store.placeOf(id), isNotNull);
    await tester.pumpWidget(
      ThemeScope(
        theme: const ThemeConfig(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FloatingTimerLayer(
            offset: offset,
            cardSizeFor: _cardSize,
            opacity: kAlwaysCompleteAnimation,
            store: store,
            sound: sound,
          ),
        ),
      ),
    );
    expect(cards(tester).single, first);
  });

  testWidgets('nothing animates at rest', (tester) async {
    await pump(tester);
    layer.currentState!.startStopwatch();
    await tester.pump();
    await tester.pump();
    await rightClick(tester, cards(tester).single.center);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    layer.currentState!.dismissMenu();
    await tester.pumpAndSettle();
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  test('a button box is where the bar draws it', () {
    final bar = overviewActionBarRect(3);
    expect(overviewActionRect(0).topLeft, bar.topLeft);
    expect(overviewActionRect(2).bottomRight, bar.bottomRight);
  });
}
