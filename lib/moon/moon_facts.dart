// What the Moon is doing *to* things: the second half of the lunar widget, and
// the half that answers "so what?".
//
// Pure, like the rest of `lib/moon/` — a fact is a kind, a title and a line of
// text, and the widget is what turns a kind into a glyph. That split is what
// keeps the wording a unit test (`test/moon_facts_test.dart` pins which facts
// appear at a new moon, at perigee and inside an eclipse window) and keeps this
// file free of Flutter.
//
// One editorial rule runs through all of it, and it is the same one
// `weather_sky.dart` states about its picture: **say only what the numbers
// support.** Spring tides, dark skies for meteor watching, the reduced activity
// of nocturnal animals under a bright moon and the eclipse windows are all
// consequences of the geometry this feature already computes. Everything the
// Moon is popularly supposed to do and demonstrably does not — to sleep, to
// moods, to birth rates, to the stock market — is absent on purpose, and a
// change that adds one of them back is a change that makes the shell lie to
// somebody.

import 'dart:math' as math;

import 'package:graceful_shell/moon/moon_ephemeris.dart';
import 'package:graceful_shell/moon/moon_format.dart';
import 'package:graceful_shell/moon/moon_phase.dart';

/// What a fact is about. The widget maps these to icons; nothing here knows
/// what an icon is.
enum MoonFactKind {
  /// Spring and neap tides.
  tides,

  /// How much light there will be tonight, and what that does.
  nightLight,

  /// What can be seen from a dark sky, or cannot be seen from a bright one.
  stargazing,

  /// A new or full Moon close enough to a node for an eclipse.
  eclipse,

  /// Perigee, apogee, and the apparent size that follows.
  distance,

  /// When the next principal phase lands.
  nextPhase,
}

/// One line of consequence.
class MoonFact {
  const MoonFact({
    required this.kind,
    required this.title,
    required this.detail,
    this.notable = false,
  });

  final MoonFactKind kind;

  /// Two or three words. The row's heading.
  final String title;

  /// One sentence under it.
  final String detail;

  /// Whether this is out of the ordinary — an eclipse window, a supermoon, the
  /// darkest night of the month. The widget draws these brighter, and they are
  /// ordered first.
  final bool notable;
}

/// A perigee close enough to call the Moon large, in km. The usual popular
/// definition of a supermoon (Nolle's) is a syzygy within 10% of the closest
/// perigee of the year, which lands near this figure.
const double kPerigeeThresholdKm = 362000;

/// Far enough out to call it small.
const double kApogeeThresholdKm = 402000;

/// How near a node a syzygy has to be for an eclipse to be possible somewhere
/// on Earth, in degrees of ecliptic latitude.
///
/// The real limits are not a single number — they depend on the Sun's and the
/// Moon's apparent sizes and on the kind of eclipse — but every eclipse falls
/// inside this and very little else does. Verified against four eclipses and
/// two ordinary syzygies in `test/moon_facts_test.dart`; the phrasing says
/// *possible*, which is what a one-number test can honestly claim.
const double kEclipseLatitudeLimit = 1.5;

/// How near a principal phase counts as "at" it, in days, for the tides.
const double _syzygyWindowDays = 1.5;

/// The facts for [reading], most notable first.
///
/// Ordered rather than filtered: the widget shows as many as it has room for
/// and drops the rest off the bottom, so what matters is that an eclipse
/// window outranks the day's tides and the day's tides outrank the countdown
/// to the next quarter.
List<MoonFact> moonFacts(MoonReading reading) {
  final facts = <MoonFact>[
    ..._eclipse(reading),
    _tides(reading),
    _nightLight(reading),
    ..._stargazing(reading),
    _distance(reading),
    _nextPhase(reading),
  ];
  // A stable sort, so the order above survives inside each group.
  final notable = facts.where((fact) => fact.notable);
  final rest = facts.where((fact) => !fact.notable);
  return [...notable, ...rest];
}

/// Days from the nearest new or full Moon.
double _daysFromSyzygy(MoonReading reading) {
  final p = reading.cyclePosition % 1.0;
  final cycles = math.min(math.min(p, (p - 0.5).abs()), 1 - p);
  return cycles * kSynodicMonthDays;
}

/// Days from the nearest quarter.
double _daysFromQuarter(MoonReading reading) {
  final p = reading.cyclePosition % 1.0;
  final cycles = math.min((p - 0.25).abs(), (p - 0.75).abs());
  return cycles * kSynodicMonthDays;
}

MoonFact _tides(MoonReading reading) {
  final toSyzygy = _daysFromSyzygy(reading);
  final toQuarter = _daysFromQuarter(reading);

  if (toSyzygy <= _syzygyWindowDays) {
    final perigean = reading.distanceKm < kPerigeeThresholdKm;
    return MoonFact(
      kind: MoonFactKind.tides,
      title: perigean ? 'Perigean spring tides' : 'Spring tides',
      detail: perigean
          ? 'The Sun and Moon are pulling in line while the Moon is also at '
              'its closest, which makes the largest tides of the year. A storm '
              'arriving on one of these is when coasts flood.'
          : 'The Sun and Moon are pulling in line, so high water is higher and '
              'low water lower than at any other point in the month.',
      notable: perigean,
    );
  }
  if (toQuarter <= _syzygyWindowDays) {
    return const MoonFact(
      kind: MoonFactKind.tides,
      title: 'Neap tides',
      detail: 'The Sun is pulling at right angles to the Moon, so the range '
          'between high and low water is the smallest it gets.',
    );
  }
  // Which milestone is *next*, not which is nearest: three days after a new
  // Moon the tides are still nearer the spring end of their range, and they are
  // nonetheless shrinking, because the quarter is what the Moon is heading for.
  final p = reading.cyclePosition % 1.0;
  final forwardToSyzygy = (0.5 - p) % 0.5;
  // Quarters are half a cycle apart too — 0.25 and 0.75 — so this is the same
  // modulus offset by a quarter. Taking it modulo 0.25 instead would find the
  // syzygy itself and call every gibbous Moon "easing".
  final forwardToQuarter = (0.25 - p) % 0.5;
  final building = forwardToSyzygy < forwardToQuarter;
  return MoonFact(
    kind: MoonFactKind.tides,
    title: building ? 'Tides building' : 'Tides easing',
    detail: building
        ? 'The Sun and Moon are coming into line: the tidal range grows a '
            'little with every cycle until they do.'
        : 'The Sun and Moon are separating, and the tidal range is shrinking '
            'towards the quarter.',
  );
}

MoonFact _nightLight(MoonReading reading) {
  final percent = reading.illuminationPercent;
  if (percent >= 85) {
    return MoonFact(
      kind: MoonFactKind.nightLight,
      title: 'Bright night',
      detail: 'A near-full Moon throws about a quarter of a lux onto the '
          'ground — enough to walk unlit country by. Many nocturnal animals '
          'move less and stay nearer cover on nights like this.',
      notable: percent >= 97,
    );
  }
  if (percent >= 40) {
    return const MoonFact(
      kind: MoonFactKind.nightLight,
      title: 'Moonlit',
      detail: 'Enough light to pick out a path, and enough to wash the '
          'faintest stars out of the part of the sky the Moon is in.',
    );
  }
  if (percent >= 10) {
    return const MoonFact(
      kind: MoonFactKind.nightLight,
      title: 'Thin light',
      detail: 'A crescent sets soon after the Sun or rises just before it, so '
          'most of the night is dark whichever way it is going.',
    );
  }
  return const MoonFact(
    kind: MoonFactKind.nightLight,
    title: 'Dark night',
    detail: 'Almost no moonlight at all. What you can see tonight is limited '
        'by your own sky, not by the Moon.',
  );
}

List<MoonFact> _stargazing(MoonReading reading) {
  final percent = reading.illuminationPercent;
  if (percent <= 15) {
    return [
      const MoonFact(
        kind: MoonFactKind.stargazing,
        title: 'Best week for faint things',
        detail: 'The darkest nights of the month: the Milky Way, faint comets '
            'and any meteor shower running now are all at their best.',
        notable: true,
      ),
    ];
  }
  if (percent >= 90) {
    return [
      const MoonFact(
        kind: MoonFactKind.stargazing,
        title: 'Poor for deep sky',
        detail: 'Moonlight drowns nebulae and galaxies for most of the night. '
            'Planets, double stars and the Moon itself are unaffected.',
      ),
    ];
  }
  return const [];
}

MoonFact _distance(MoonReading reading) {
  final km = reading.distanceKm;
  if (km <= kPerigeeThresholdKm) {
    final atSyzygy = _daysFromSyzygy(reading) <= _syzygyWindowDays;
    return MoonFact(
      kind: MoonFactKind.distance,
      // "Supermoon" is the popular name for a *full* Moon at perigee; the new
      // one at the other end of the orbit is the same geometry and nobody can
      // see it.
      title: atSyzygy && reading.illuminationPercent >= 95
          ? 'Supermoon'
          : 'Near perigee',
      detail: 'At ${formatKilometres(km)} the disc is about a seventh wider '
          'and a third brighter than it is at the far end of its orbit.',
      notable: true,
    );
  }
  if (km >= kApogeeThresholdKm) {
    return MoonFact(
      kind: MoonFactKind.distance,
      title: 'Near apogee',
      detail: 'At ${formatKilometres(km)} this is close to the smallest the '
          'Moon looks all year.',
    );
  }
  return MoonFact(
    kind: MoonFactKind.distance,
    title: 'Distance',
    detail: '${formatKilometres(km)} away — ${formatLightTime(km)}, and about '
        'thirty Earths end to end.',
  );
}

MoonFact _nextPhase(MoonReading reading) {
  final when = formatMoonCountdown(reading.nextPrincipalTime, reading.time);
  return MoonFact(
    kind: MoonFactKind.nextPhase,
    title: '${reading.nextPrincipalPhase.label} $when',
    detail: '${formatMoonDate(reading.nextPrincipalTime, reference: reading.time)} '
        'at ${formatMoonTime(reading.nextPrincipalTime)}, local time.',
  );
}

/// The eclipse window, or nothing.
///
/// An eclipse happens when a syzygy falls near one of the two points where the
/// Moon's orbit crosses the ecliptic — which is exactly the statement that the
/// Moon's ecliptic latitude is near zero at that instant, and that latitude is
/// something `moon_ephemeris.dart` already computes to a thousandth of a
/// degree. Both upcoming syzygies are checked, because the interesting one is
/// as often the full Moon as the new one.
List<MoonFact> _eclipse(MoonReading reading) {
  final facts = <MoonFact>[];
  final candidates = <(DateTime, bool)>[
    (reading.nextNewMoon, true),
    (reading.nextFullMoon, false),
  ]..sort((a, b) => a.$1.compareTo(b.$1));

  for (final (instant, solar) in candidates) {
    final latitude =
        moonPosition(julianCenturies(instant)).latitude.abs();
    if (latitude > kEclipseLatitudeLimit) continue;
    final date = formatMoonDate(instant, reference: reading.time);
    facts.add(MoonFact(
      kind: MoonFactKind.eclipse,
      title: solar ? 'Solar eclipse window' : 'Lunar eclipse window',
      detail: solar
          ? 'The new Moon on $date passes almost exactly across the Sun\'s '
              'line, so somewhere on Earth will see it eclipsed.'
          : 'The full Moon on $date passes through the Earth\'s shadow, which '
              'is a lunar eclipse for the whole night side of the planet.',
      notable: true,
    ));
  }
  return facts;
}
