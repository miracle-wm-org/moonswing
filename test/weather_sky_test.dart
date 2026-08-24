import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/weather/weather_condition.dart';
import 'package:graceful_shell/weather/weather_sky.dart';

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

    test('snow drifts sideways and rain does not', () {
      expect(_field(75).drops.every((d) => d.sway > 0), isTrue);
      expect(_field(65).drops.every((d) => d.sway == 0), isTrue);
    });

    test('sleet is the mixed case, so only some of it drifts', () {
      // Giving the whole field a sway would make freezing rain fall like a
      // blizzard; giving it none makes it a vertical sheet.
      final drops = _field(66).drops;
      expect(drops.any((d) => d.sway > 0), isTrue);
      expect(drops.any((d) => d.sway == 0), isTrue);
    });

    test('snow falls slower than rain', () {
      final snow = _field(73).drops.map((d) => d.speed).reduce((a, b) => a + b) /
          _field(73).drops.length;
      final rain = _field(63).drops.map((d) => d.speed).reduce((a, b) => a + b) /
          _field(63).drops.length;
      expect(snow, lessThan(rain));
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
      // Alternating directions, so the bands slide past each other rather than
      // travelling as one sheet.
      final speeds = _field(45).fogBands.map((b) => b.speed).toList();
      expect(speeds.any((s) => s > 0), isTrue);
      expect(speeds.any((s) => s < 0), isTrue);
    });

    test('only the thunderstorms flash', () {
      expect(_field(95).lightningPeriod, greaterThan(0));
      expect(_field(99).lightningPeriod, greaterThan(0));
      expect(_field(65).lightningPeriod, 0);
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
    testWidgets('paints without a ticker when animate is false',
        (tester) async {
      // The escape hatch every widget test rendering this needs: a Ticker never
      // settles, so `pumpAndSettle` would hang forever with it running.
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
              animate: false,
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
                  animate: false,
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
              animate: false,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
