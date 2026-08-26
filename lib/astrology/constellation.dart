// The twelve zodiac constellations as stick figures, from a real star
// catalogue.
//
// Every vertex here is a catalogued star, not a decorative dot: the figures are
// d3-celestial's `constellations.lines.json` (Olaf Frohn, BSD-3-Clause) and
// each vertex's brightness is the Hipparcos/Yale magnitude of the star that
// sits there, matched within 0.02°. All 173 of them matched, so nothing on the
// card is invented — the alternative was hand-drawing twelve asterisms from
// memory, which is the picture *looking* like a star chart while being a
// doodle, and this file would then have had to say so.
//
// The coordinates were projected once, offline, by
// `tool/gen_constellations.py`: a tangent plane about each figure's own
// centroid, with right ascension flipped (RA grows eastward, which is leftward
// on a sky chart) and declination flipped (north is up, which is -y on a
// canvas), then scaled — **both axes by the same factor**, so the shapes are
// not stretched — into `[0, 1]` and centred. A figure therefore fills its unit
// box on its longer axis and is inset on the other, and a painter maps that box
// to a square: see `zodiac_sky.dart`, which letterboxes rather than fills.
//
// Flutter-free: plain numbers, so `test/constellation_test.dart` checks the
// table without a canvas.

import 'package:flutter/foundation.dart' show immutable;

/// One star of a figure: where it sits in the unit box, and how bright it is.
@immutable
class ConstellationStar {
  const ConstellationStar(this.x, this.y, this.magnitude);

  /// Position in `[0, 1]`, y downwards.
  final double x;
  final double y;

  /// Apparent visual magnitude — **smaller is brighter**, and it runs negative
  /// for the brightest stars in the sky. Nothing in the zodiac is negative
  /// (Antares at 1.06 is the brightest star in this table), but the painter's
  /// scale is written so one would not break it.
  final double magnitude;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstellationStar &&
          other.x == x &&
          other.y == y &&
          other.magnitude == magnitude;

  @override
  int get hashCode => Object.hash(x, y, magnitude);
}

/// One constellation figure.
@immutable
class Constellation {
  const Constellation({
    required this.code,
    required this.name,
    required this.stars,
    required this.lines,
  });

  /// The IAU abbreviation — `Leo`, `Sco`. What `ZodiacSign.constellationCode`
  /// holds.
  final String code;

  /// The constellation's own name, which is **not** always the sign's: the
  /// signs are Scorpio and Capricorn, the constellations Scorpius and
  /// Capricornus.
  final String name;

  final List<ConstellationStar> stars;

  /// The figure's strokes, as paths of indices into [stars]. Several, because
  /// most of these are not one unbroken line — Taurus has the V of the Hyades
  /// and two horns, Sagittarius has the teapot and the bow.
  final List<List<int>> lines;
}

/// The figure for an IAU code, or null for one this table does not carry.
///
/// Null rather than a throw, `conditionForCode`'s rule: this is reached from a
/// `build`, and a code the table does not know must cost the drawing rather
/// than the card.
Constellation? constellationFor(String code) => _figures[code];

/// Every figure, keyed by IAU code.
const Map<String, Constellation> zodiacConstellations = _figures;

const Map<String, Constellation> _figures = {
  'Ari': Constellation(
    code: 'Ari',
    name: 'Aries',
    stars: [
      ConstellationStar(0.0, 0.1941, 3.61),
      ConstellationStar(0.7583, 0.4858, 2.01),
      ConstellationStar(0.9803, 0.6897, 2.64),
      ConstellationStar(1.0, 0.8059, 3.88),
    ],
    lines: [
      [0, 1, 2, 3],
    ],
  ),
  'Tau': Constellation(
    code: 'Tau',
    name: 'Taurus',
    stars: [
      ConstellationStar(0.0, 0.2939, 2.97),
      ConstellationStar(0.4647, 0.4378, 0.87),
      ConstellationStar(0.5193, 0.4576, 3.4),
      ConstellationStar(0.5861, 0.4651, 3.65),
      ConstellationStar(0.5624, 0.4057, 3.77),
      ConstellationStar(0.5197, 0.3548, 3.53),
      ConstellationStar(0.0855, 0.0621, 1.65),
      ConstellationStar(0.73, 0.5625, 3.41),
      ConstellationStar(0.9823, 0.6482, 3.73),
      ConstellationStar(0.7113, 0.7644, 3.91),
      ConstellationStar(1.0, 0.67, 3.61),
      ConstellationStar(0.9092, 0.9379, 4.29),
    ],
    lines: [
      [0, 1, 2, 3, 4, 5, 6],
      [3, 7, 8, 9],
      [8, 10, 11],
    ],
  ),
  'Gem': Constellation(
    code: 'Gem',
    name: 'Gemini',
    stars: [
      ConstellationStar(1.0, 0.4945, 3.31),
      ConstellationStar(0.9106, 0.4942, 2.87),
      ConstellationStar(0.6787, 0.3685, 3.06),
      ConstellationStar(0.3779, 0.123, 4.41),
      ConstellationStar(0.1185, 0.0441, 1.58),
      ConstellationStar(0.0, 0.2295, 1.16),
      ConstellationStar(0.1039, 0.2838, 4.06),
      ConstellationStar(0.2786, 0.5197, 3.5),
      ConstellationStar(0.4556, 0.5875, 4.01),
      ConstellationStar(0.7475, 0.7877, 1.93),
      ConstellationStar(0.6637, 0.9559, 3.35),
      ConstellationStar(0.301, 0.7809, 3.58),
    ],
    lines: [
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      [7, 11],
    ],
  ),
  'Cnc': Constellation(
    code: 'Cnc',
    name: 'Cancer',
    stars: [
      ConstellationStar(0.2451, 0.8635, 4.26),
      ConstellationStar(0.4127, 0.5419, 3.94),
      ConstellationStar(0.4297, 0.3727, 4.66),
      ConstellationStar(0.3887, 0.0, 4.03),
      ConstellationStar(0.7549, 1.0, 3.53),
    ],
    lines: [
      [0, 1, 2, 3],
      [1, 4],
    ],
  ),
  'Leo': Constellation(
    code: 'Leo',
    name: 'Leo',
    stars: [
      ConstellationStar(0.8172, 0.7404, 1.36),
      ConstellationStar(0.8257, 0.5762, 3.48),
      ConstellationStar(0.7231, 0.4707, 2.01),
      ConstellationStar(0.2837, 0.4474, 2.56),
      ConstellationStar(0.0, 0.6512, 2.14),
      ConstellationStar(0.2826, 0.6218, 3.33),
      ConstellationStar(0.7497, 0.3483, 3.43),
      ConstellationStar(0.9439, 0.2596, 3.88),
      ConstellationStar(1.0, 0.3361, 2.97),
    ],
    lines: [
      [0, 1, 2, 3, 4, 5, 0],
      [2, 6, 7, 8],
    ],
  ),
  'Vir': Constellation(
    code: 'Vir',
    name: 'Virgo',
    stars: [
      ConstellationStar(1.0, 0.353, 4.04),
      ConstellationStar(0.9732, 0.4586, 3.59),
      ConstellationStar(0.8113, 0.5125, 3.89),
      ConstellationStar(0.6907, 0.5299, 2.74),
      ConstellationStar(0.5338, 0.6206, 4.38),
      ConstellationStar(0.4493, 0.7453, 0.98),
      ConstellationStar(0.1676, 0.6308, 4.07),
      ConstellationStar(0.0177, 0.6232, 3.87),
      ConstellationStar(0.5769, 0.2547, 2.85),
      ConstellationStar(0.6134, 0.4224, 3.39),
      ConstellationStar(0.3967, 0.511, 3.38),
      ConstellationStar(0.2473, 0.4635, 4.23),
      ConstellationStar(0.0, 0.4558, 3.73),
    ],
    lines: [
      [0, 1, 2, 3, 4, 5, 6, 7],
      [8, 9, 3],
      [4, 10, 11, 12],
    ],
  ),
  'Lib': Constellation(
    code: 'Lib',
    name: 'Libra',
    stars: [
      ConstellationStar(0.6238, 0.7796, 3.25),
      ConstellationStar(0.7764, 0.3265, 2.75),
      ConstellationStar(0.4741, 0.0, 2.61),
      ConstellationStar(0.2598, 0.2651, 3.91),
      ConstellationStar(0.2425, 0.9195, 3.6),
      ConstellationStar(0.2236, 1.0, 3.66),
    ],
    lines: [
      [0, 1, 2, 3, 4, 5],
      [1, 3],
    ],
  ),
  'Sco': Constellation(
    code: 'Sco',
    name: 'Scorpius',
    stars: [
      ConstellationStar(0.9888, 0.2692, 2.89),
      ConstellationStar(0.9754, 0.1202, 2.29),
      ConstellationStar(0.9296, 0.0, 2.56),
      ConstellationStar(0.788, 0.247, 2.9),
      ConstellationStar(0.7141, 0.2828, 1.06),
      ConstellationStar(0.6559, 0.3589, 2.82),
      ConstellationStar(0.5275, 0.6182, 2.29),
      ConstellationStar(0.5121, 0.7784, 3),
      ConstellationStar(0.4877, 0.9625, 3.62),
      ConstellationStar(0.3298, 1.0, 3.32),
      ConstellationStar(0.1035, 0.9897, 1.86),
      ConstellationStar(0.0112, 0.8672, 2.99),
      ConstellationStar(0.0571, 0.8204, 2.39),
      ConstellationStar(0.1369, 0.7382, 1.62),
    ],
    lines: [
      [0, 1, 2],
      [1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
    ],
  ),
  'Sgr': Constellation(
    code: 'Sgr',
    name: 'Sagittarius',
    stars: [
      ConstellationStar(0.8508, 0.73, 3.1),
      ConstellationStar(0.7999, 0.6466, 1.79),
      ConstellationStar(0.8246, 0.4867, 2.72),
      ConstellationStar(0.7704, 0.3321, 2.82),
      ConstellationStar(0.8808, 0.1791, 3.84),
      ConstellationStar(0.3456, 1.0, 3.96),
      ConstellationStar(0.3359, 0.8652, 3.96),
      ConstellationStar(0.5012, 0.4885, 2.6),
      ConstellationStar(0.633, 0.3872, 3.17),
      ConstellationStar(0.0922, 0.9091, 4.12),
      ConstellationStar(0.0574, 0.6778, 4.37),
      ConstellationStar(0.0877, 0.3629, 4.7),
      ConstellationStar(0.2363, 0.3132, 4.59),
      ConstellationStar(0.3252, 0.3001, 5.02),
      ConstellationStar(0.4008, 0.3263, 4.86),
      ConstellationStar(0.5583, 0.3628, 2.05),
      ConstellationStar(0.9426, 0.5076, 2.98),
      ConstellationStar(0.4676, 0.411, 3.32),
      ConstellationStar(0.4852, 0.203, 3.76),
      ConstellationStar(0.4457, 0.1778, 2.88),
      ConstellationStar(0.3845, 0.1052, 4.88),
      ConstellationStar(0.3531, 0.0664, 3.92),
      ConstellationStar(0.3527, 0.0, 4.52),
      ConstellationStar(0.5392, 0.1807, 3.52),
      ConstellationStar(0.5668, 0.2382, 4.86),
    ],
    lines: [
      [0, 1, 2, 3, 4],
      [5, 6, 7, 8, 3],
      [9, 10, 11, 12, 13, 14, 15, 8, 2, 16, 1, 7, 17, 15, 18, 19, 20, 21, 22],
      [18, 23, 24, 15],
    ],
  ),
  'Cap': Constellation(
    code: 'Cap',
    name: 'Capricornus',
    stars: [
      ConstellationStar(1.0, 0.1608, 4.3),
      ConstellationStar(0.9624, 0.2678, 3.05),
      ConstellationStar(0.8746, 0.4106, 4.77),
      ConstellationStar(0.6818, 0.7616, 4.13),
      ConstellationStar(0.6177, 0.8392, 4.12),
      ConstellationStar(0.2279, 0.627, 3.77),
      ConstellationStar(0.0, 0.3312, 2.85),
      ConstellationStar(0.0777, 0.3564, 3.69),
      ConstellationStar(0.2774, 0.3645, 4.28),
      ConstellationStar(0.4597, 0.3832, 4.08),
    ],
    lines: [
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0],
    ],
  ),
  'Aqr': Constellation(
    code: 'Aqr',
    name: 'Aquarius',
    stars: [
      ConstellationStar(1.0, 0.4907, 3.78),
      ConstellationStar(0.9714, 0.4788, 4.73),
      ConstellationStar(0.7479, 0.3998, 2.9),
      ConstellationStar(0.5513, 0.2782, 2.95),
      ConstellationStar(0.4602, 0.3029, 3.86),
      ConstellationStar(0.4189, 0.2712, 3.65),
      ConstellationStar(0.3815, 0.2735, 4.04),
      ConstellationStar(0.2823, 0.4463, 3.73),
      ConstellationStar(0.1371, 0.4834, 4.41),
      ConstellationStar(0.1856, 0.7611, 3.68),
      ConstellationStar(0.5476, 0.592, 4.29),
      ConstellationStar(0.4879, 0.451, 4.17),
      ConstellationStar(0.4394, 0.2389, 4.8),
      ConstellationStar(0.108, 0.7363, 3.96),
      ConstellationStar(0.0, 0.6834, 4.82),
    ],
    lines: [
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
      [2, 10],
      [3, 11],
      [5, 12],
      [13, 8, 14],
    ],
  ),
  'Psc': Constellation(
    code: 'Psc',
    name: 'Pisces',
    stars: [
      ConstellationStar(0.2711, 0.2971, 4.67),
      ConstellationStar(0.2828, 0.1718, 4.51),
      ConstellationStar(0.239, 0.2361, 4.74),
      ConstellationStar(0.284, 0.3779, 4.66),
      ConstellationStar(0.1715, 0.5074, 3.62),
      ConstellationStar(0.0935, 0.6483, 4.26),
      ConstellationStar(0.0, 0.7939, 3.82),
      ConstellationStar(0.0477, 0.7843, 4.61),
      ConstellationStar(0.1157, 0.7319, 4.45),
      ConstellationStar(0.1788, 0.717, 4.84),
      ConstellationStar(0.2712, 0.6844, 5.21),
      ConstellationStar(0.3317, 0.6772, 4.27),
      ConstellationStar(0.4118, 0.6841, 4.44),
      ConstellationStar(0.6889, 0.7006, 4.03),
      ConstellationStar(0.7975, 0.7287, 4.13),
      ConstellationStar(0.8648, 0.7116, 4.27),
      ConstellationStar(0.9076, 0.7343, 5.05),
      ConstellationStar(0.9254, 0.7821, 3.7),
      ConstellationStar(0.8706, 0.8282, 4.95),
      ConstellationStar(0.7858, 0.8163, 4.49),
      ConstellationStar(0.7614, 0.7774, 4.95),
      ConstellationStar(1.0, 0.7699, 4.48),
    ],
    lines: [
      [0, 1, 2, 0, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
        20, 14],
      [17, 21],
    ],
  ),
};
