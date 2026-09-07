// The analog clock desktop widget: the hand geometry, the face's detail
// ladder, the lease, and the two promises the card is built on — that it never
// draws seconds, and that the minute turning over does not repaint the desktop
// around it.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/clock/clock_face.dart';
import 'package:graceful_shell/clock/clock_hands.dart';
import 'package:graceful_shell/clock/minute_clock_store.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/widgets/analog_clock_widget.dart';
import 'package:graceful_shell/desktop/widgets/desktop_widget.dart';
import 'package:graceful_shell/scopes.dart';

import 'paint_counter.dart';

/// The content box of a 1x1 card on the default grid: a 96px cell less the
/// spec's own inset, which is the box the widget's builder is handed.
const Size _oneByOne = Size(84, 84);

/// The same for 2x2 — `2*96 + 12` less the inset — the widget's default span.
const Size _twoByTwo = Size(192, 192);

final DateTime _tenTwenty = DateTime(2026, 9, 7, 10, 20, 30);

({MinuteClockStore store, void Function(DateTime) setNow}) _store({
  DateTime? start,
}) {
  var now = start ?? _tenTwenty;
  final store = MinuteClockStore.forTesting(clock: () => now);
  addTearDown(store.dispose);
  return (store: store, setNow: (value) => now = value);
}

Future<void> pumpClock(
  WidgetTester tester,
  Widget child, {
  Size size = _twoByTwo,
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
              width: size.width,
              height: size.height,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

ClockFacePainter _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.descendant(
      of: find.byType(ClockFace),
      matching: find.byType(CustomPaint),
    ))
    .painter! as ClockFacePainter;

/// What the face on screen actually draws, which is a question about the box it
/// was given — the painter resolves it at paint time.
ClockDialDetail _detail(WidgetTester tester) {
  final box = tester.getRect(find.descendant(
    of: find.byType(ClockFace),
    matching: find.byType(CustomPaint),
  ));
  return _painter(tester).detailFor(math.min(box.width, box.height) / 2);
}

void main() {
  group('where the hands point', () {
    test('twelve is straight up and three is a quarter turn', () {
      expect(ClockHands.at(DateTime(2026, 9, 7, 12)).hourTurns, 0);
      expect(ClockHands.at(DateTime(2026, 9, 7, 12)).minuteTurns, 0);
      expect(ClockHands.at(DateTime(2026, 9, 7, 3)).hourTurns, 0.25);
      expect(ClockHands.at(DateTime(2026, 9, 7, 12, 15)).minuteTurns, 0.25);
    });

    test('midnight and noon both point up, not off the end of the dial', () {
      expect(ClockHands.at(DateTime(2026, 9, 7, 0)).hourTurns, 0);
      expect(ClockHands.at(DateTime(2026, 9, 7, 23)).hourTurns,
          closeTo(11 / 12, 1e-12));
    });

    test('the hour hand carries the minutes with it', () {
      // An hour hand that jumps between numerals reads as a broken clock: at
      // half past six it is halfway between the six and the seven.
      final half = ClockHands.at(DateTime(2026, 9, 7, 6, 30));
      expect(half.hourTurns, closeTo(6.5 / 12, 1e-12));
      expect(half.minuteTurns, 0.5);
    });

    test('the seconds are dropped, which is the whole feature', () {
      // Nothing on this card may depend on the second, or the store behind it
      // would have to wake sixty times as often on every monitor.
      expect(
        ClockHands.at(DateTime(2026, 9, 7, 10, 20, 59, 999)),
        ClockHands.at(DateTime(2026, 9, 7, 10, 20)),
      );
    });

    test('radians agree with turns', () {
      final hands = ClockHands.at(DateTime(2026, 9, 7, 3, 15));
      expect(hands.hourRadians, closeTo(hands.hourTurns * 2 * math.pi, 1e-12));
      expect(
          hands.minuteRadians, closeTo(hands.minuteTurns * 2 * math.pi, 1e-12));
    });
  });

  group('the direction of a mark', () {
    test('runs clockwise from twelve, in screen coordinates', () {
      // y is *down*, so twelve is negative y — the sign that decides whether
      // the clock runs backwards.
      expect(clockDirection(0).dx, closeTo(0, 1e-12));
      expect(clockDirection(0).dy, closeTo(-1, 1e-12));
      expect(clockDirection(0.25).dx, closeTo(1, 1e-12));
      expect(clockDirection(0.25).dy, closeTo(0, 1e-12));
      expect(clockDirection(0.5).dy, closeTo(1, 1e-12));
      expect(clockDirection(0.75).dx, closeTo(-1, 1e-12));
    });
  });

  group('the dial buys its detail at the size it has', () {
    test('takes the hour marks alone on a small face', () {
      expect(ClockDialDetail.forRadius(20), ClockDialDetail.hours);
      expect(ClockDialDetail.forRadius(kMinuteTickDialRadius - 1),
          ClockDialDetail.hours);
    });

    test('adds the minute marks, then the numerals', () {
      expect(ClockDialDetail.forRadius(kMinuteTickDialRadius),
          ClockDialDetail.minutes);
      expect(ClockDialDetail.forRadius(kNumeralDialRadius - 1),
          ClockDialDetail.minutes);
      expect(ClockDialDetail.forRadius(kNumeralDialRadius),
          ClockDialDetail.numerals);
      expect(ClockDialDetail.forRadius(400), ClockDialDetail.numerals);
    });

    test('the ladder only ever adds', () {
      expect(ClockDialDetail.hours.hasMinuteTicks, isFalse);
      expect(ClockDialDetail.hours.hasNumerals, isFalse);
      expect(ClockDialDetail.minutes.hasMinuteTicks, isTrue);
      expect(ClockDialDetail.minutes.hasNumerals, isFalse);
      expect(ClockDialDetail.numerals.hasMinuteTicks, isTrue);
      expect(ClockDialDetail.numerals.hasNumerals, isTrue);
    });
  });

  group('the card', () {
    testWidgets('draws the face at every span the registry allows',
        (tester) async {
      for (final size in const [_oneByOne, _twoByTwo, Size(420, 420)]) {
        await pumpClock(tester, AnalogClockWidget(store: _store().store),
            size: size);
        expect(find.byType(ClockFace), findsOneWidget, reason: '$size');
      }
    });

    testWidgets('sets the hands from the store', (tester) async {
      final s = _store();
      await pumpClock(tester, AnalogClockWidget(store: s.store));
      expect(_painter(tester).hands, ClockHands.at(_tenTwenty));
    });

    testWidgets('takes the shorter edge, so the dial stays round',
        (tester) async {
      await pumpClock(tester, AnalogClockWidget(store: _store().store),
          size: const Size(420, 120));
      final face = tester.getRect(find.descendant(
        of: find.byType(ClockFace),
        matching: find.byType(CustomPaint),
      ));
      expect(face.width, face.height);
      expect(face.width, 120);
    });

    testWidgets('shrinks into a box smaller than any cell without overflowing',
        (tester) async {
      // A cell is configurable down to 32px. A circle scales cleanly where a
      // column of text would have to be clipped, so this one simply gets small
      // rather than reporting a flex overflow every frame on a surface whose
      // console nobody is reading.
      await pumpClock(tester, AnalogClockWidget(store: _store().store),
          size: const Size(24, 24));
      expect(tester.takeException(), isNull);
      expect(find.byType(ClockFace), findsOneWidget);
      expect(_detail(tester), ClockDialDetail.hours);
    });

    testWidgets('drops the marks it has no room for and adds them back',
        (tester) async {
      await pumpClock(tester, AnalogClockWidget(store: _store().store),
          size: _oneByOne);
      expect(_detail(tester), ClockDialDetail.hours);

      await pumpClock(tester, AnalogClockWidget(store: _store().store),
          size: _twoByTwo);
      expect(_detail(tester), ClockDialDetail.numerals);
    });

    testWidgets('restyles with the theme rather than freezing a palette',
        (tester) async {
      const other = ThemeConfig(accent: Color(0xFF00FF00));
      final store = _store().store;

      await pumpClock(tester, AnalogClockWidget(store: store));
      expect(_painter(tester).palette, ClockFacePalette.of(const ThemeConfig()));

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 14),
            child: ThemeScope(
              theme: other,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: _twoByTwo.width,
                  height: _twoByTwo.height,
                  child: AnalogClockWidget(store: store),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(_painter(tester).palette, ClockFacePalette.of(other));
      expect(_painter(tester).palette.cap, const Color(0xFF00FF00));
    });
  });

  group('the lease', () {
    testWidgets('is taken and released with the widget lifetime',
        (tester) async {
      final s = _store();
      await pumpClock(tester, AnalogClockWidget(store: s.store));
      expect(s.store.leaseCount, 1);
      expect(s.store.ticking, isTrue);

      await tester.pumpWidget(const SizedBox());
      expect(s.store.leaseCount, 0);
      // The card is gone, so nothing is left waiting for the minute.
      expect(s.store.ticking, isFalse);
    });

    testWidgets('moves when the store does', (tester) async {
      final first = _store();
      final second = _store();

      await pumpClock(tester, AnalogClockWidget(store: first.store));
      expect(first.store.leaseCount, 1);

      await pumpClock(tester, AnalogClockWidget(store: second.store));
      expect(first.store.leaseCount, 0);
      expect(second.store.leaseCount, 1);
    });
  });

  group('the minute turning over', () {
    testWidgets('moves the hands without being rebuilt from above',
        (tester) async {
      final s = _store();
      await pumpClock(tester, AnalogClockWidget(store: s.store));
      expect(_painter(tester).hands, ClockHands.at(_tenTwenty));

      s.setNow(DateTime(2026, 9, 7, 10, 21));
      s.store.tickNow();
      await tester.pump();

      expect(_painter(tester).hands,
          ClockHands.at(DateTime(2026, 9, 7, 10, 21)));
    });

    testWidgets('does not repaint the surface around the card',
        (tester) async {
      // The desktop surface has no repaint boundary of its own, so anything
      // marked needing paint outside the face re-records the whole picture and
      // damages the whole output — once a minute, on every monitor. This is the
      // test that the boundary inside `ClockFace` actually contains it.
      final s = _store();
      await pumpClock(
        tester,
        RepaintBoundary(
          child: PaintCounter(child: AnalogClockWidget(store: s.store)),
        ),
      );
      final counter =
          tester.renderObject<RenderPaintCounter>(find.byType(PaintCounter));
      final before = counter.paints;

      s.setNow(DateTime(2026, 9, 7, 10, 21));
      s.store.tickNow();
      await tester.pump();

      expect(_painter(tester).hands,
          ClockHands.at(DateTime(2026, 9, 7, 10, 21)));
      expect(counter.paints, before, reason: 'the repaint stayed in the face');
    });
  });

  group('nothing on the card animates', () {
    testWidgets('it settles, and leaves no ticker behind', (tester) async {
      // The lunar, fortune and Tux cards' rule, and the reason this one has no
      // second hand: a `Ticker` added anywhere in here hangs this test rather
      // than failing it.
      await pumpClock(tester, AnalogClockWidget(store: _store().store));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);

      await pumpClock(tester, AnalogClockWidget(store: _store().store),
          size: _oneByOne);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('the card stays draggable', () {
    testWidgets('it claims no gesture of its own', (tester) async {
      // The desktop grid drags a widget from anywhere on its card. A clock is
      // read, never pressed, so it takes no recognizer at all — and a drag
      // across it has to reach the grid.
      var pans = 0;
      await pumpClock(
        tester,
        GestureDetector(
          onPanUpdate: (_) => pans++,
          child: AnalogClockWidget(store: _store().store),
        ),
      );

      await tester.drag(find.byType(AnalogClockWidget), const Offset(60, 0));
      await tester.pump();

      expect(pans, greaterThan(0));
    });
  });

  group('the registry entry', () {
    test('is what the "Add widget…" menu needs', () {
      expect(analogClockDesktopWidget.type, 'analog_clock');
      expect(analogClockDesktopWidget.name, 'Analog clock');
      expect(analogClockDesktopWidget.icon, analogClockDesktopWidgetIcon);
      expect(analogClockDesktopWidget.description, isNotEmpty);
    });

    test('fits one cell and defaults to a face with its marks', () {
      expect(analogClockDesktopWidget.minSpan, (columns: 1, rows: 1));
      expect(analogClockDesktopWidget.defaultSpan, (columns: 2, rows: 2));
    });

    test('clamps a span authored outside its limits', () {
      const item = DesktopWidgetItem(
        id: 'analog_clock-1',
        type: 'analog_clock',
        column: 0,
        row: 0,
        columnSpan: 12,
        rowSpan: 12,
      );
      expect(spanFor(analogClockDesktopWidget, item),
          analogClockDesktopWidget.maxSpan);
    });

    testWidgets('builds', (tester) async {
      const item = DesktopWidgetItem(
        id: 'analog_clock-1',
        type: 'analog_clock',
        column: 0,
        row: 0,
      );
      await pumpClock(
        tester,
        Builder(
          builder: (context) => analogClockDesktopWidget.builder(
            context,
            DesktopWidgetContext(
              item: item,
              size: _twoByTwo,
              span: analogClockDesktopWidget.defaultSpan,
            ),
          ),
        ),
      );
      expect(find.byType(ClockFace), findsOneWidget);
      // The registry's builder reaches the process-wide store, so the lease it
      // took has to come back off it when the card goes.
      await tester.pumpWidget(const SizedBox());
      expect(MinuteClockStore.instance.leaseCount, 0);
    });
  });
}
