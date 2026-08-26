// The figure table: that it covers the zodiac, that every index in it points at
// a star, and that the coordinates are the unit box the painter assumes.
//
// A generated table, so what is worth pinning is its *shape* — a regenerated
// one with a projection bug produces coordinates outside the box or indices
// past the end of the star list, and both of those reach `zodiac_sky.dart` as a
// silently wrong picture or a range error out of a `paint`.

import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/astrology/constellation.dart';
import 'package:graceful_shell/astrology/zodiac.dart';

void main() {
  group('the zodiac figures', () {
    test('every sign resolves to one', () {
      // The guardrail `weather_icons_test.dart` is for the Meteocons: a sign
      // whose code the table does not carry costs the drawing silently, so the
      // test walks all twelve rather than trusting the map's size.
      for (final sign in ZodiacSign.values) {
        expect(
          constellationFor(sign.constellationCode),
          isNotNull,
          reason: '${sign.label} (${sign.constellationCode})',
        );
      }
      expect(zodiacConstellations, hasLength(12));
    });

    test('an unknown code degrades rather than throwing', () {
      // Reached from a build: a code this table does not know must cost the
      // drawing, never the card. `conditionForCode`'s rule.
      expect(constellationFor('Oph'), isNull);
      expect(constellationFor(''), isNull);
    });

    test('names the constellation, which is not always the sign', () {
      // Precession has moved the two apart, and so has the naming: the signs
      // are Scorpio and Capricorn, the constellations Scorpius and
      // Capricornus.
      expect(constellationFor('Sco')!.name, 'Scorpius');
      expect(constellationFor('Cap')!.name, 'Capricornus');
      expect(constellationFor('Leo')!.name, 'Leo');
    });

    test('every star sits inside the unit box', () {
      for (final figure in zodiacConstellations.values) {
        expect(figure.stars, isNotEmpty, reason: figure.code);
        for (final star in figure.stars) {
          expect(star.x, inInclusiveRange(0, 1), reason: figure.code);
          expect(star.y, inInclusiveRange(0, 1), reason: figure.code);
        }
      }
    });

    test('the figure fills its box on one axis and is inset on the other', () {
      // Both axes are scaled by one factor, so nothing is stretched: the longer
      // side spans the whole box and the shorter one is centred inside it.
      for (final figure in zodiacConstellations.values) {
        final xs = figure.stars.map((s) => s.x);
        final ys = figure.stars.map((s) => s.y);
        final spanX = xs.reduce(_max) - xs.reduce(_min);
        final spanY = ys.reduce(_max) - ys.reduce(_min);
        expect(_max(spanX, spanY), closeTo(1.0, 1e-3), reason: figure.code);
      }
    });

    test('every line points at a star that exists', () {
      for (final figure in zodiacConstellations.values) {
        expect(figure.lines, isNotEmpty, reason: figure.code);
        for (final segment in figure.lines) {
          expect(segment.length, greaterThan(1), reason: figure.code);
          for (final index in segment) {
            expect(index, inInclusiveRange(0, figure.stars.length - 1),
                reason: figure.code);
          }
        }
      }
    });

    test('every star is on at least one line', () {
      // A dot nothing joins is a vertex the projection dropped or an index that
      // slipped: the source figures are stick figures, so there are no loose
      // stars in them.
      for (final figure in zodiacConstellations.values) {
        final joined = {for (final s in figure.lines) ...s};
        expect(joined.length, figure.stars.length, reason: figure.code);
      }
    });

    test('the magnitudes are real and are naked-eye', () {
      // Every vertex matched a catalogued star within 0.02°, and the source is
      // a magnitude-6 catalogue — the limit of the unaided eye. A value outside
      // this range is a lookup that matched the wrong thing.
      for (final figure in zodiacConstellations.values) {
        for (final star in figure.stars) {
          expect(star.magnitude, inInclusiveRange(-2.0, 6.5),
              reason: figure.code);
        }
      }
    });

    test('carries the bright stars the figures are known by', () {
      // Antares in Scorpius, Regulus in Leo, Spica in Virgo, Aldebaran in
      // Taurus — the four first-magnitude stars of the zodiac. If a
      // regenerated table lost the brightness column these all come back the
      // same.
      double brightest(String code) => constellationFor(code)!
          .stars
          .map((s) => s.magnitude)
          .reduce(_min);
      expect(brightest('Sco'), closeTo(1.06, 0.05), reason: 'Antares');
      expect(brightest('Leo'), closeTo(1.36, 0.05), reason: 'Regulus');
      expect(brightest('Vir'), closeTo(0.98, 0.05), reason: 'Spica');
      expect(brightest('Tau'), closeTo(0.87, 0.05), reason: 'Aldebaran');
    });
  });
}

double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;
