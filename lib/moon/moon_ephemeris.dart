// Where the Moon and the Sun are, as arithmetic.
//
// The bottom layer of `lib/moon/`: no Flutter, no I/O, no clock of its own —
// every function is a pure function of a `DateTime` and, where the observer
// matters, a pair of coordinates. That is what makes the whole lunar feature a
// plain unit test rather than something only a live sky can exercise.
//
// The series are Meeus, *Astronomical Algorithms* (2nd ed.): chapter 47 for the
// Moon's position (tables 47.A and 47.B, complete), 25 for the Sun's, 22 for the
// obliquity and 12 for sidereal time. Truncating 47.A/B further is a false
// economy: the tables *are* the accuracy, they cost a few hundred multiply-adds
// once a minute, and the widget shows a moonrise time to the minute.
//
// Three deliberate omissions, each worth about as much as the last digit printed:
//
// - **UTC is used where the algorithms want TD.** ΔT is ~70 seconds this
//   century, which is under a minute of moonrise time.
// - **Geometric positions, not apparent ones** — no nutation, aberration or
//   light-time, together a few arcseconds.
// - **The observer is at sea level on a spherical Earth**, with the standard
//   mean refraction baked into the rise/set altitude.
//
// Checked against Meeus's own worked examples in `test/moon_ephemeris_test.dart`.

import 'dart:math' as math;

const double _rad = math.pi / 180.0;

/// The mean length of a lunation, in days. Used only where a *nominal* month
/// is wanted (a progress ring, a "day 14 of 29.5" readout); every actual phase
/// instant is found by search — see `moon_phase.dart`.
const double kSynodicMonthDays = 29.530588853;

/// Earth's equatorial radius in km, for the Moon's horizontal parallax.
const double kEarthRadiusKm = 6378.14;

/// The Julian Day for [time], which is converted to UTC first.
double julianDay(DateTime time) {
  final utc = time.toUtc();
  var year = utc.year;
  var month = utc.month;
  final day = utc.day +
      (utc.hour +
              (utc.minute + (utc.second + utc.millisecond / 1000) / 60) / 60) /
          24;
  if (month <= 2) {
    year -= 1;
    month += 12;
  }
  final a = (year / 100).floor();
  final b = 2 - a + (a / 4).floor();
  return (365.25 * (year + 4716)).floor() +
      (30.6001 * (month + 1)).floor() +
      day +
      b -
      1524.5;
}

/// Julian centuries from J2000.0 — the argument every series here takes.
double julianCenturies(DateTime time) => (julianDay(time) - 2451545.0) / 36525.0;

/// [degrees] wrapped into `[0, 360)`.
double normalizeDegrees(double degrees) {
  final wrapped = degrees % 360.0;
  return wrapped < 0 ? wrapped + 360.0 : wrapped;
}

/// The signed difference `a - b`, in `(-180, 180]`.
///
/// The one piece of angle arithmetic every caller here gets wrong first: the
/// difference between 359° and 1° is 2, not 358.
double angleDifference(double a, double b) {
  final delta = (a - b) % 360.0;
  if (delta > 180.0) return delta - 360.0;
  if (delta <= -180.0) return delta + 360.0;
  return delta;
}

/// Where the Moon is, geocentrically.
class MoonPosition {
  const MoonPosition({
    required this.longitude,
    required this.latitude,
    required this.distanceKm,
  });

  /// Apparent ecliptic longitude, degrees.
  final double longitude;

  /// Ecliptic latitude, degrees. Small — the Moon's orbit is inclined about
  /// 5.1° — and the sign of it near a new or full Moon is what says whether an
  /// eclipse is on: at syzygy an almost-zero latitude means the three bodies
  /// are very nearly in a line.
  final double latitude;

  /// Centre-to-centre distance in km. 356,500 at the closest perigee and
  /// 406,700 at the furthest apogee, which is a 14% swing in apparent size.
  final double distanceKm;

  /// The Moon's apparent diameter in degrees — about half a degree, varying
  /// with [distanceKm]. (The IAU mean radius, 1737.4 km.)
  double get angularDiameterDegrees =>
      2 * math.asin(1737.4 / distanceKm) / _rad;

  /// Equatorial horizontal parallax, degrees.
  double get parallaxDegrees => math.asin(kEarthRadiusKm / distanceKm) / _rad;
}

/// Where the Sun is, in as much detail as the phase needs.
class SunPosition {
  const SunPosition({required this.longitude, required this.distanceAu});

  /// True geometric ecliptic longitude, degrees.
  final double longitude;

  /// Earth–Sun distance in astronomical units.
  final double distanceAu;

  static const double kAuKm = 149597870.7;

  double get distanceKm => distanceAu * kAuKm;
}

/// Meeus table 47.A: the arguments `(D, M, M', F)` and the coefficients of the
/// longitude (1e-6 degrees) and distance (1e-3 km) series.
const List<(int, int, int, int, int, int)> _moonLongitudeDistanceTerms = [
  (0, 0, 1, 0, 6288774, -20905355),
  (2, 0, -1, 0, 1274027, -3699111),
  (2, 0, 0, 0, 658314, -2955968),
  (0, 0, 2, 0, 213618, -569925),
  (0, 1, 0, 0, -185116, 48888),
  (0, 0, 0, 2, -114332, -3149),
  (2, 0, -2, 0, 58793, 246158),
  (2, -1, -1, 0, 57066, -152138),
  (2, 0, 1, 0, 53322, -170733),
  (2, -1, 0, 0, 45758, -204586),
  (0, 1, -1, 0, -40923, -129620),
  (1, 0, 0, 0, -34720, 108743),
  (0, 1, 1, 0, -30383, 104755),
  (2, 0, 0, -2, 15327, 10321),
  (0, 0, 1, 2, -12528, 0),
  (0, 0, 1, -2, 10980, 79661),
  (4, 0, -1, 0, 10675, -34782),
  (0, 0, 3, 0, 10034, -23210),
  (4, 0, -2, 0, 8548, -21636),
  (2, 1, -1, 0, -7888, 24208),
  (2, 1, 0, 0, -6766, 30824),
  (1, 0, -1, 0, -5163, -8379),
  (1, 1, 0, 0, 4987, -16675),
  (2, -1, 1, 0, 4036, -12831),
  (2, 0, 2, 0, 3994, -10445),
  (4, 0, 0, 0, 3861, -11650),
  (2, 0, -3, 0, 3665, 14403),
  (0, 1, -2, 0, -2689, -7003),
  (2, 0, -1, 2, -2602, 0),
  (2, -1, -2, 0, 2390, 10056),
  (1, 0, 1, 0, -2348, 6322),
  (2, -2, 0, 0, 2236, -9884),
  (0, 1, 2, 0, -2120, 5751),
  (0, 2, 0, 0, -2069, 0),
  (2, -2, -1, 0, 2048, -4950),
  (2, 0, 1, -2, -1773, 4130),
  (2, 0, 0, 2, -1595, 0),
  (4, -1, -1, 0, 1215, -3958),
  (0, 0, 2, 2, -1110, 0),
  (3, 0, -1, 0, -892, 3258),
  (2, 1, 1, 0, -810, 2616),
  (4, -1, -2, 0, 759, -1897),
  (0, 2, -1, 0, -713, -2117),
  (2, 2, -1, 0, -700, 2354),
  (2, 1, -2, 0, 691, 0),
  (2, -1, 0, -2, 596, 0),
  (4, 0, 1, 0, 549, -1423),
  (0, 0, 4, 0, 537, -1117),
  (4, -1, 0, 0, 520, -1571),
  (1, 0, -2, 0, -487, -1739),
  (2, 1, 0, -2, -399, 0),
  (0, 0, 2, -2, -381, -4421),
  (1, 1, 1, 0, 351, 0),
  (3, 0, -2, 0, -340, 0),
  (4, 0, -3, 0, 330, 0),
  (2, -1, 2, 0, 327, 0),
  (0, 2, 1, 0, -323, 1165),
  (1, 1, -1, 0, 299, 0),
  (2, 0, 3, 0, 294, 0),
  (2, 0, -1, -2, 0, 8752),
];

/// Meeus table 47.B: the ecliptic-latitude series, 1e-6 degrees.
const List<(int, int, int, int, int)> _moonLatitudeTerms = [
  (0, 0, 0, 1, 5128122),
  (0, 0, 1, 1, 280602),
  (0, 0, 1, -1, 277693),
  (2, 0, 0, -1, 173237),
  (2, 0, -1, 1, 55413),
  (2, 0, -1, -1, 46271),
  (2, 0, 0, 1, 32573),
  (0, 0, 2, 1, 17198),
  (2, 0, 1, -1, 9266),
  (0, 0, 2, -1, 8822),
  (2, -1, 0, -1, 8216),
  (2, 0, -2, -1, 4324),
  (2, 0, 1, 1, 4200),
  (2, 1, 0, -1, -3359),
  (2, -1, -1, 1, 2463),
  (2, -1, 0, 1, 2211),
  (2, -1, -1, -1, 2065),
  (0, 1, -1, -1, -1870),
  (4, 0, -1, -1, 1828),
  (0, 1, 0, 1, -1794),
  (0, 0, 0, 3, -1749),
  (0, 1, -1, 1, -1565),
  (1, 0, 0, 1, -1491),
  (0, 1, 1, 1, -1475),
  (0, 1, 1, -1, -1410),
  (0, 1, 0, -1, -1344),
  (1, 0, 0, -1, -1335),
  (0, 0, 3, 1, 1107),
  (4, 0, 0, -1, 1021),
  (4, 0, -1, 1, 833),
  (0, 0, 1, -3, 777),
  (4, 0, -2, 1, 671),
  (2, 0, 0, -3, 607),
  (2, 0, 2, -1, 596),
  (2, -1, 1, -1, 491),
  (2, 0, -2, 1, -451),
  (0, 0, 3, -1, 439),
  (2, 0, 2, 1, 422),
  (2, 0, -3, -1, 421),
  (2, 1, -1, 1, -366),
  (2, 1, 0, 1, -351),
  (4, 0, 0, 1, 331),
  (2, -1, 1, 1, 315),
  (2, -2, 0, -1, 302),
  (0, 0, 1, 3, -283),
  (2, 1, 1, -1, -229),
  (1, 1, 0, -1, 223),
  (1, 1, 0, 1, 223),
  (0, 1, -2, -1, -220),
  (2, 1, -1, -1, -220),
  (1, 0, 1, 1, -185),
  (2, -1, -2, -1, 181),
  (0, 1, 2, 1, -177),
  (4, 0, -2, -1, 176),
  (4, -1, -1, -1, 166),
  (1, 0, 1, -1, -164),
  (4, 0, 1, -1, 132),
  (1, 0, -1, -1, -119),
  (4, -1, 0, -1, 115),
  (2, -2, 0, 1, 107),
];

/// The Moon's geocentric position at [t] Julian centuries from J2000.
MoonPosition moonPosition(double t) {
  final t2 = t * t;
  final t3 = t2 * t;
  final t4 = t3 * t;

  // Mean longitude, mean elongation, the Sun's and the Moon's mean anomalies,
  // and the argument of latitude (Meeus 47.1–47.5).
  final lp = 218.3164477 +
      481267.88123421 * t -
      0.0015786 * t2 +
      t3 / 538841 -
      t4 / 65194000;
  final d = 297.8501921 +
      445267.1114034 * t -
      0.0018819 * t2 +
      t3 / 545868 -
      t4 / 113065000;
  final m = 357.5291092 + 35999.0502909 * t - 0.0001536 * t2 + t3 / 24490000;
  final mp = 134.9633964 +
      477198.8675055 * t +
      0.0087414 * t2 +
      t3 / 69699 -
      t4 / 14712000;
  final f = 93.2720950 +
      483202.0175233 * t -
      0.0036539 * t2 -
      t3 / 3526000 +
      t4 / 863310000;

  // The three additive arguments: Venus, Jupiter, and the flattening of the
  // Earth (Meeus, chapter 47, "Additive terms").
  final a1 = 119.75 + 131.849 * t;
  final a2 = 53.09 + 479264.290 * t;
  final a3 = 313.45 + 481266.484 * t;

  // The eccentricity correction, applied once for a term in M and twice for a
  // term in 2M — the Earth's orbit is not what it was in 1900.
  final e = 1 - 0.002516 * t - 0.0000074 * t2;
  final e2 = e * e;

  var sumL = 0.0;
  var sumR = 0.0;
  for (final term in _moonLongitudeDistanceTerms) {
    final argument =
        (term.$1 * d + term.$2 * m + term.$3 * mp + term.$4 * f) * _rad;
    final factor = switch (term.$2.abs()) { 0 => 1.0, 1 => e, _ => e2 };
    sumL += term.$5 * factor * math.sin(argument);
    sumR += term.$6 * factor * math.cos(argument);
  }

  var sumB = 0.0;
  for (final term in _moonLatitudeTerms) {
    final argument =
        (term.$1 * d + term.$2 * m + term.$3 * mp + term.$4 * f) * _rad;
    final factor = switch (term.$2.abs()) { 0 => 1.0, 1 => e, _ => e2 };
    sumB += term.$5 * factor * math.sin(argument);
  }

  sumL += 3958 * math.sin(a1 * _rad) +
      1962 * math.sin((lp - f) * _rad) +
      318 * math.sin(a2 * _rad);
  sumB += -2235 * math.sin(lp * _rad) +
      382 * math.sin(a3 * _rad) +
      175 * math.sin((a1 - f) * _rad) +
      175 * math.sin((a1 + f) * _rad) +
      127 * math.sin((lp - mp) * _rad) -
      115 * math.sin((lp + mp) * _rad);

  return MoonPosition(
    longitude: normalizeDegrees(lp + sumL / 1e6),
    latitude: sumB / 1e6,
    distanceKm: 385000.56 + sumR / 1000.0,
  );
}

/// The Sun's geometric position at [t] Julian centuries from J2000
/// (Meeus, chapter 25, the low-accuracy series — good to about 0.01°).
SunPosition sunPosition(double t) {
  final t2 = t * t;
  final l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t2;
  final m = 357.52911 + 35999.05029 * t - 0.0001537 * t2;
  final centre = (1.914602 - 0.004817 * t - 0.000014 * t2) * math.sin(m * _rad) +
      (0.019993 - 0.000101 * t) * math.sin(2 * m * _rad) +
      0.000289 * math.sin(3 * m * _rad);
  final trueAnomaly = m + centre;
  final eccentricity = 0.016708634 - 0.000042037 * t - 0.0000001267 * t2;
  final distance = 1.000001018 *
      (1 - eccentricity * eccentricity) /
      (1 + eccentricity * math.cos(trueAnomaly * _rad));
  return SunPosition(
    longitude: normalizeDegrees(l0 + centre),
    distanceAu: distance,
  );
}

/// The mean obliquity of the ecliptic at [t], degrees (Meeus 22.2).
double meanObliquity(double t) =>
    23.4392911 - 0.0130042 * t - 1.64e-7 * t * t + 5.04e-7 * t * t * t;

/// Mean sidereal time at Greenwich for [jd], degrees (Meeus 12.4).
double greenwichSiderealTime(double jd) {
  final t = (jd - 2451545.0) / 36525.0;
  return normalizeDegrees(280.46061837 +
      360.98564736629 * (jd - 2451545.0) +
      0.000387933 * t * t -
      t * t * t / 38710000);
}

/// A body's right ascension and declination, in degrees.
typedef Equatorial = ({double rightAscension, double declination});

/// [longitude]/[latitude] on the ecliptic, converted to the equator of date.
Equatorial equatorialFromEcliptic({
  required double longitude,
  required double latitude,
  required double obliquity,
}) {
  final l = longitude * _rad;
  final b = latitude * _rad;
  final e = obliquity * _rad;
  final ra = math.atan2(
    math.sin(l) * math.cos(e) - math.tan(b) * math.sin(e),
    math.cos(l),
  );
  final dec = math.asin(
    math.sin(b) * math.cos(e) + math.cos(b) * math.sin(e) * math.sin(l),
  );
  return (
    rightAscension: normalizeDegrees(ra / _rad),
    declination: dec / _rad,
  );
}

/// How high the Moon is above [latitude]/[longitude]'s horizon at [time], and the
/// altitude its centre has to reach to count as risen.
///
/// [horizonDegrees] is the standard rise/set altitude for the Moon:
/// `0.7275 × parallax − 34′`, the upper limb clearing a refracted horizon. It is
/// a hair *above* zero rather than below — the Moon is close enough that its
/// parallax outweighs the refraction every other body's rise time subtracts.
({double altitudeDegrees, double horizonDegrees}) moonAltitude({
  required DateTime time,
  required double latitude,
  required double longitude,
}) {
  final jd = julianDay(time);
  final t = (jd - 2451545.0) / 36525.0;
  final moon = moonPosition(t);
  final equatorial = equatorialFromEcliptic(
    longitude: moon.longitude,
    latitude: moon.latitude,
    obliquity: meanObliquity(t),
  );
  // East longitudes positive, which is what every coordinate the shell holds
  // already is — `WeatherPlace.longitude` comes from Open-Meteo and ipapi.
  final hourAngle = (greenwichSiderealTime(jd) +
          longitude -
          equatorial.rightAscension) *
      _rad;
  final phi = latitude * _rad;
  final dec = equatorial.declination * _rad;
  final altitude = math.asin(
    math.sin(phi) * math.sin(dec) +
        math.cos(phi) * math.cos(dec) * math.cos(hourAngle),
  );
  return (
    altitudeDegrees: altitude / _rad,
    horizonDegrees: 0.7275 * moon.parallaxDegrees - 0.5667,
  );
}
