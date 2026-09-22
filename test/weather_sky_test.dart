import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/weather/weather_condition.dart';
import 'package:moonswing/weather/weather_sky.dart';

SkyField _field(int code, {double? cover, bool night = false}) {
  final condition = conditionForCode(code);
  return SkyField.build(
    condition: condition,
    cloudCover: cover ?? condition.cloudCover,
    night: night,
  );
}

void main() {
  group('cloudsForCover', () {
    test('a clear sky draws no clouds at all', () {
      // The one case that has to be exact: a stray cloud over a "Clear sky"
      // label is the animation contradicting the reading beside it.
      expect(cloudsForCover(0), 0);
      expect(cloudsForCover(0.04), 0);
    });

    test('any cover to speak of draws at least one', () {
      expect(cloudsForCover(0.05), greaterThanOrEqualTo(1));
      expect(cloudsForCover(0.1), greaterThanOrEqualTo(1));
    });

    test('rises with the cover and stops at the ceiling', () {
      expect(cloudsForCover(0.25), lessThan(cloudsForCover(0.75)));
      expect(cloudsForCover(1.0), kMaxClouds);
      // Out-of-range input is clamped rather than producing a runaway count.
      expect(cloudsForCover(3.5), kMaxClouds);
      expect(cloudsForCover(-1), 0);
    });
  });

  group('SkyField', () {
    test('is deterministic, so the same weather draws the same sky', () {
      // A cloud field that reshuffled itself whenever the widget rebuilt would
      // be the most distracting thing on the desktop — and the two monitors
      // would disagree.
      final a = _field(3);
      final b = _field(3);
      expect(a.clouds.length, b.clouds.length);
      expect(a.clouds.first.x, b.clouds.first.x);
      expect(a.clouds.first.puffs, b.clouds.first.puffs);
    });

    test('nothing falls out of a clear sky', () {
      expect(_field(0).drops, isEmpty);
      expect(_field(2).drops, isEmpty);
      expect(_field(3).drops, isEmpty);
    });

    test('heavier weather drops more', () {
      expect(_field(61).drops.length, lessThan(_field(65).drops.length));
      expect(_field(71).drops.length, lessThan(_field(75).drops.length));
      expect(_field(65).drops.length, lessThanOrEqualTo(kMaxDrops));
    });

    test('snow falls as flakes, rain as streaks and hail as pellets', () {
      // The shape is on the drop rather than re-derived in the painter, which
      // is what lets the next case be a genuine mixture.
      expect(_field(75).drops.every((d) => d.shape == SkyDropShape.flake),
          isTrue);
      expect(_field(65).drops.every((d) => d.shape == SkyDropShape.streak),
          isTrue);
      expect(_field(96).drops.every((d) => d.shape == SkyDropShape.pellet),
          isTrue);
    });

    test('sleet is the mixed case, so only some of it falls as flakes', () {
      // One shape for the whole field makes freezing rain either a blizzard or
      // a vertical sheet.
      final shapes = _field(66).drops.map((d) => d.shape).toSet();
      expect(shapes, contains(SkyDropShape.flake));
      expect(shapes, contains(SkyDropShape.streak));
    });

    test('a still field is spread down the whole card, not clumped', () {
      // The one thing motion used to excuse: a frozen frame is studied, so the
      // drops are stratified rather than scattered. Nothing may sit in a band.
      final drops = _field(63).drops;
      expect(drops.map((d) => d.y).reduce(math.min), lessThan(0.15));
      expect(drops.map((d) => d.y).reduce(math.max), greaterThan(0.85));
      // And they are not all the same weight, or the field reads as a screen
      // door rather than as rain with depth in it.
      expect(drops.map((d) => d.opacity).toSet().length, greaterThan(1));
    });

    test('stars come out at night, under a sky that has gaps in it', () {
      expect(_field(0, night: true).stars, isNotEmpty);
      expect(_field(0, night: false).stars, isEmpty);
      // Behind a lid they would not be visible, and painting them there is work
      // nobody sees.
      expect(_field(3, night: true).stars, isEmpty);
    });

    test('stars stay out of the bottom third, where the readout is', () {
      for (final star in _field(0, night: true).stars) {
        expect(star.y, lessThan(0.6));
      }
    });

    test('only fog gets fog bands', () {
      expect(_field(45).fogBands, isNotEmpty);
      expect(_field(3).fogBands, isEmpty);
      // Offset in both directions, so the bands lie past each other rather
      // than stacking into one flat veil.
      final shifts = _field(45).fogBands.map((b) => b.shift).toList();
      expect(shifts.any((s) => s > 0), isTrue);
      expect(shifts.any((s) => s < 0), isTrue);
      // And at distinct heights, which is the other half of the same picture.
      expect(_field(45).fogBands.map((b) => b.y).toSet().length,
          _field(45).fogBands.length);
    });

    test('only the thunderstorms get a bolt', () {
      // A flash is meaningless in a picture painted once — it is either always
      // on or never seen — so a still storm gets one stroke instead.
      expect(_field(95).bolt, isNotNull);
      expect(_field(99).bolt, isNotNull);
      expect(_field(65).bolt, isNull);
      // Top to bottom, left of the sun: `kCelestialCentre` is at 0.78 of the
      // width and a bolt through the disc reads as a mistake.
      final points = _field(95).bolt!.points;
      expect(points.length, greaterThan(2));
      expect(points.first.dy, lessThan(points.last.dy));
      expect(points.every((p) => p.dx < kCelestialCentre.dx), isTrue);
    });

    test('the clouds carry depth, and are ordered back to front', () {
      // The still picture's substitute for parallax. Without it a static field
      // reads as stickers on a gradient, which is what the drift used to hide.
      final clouds = _field(3, cover: 0.9).clouds;
      expect(clouds.length, greaterThan(2));
      expect(clouds.map((c) => c.depth).toSet().length, greaterThan(1));
      for (var i = 1; i < clouds.length; i++) {
        expect(clouds[i].depth, greaterThanOrEqualTo(clouds[i - 1].depth));
      }
    });

    test('the sun is hidden under a closed lid, not merely dimmed', () {
      // A sun burning through overcast is the picture of a *break* in the
      // cloud, which is the one thing an overcast reading rules out.
      expect(_field(0).celestialOpacity, 1.0);
      expect(_field(3, cover: 1.0).celestialOpacity, 0.0);
      final partly = _field(2, cover: 0.5).celestialOpacity;
      expect(partly, greaterThan(0));
      expect(partly, lessThan(1));
    });
  });

  group('skyPalette', () {
    test('night and day differ for every condition', () {
      for (final code in const [0, 2, 3, 45, 63, 75, 95]) {
        final condition = conditionForCode(code);
        expect(
          skyPalette(condition, night: true).top,
          isNot(skyPalette(condition, night: false).top),
          reason: 'code $code',
        );
      }
    });

    test('a storm is darker than a clear day', () {
      final storm = skyPalette(conditionForCode(95), night: false);
      final clear = skyPalette(conditionForCode(0), night: false);
      expect(storm.top.computeLuminance(), lessThan(clear.top.computeLuminance()));
    });

    test('stars are only lit where the palette expects them', () {
      expect(skyPalette(conditionForCode(0), night: true).starOpacity,
          greaterThan(0));
      expect(skyPalette(conditionForCode(0), night: false).starOpacity, 0);
      expect(skyPalette(conditionForCode(95), night: true).starOpacity, 0);
    });

    test('an unknown code still gets a sky', () {
      expect(
        () => skyPalette(conditionForCode(4242), night: false),
        returnsNormally,
      );
    });
  });

  group('WeatherSky', () {
    testWidgets('settles, because there is no ticker behind it', (tester) async {
      // The property the whole file exists for, and the one a widget test can
      // actually observe: this used to run a 30fps `Ticker` for as long as it
      // was on screen, so `pumpAndSettle` on any tree containing one hung
      // forever and every test had to remember to pass `animate: false`.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 300,
            height: 200,
            child: WeatherSky(
              condition: conditionForCode(95),
              cloudCover: 1.0,
              night: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WeatherSky), findsOneWidget);
    });

    testWidgets('rebuilds its field when the conditions change',
        (tester) async {
      Future<void> pump(int code) => tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox(
                width: 300,
                height: 200,
                child: WeatherSky(
                  condition: conditionForCode(code),
                  cloudCover: conditionForCode(code).cloudCover,
                  night: false,
                ),
              ),
            ),
          );

      await pump(0);
      await pump(75);
      await tester.pumpAndSettle();
      // Nothing observable from outside but that it survived the swap: the
      // field is private, and what this guards is `didUpdateWidget` throwing or
      // leaving a snow field over a clear-sky palette.
      expect(tester.takeException(), isNull);
    });

    testWidgets('a zero-sized box paints nothing rather than dividing by it',
        (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 0,
            height: 0,
            child: WeatherSky(
              condition: conditionForCode(63),
              cloudCover: 0.9,
              night: false,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
