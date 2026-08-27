// The geometry of the lit region.
//
// The picture itself is not something a test can judge, but the *shape* is: a
// crescent has to be a crescent, a gibbous has to be more than half a disc, and
// neither may ever be drawn outside the circle. The terminator is the one piece
// of this file's arithmetic that a plausible-looking mistake survives — two
// overlapping circles produce a perfectly convincing crescent and cannot draw a
// gibbous at all — so it is pinned by containment rather than by eye.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/moon/moon_render.dart';

const Offset _centre = Offset(100, 100);
const double _radius = 50;

Path _lit(double illumination, {bool waxing = true}) => moonLitPath(
      centre: _centre,
      radius: _radius,
      illumination: illumination,
      waxing: waxing,
    );

/// A point [fraction] of the way from the centre towards the lit limb of a
/// waxing Moon.
Offset _right(double fraction) => _centre.translate(_radius * fraction, 0);

Offset _left(double fraction) => _centre.translate(-_radius * fraction, 0);

void main() {
  group('moonLitPath', () {
    test('a full Moon is the whole disc', () {
      final path = _lit(1);
      expect(path.contains(_centre), isTrue);
      expect(path.contains(_right(0.95)), isTrue);
      expect(path.contains(_left(0.95)), isTrue);
      final bounds = path.getBounds();
      expect(bounds.width, closeTo(_radius * 2, 0.5));
      expect(bounds.height, closeTo(_radius * 2, 0.5));
    });

    test('a new Moon encloses nothing at all', () {
      // Measured by containment rather than by bounds: at zero the terminator
      // lies exactly along the limb, so the outline still spans the lit half of
      // the box while enclosing no area whatsoever.
      final path = _lit(0);
      expect(path.contains(_centre), isFalse);
      expect(path.contains(_right(0.5)), isFalse);
      expect(path.contains(_right(0.95)), isFalse);
    });

    test('a quarter is exactly half the disc, split down the middle', () {
      final path = _lit(0.5);
      final bounds = path.getBounds();
      expect(bounds.left, closeTo(_centre.dx, 0.5));
      expect(bounds.width, closeTo(_radius, 0.5));
      expect(bounds.height, closeTo(_radius * 2, 0.5));
      expect(path.contains(_right(0.5)), isTrue);
      expect(path.contains(_left(0.5)), isFalse);
    });

    test('a crescent is thinner than half, and hollow at the centre', () {
      final path = _lit(0.2);
      expect(path.contains(_right(0.9)), isTrue);
      expect(path.contains(_centre), isFalse);
      expect(path.contains(_right(0.3)), isFalse);
      // The horns still reach the poles of the disc: a crescent is a lens
      // between two arcs of the same circle, not a smaller circle bitten out.
      expect(path.getBounds().height, closeTo(_radius * 2, 0.5));
    });

    test('a gibbous is more than half, and never more than the disc', () {
      final path = _lit(0.8);
      expect(path.contains(_centre), isTrue);
      expect(path.contains(_left(0.5)), isTrue);
      expect(path.contains(_left(0.95)), isFalse);
      final bounds = path.getBounds();
      expect(bounds.width, greaterThan(_radius));
      expect(bounds.width, lessThanOrEqualTo(_radius * 2 + 0.5));
    });

    test('waning is the mirror of waxing', () {
      final waxing = _lit(0.25);
      final waning = _lit(0.25, waxing: false);
      expect(waxing.contains(_right(0.9)), isTrue);
      expect(waxing.contains(_left(0.9)), isFalse);
      expect(waning.contains(_left(0.9)), isTrue);
      expect(waning.contains(_right(0.9)), isFalse);
      // Same area, opposite side.
      expect(
        waning.getBounds().width,
        closeTo(waxing.getBounds().width, 0.01),
      );
    });

    test('an out-of-range fraction is clamped rather than inverted', () {
      // Nothing should be able to hand this a negative area or a path outside
      // the disc, whatever arrives from a future caller.
      expect(_lit(-1).contains(_centre), isFalse);
      expect(_lit(2).contains(_centre), isTrue);
      expect(_lit(2).getBounds().width, closeTo(_radius * 2, 0.5));
    });
  });

  group('MoonPainter', () {
    test('repaints only when the picture would differ', () {
      const base = MoonPainter(illumination: 0.5, waxing: true);
      expect(
        base.shouldRepaint(
          const MoonPainter(illumination: 0.5, waxing: true),
        ),
        isFalse,
      );
      expect(
        base.shouldRepaint(
          const MoonPainter(illumination: 0.6, waxing: true),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const MoonPainter(illumination: 0.5, waxing: false),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const MoonPainter(
            illumination: 0.5,
            waxing: true,
            southernView: true,
          ),
        ),
        isTrue,
      );
    });
  });

  group('MoonDisc', () {
    testWidgets('paints at every phase without a ticker behind it',
        (tester) async {
      for (final phase in [0.0, 0.12, 0.5, 0.87, 1.0]) {
        await tester.pumpWidget(
          Center(
            child: SizedBox(
              width: 120,
              height: 120,
              child: MoonDisc(illumination: phase, waxing: phase < 0.5),
            ),
          ),
        );
        // Nothing here animates, so this settles — which is the property that
        // makes the widget above it testable at all.
        await tester.pumpAndSettle();
        expect(find.byType(MoonDisc), findsOneWidget);
      }
    });

    testWidgets('the night sky settles too', (tester) async {
      await tester.pumpWidget(
        const SizedBox(
          width: 200,
          height: 120,
          child: MoonNightSky(illumination: 0.9),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MoonNightSky), findsOneWidget);
    });
  });

  group('drawnIllumination', () {
    test('snaps to a step the terminator could not have shown', () {
      // The lit fraction moves by under 1e-4 a minute at its fastest, so a
      // painter handed the raw number repaints every tick for a change of a
      // twentieth of a pixel. A thousandth of the disc is the floor of what the
      // picture can express.
      expect(drawnIllumination(0.5), closeTo(0.5, 1e-9));
      expect(drawnIllumination(0.5001), closeTo(0.5, 1e-9));
      expect(drawnIllumination(0.50049), closeTo(0.5, 1e-9));
      expect(drawnIllumination(0.5006), closeTo(0.501, 1e-9));
    });

    test('keeps the ends, and clamps outside them', () {
      // A new Moon has to stay a new Moon and a full one full: rounding to the
      // printed percentage instead would round the last sliver of a crescent
      // away, which is why the step is a thousandth and not a hundredth.
      expect(drawnIllumination(0), closeTo(0, 1e-9));
      expect(drawnIllumination(1), closeTo(1, 1e-9));
      expect(drawnIllumination(0.0004), closeTo(0, 1e-9));
      expect(drawnIllumination(0.004), closeTo(0.004, 1e-9));
      expect(drawnIllumination(-0.2), closeTo(0, 1e-9));
      expect(drawnIllumination(1.4), closeTo(1, 1e-9));
    });

    test('a painter built from it compares equal across a tick', () {
      // The point of the whole thing: `shouldRepaint` is what stands between a
      // reading that moves every minute and the most expensive painter in the
      // shell.
      final before = MoonPainter(
        illumination: drawnIllumination(0.5),
        waxing: true,
      );
      final after = MoonPainter(
        illumination: drawnIllumination(0.50021),
        waxing: true,
      );
      expect(after.shouldRepaint(before), isFalse);
      expect(
        MoonPainter(illumination: drawnIllumination(0.503), waxing: true)
            .shouldRepaint(before),
        isTrue,
      );
    });
  });
}
