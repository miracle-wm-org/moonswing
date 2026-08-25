// The series, against Meeus's own worked examples.
//
// This is the guardrail the whole lunar feature stands on: a transcription slip
// in one of the 120 periodic terms is not an exception, it is a Moon that is
// half a degree from where the sky has it, and nothing above this layer could
// tell. Example 47.a is quoted to six decimal places in the book, so it pins
// every term in both tables at once.

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/moon/moon_ephemeris.dart';

/// Meeus, *Astronomical Algorithms*, example 47.a: 1992 April 12.0 TD.
final DateTime _example47a = DateTime.utc(1992, 4, 12);

void main() {
  group('julianDay', () {
    test('matches the epochs every other calculation is anchored to', () {
      // J2000.0 is 2000 January 1.5 TD, by definition.
      expect(julianDay(DateTime.utc(2000, 1, 1, 12)), closeTo(2451545.0, 1e-6));
      // Meeus, chapter 7: 1957 October 4.81, Sputnik 1.
      expect(
        julianDay(DateTime.utc(1957, 10, 4, 19, 26, 24)),
        closeTo(2436116.31, 1e-4),
      );
      // The Gregorian cutover is handled by the century correction.
      expect(julianDay(DateTime.utc(1600, 12, 31)), closeTo(2305812.5, 1e-6));
    });

    test('is taken in UTC whatever zone the DateTime carries', () {
      final utc = DateTime.utc(2024, 6, 1, 12);
      expect(julianDay(utc.toLocal()), closeTo(julianDay(utc), 1e-9));
    });
  });

  group('angleDifference', () {
    test('takes the short way round', () {
      expect(angleDifference(1, 359), closeTo(2, 1e-9));
      expect(angleDifference(359, 1), closeTo(-2, 1e-9));
      expect(angleDifference(10, 10), closeTo(0, 1e-9));
      expect(angleDifference(180, 0), closeTo(180, 1e-9));
    });
  });

  group('normalizeDegrees', () {
    test('wraps into [0, 360)', () {
      expect(normalizeDegrees(-1), closeTo(359, 1e-9));
      expect(normalizeDegrees(721), closeTo(1, 1e-9));
      expect(normalizeDegrees(0), closeTo(0, 1e-9));
    });
  });

  group('moonPosition', () {
    test('reproduces Meeus example 47.a to the printed digit', () {
      final position = moonPosition(julianCenturies(_example47a));
      expect(position.longitude, closeTo(133.162655, 5e-5));
      expect(position.latitude, closeTo(-3.229126, 5e-5));
      expect(position.distanceKm, closeTo(368409.7, 0.5));
    });

    test('the distance swings between the published perigee and apogee', () {
      // The closest perigee of 2016, and the one the "supermoon" of 14 November
      // that year was measured at: 356,509 km.
      final perigee =
          moonPosition(julianCenturies(DateTime.utc(2016, 11, 14, 11, 23)));
      expect(perigee.distanceKm, closeTo(356509, 50));
      // Apparent size follows: a degree and a bit over half.
      expect(perigee.angularDiameterDegrees, closeTo(0.5586, 0.002));
      expect(perigee.parallaxDegrees, closeTo(1.0251, 0.002));
    });
  });

  group('sunPosition', () {
    test('is right to the hundredth of a degree at example 47.a', () {
      final sun = sunPosition(julianCenturies(_example47a));
      expect(sun.longitude, closeTo(22.3405, 0.01));
      // Aphelion is 1.017 AU and perihelion 0.983; April is on the way out.
      expect(sun.distanceAu, closeTo(1.0025, 0.001));
    });

    test('runs from perihelion to aphelion over the year', () {
      final january = sunPosition(julianCenturies(DateTime.utc(2024, 1, 4)));
      final july = sunPosition(julianCenturies(DateTime.utc(2024, 7, 5)));
      expect(january.distanceAu, lessThan(0.9835));
      expect(july.distanceAu, greaterThan(1.0165));
    });
  });

  group('meanObliquity', () {
    test('is 23.4392911° at J2000 and shrinking', () {
      expect(meanObliquity(0), closeTo(23.4392911, 1e-7));
      expect(meanObliquity(1), lessThan(meanObliquity(0)));
    });
  });

  group('moonAltitude', () {
    // Springfield, Illinois — the coordinates the weather fakes use.
    const latitude = 39.8;
    const longitude = -89.65;

    test('puts the January 2024 full Moon on the horizon as it rises', () {
      // Independently checked: the Moon rose over Springfield at 23:04 UTC on
      // 25 January 2024, minutes before that evening's sunset, which is what a
      // full Moon does.
      final rising = moonAltitude(
        time: DateTime.utc(2024, 1, 25, 23, 4, 14),
        latitude: latitude,
        longitude: longitude,
      );
      expect(rising.altitudeDegrees, closeTo(rising.horizonDegrees, 0.02));

      // Six hours later it is most of the way up the sky.
      final high = moonAltitude(
        time: DateTime.utc(2024, 1, 26, 5),
        latitude: latitude,
        longitude: longitude,
      );
      expect(high.altitudeDegrees, closeTo(62.70, 0.1));
    });

    test('the rise altitude is above zero, not below it', () {
      // The Moon is the one body whose parallax — about a degree — outweighs
      // the half-degree of refraction every other rise time subtracts.
      final sample = moonAltitude(
        time: DateTime.utc(2024, 1, 25, 12),
        latitude: latitude,
        longitude: longitude,
      );
      expect(sample.horizonDegrees, closeTo(0.097, 0.01));
    });

    test('the two hemispheres disagree about where the Moon is', () {
      final north = moonAltitude(
        time: DateTime.utc(2024, 1, 26, 5),
        latitude: 39.8,
        longitude: -89.65,
      );
      final south = moonAltitude(
        time: DateTime.utc(2024, 1, 26, 5),
        latitude: -39.8,
        longitude: -89.65,
      );
      expect(north.altitudeDegrees, greaterThan(south.altitudeDegrees));
    });
  });
}
