// The sign arithmetic: which arc a birthday falls in, when the Sun crosses
// into one, and the two days a month a date alone cannot answer.
//
// The point of computing this rather than tabulating it is that the boundaries
// move, so the interesting cases are the ones a table of "Mar 21 – Apr 19"
// gets wrong. Every expectation below is a published almanac value or a
// well-known birthday, never a re-recording of what the code happens to say.

import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/astrology/zodiac.dart';

/// The Sun's longitude at local noon on a date, which is what
/// [zodiacReadingFor] reads.
double _noon(int year, int month, int day) =>
    solarLongitude(DateTime(year, month, day, 12));

void main() {
  group('signAtLongitude', () {
    test('cuts the ecliptic into twelve arcs from the equinox', () {
      expect(signAtLongitude(0), ZodiacSign.aries);
      expect(signAtLongitude(29.99), ZodiacSign.aries);
      expect(signAtLongitude(30), ZodiacSign.taurus);
      expect(signAtLongitude(150), ZodiacSign.virgo);
      expect(signAtLongitude(359.99), ZodiacSign.pisces);
    });

    test('wraps rather than throwing', () {
      // The longitude comes out of a series; a caller handing it 360 exactly,
      // or a negative, must not take a card down.
      expect(signAtLongitude(360), ZodiacSign.aries);
      expect(signAtLongitude(-1), ZodiacSign.pisces);
      expect(signAtLongitude(725), ZodiacSign.taurus);
    });

    test('every sign owns its own 30 degrees, in ecliptic order', () {
      for (final sign in ZodiacSign.values) {
        expect(sign.startLongitude, sign.ordinal * 30.0);
        expect(signAtLongitude(sign.startLongitude), sign);
        expect(signAtLongitude(sign.startLongitude + 29.5), sign);
      }
    });
  });

  group('zodiacReadingFor', () {
    test('resolves ordinary birthdays', () {
      expect(zodiacReadingFor(DateTime(1990, 4, 17)).sign, ZodiacSign.aries);
      expect(zodiacReadingFor(DateTime(2000, 7, 30)).sign, ZodiacSign.leo);
      expect(zodiacReadingFor(DateTime(1969, 7, 20)).sign, ZodiacSign.cancer);
      expect(zodiacReadingFor(DateTime(2001, 9, 11)).sign, ZodiacSign.virgo);
      expect(zodiacReadingFor(DateTime(1977, 2, 25)).sign, ZodiacSign.pisces);
    });

    test('reads only the date part', () {
      // A birthday is a date; a time attached to one is noise, and two
      // different times on the same day must not give two different signs.
      final morning = zodiacReadingFor(DateTime(1990, 4, 17, 3, 15));
      final evening = zodiacReadingFor(DateTime(1990, 4, 17, 23, 45));
      expect(morning, evening);
      expect(morning.birthday, DateTime(1990, 4, 17));
    });

    test('names both signs on the day the Sun crossed', () {
      // Exactly one day in March holds the crossing into Aries. *Which*
      // calendar day it is depends on the machine's time zone, which is
      // precisely why the reading is built from the local day's own two ends
      // rather than from a UTC instant — so the test looks for it rather than
      // naming it.
      final march = [
        for (var day = 1; day <= 31; day++)
          zodiacReadingFor(DateTime(2026, 3, day)),
      ];
      final cusps = march.where((r) => r.onCusp).toList();
      expect(cusps, hasLength(1));
      expect(
        {cusps.single.sign, cusps.single.neighbour},
        {ZodiacSign.pisces, ZodiacSign.aries},
      );
    });

    test('the day after a crossing is wholly in the new sign', () {
      final march = [
        for (var day = 1; day <= 31; day++)
          zodiacReadingFor(DateTime(2026, 3, day)),
      ];
      final crossing = march.indexWhere((r) => r.onCusp);
      final after = march[crossing + 1];
      expect(after.sign, ZodiacSign.aries);
      expect(after.onCusp, isFalse);
      expect(after.neighbour, isNull);
    });

    test('most days are not cusps', () {
      // Roughly twenty-eight days in thirty. A reading that reported a cusp
      // more often than that would be one whose day boundaries are wrong.
      var cusps = 0;
      for (var day = 1; day <= 28; day++) {
        if (zodiacReadingFor(DateTime(2026, 2, day)).onCusp) cusps++;
      }
      expect(cusps, 1);
    });

    test('degreesIntoSign stays inside the arc', () {
      for (var month = 1; month <= 12; month++) {
        final reading = zodiacReadingFor(DateTime(2026, month, 9));
        expect(reading.degreesIntoSign, inInclusiveRange(0, 30));
      }
    });
  });

  group('the boundaries move, which is why they are searched for', () {
    test('the same calendar day is a different sign in different years', () {
      // The tropical year is a quarter-day longer than the calendar's, so an
      // ingress slips about six hours a year and jumps back on a leap day.
      // 22 July is the case a fixed table gets wrong: Leo in some years,
      // Cancer in others.
      // Read at noon UTC rather than through [zodiacReadingFor], whose answer
      // is the machine's local day — this test is about the ingress moving
      // between years, and a time zone would be a second thing moving.
      final signs = {
        for (var year = 2020; year <= 2027; year++)
          year: signAtLongitude(solarLongitude(DateTime.utc(year, 7, 22, 12))),
      };
      expect(signs.values.toSet().length, greaterThan(1),
          reason: 'a fixed date range would answer the same every year');
      expect(signs.values.toSet(), {ZodiacSign.cancer, ZodiacSign.leo});
    });
  });

  group('solarIngressAfter', () {
    test('lands on the published day', () {
      // Almanac dates for 2026 (UTC). The instants are geometric rather than
      // apparent, so they run about eight minutes early — far inside a day.
      const expected = {
        ZodiacSign.aries: (3, 20),
        ZodiacSign.taurus: (4, 20),
        ZodiacSign.gemini: (5, 21),
        ZodiacSign.cancer: (6, 21),
        ZodiacSign.leo: (7, 22),
        ZodiacSign.virgo: (8, 23),
        ZodiacSign.libra: (9, 23),
        ZodiacSign.scorpio: (10, 23),
        ZodiacSign.sagittarius: (11, 22),
        ZodiacSign.capricorn: (12, 21),
        ZodiacSign.aquarius: (1, 20),
        ZodiacSign.pisces: (2, 18),
      };
      for (final entry in expected.entries) {
        final at = solarIngressAfter(DateTime.utc(2026), entry.key).toUtc();
        expect((at.month, at.day), entry.value, reason: entry.key.label);
      }
    });

    test('the Sun is at the arc boundary when it arrives', () {
      for (final sign in ZodiacSign.values) {
        final at = solarIngressAfter(DateTime.utc(2026), sign);
        final error = (solarLongitude(at) - sign.startLongitude).abs() % 360;
        expect(error < 1e-4 || (360 - error) < 1e-4, isTrue,
            reason: '${sign.label}: ${solarLongitude(at)}');
      }
    });

    test('is strict: asked at an ingress, it answers the next one', () {
      final first = solarIngressAfter(DateTime.utc(2026), ZodiacSign.leo);
      final next = solarIngressAfter(first, ZodiacSign.leo);
      expect(next.difference(first).inDays, inInclusiveRange(360, 370));
    });
  });

  group('solarSeasonIn', () {
    test('runs from one ingress to the next sign\'s', () {
      final season = solarSeasonIn(2026, ZodiacSign.leo);
      expect(season.start.toUtc().month, 7);
      expect(season.end.toUtc().month, 8);
      expect(season.end.isAfter(season.start), isTrue);
      // Every arc is 30° of a 365-day circuit, so no season is far off a month.
      expect(season.end.difference(season.start).inDays,
          inInclusiveRange(29, 32));
    });

    test('finds exactly one of each sign per calendar year', () {
      // Capricorn is the near case — its ingress is around 21 December, ten
      // days from the boundary a search from New Year starts at.
      for (final sign in ZodiacSign.values) {
        final season = solarSeasonIn(2026, sign);
        expect(season.start.toUtc().year, 2026, reason: sign.label);
      }
    });
  });

  group('ZodiacSign', () {
    test('parses its own label, case-insensitively', () {
      expect(ZodiacSign.parse('Leo'), ZodiacSign.leo);
      expect(ZodiacSign.parse('  sagittarius '), ZodiacSign.sagittarius);
      // A config value is a string the user typed; a misspelling costs the
      // setting rather than the widget.
      expect(ZodiacSign.parse('Ophiuchus'), isNull);
      expect(ZodiacSign.parse(''), isNull);
    });

    test('every sign carries an attribute line and a constellation', () {
      for (final sign in ZodiacSign.values) {
        expect(sign.attributes, contains(sign.element.label));
        expect(sign.attributes, contains(sign.rulingPlanet));
        expect(sign.constellationCode.length, 3);
      }
    });

    test('the modalities and elements repeat in the classical cycle', () {
      // Fire, earth, air, water round and round; cardinal, fixed, mutable the
      // same. A table that broke this has a row in the wrong place.
      for (final sign in ZodiacSign.values) {
        expect(sign.element.index, sign.ordinal % 4);
        expect(sign.modality.index, sign.ordinal % 3);
      }
    });
  });

  group('solarLongitude', () {
    test('advances about a degree a day', () {
      final start = _noon(2026, 5, 1);
      final later = _noon(2026, 5, 11);
      expect(((later - start) % 360) / 10, closeTo(0.97, 0.05));
    });
  });
}
