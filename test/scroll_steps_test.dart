import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/scroll_steps.dart';

void main() {
  group('ScrollStepAccumulator', () {
    test('a notched wheel moves one step per notch', () {
      final acc = ScrollStepAccumulator();
      expect(acc.add(53), 1);
      expect(acc.add(53), 1);
      expect(acc.add(-53), -1);
    });

    test('small deltas carry until they add up to a step', () {
      final acc = ScrollStepAccumulator();
      for (var i = 0; i < 4; i++) {
        expect(acc.add(10), 0);
      }
      expect(acc.add(10), 1);
      expect(acc.add(10), 0);
    });

    test('a long delta crosses several steps at once', () {
      expect(ScrollStepAccumulator().add(-160), -3);
    });

    test('a reversal drops what was owed the other way', () {
      final acc = ScrollStepAccumulator();
      expect(acc.add(40), 0);
      expect(acc.add(-40), 0);
      expect(acc.add(-10), -1);
    });

    test('reset forgets a partial step', () {
      final acc = ScrollStepAccumulator();
      acc.add(40);
      acc.reset();
      expect(acc.add(40), 0);
    });

    test('a non-finite delta is ignored', () {
      final acc = ScrollStepAccumulator();
      expect(acc.add(double.nan), 0);
      expect(acc.add(double.infinity), 0);
      expect(acc.add(50), 1);
    });
  });

  group('ScrollSteps', () {
    Future<List<int>> pumpSteps(
      WidgetTester tester, {
      bool enabled = true,
    }) async {
      final reported = <int>[];
      await tester.pumpWidget(
        Center(
          child: ScrollSteps(
            onSteps: enabled ? reported.add : null,
            child: const SizedBox(width: 40, height: 20),
          ),
        ),
      );
      return reported;
    }

    testWidgets('a wheel up is a step up, a wheel down a step down', (
      tester,
    ) async {
      final reported = await pumpSteps(tester);
      // A corner, not the centre: the listener must take the whole box.
      final at =
          tester.getTopLeft(find.byType(ScrollSteps)) + const Offset(1, 1);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(at));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -53)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 53)));
      expect(reported, [1, -1]);
    });

    testWidgets('a sideways scroll counts, right as up', (tester) async {
      final reported = await pumpSteps(tester);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.byType(ScrollSteps))),
      );
      await tester.sendEventToBinding(pointer.scroll(const Offset(53, 0)));
      expect(reported, [1]);
    });

    testWidgets('a touchpad pan counts by distance', (tester) async {
      final reported = await pumpSteps(tester);
      final pointer = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(
        pointer.panZoomStart(tester.getCenter(find.byType(ScrollSteps))),
      );
      // Fingers moving down: the content follows them, which is scrolling up.
      await tester.sendEventToBinding(
        pointer.panZoomUpdate(
          tester.getCenter(find.byType(ScrollSteps)),
          pan: const Offset(0, 30),
        ),
      );
      expect(reported, isEmpty);
      await tester.sendEventToBinding(
        pointer.panZoomUpdate(
          tester.getCenter(find.byType(ScrollSteps)),
          pan: const Offset(0, 60),
        ),
      );
      await tester.sendEventToBinding(pointer.panZoomEnd());
      expect(reported, [1]);
    });

    testWidgets('a null callback reports nothing', (tester) async {
      final reported = await pumpSteps(tester, enabled: false);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.byType(ScrollSteps))),
      );
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -53)));
      expect(reported, isEmpty);
    });
  });
}
