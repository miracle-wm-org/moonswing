import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/weather/weather_condition.dart';

void main() {
  group('the WMO table', () {
    test('resolves the codes Open-Meteo documents', () {
      expect(conditionForCode(0).kind, WeatherKind.clear);
      expect(conditionForCode(3).kind, WeatherKind.overcast);
      expect(conditionForCode(48).kind, WeatherKind.fog);
      expect(conditionForCode(65).kind, WeatherKind.rain);
      expect(conditionForCode(75).kind, WeatherKind.snow);
      expect(conditionForCode(82).kind, WeatherKind.rainShowers);
      expect(conditionForCode(99).kind, WeatherKind.thunderstormHail);
    });

    test('a code this build does not know costs the icon, not the panel', () {
      // The whole point of a fallback here: the code arrives from a web API,
      // and a value nobody has seen before must not throw inside a build.
      final condition = conditionForCode(4242);
      expect(condition.kind, WeatherKind.unknown);
      expect(condition.label, isNotEmpty);
      expect(condition.isPrecipitating, isFalse);
    });

    test('clear sky is genuinely clear', () {
      // Load-bearing: `cloudsForCover` draws nothing below 0.05, and a stray
      // cloud over a "Clear sky" label is the animation contradicting the
      // reading beside it.
      expect(conditionForCode(0).cloudCover, 0.0);
      expect(conditionForCode(0).isPrecipitating, isFalse);
    });

    test('intensity rises with the code within a family', () {
      expect(conditionForCode(61).intensity,
          lessThan(conditionForCode(63).intensity));
      expect(conditionForCode(63).intensity,
          lessThan(conditionForCode(65).intensity));
      expect(conditionForCode(71).intensity,
          lessThan(conditionForCode(75).intensity));
    });

    test('only the thunderstorm codes flash', () {
      final flashing = [
        for (var code = 0; code <= 100; code++)
          if (conditionForCode(code).lightning) code,
      ];
      expect(flashing, [95, 96, 99]);
    });

    test('everything that precipitates says what and how hard', () {
      for (var code = 0; code <= 100; code++) {
        final condition = conditionForCode(code);
        if (condition.precipitation == Precipitation.none) {
          expect(condition.intensity, 0, reason: 'code $code');
        } else {
          expect(condition.intensity, greaterThan(0), reason: 'code $code');
        }
      }
    });

    test('every condition carries a usable cloud cover', () {
      for (var code = 0; code <= 100; code++) {
        final cover = conditionForCode(code).cloudCover;
        expect(cover, inInclusiveRange(0.0, 1.0), reason: 'code $code');
      }
    });

    test('freezing rain and drizzle fall as sleet, not as rain', () {
      // The animation gives sleet a partial sway — half of it drifts like
      // snow. Reading them as plain rain is what made freezing rain fall as a
      // vertical sheet.
      expect(conditionForCode(56).precipitation, Precipitation.sleet);
      expect(conditionForCode(66).precipitation, Precipitation.sleet);
    });
  });
}
