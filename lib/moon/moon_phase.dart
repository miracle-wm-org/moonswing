// What the Moon is doing right now, as one value object.
//
// The layer above `moon_ephemeris.dart`: it turns the raw series into the four
// things a person asks — which phase this is, how lit it is, when the next
// principal phase lands, and (where the shell knows where the user is) when the
// Moon rises and sets.
//
// Still Flutter-free and clock-free: every entry point takes the instant it is
// asked about. `MoonStore` is the only thing in the feature that knows the time.
//
// **Every phase instant here is found by search, never by counting synodic
// months from a fixed epoch.** A mean lunation is 29.530588853 days and a real
// one runs from 29.27 to 29.83, so epoch-plus-multiples is up to seven hours out
// — a full moon predicted on the wrong evening. Newton's method against the true
// elongation costs about six position evaluations and lands within a couple of
// minutes of the published times.

import 'dart:math' as math;

import 'package:moonswing/moon/moon_ephemeris.dart';

/// The eight phases, in cycle order from new.
enum MoonPhase {
  newMoon('New moon'),
  waxingCrescent('Waxing crescent'),
  firstQuarter('First quarter'),
  waxingGibbous('Waxing gibbous'),
  fullMoon('Full moon'),
  waningGibbous('Waning gibbous'),
  lastQuarter('Last quarter'),
  waningCrescent('Waning crescent');

  const MoonPhase(this.label);

  final String label;

  /// The four the almanacs print a time for. The other four are the stretches
  /// between them.
  bool get isPrincipal =>
      this == newMoon ||
      this == firstQuarter ||
      this == fullMoon ||
      this == lastQuarter;

  /// Whether the lit fraction is growing.
  ///
  /// The two principal phases at the ends of the cycle are neither, and answer
  /// for the half they lead into — which is what the picture does too: a new
  /// moon is drawn as the start of a waxing crescent.
  bool get waxing => index < MoonPhase.fullMoon.index;
}

/// How far either side of a principal phase still counts as that phase, in
/// cycles. 0.02 of a lunation is about 14 hours.
///
/// A wider window is the more common implementation and reads wrong: at an eighth
/// of a cycle either side, the sky shows an obvious crescent for nearly two days
/// after the shell has stopped calling it new.
const double _principalWindow = 0.02;

/// The phase at [cyclePosition], a fraction of the lunation from new (0) to
/// new (1).
MoonPhase phaseForCyclePosition(double cyclePosition) {
  final p = cyclePosition % 1.0;
  if (p < _principalWindow || p >= 1 - _principalWindow) return MoonPhase.newMoon;
  if (p < 0.25 - _principalWindow) return MoonPhase.waxingCrescent;
  if (p < 0.25 + _principalWindow) return MoonPhase.firstQuarter;
  if (p < 0.5 - _principalWindow) return MoonPhase.waxingGibbous;
  if (p < 0.5 + _principalWindow) return MoonPhase.fullMoon;
  if (p < 0.75 - _principalWindow) return MoonPhase.waningGibbous;
  if (p < 0.75 + _principalWindow) return MoonPhase.lastQuarter;
  return MoonPhase.waningCrescent;
}

/// The Moon's elongation from the Sun at [time] — 0° at new, 180° at full.
///
/// The cycle position is measured from this rather than from the mean
/// elongation `D`, so the phase the shell names always agrees with the phase it
/// draws.
double moonElongation(DateTime time) {
  final t = julianCenturies(time);
  return normalizeDegrees(moonPosition(t).longitude - sunPosition(t).longitude);
}

/// How fast the elongation runs, in degrees per day, averaged over a lunation.
/// Only ever an initial guess — see [_solveElongation].
const double _meanElongationRate = 360.0 / kSynodicMonthDays;

DateTime _addDays(DateTime time, double days) =>
    time.add(Duration(microseconds: (days * Duration.microsecondsPerDay).round()));

/// Newton's method on the elongation, from [estimate].
///
/// Converges on whichever crossing of [target] is nearest the estimate, which is
/// what makes one solver answer both [moonPhaseAfter] and [moonPhaseBefore]. The
/// derivative is taken over ten minutes rather than analytically: the elongation
/// rate swings by a quarter between perigee and apogee, so a constant would cost
/// iterations, and measuring the series is simpler than differentiating it.
DateTime _solveElongation(DateTime estimate, double target) {
  var time = estimate;
  for (var i = 0; i < 6; i++) {
    final error = angleDifference(moonElongation(time), target);
    if (error.abs() < 1e-7) break;
    const step = Duration(minutes: 10);
    final ahead = angleDifference(moonElongation(time.add(step)), target);
    final rate = (ahead - error) / (step.inMinutes / (60 * 24));
    if (rate == 0) break;
    time = _addDays(time, -error / rate);
  }
  return time;
}

/// How close to [start] a solution counts as *being* [start] rather than the next
/// one along.
///
/// Both searches are strict: asked for the next full Moon at the instant of one,
/// the answer has to be next month's. Without a tolerance that depends on which
/// side of the root Newton landed, and "full moon in 0 days" is a readout nobody
/// wants. A second is enormous next to the solver's convergence and nothing next
/// to the 29 days between roots.
const Duration _phaseSearchEpsilon = Duration(seconds: 1);

/// The first time strictly after [start] that the Moon's elongation is
/// [target].
DateTime moonPhaseAfter(DateTime start, double target) {
  final ahead = (target - moonElongation(start)) % 360.0;
  var solved = _solveElongation(
    _addDays(start, ahead / _meanElongationRate),
    target,
  );
  // Newton lands on whichever root is nearest the guess, which for a target the
  // Moon is already at is the one just gone.
  if (solved.isBefore(start.add(_phaseSearchEpsilon))) {
    solved = _solveElongation(_addDays(solved, kSynodicMonthDays), target);
  }
  return solved;
}

/// The last time strictly before [start] that the Moon's elongation was
/// [target].
DateTime moonPhaseBefore(DateTime start, double target) {
  final behind = (moonElongation(start) - target) % 360.0;
  var solved = _solveElongation(
    _addDays(start, -behind / _meanElongationRate),
    target,
  );
  if (solved.isAfter(start.subtract(_phaseSearchEpsilon))) {
    solved = _solveElongation(_addDays(solved, -kSynodicMonthDays), target);
  }
  return solved;
}

/// Everything the shell knows about the Moon at one instant.
///
/// **The four phase instants are found on first read, not on construction.** Each
/// is a Newton search costing about a dozen evaluations of the whole of Meeus
/// 47.A/B, and together they were nine tenths of a reading — paid every minute by
/// `MoonStore._tick`, whose `_publish` needs none of them, and again by a compact
/// card that draws neither an age nor a countdown. Everything eager here falls
/// out of the one position evaluation the reading already makes.
class MoonReading {
  MoonReading({
    required this.time,
    required this.cyclePosition,
    required this.illumination,
    required this.phaseAngleDegrees,
    required this.eclipticLatitude,
    required this.distanceKm,
    required this.angularDiameterDegrees,
    required this.nextPrincipalTargetDegrees,
    this.altitudeDegrees,
    this.horizonDegrees,
    this.southernView = false,
  });

  /// The instant this was computed for.
  final DateTime time;

  /// Where in the lunation this is: 0 at new, 0.5 at full, 1 at new again.
  final double cyclePosition;

  /// The lit fraction of the disc, 0..1. Not linear in [cyclePosition] — the
  /// quarters are half lit at a quarter of the way round, and the crescents
  /// stay thin for longer than a naive reading of the fraction suggests.
  final double illumination;

  /// The Sun–Moon–Earth angle, degrees: 0 at full, 180 at new.
  final double phaseAngleDegrees;

  /// The Moon's ecliptic latitude, degrees. Near zero at a new or full Moon
  /// means an eclipse — see `moon_facts.dart`.
  final double eclipticLatitude;

  final double distanceKm;
  final double angularDiameterDegrees;

  /// The elongation the next principal phase lands at: 0, 90, 180 or 270.
  ///
  /// Which phase is next is not a search but which quadrant of the elongation the
  /// Moon is in, which this reading already has. Carried as the target because it
  /// is also the key [nextPrincipalTime] is memoised against.
  final int nextPrincipalTargetDegrees;

  /// The next of the four principal phases.
  MoonPhase get nextPrincipalPhase => switch (nextPrincipalTargetDegrees) {
        90 => MoonPhase.firstQuarter,
        180 => MoonPhase.fullMoon,
        270 => MoonPhase.lastQuarter,
        _ => MoonPhase.newMoon,
      };

  DateTime? _lastNewMoon;
  DateTime? _nextNewMoon;
  DateTime? _nextFullMoon;
  DateTime? _nextPrincipalTime;

  /// When the lunation this reading is in began.
  DateTime get lastNewMoon => _lastNewMoon ??= moonPhaseBefore(time, 0);

  DateTime get nextNewMoon => _nextNewMoon ??= moonPhaseAfter(time, 0);

  DateTime get nextFullMoon => _nextFullMoon ??= moonPhaseAfter(time, 180);

  /// When [nextPrincipalPhase] lands.
  ///
  /// Half the month this is the very search [nextNewMoon] or [nextFullMoon]
  /// makes — same function, same arguments — so it is answered from them
  /// rather than repeated, and only a quarter needs a solve of its own.
  DateTime get nextPrincipalTime => switch (nextPrincipalTargetDegrees) {
        0 => nextNewMoon,
        180 => nextFullMoon,
        final target =>
          _nextPrincipalTime ??= moonPhaseAfter(time, target.toDouble()),
      };

  /// How high the Moon is above the horizon, or null when the shell does not
  /// know where the user is.
  final double? altitudeDegrees;

  /// The altitude that counts as risen at [time]; see [moonAltitude].
  final double? horizonDegrees;

  /// Whether the observer is in the southern hemisphere, where the whole disc
  /// is seen rotated half a turn — a waxing crescent is lit on the *left*.
  final bool southernView;

  MoonPhase get phase => phaseForCyclePosition(cyclePosition);

  /// Whether the lit fraction is growing. Taken from the elongation rather
  /// than from [phase], so it is right inside the principal windows too.
  bool get waxing => cyclePosition < 0.5;

  /// How long since the last new moon.
  Duration get age => time.difference(lastNewMoon);

  /// The age in days, which is how almanacs print it.
  double get ageDays => age.inMinutes / (60 * 24);

  /// `78` — the lit percentage, rounded, which is all any readout shows.
  int get illuminationPercent => (illumination * 100).round();

  /// Whether the Moon is above the horizon, or null with no location.
  bool? get isUp {
    final altitude = altitudeDegrees;
    final horizon = horizonDegrees;
    if (altitude == null || horizon == null) return null;
    return altitude > horizon;
  }

  /// How far from the mean distance this is, as a fraction: negative towards
  /// perigee, positive towards apogee.
  double get distanceAnomaly => (distanceKm - 385000.56) / 385000.56;
}

/// The reading at [at], for an observer at [latitude]/[longitude] where they are
/// known.
///
/// The phase half is the same everywhere on Earth, so a shell that has never
/// resolved a location still draws the right shape. The location buys two things
/// and no more: the altitude (and with it the rise and set times) and the
/// hemisphere the disc is seen from.
MoonReading computeMoonReading({
  required DateTime at,
  double? latitude,
  double? longitude,
}) {
  final t = julianCenturies(at);
  final moon = moonPosition(t);
  final sun = sunPosition(t);

  final elongation = normalizeDegrees(moon.longitude - sun.longitude);

  // Meeus 48.2/48.3: the phase angle from the Sun–Moon–Earth triangle, and the
  // lit fraction from it. Going through the triangle rather than taking
  // `(1 - cos(elongation)) / 2` is what makes the Sun's actual distance and the
  // Moon's ecliptic latitude count, which is worth about a percent of
  // illumination near the quarters.
  final psi = math.acos(
    math.cos(moon.latitude * math.pi / 180) *
        math.cos(elongation * math.pi / 180),
  );
  final sunKm = sun.distanceKm;
  final phaseAngle = math.atan2(
    sunKm * math.sin(psi),
    moon.distanceKm - sunKm * math.cos(psi),
  );
  final illumination = (1 + math.cos(phaseAngle)) / 2;

  // The next quarter-turn of elongation the Moon reaches: 90 from a waxing
  // crescent, 180 from a waxing gibbous, and so on. The instant it lands at —
  // and the two syzygies either side of it — are left to [MoonReading]'s own
  // getters, which search only if somebody asks.
  final nextQuadrant = ((elongation / 90).floor() + 1) * 90;

  double? altitude;
  double? horizon;
  if (latitude != null && longitude != null) {
    final position =
        moonAltitude(time: at, latitude: latitude, longitude: longitude);
    altitude = position.altitudeDegrees;
    horizon = position.horizonDegrees;
  }

  return MoonReading(
    time: at,
    cyclePosition: elongation / 360.0,
    illumination: illumination,
    phaseAngleDegrees: phaseAngle * 180 / math.pi,
    eclipticLatitude: moon.latitude,
    distanceKm: moon.distanceKm,
    angularDiameterDegrees: moon.angularDiameterDegrees,
    nextPrincipalTargetDegrees: nextQuadrant % 360,
    altitudeDegrees: altitude,
    horizonDegrees: horizon,
    southernView: latitude != null && latitude < 0,
  );
}

/// When the Moon rises and sets on one local day.
///
/// Both are nullable and both being null is not a failure: near the poles the
/// Moon regularly stays up or down for a whole day, and at every latitude it
/// rises about fifty minutes later each day, so roughly once a month a calendar
/// day contains no moonrise. [alwaysUp] and [alwaysDown] tell those cases apart,
/// so the widget can say which it is instead of showing two blanks.
class MoonTimes {
  const MoonTimes({
    this.rise,
    this.set,
    this.alwaysUp = false,
    this.alwaysDown = false,
  });

  final DateTime? rise;
  final DateTime? set;
  final bool alwaysUp;
  final bool alwaysDown;

  bool get hasAny => rise != null || set != null;
}

/// The Moon's rise and set on the local calendar day containing [day].
///
/// Found by sampling the altitude every twenty minutes and bisecting the sign
/// changes, rather than by Meeus's interpolation from three positions: the Moon's
/// declination moves several degrees in a day and its parallax moves the horizon
/// it is measured against, while a scan handles a day with two moonrises, or
/// none, by simply not finding a crossing. Seventy-two altitude evaluations is a
/// millisecond, once a day.
MoonTimes moonTimesFor({
  required DateTime day,
  required double latitude,
  required double longitude,
}) {
  // The calendar day, built from its parts rather than by adding 24 hours — the
  // `overlay/calendar/month.dart` discipline. A day on which the clocks change
  // is 23 or 25 hours long, and a scan that assumed 24 would miss an hour of it.
  final start = DateTime(day.year, day.month, day.day);
  final end = DateTime(day.year, day.month, day.day + 1);
  final totalMinutes = end.difference(start).inMinutes;
  const stepMinutes = 20;

  DateTime? rise;
  DateTime? set;
  double? previous;
  var previousTime = start;
  var everUp = false;

  for (var minutes = 0; minutes <= totalMinutes; minutes += stepMinutes) {
    final time = start.add(Duration(minutes: minutes));
    final sample = moonAltitude(
      time: time,
      latitude: latitude,
      longitude: longitude,
    );
    final value = sample.altitudeDegrees - sample.horizonDegrees;
    if (value > 0) everUp = true;

    if (previous != null && previous * value < 0) {
      final crossing = _bisectHorizon(
        earlier: previousTime,
        later: time,
        earlierBelow: previous < 0,
        latitude: latitude,
        longitude: longitude,
      );
      if (previous < 0) {
        rise ??= crossing;
      } else {
        set ??= crossing;
      }
    }
    previous = value;
    previousTime = time;
  }

  return MoonTimes(
    rise: rise,
    set: set,
    alwaysUp: rise == null && set == null && everUp,
    alwaysDown: rise == null && set == null && !everUp,
  );
}

/// The instant between [earlier] and [later] at which the Moon crosses its
/// rise/set altitude. Sixteen halvings of a twenty-minute bracket is a fifth of
/// a second, which is four orders of magnitude finer than the minute the widget
/// prints — and cheaper than being clever about it.
DateTime _bisectHorizon({
  required DateTime earlier,
  required DateTime later,
  required bool earlierBelow,
  required double latitude,
  required double longitude,
}) {
  var low = earlier;
  var high = later;
  for (var i = 0; i < 16; i++) {
    final middle = low.add(Duration(
      microseconds: high.difference(low).inMicroseconds ~/ 2,
    ));
    final sample = moonAltitude(
      time: middle,
      latitude: latitude,
      longitude: longitude,
    );
    final below = sample.altitudeDegrees - sample.horizonDegrees < 0;
    if (below == earlierBelow) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return low.add(Duration(
    microseconds: high.difference(low).inMicroseconds ~/ 2,
  ));
}
