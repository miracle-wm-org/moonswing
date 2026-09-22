// The phase layer: the instants, the labels, and the rise and set scan.
//
// The phase instants are checked against published times rather than against this
// implementation's own output. Four of them, spread over half a century, because
// the error a mean-lunation shortcut makes is small in the year it was calibrated
// for and hours out a couple of decades either side.

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/moon/moon_ephemeris.dart';
import 'package:moonswing/moon/moon_phase.dart';

/// Asserts [found] is within [minutes] of [expected].
void _expectNear(DateTime found, DateTime expected, {int minutes = 6}) {
  final off = found.difference(expected).inSeconds.abs() / 60;
  expect(
    off,
    lessThanOrEqualTo(minutes.toDouble()),
    reason: 'expected $expected, found $found (${off.toStringAsFixed(1)} min)',
  );
}

void main() {
  group('phase instants', () {
    test('land within minutes of the published times', () {
      _expectNear(
        moonPhaseAfter(DateTime.utc(2024, 1, 5), 0),
        DateTime.utc(2024, 1, 11, 11, 57),
      );
      _expectNear(
        moonPhaseAfter(DateTime.utc(2024, 1, 20), 180),
        DateTime.utc(2024, 1, 25, 17, 54),
      );
      _expectNear(
        moonPhaseAfter(DateTime.utc(2000, 1, 2), 0),
        DateTime.utc(2000, 1, 6, 18, 14),
      );
      // Meeus, example 49.a — the new Moon of February 1977, quoted as
      // 1977 February 18 at 03:37:42 TD.
      _expectNear(
        moonPhaseAfter(DateTime.utc(1977, 2, 14), 0),
        DateTime.utc(1977, 2, 18, 3, 37, 42),
      );
    });

    test('searching backwards finds the one just gone', () {
      final before = moonPhaseBefore(DateTime.utc(2024, 1, 20), 0);
      _expectNear(before, DateTime.utc(2024, 1, 11, 11, 57));
      expect(before.isBefore(DateTime.utc(2024, 1, 20)), isTrue);
    });

    test('a search from an instant that is already the phase moves on', () {
      // Both directions have to step a whole lunation rather than answering
      // with the instant they were handed, or "next full Moon" would read as
      // "now" for the fourteen hours either side of one.
      final full = moonPhaseAfter(DateTime.utc(2024, 1, 20), 180);
      final next = moonPhaseAfter(full, 180);
      expect(next.difference(full).inDays, inInclusiveRange(29, 30));
      final previous = moonPhaseBefore(full, 180);
      expect(full.difference(previous).inDays, inInclusiveRange(29, 30));
    });

    test('successive lunations are 29.27 to 29.83 days apart', () {
      // The spread is the whole reason these are searched for rather than
      // counted off a mean month: a fixed 29.53 is seven hours out at the ends
      // of that range.
      var previous = moonPhaseAfter(DateTime.utc(2026, 1, 1), 0);
      for (var i = 0; i < 12; i++) {
        final next = moonPhaseAfter(previous.add(const Duration(days: 1)), 0);
        final days = next.difference(previous).inMinutes / (60 * 24);
        expect(days, inInclusiveRange(29.2, 29.9));
        previous = next;
      }
    });
  });

  group('phaseForCyclePosition', () {
    test('names the eight phases in order', () {
      expect(phaseForCyclePosition(0), MoonPhase.newMoon);
      expect(phaseForCyclePosition(0.125), MoonPhase.waxingCrescent);
      expect(phaseForCyclePosition(0.25), MoonPhase.firstQuarter);
      expect(phaseForCyclePosition(0.375), MoonPhase.waxingGibbous);
      expect(phaseForCyclePosition(0.5), MoonPhase.fullMoon);
      expect(phaseForCyclePosition(0.625), MoonPhase.waningGibbous);
      expect(phaseForCyclePosition(0.75), MoonPhase.lastQuarter);
      expect(phaseForCyclePosition(0.875), MoonPhase.waningCrescent);
      expect(phaseForCyclePosition(1.0), MoonPhase.newMoon);
    });

    test('the principal windows are narrow, so a crescent is called one', () {
      // Half a day past new is a visible crescent, and an eighth-of-a-cycle
      // window — the common implementation — would still be calling it new.
      expect(phaseForCyclePosition(0.03), MoonPhase.waxingCrescent);
      expect(phaseForCyclePosition(0.97), MoonPhase.waningCrescent);
      expect(phaseForCyclePosition(0.015), MoonPhase.newMoon);
    });

    test('waxing is the first half of the cycle', () {
      expect(MoonPhase.waxingCrescent.waxing, isTrue);
      expect(MoonPhase.firstQuarter.waxing, isTrue);
      expect(MoonPhase.fullMoon.waxing, isFalse);
      expect(MoonPhase.waningCrescent.waxing, isFalse);
      expect(MoonPhase.firstQuarter.isPrincipal, isTrue);
      expect(MoonPhase.waxingGibbous.isPrincipal, isFalse);
    });
  });

  group('computeMoonReading', () {
    test('is dark at the new Moon and lit at the full', () {
      final atNew = computeMoonReading(at: DateTime.utc(2024, 1, 11, 11, 57));
      expect(atNew.illumination, closeTo(0.002, 0.005));
      expect(atNew.illuminationPercent, 0);
      expect(atNew.phase, MoonPhase.newMoon);
      expect(atNew.cyclePosition, closeTo(1, 0.001));
      // Three minutes *before* the instant of new, so the lunation this belongs
      // to is the one about to end — the age counts from the last new Moon, and
      // 29.5 is what that means here rather than 0.
      expect(atNew.ageDays, closeTo(29.52, 0.05));

      // Two hours later it has restarted.
      final justAfter = computeMoonReading(at: DateTime.utc(2024, 1, 11, 14));
      expect(justAfter.ageDays, closeTo(0.084, 0.01));
      expect(justAfter.waxing, isTrue);

      final atFull = computeMoonReading(at: DateTime.utc(2024, 1, 25, 17, 54));
      expect(atFull.illumination, closeTo(0.998, 0.005));
      expect(atFull.phase, MoonPhase.fullMoon);
      // Two minutes before the exact instant, so it is still — barely —
      // waxing. Which way it is going is a different question from which phase
      // it is in, and the two only agree away from the principal windows.
      expect(atFull.waxing, isTrue);
      expect(
        computeMoonReading(at: DateTime.utc(2024, 1, 26)).waxing,
        isFalse,
      );
      // Half a lunation later, which is where the age readout comes from.
      expect(atFull.ageDays, closeTo(14.25, 0.2));
    });

    test('a quarter is half lit, a quarter of the way round', () {
      final quarter = computeMoonReading(at: DateTime.utc(2024, 1, 18, 3, 53));
      expect(quarter.cyclePosition, closeTo(0.25, 0.001));
      // Half lit at a quarter of the cycle is the fact that makes
      // illumination and cycle position two different numbers.
      expect(quarter.illumination, closeTo(0.5, 0.01));
      expect(quarter.phase, MoonPhase.firstQuarter);
      expect(quarter.waxing, isTrue);
    });

    test('reproduces Meeus example 48.a', () {
      final reading = computeMoonReading(at: DateTime.utc(1992, 4, 12));
      expect(reading.phaseAngleDegrees, closeTo(69.0756, 0.01));
      expect(reading.illumination, closeTo(0.6786, 0.001));
    });

    test('carries the next principal phase and the syzygies around it', () {
      final reading = computeMoonReading(at: DateTime.utc(2024, 1, 20));
      expect(reading.nextPrincipalPhase, MoonPhase.fullMoon);
      _expectNear(reading.nextPrincipalTime, DateTime.utc(2024, 1, 25, 17, 54));
      _expectNear(reading.nextFullMoon, DateTime.utc(2024, 1, 25, 17, 54));
      _expectNear(reading.lastNewMoon, DateTime.utc(2024, 1, 11, 11, 57));
      expect(reading.nextNewMoon.isAfter(reading.nextFullMoon), isTrue);
    });

    test('the phase instants are memoised, and shared where they coincide', () {
      // Waxing gibbous, so the next principal phase *is* the next full Moon:
      // the same search with the same arguments, answered once.
      final gibbous = computeMoonReading(at: DateTime.utc(2024, 1, 20));
      expect(gibbous.nextPrincipalTargetDegrees, 180);
      expect(identical(gibbous.nextPrincipalTime, gibbous.nextFullMoon), isTrue);

      // And a repeat read is the same object rather than a second solve — the
      // property `MoonStore.facts` and the widget's `ageDays` both lean on.
      expect(identical(gibbous.lastNewMoon, gibbous.lastNewMoon), isTrue);
      expect(identical(gibbous.nextNewMoon, gibbous.nextNewMoon), isTrue);

      // A waxing crescent's next principal is the first quarter, which is
      // neither syzygy and does need its own.
      final crescent = computeMoonReading(at: DateTime.utc(2024, 1, 15));
      expect(crescent.nextPrincipalTargetDegrees, 90);
      expect(crescent.nextPrincipalPhase, MoonPhase.firstQuarter);
      expect(
        identical(crescent.nextPrincipalTime, crescent.nextPrincipalTime),
        isTrue,
      );
      _expectNear(crescent.nextPrincipalTime, DateTime.utc(2024, 1, 18, 3, 53));
    });

    test('the altitude and the hemisphere need a location; the phase does not',
        () {
      // Six hours after moonrise over Springfield, when it is unambiguously up.
      final nowhere = computeMoonReading(at: DateTime.utc(2024, 1, 26, 5));
      expect(nowhere.altitudeDegrees, isNull);
      expect(nowhere.isUp, isNull);
      expect(nowhere.southernView, isFalse);
      expect(nowhere.illuminationPercent, greaterThan(90));

      final somewhere = computeMoonReading(
        at: DateTime.utc(2024, 1, 26, 5),
        latitude: 39.8,
        longitude: -89.65,
      );
      expect(somewhere.altitudeDegrees, isNotNull);
      expect(somewhere.isUp, isTrue);
      expect(somewhere.southernView, isFalse);
      // The same instant, the same phase — that half of the reading is not the
      // observer's.
      expect(somewhere.illumination, closeTo(nowhere.illumination, 1e-12));

      final southern = computeMoonReading(
        at: DateTime.utc(2024, 1, 26, 5),
        latitude: -33.87,
        longitude: 151.21,
      );
      expect(southern.southernView, isTrue);
    });

    test('distance and apparent size move together', () {
      final near = computeMoonReading(at: DateTime.utc(2016, 11, 14, 11, 23));
      expect(near.distanceKm, closeTo(356509, 50));
      expect(near.distanceAnomaly, lessThan(-0.06));
      expect(near.angularDiameterDegrees, greaterThan(0.55));
    });
  });

  group('moonTimesFor', () {
    const latitude = 39.8;
    const longitude = -89.65;

    /// Every crossing the scan reports has to *be* one: the altitude at it is the
    /// rise altitude, and the quarter of an hour either side is on the right side
    /// of that. Asserted rather than a wall-clock time, because the scan covers
    /// the *local* day and the runner's zone is not this repository's to choose.
    void expectRealCrossing(DateTime at, {required bool rising}) {
      final sample =
          moonAltitude(time: at, latitude: latitude, longitude: longitude);
      expect(sample.altitudeDegrees, closeTo(sample.horizonDegrees, 0.02));

      final before = moonAltitude(
        time: at.subtract(const Duration(minutes: 15)),
        latitude: latitude,
        longitude: longitude,
      );
      final after = moonAltitude(
        time: at.add(const Duration(minutes: 15)),
        latitude: latitude,
        longitude: longitude,
      );
      if (rising) {
        expect(before.altitudeDegrees, lessThan(before.horizonDegrees));
        expect(after.altitudeDegrees, greaterThan(after.horizonDegrees));
      } else {
        expect(before.altitudeDegrees, greaterThan(before.horizonDegrees));
        expect(after.altitudeDegrees, lessThan(after.horizonDegrees));
      }
    }

    test('finds a rise and a set, and both are real crossings', () {
      final times = moonTimesFor(
        day: DateTime(2024, 1, 25),
        latitude: latitude,
        longitude: longitude,
      );
      expect(times.hasAny, isTrue);
      if (times.rise != null) expectRealCrossing(times.rise!, rising: true);
      if (times.set != null) expectRealCrossing(times.set!, rising: false);
    });

    test('every crossing falls inside the day it was asked about', () {
      final start = DateTime(2024, 3, 9);
      final end = DateTime(2024, 3, 10);
      final times = moonTimesFor(
        day: start,
        latitude: latitude,
        longitude: longitude,
      );
      for (final crossing in [times.rise, times.set]) {
        if (crossing == null) continue;
        expect(crossing.isBefore(start), isFalse);
        expect(crossing.isBefore(end), isTrue);
      }
    });

    test('a circumpolar Moon says so rather than showing two blanks', () {
      // 25 January 2024: the Moon is at a high northern declination, so at 80°N
      // it never sets and at 80°S it never rises — whatever twenty-four hours
      // the runner's local day happens to be.
      final north = moonTimesFor(
        day: DateTime(2024, 1, 25),
        latitude: 80,
        longitude: 20,
      );
      expect(north.hasAny, isFalse);
      expect(north.alwaysUp, isTrue);
      expect(north.alwaysDown, isFalse);

      final south = moonTimesFor(
        day: DateTime(2024, 1, 25),
        latitude: -80,
        longitude: 20,
      );
      expect(south.hasAny, isFalse);
      expect(south.alwaysDown, isTrue);
      expect(south.alwaysUp, isFalse);
    });

    test('the Moon rises about fifty minutes later each day', () {
      // The reason a calendar day sometimes has no moonrise in it at all. Only
      // consecutive days that *both* carry a rise are compared: which local day
      // the missing one falls on depends on the runner's zone, and measuring
      // across it would measure two retardations at once.
      DateTime? previous;
      final gaps = <double>[];
      for (var day = 10; day <= 16; day++) {
        final rise = moonTimesFor(
          day: DateTime(2024, 6, day),
          latitude: latitude,
          longitude: longitude,
        ).rise;
        if (rise != null && previous != null) {
          gaps.add(rise.difference(previous).inMinutes / 60.0);
        }
        previous = rise;
      }
      expect(gaps, isNotEmpty);
      for (final gap in gaps) {
        expect(gap, inInclusiveRange(24.2, 25.6));
      }
    });
  });
}
