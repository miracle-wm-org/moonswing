// The twelve signs, and which one a birthday falls in.
//
// The sign is *computed*, not looked up. A tropical sun sign is a 30° arc of
// ecliptic longitude measured from the vernal equinox, so the question "which
// sign is this birthday" is the question "where was the Sun that day" — and
// `lib/moon/moon_ephemeris.dart` already answers that to about 0.01° with
// Meeus's chapter 25 series, because the lunar phase needs it. Borrowing it
// costs nothing and buys the one thing a table of date ranges cannot give: the
// boundaries move by a day or so from year to year (the tropical year is not
// 365 days, and the leap-day correction slips it back), so "Aries starts on
// 21 March" is right about three years in four and wrong on the fourth for
// anyone born near a cusp. The ranges this file reports are therefore searched
// for in the birth year rather than quoted.
//
// Flutter-free — the ephemeris and nothing else — so all of it is a plain unit
// test.

import 'package:graceful_shell/moon/moon_ephemeris.dart';

/// The classical element a sign belongs to.
enum ZodiacElement {
  fire('Fire'),
  earth('Earth'),
  air('Air'),
  water('Water');

  const ZodiacElement(this.label);

  final String label;
}

/// The classical modality — cardinal signs open a season, fixed signs sit in
/// the middle of one, mutable signs end it.
enum ZodiacModality {
  cardinal('Cardinal'),
  fixed('Fixed'),
  mutable('Mutable');

  const ZodiacModality(this.label);

  final String label;
}

/// One of the twelve signs.
///
/// Declaration order is the order of the arcs along the ecliptic starting at
/// the vernal equinox, which is what [startLongitude] and [ordinal] rely on:
/// Aries begins at 0°, and each sign is the 30° after the last.
enum ZodiacSign {
  aries('Aries', ZodiacElement.fire, ZodiacModality.cardinal, 'Mars', 'Ari'),
  taurus('Taurus', ZodiacElement.earth, ZodiacModality.fixed, 'Venus', 'Tau'),
  gemini('Gemini', ZodiacElement.air, ZodiacModality.mutable, 'Mercury', 'Gem'),
  cancer('Cancer', ZodiacElement.water, ZodiacModality.cardinal, 'Moon', 'Cnc'),
  leo('Leo', ZodiacElement.fire, ZodiacModality.fixed, 'Sun', 'Leo'),
  virgo('Virgo', ZodiacElement.earth, ZodiacModality.mutable, 'Mercury', 'Vir'),
  libra('Libra', ZodiacElement.air, ZodiacModality.cardinal, 'Venus', 'Lib'),
  scorpio('Scorpio', ZodiacElement.water, ZodiacModality.fixed, 'Mars', 'Sco'),
  sagittarius('Sagittarius', ZodiacElement.fire, ZodiacModality.mutable,
      'Jupiter', 'Sgr'),
  capricorn('Capricorn', ZodiacElement.earth, ZodiacModality.cardinal, 'Saturn',
      'Cap'),
  aquarius(
      'Aquarius', ZodiacElement.air, ZodiacModality.fixed, 'Saturn', 'Aqr'),
  pisces('Pisces', ZodiacElement.water, ZodiacModality.mutable, 'Jupiter',
      'Psc');

  const ZodiacSign(
    this.label,
    this.element,
    this.modality,
    this.rulingPlanet,
    this.constellationCode,
  );

  /// "Aries". Also what the horoscope API's `sign` parameter wants, which is
  /// why there is no second spelling of it.
  final String label;

  final ZodiacElement element;
  final ZodiacModality modality;

  /// The classical ruler. Deliberately the classical one rather than the modern
  /// outer-planet assignment (Pluto for Scorpio, Uranus for Aquarius, Neptune
  /// for Pisces): the two schemes disagree about three signs, and the classical
  /// set is the one whose bodies are all visible to the eye — which is the only
  /// sense in which the attribution was ever an observation.
  final String rulingPlanet;

  /// The IAU abbreviation of the constellation the sign is named for. The key
  /// into `constellation.dart`'s figures.
  ///
  /// Sign and constellation are **not** the same thing and this is the one
  /// place the shell brings them together: precession has moved the two apart
  /// by about a sign since the arcs were named, so the Sun is in the *sign*
  /// Aries while it is in front of the *constellation* Pisces. The card draws
  /// the constellation the sign is named after, which is what somebody looking
  /// at it expects to see, and says nothing that implies the Sun is there.
  final String constellationCode;

  /// The sign's position in the ecliptic order, Aries first.
  int get ordinal => index;

  /// Where the sign's arc begins, in degrees of ecliptic longitude.
  double get startLongitude => index * 30.0;

  /// "Fire · Cardinal · ruled by Mars" — the attribute line, in one place so
  /// both the card and the settings row read the same.
  String get attributes =>
      '${element.label} · ${modality.label} · ruled by $rulingPlanet';

  /// [name]'s sign, matched case-insensitively against [label], or null.
  /// Config values are strings the user typed, so a misspelling costs the
  /// setting rather than the widget.
  static ZodiacSign? parse(String name) {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    for (final sign in ZodiacSign.values) {
      if (sign.label.toLowerCase() == wanted) return sign;
    }
    return null;
  }
}

/// The sign whose arc contains [eclipticLongitude], in degrees.
ZodiacSign signAtLongitude(double eclipticLongitude) {
  final normalized = normalizeDegrees(eclipticLongitude);
  // `normalizeDegrees` answers `[0, 360)`, so the divide lands in `[0, 12)` and
  // the clamp only ever catches a floating-point edge exactly at 360.
  final index =
      (normalized / 30).floor().clamp(0, ZodiacSign.values.length - 1);
  return ZodiacSign.values[index];
}

/// The Sun's true geometric ecliptic longitude at [time], in degrees.
double solarLongitude(DateTime time) =>
    sunPosition(julianCenturies(time)).longitude;

/// The Sun's mean motion, degrees per day. Only ever an initial guess — see
/// [solarIngressAfter].
const double _meanSolarRate = 360.0 / 365.2422;

DateTime _addDays(DateTime time, double days) => time
    .add(Duration(microseconds: (days * Duration.microsecondsPerDay).round()));

/// Newton's method on the solar longitude, from [estimate].
///
/// `moon_phase.dart`'s `_solveElongation`, with the Sun's series in place of
/// the elongation and the derivative measured over an hour rather than ten
/// minutes — the Sun moves a fortieth as fast, so a ten-minute baseline is
/// mostly measuring the rounding in the series.
DateTime _solveLongitude(DateTime estimate, double target) {
  var time = estimate;
  for (var i = 0; i < 6; i++) {
    final error = angleDifference(solarLongitude(time), target);
    if (error.abs() < 1e-7) break;
    const step = Duration(hours: 1);
    final ahead = angleDifference(solarLongitude(time.add(step)), target);
    final rate = (ahead - error) / (step.inMinutes / (60 * 24));
    if (rate == 0) break;
    time = _addDays(time, -error / rate);
  }
  return time;
}

/// How close to the start a solution counts as *being* the start.
/// `moon_phase`'s `_phaseSearchEpsilon`, and there for the same reason: asked
/// for the next ingress at the instant of one, the answer has to be next
/// year's.
const Duration _ingressEpsilon = Duration(seconds: 1);

/// The first time strictly after [start] that the Sun enters [sign].
///
/// Geometric longitude, so this lands about eight minutes before the instant an
/// almanac quotes — those are *apparent* longitude, which subtracts the roughly
/// 20 arcseconds of annual aberration and adds nutation. Both are far below the
/// resolution of a date with no time on it, and correcting for them would mean
/// carrying a nutation series for a readout that names a day.
DateTime solarIngressAfter(DateTime start, ZodiacSign sign) {
  final target = sign.startLongitude;
  final ahead = (target - solarLongitude(start)) % 360.0;
  var solved = _solveLongitude(_addDays(start, ahead / _meanSolarRate), target);
  // Newton lands on whichever root is nearest the guess, which for a target the
  // Sun is already at is the one just gone.
  if (solved.isBefore(start.add(_ingressEpsilon))) {
    solved = _solveLongitude(_addDays(solved, 365.2422), target);
  }
  return solved;
}

/// When the Sun enters and leaves [sign] during [year].
///
/// Exactly one ingress per sign per calendar year: the twelve are spaced about
/// 30.4 days apart across a 365.24-day year, so there is always one of each and
/// never two. The nearest any of them comes to the year boundary is Capricorn's
/// around 21 December, which is ten days of margin — so searching forward from
/// New Year cannot skip one or find the same one twice.
///
/// Both instants are UTC, because that is what the search works in; a caller
/// wanting them as dates converts with [DateTime.toLocal] first — which is the
/// difference between "23 July" and "22 July" for a user far enough west.
({DateTime start, DateTime end}) solarSeasonIn(int year, ZodiacSign sign) {
  final start = solarIngressAfter(DateTime.utc(year), sign);
  final next = ZodiacSign.values[(sign.index + 1) % ZodiacSign.values.length];
  return (start: start, end: solarIngressAfter(start, next));
}

/// A birthday resolved into a sign.
class ZodiacReading {
  const ZodiacReading({
    required this.sign,
    required this.birthday,
    required this.longitude,
    required this.neighbour,
  });

  final ZodiacSign sign;

  /// The date the reading was made for, as the user gave it.
  final DateTime birthday;

  /// The Sun's ecliptic longitude at local noon on [birthday], degrees.
  final double longitude;

  /// The *other* sign the birthday touches, or null on all but two days a
  /// month.
  ///
  /// The Sun crosses a boundary at some clock time, and a birthday is a date:
  /// on the day of an ingress, a person born in the morning and a person born
  /// in the evening have different signs and the date alone cannot say which.
  /// Rather than pick silently, the reading names both and the surfaces that
  /// have room say so. Null means the whole local day sat inside one arc, which
  /// is the case for roughly twenty-eight days in thirty.
  final ZodiacSign? neighbour;

  /// Whether [birthday] is a day the Sun changed signs.
  bool get onCusp => neighbour != null;

  /// How far into the sign's 30° arc the Sun had travelled, `[0, 30)`.
  double get degreesIntoSign => longitude - sign.startLongitude;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ZodiacReading &&
          other.sign == sign &&
          other.birthday == birthday &&
          other.longitude == longitude &&
          other.neighbour == neighbour;

  @override
  int get hashCode => Object.hash(sign, birthday, longitude, neighbour);

  @override
  String toString() =>
      'ZodiacReading(${sign.label}, ${longitude.toStringAsFixed(2)}°'
      '${onCusp ? ', cusp with ${neighbour!.label}' : ''})';
}

/// The sign [birthday] falls in.
///
/// Only the date part is read. It is evaluated at **local noon**, which is the
/// convention for a birth time nobody recorded: it is the instant furthest from
/// either end of the day, so it is the answer least likely to be wrong by the
/// hours the missing time could have moved it.
///
/// The two ends of the same local day decide [ZodiacReading.neighbour]. Both
/// are built with `DateTime(y, m, d)` and `DateTime(y, m, d + 1)` rather than
/// by adding 24 hours, the discipline `overlay/calendar/month.dart` states: the
/// day the clocks change is 23 or 25 hours long, and the boundary this is
/// looking for can fall inside the difference.
ZodiacReading zodiacReadingFor(DateTime birthday) {
  final dayStart = DateTime(birthday.year, birthday.month, birthday.day);
  final dayEnd = DateTime(birthday.year, birthday.month, birthday.day + 1);
  final noon = DateTime(birthday.year, birthday.month, birthday.day, 12);

  final longitude = solarLongitude(noon);
  final sign = signAtLongitude(longitude);
  final atStart = signAtLongitude(solarLongitude(dayStart));
  final atEnd = signAtLongitude(solarLongitude(dayEnd));

  // The day holds an ingress when its two ends disagree. Which of them is the
  // neighbour depends on which side of the crossing noon fell.
  final ZodiacSign? neighbour = atStart == atEnd
      ? null
      : sign == atStart
          ? atEnd
          : atStart;

  return ZodiacReading(
    sign: sign,
    birthday: dayStart,
    longitude: longitude,
    neighbour: neighbour,
  );
}
