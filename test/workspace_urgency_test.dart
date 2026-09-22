import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/modules/workspaces.dart';

/// Pins the workspace row's urgency flash: the shape of one breath, the
/// wall-clock phase that keeps every urgent button on every monitor breathing
/// together, and the widget's three rules — it runs only while it is in the tree,
/// it passes through both colours, and it never takes a click.
///
/// Nothing here may be `pumpAndSettle`ed: a flash that settled would be one that
/// stopped.
void main() {
  group('urgencyFlashWash', () {
    test('rests at the button own colour and peaks at the flash colour', () {
      // Resting at exactly 0 is what makes an urgent workspace pass through
      // the very colour its neighbours are, once a breath — the flash then
      // reads as this button changing rather than as a different button.
      expect(urgencyFlashWash(0), closeTo(0, 1e-9));
      expect(urgencyFlashWash(1), closeTo(0, 1e-9));
      expect(urgencyFlashWash(0.5), closeTo(1, 1e-9));
      expect(urgencyFlashWash(0.25), closeTo(0.5, 1e-9));
      expect(urgencyFlashWash(0.75), closeTo(0.5, 1e-9));
    });

    test('stays inside the unit range across a whole breath', () {
      for (var i = 0; i <= 200; i++) {
        final wash = urgencyFlashWash(i / 200);
        expect(wash, inInclusiveRange(0, 1), reason: 't = ${i / 200}');
      }
    });

    test('is still at both ends and quickest through the middle', () {
      // The point of the raised cosine over a linear ping-pong: a linear one
      // reverses at a corner, and a corner is the one thing in a very slow
      // animation the eye reliably catches — which puts the emphasis on the
      // moment the flash is quietest.
      const step = 0.01;
      final atRest = urgencyFlashWash(step) - urgencyFlashWash(0);
      final atMiddle =
          (urgencyFlashWash(0.25 + step) - urgencyFlashWash(0.25)).abs();
      expect(atRest, lessThan(atMiddle / 10));
      // And symmetric, so the way up and the way down are the same shape.
      for (var i = 0; i <= 50; i++) {
        final t = i / 100;
        expect(urgencyFlashWash(0.5 + t), closeTo(urgencyFlashWash(0.5 - t), 1e-9));
      }
    });
  });

  group('urgencyFlashPhase', () {
    const period = Duration(seconds: 4);

    test('is a function of the wall clock alone', () {
      // Which is the whole point: two bars are two FlutterViews with two
      // tickers started at different moments, and a row of dots pulsing at
      // random phases reads as a rendering fault rather than as one alarm.
      final start = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      expect(urgencyFlashPhase(start, period),
          closeTo(urgencyFlashPhase(start.add(period), period), 1e-9));
      expect(urgencyFlashPhase(start.add(period * 7), period),
          closeTo(urgencyFlashPhase(start, period), 1e-9));
    });

    test('advances proportionally through the period', () {
      // Anchored on an exact multiple of the period, so the arithmetic is
      // visible rather than merely self-consistent.
      final zero = DateTime.fromMillisecondsSinceEpoch(0);
      expect(urgencyFlashPhase(zero, period), closeTo(0, 1e-9));
      expect(urgencyFlashPhase(zero.add(const Duration(seconds: 1)), period),
          closeTo(0.25, 1e-9));
      expect(urgencyFlashPhase(zero.add(const Duration(seconds: 3)), period),
          closeTo(0.75, 1e-9));
    });

    test('answers rather than throws for a period nothing could divide by', () {
      // Unreachable through the config, which clamps — but a division by zero
      // in a bar module is worth being unable to write at all.
      expect(urgencyFlashPhase(DateTime.now(), Duration.zero), 0);
    });
  });

  group('UrgencyFlash', () {
    const period = Duration(seconds: 4);

    Widget host({VoidCallback? onTap}) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: UrgencyFlash(
              color: const Color(0xFF853953),
              period: period,
              borderRadius: BorderRadius.circular(6),
              background: const ColoredBox(color: Color(0xFF2C2C2C)),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: const SizedBox(
                  width: 40,
                  height: 20,
                  child: Text('7'),
                ),
              ),
            ),
          ),
        );

    Color washColour(WidgetTester tester) => (tester
            .widget<DecoratedBox>(find.descendant(
              of: find.byType(IgnorePointer),
              matching: find.byType(DecoratedBox),
            ))
            .decoration as BoxDecoration)
        .color!;

    testWidgets('passes through both colours over one breath', (tester) async {
      await tester.pumpWidget(host());

      // Sampled across a whole period rather than at two arbitrary instants:
      // the phase comes off the real clock, so where in the breath the first
      // frame lands is not this test's to choose.
      var lowest = 1.0;
      var highest = 0.0;
      const samples = 20;
      for (var i = 0; i < samples; i++) {
        final alpha = washColour(tester).a;
        lowest = math.min(lowest, alpha);
        highest = math.max(highest, alpha);
        await tester.pump(period ~/ samples);
      }

      expect(lowest, lessThan(0.05), reason: 'it reaches the resting colour');
      expect(highest, greaterThan(0.95), reason: 'and the flash colour');
    });

    testWidgets('runs a ticker only while it is in the tree', (tester) async {
      await tester.pumpWidget(host());
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      // The caller wraps this only while the workspace is urgent, so the alarm
      // clearing has to leave a bar that costs exactly what it did before the
      // feature existed.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('paints the wash under the label, never over it', (tester) async {
      // The obvious shape — one wash across the whole button — erases the number
      // the user switches by at the top of every breath, which reads as the bar
      // glitching rather than as an alarm. The label is therefore the last child
      // of the stack, and the only unpositioned one, so the two properties cannot
      // be separated by a reorder.
      await tester.pumpWidget(host());

      final stack = tester.widget<Stack>(find.byType(Stack));
      expect(stack.children.last, isA<RepaintBoundary>());
      expect(
          find.descendant(
              of: find.byWidget(stack.children.last), matching: find.text('7')),
          findsOneWidget);
      expect(
          stack.children
              .take(stack.children.length - 1)
              .every((child) => child is Positioned),
          isTrue,
          reason: 'only the label sizes the surface');
    });

    testWidgets('never takes the click that switches workspace', (tester) async {
      // `RenderDecoratedBox.hitTestSelf` answers for any non-null fill, so a
      // full-size wash over the button would swallow the tap — including at the
      // top of the breath, when it is opaque.
      var taps = 0;
      await tester.pumpWidget(host(onTap: () => taps++));

      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byType(GestureDetector));
        await tester.pump(period ~/ 8);
      }

      expect(taps, 8);
    });
  });
}
