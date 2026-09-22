// The sky the weather desktop widget is drawn on: one still picture of the
// conditions — a graded sky, a sun or moon behind however much cloud there
// actually is, and whatever is falling out of it.
//
// **Nothing here moves, and that is the design rather than an omission.** This
// painter used to run a 30fps `Ticker` for as long as the widget was on the
// desktop, for a decoration. The card now paints once per change of conditions
// and costs nothing until the next reading lands. There is no `Ticker`, no
// `ValueNotifier` handed to a painter and no `animate` flag, so a tree
// containing [WeatherSky] may be `pumpAndSettle`ed.
//
// A still frame has to carry the picture on its own, which is what the rest of
// the file is arranged around:
//
// - **The layout is data, computed once.** [SkyField] holds every cloud, drop,
//   star and fog band as plain numbers, built from a seeded [math.Random] when
//   the conditions change — which makes the counts plain unit tests and is the
//   whole per-card cost.
// - **Everything a frame used to derive from elapsed time is a field.** A drop
//   carries its [SkyDrop.y], a star its [SkyStar.brightness], a fog band its
//   [SkyFogBand.shift] — chosen once from the seed, so the picture is stable
//   across a rebuild, a resize, a restart and both monitors.
// - **A drop knows what shape it is.** [SkyDropShape] is on the drop rather than
//   re-derived in the painter, which is what lets sleet be a real mixture.
// - **Depth is what makes a still sky a scene.** [SkyCloud.depth] paints the far
//   clouds smaller, higher, paler and flatter. Without it a static field reads
//   as stickers on a gradient, which motion was hiding.
// - **The clouds are one path, not a pile of circles.** Overlapping ovals in a
//   single non-zero path fill as their union, so a translucent cloud has no
//   seams. Each is painted in three passes — a blurred mass, a graded body, and
//   a lit crown clipped inside its own silhouette.
// - **A thunderstorm gets a bolt, not a flash.** A veil lasting a fifth of a
//   second is meaningless in a picture painted once, so the field carries a
//   single [SkyBolt] with a glow behind it.
//
// The cloud count comes from the API's `cloud_cover`, the fall rate from the WMO
// code's intensity, and the sun or moon from the location's own `is_day`.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:moonswing/weather/weather_condition.dart';
/// The colours one condition is drawn in.
///
/// Deliberately *not* from [ThemeConfig]: this is a picture of the sky, and a sky
/// that took its blue from the user's accent colour would stop being one. The
/// widget's text sits on a scrim above it for that reason.
class SkyPalette {
  const SkyPalette({
    required this.top,
    required this.middle,
    required this.horizon,
    required this.cloudLight,
    required this.cloudDark,
    required this.precipitation,
    this.starOpacity = 0.0,
  });

  /// The three stops of the sky gradient, top to horizon.
  final Color top;
  final Color middle;
  final Color horizon;

  /// A cloud's sunlit top and its shaded underside.
  final Color cloudLight;
  final Color cloudDark;

  /// Rain streaks, snowflakes and hail.
  final Color precipitation;

  /// How brightly the stars come through, 0 by day.
  final double starOpacity;

  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [top, middle, horizon],
        stops: const [0.0, 0.55, 1.0],
      );
}

/// Which palette [condition] is drawn in.
///
/// Grouped by what the sky *looks* like rather than by [WeatherKind]: drizzle,
/// rain and rain showers are one grey, and both thunderstorm codes are the same
/// near-black.
SkyPalette skyPalette(WeatherCondition condition, {required bool night}) {
  switch (condition.kind) {
    case WeatherKind.thunderstorm:
    case WeatherKind.thunderstormHail:
      return night ? _nightStorm : _dayStorm;
    case WeatherKind.fog:
      return night ? _nightFog : _dayFog;
    case WeatherKind.snow:
    case WeatherKind.snowGrains:
    case WeatherKind.snowShowers:
      return night ? _nightSnow : _daySnow;
    case WeatherKind.drizzle:
    case WeatherKind.freezingDrizzle:
    case WeatherKind.rain:
    case WeatherKind.freezingRain:
    case WeatherKind.rainShowers:
      return night ? _nightRain : _dayRain;
    case WeatherKind.overcast:
      return night ? _nightOvercast : _dayOvercast;
    case WeatherKind.partlyCloudy:
      return night ? _nightPartly : _dayPartly;
    case WeatherKind.clear:
    case WeatherKind.mainlyClear:
    case WeatherKind.unknown:
      return night ? _nightClear : _dayClear;
  }
}

const _dayClear = SkyPalette(
  top: Color(0xFF2F7FD0),
  middle: Color(0xFF6BAFE4),
  horizon: Color(0xFFBEE0F5),
  cloudLight: Color(0xFFFFFFFF),
  cloudDark: Color(0xFFD3E2EE),
  precipitation: Color(0xFFDCEBF7),
);
const _dayPartly = SkyPalette(
  top: Color(0xFF3D7FBF),
  middle: Color(0xFF7FADD5),
  horizon: Color(0xFFCADCE8),
  cloudLight: Color(0xFFFFFFFF),
  cloudDark: Color(0xFFC8D6E2),
  precipitation: Color(0xFFDCEBF7),
);
const _dayOvercast = SkyPalette(
  top: Color(0xFF6E7F8E),
  middle: Color(0xFF95A3AF),
  horizon: Color(0xFFBEC7CE),
  cloudLight: Color(0xFFE4E9ED),
  cloudDark: Color(0xFFA9B4BE),
  precipitation: Color(0xFFD5DDE4),
);
const _dayRain = SkyPalette(
  top: Color(0xFF4A5D6E),
  middle: Color(0xFF6E8090),
  horizon: Color(0xFF93A2AD),
  cloudLight: Color(0xFFC6D0D8),
  cloudDark: Color(0xFF7C8996),
  precipitation: Color(0xFFCFE2F0),
);
const _dayStorm = SkyPalette(
  top: Color(0xFF262F39),
  middle: Color(0xFF3C4854),
  horizon: Color(0xFF56626E),
  cloudLight: Color(0xFF8792A0),
  cloudDark: Color(0xFF454F5C),
  precipitation: Color(0xFFBFD3E4),
);
const _daySnow = SkyPalette(
  top: Color(0xFF7B93A8),
  middle: Color(0xFFA7BACA),
  horizon: Color(0xFFD8E3EB),
  cloudLight: Color(0xFFF2F6F9),
  cloudDark: Color(0xFFBCC9D4),
  precipitation: Color(0xFFFFFFFF),
);
// Darker than the greyness of real fog, on purpose: the haze bands are painted
// in near-white and there has to be something for them to be lighter *than*. A
// palette matched to the fog itself leaves the condition indistinguishable from
// overcast.
const _dayFog = SkyPalette(
  top: Color(0xFF72808A),
  middle: Color(0xFF95A1A9),
  horizon: Color(0xFFB6BEC3),
  cloudLight: Color(0xFFF4F7F9),
  cloudDark: Color(0xFFAFB9C0),
  precipitation: Color(0xFFE0E5E7),
);

const _nightClear = SkyPalette(
  top: Color(0xFF07132A),
  middle: Color(0xFF122645),
  horizon: Color(0xFF27435F),
  cloudLight: Color(0xFF48586C),
  cloudDark: Color(0xFF2A3648),
  precipitation: Color(0xFFAFC4D8),
  starOpacity: 1.0,
);
const _nightPartly = SkyPalette(
  top: Color(0xFF0C1930),
  middle: Color(0xFF182E4C),
  horizon: Color(0xFF2E4A66),
  cloudLight: Color(0xFF52627A),
  cloudDark: Color(0xFF2F3D51),
  precipitation: Color(0xFFAFC4D8),
  starOpacity: 0.7,
);
const _nightOvercast = SkyPalette(
  top: Color(0xFF151C27),
  middle: Color(0xFF222B38),
  horizon: Color(0xFF313B48),
  cloudLight: Color(0xFF4B5766),
  cloudDark: Color(0xFF2A323D),
  precipitation: Color(0xFF9FB2C4),
);
const _nightRain = SkyPalette(
  top: Color(0xFF101822),
  middle: Color(0xFF1B2531),
  horizon: Color(0xFF2A3540),
  cloudLight: Color(0xFF46525F),
  cloudDark: Color(0xFF232C37),
  precipitation: Color(0xFFA9C2D8),
);
const _nightStorm = SkyPalette(
  top: Color(0xFF070A0F),
  middle: Color(0xFF11161E),
  horizon: Color(0xFF1C232C),
  cloudLight: Color(0xFF3A424E),
  cloudDark: Color(0xFF171D25),
  precipitation: Color(0xFFA9C2D8),
);
const _nightSnow = SkyPalette(
  top: Color(0xFF151F30),
  middle: Color(0xFF243146),
  horizon: Color(0xFF36455C),
  cloudLight: Color(0xFF5A6B82),
  cloudDark: Color(0xFF2C384B),
  precipitation: Color(0xFFF0F5FA),
  starOpacity: 0.35,
);
const _nightFog = SkyPalette(
  top: Color(0xFF141A21),
  middle: Color(0xFF1F262E),
  horizon: Color(0xFF2C343C),
  cloudLight: Color(0xFF5C6772),
  cloudDark: Color(0xFF262E36),
  precipitation: Color(0xFFB9C2CA),
);

// --- the layout ------------------------------------------------------------

/// One cloud, in unit coordinates.
///
/// [x] and [y] are fractions of the painted box, [puffs] and [radii] relative to
/// [scale] — so one field draws correctly at every size the widget is resized to.
class SkyCloud {
  const SkyCloud({
    required this.x,
    required this.y,
    required this.scale,
    required this.depth,
    required this.opacity,
    required this.puffs,
    required this.radii,
  });

  final double x;
  final double y;
  final double scale;

  /// How near the front of the scene this cloud is, 0..1.
  ///
  /// The still picture's substitute for parallax: the far ones smaller, higher,
  /// paler and flatter, the near ones larger and more contrasted. A field with no
  /// depth reads as stickers on a gradient.
  final double depth;

  final double opacity;

  /// Puff centres, relative to the cloud's own origin.
  final List<Offset> puffs;

  /// Each puff's radius, in the same units.
  final List<double> radii;
}

/// What one falling thing is drawn as.
///
/// On the drop rather than re-derived in the painter, which is what lets sleet be
/// a genuine mixture: the decision is made once, where the field is built.
enum SkyDropShape {
  /// Rain and drizzle: a leaning line.
  streak,

  /// Snow: a soft round flake.
  flake,

  /// Hail: a small hard pellet.
  pellet,
}

/// One falling thing — a raindrop, a flake, a hailstone — caught where it is.
class SkyDrop {
  const SkyDrop({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
    required this.shape,
  });

  /// Horizontal position, 0..1 of the width.
  final double x;

  /// Vertical position, 0..1 of the height. Stratified when the field is built
  /// rather than drawn at random: in a still frame a clump of drops cannot be
  /// excused by the next frame moving them apart.
  final double y;

  /// Length (a streak) or radius (a flake, a pellet), in fractions of the
  /// height.
  final double size;

  /// Its own alpha. Varying this is what gives a static shower its depth —
  /// every drop at one opacity reads as a screen door.
  final double opacity;

  final SkyDropShape shape;
}

class SkyStar {
  const SkyStar({
    required this.x,
    required this.y,
    required this.radius,
    required this.brightness,
  });

  final double x;
  final double y;
  final double radius;

  /// 0..1, fixed. The animated sky twinkled these; a still one varies them across
  /// the field instead, which is the same picture at one instant and costs no
  /// frames.
  final double brightness;
}

/// A band of fog.
class SkyFogBand {
  const SkyFogBand({
    required this.y,
    required this.height,
    required this.shift,
    required this.opacity,
  });

  final double y;
  final double height;

  /// How far along the width this band sits, ± a fraction of the box. Bands at
  /// different offsets read as layers of air; bands lined up read as a veil.
  final double shift;

  final double opacity;
}

/// The single lightning stroke a thunderstorm is drawn with, in unit coordinates.
///
/// The animated sky flashed the whole card for a fifth of a second every six. In
/// a picture painted once that is either always on or never seen, so the still
/// answer is the one every illustration of a storm uses: one bolt with a glow.
class SkyBolt {
  const SkyBolt(this.points);

  /// Top to bottom, each a fraction of the box.
  final List<Offset> points;
}

/// How many clouds a cover fraction draws.
///
/// Zero at a genuinely clear sky — the one case that has to be exact, because a
/// stray cloud over a "Clear sky" label is the picture contradicting the reading
/// beside it. [kMaxClouds] at a closed lid, rounding *up* in between so the first
/// wisp appears as soon as there is any cover to speak of.
int cloudsForCover(double cover) {
  final clamped = cover.clamp(0.0, 1.0);
  if (clamped < 0.05) return 0;
  return (clamped * kMaxClouds).ceil().clamp(1, kMaxClouds);
}

/// The cloud ceiling. Past this the sky is a grey wash rather than a set of
/// distinguishable clouds, and each one is three path fills.
const int kMaxClouds = 7;

/// The particle ceiling. A desktop widget is a few hundred pixels across; a
/// hundred drops in that is already a downpour.
const int kMaxDrops = 90;

/// Everything the painter draws, resolved once per change of conditions.
class SkyField {
  const SkyField({
    required this.condition,
    required this.cloudCover,
    required this.night,
    required this.clouds,
    required this.drops,
    required this.stars,
    required this.fogBands,
    required this.bolt,
  });

  final WeatherCondition condition;
  final double cloudCover;
  final bool night;

  /// Farthest first, so the painter walks the list in the order it draws.
  final List<SkyCloud> clouds;

  final List<SkyDrop> drops;
  final List<SkyStar> stars;
  final List<SkyFogBand> fogBands;

  /// The storm's one stroke, or null when there is no lightning.
  final SkyBolt? bolt;

  /// How visible the sun or moon is through the cloud, 0..1.
  ///
  /// Fully hidden under a closed lid rather than merely dimmed — a sun burning
  /// through overcast is the picture of a *break* in the cloud. Everywhere short
  /// of that it stays mostly visible, which is why the ramp is steep rather than
  /// linear: the clouds already occlude the disc, so fading it in proportion to
  /// the cover dims it twice over — and a half-alpha yellow disc over a blue sky
  /// composites to green.
  double get celestialOpacity {
    // Ramped off a floor rather than straight off the cover. The clouds are drawn
    // in a band across the top of the card, so at 90% cover the linear figure
    // left a pale circle hanging in clear air below the cloud line — a smudge on
    // the wallpaper rather than the sun. Subtracting the floor and rescaling
    // keeps the whole range in play.
    final open =
        (((1.0 - cloudCover) * 1.7 - 0.25) / 0.75).clamp(0.0, 1.0).toDouble();
    // Fog draws no clouds, so nothing else would be holding the disc back — and
    // a bright sun over a fog reading is the picture contradicting the word under
    // it. A pale one showing through is what the cap leaves.
    if (condition.kind == WeatherKind.fog) return math.min(open, 0.35);
    return open;
  }

  /// Builds the layout for one set of conditions.
  ///
  /// [seed] is fixed by default, so the same weather draws the same sky on every
  /// monitor and across a restart. A cloud field that reshuffled itself on every
  /// rebuild would be the most distracting thing on the desktop — and, with
  /// nothing moving, the only thing that ever changed.
  factory SkyField.build({
    required WeatherCondition condition,
    required double cloudCover,
    required bool night,
    int seed = 7,
  }) {
    final random = math.Random(seed);
    final cover = cloudCover.clamp(0.0, 1.0).toDouble();

    // Fog is the one condition drawn with no clouds at all, whatever the cover
    // says. A cover figure taken during fog describes a lid nobody under it can
    // see, and drawing it puts edged clouds over the haze bands that are the
    // actual picture — indistinguishable from overcast.
    final cloudCount =
        condition.kind == WeatherKind.fog ? 0 : cloudsForCover(cover);
    final clouds = <SkyCloud>[
      for (var i = 0; i < cloudCount; i++)
        _buildCloud(random, i, cloudCount, cover, condition),
    ]..sort((a, b) => a.depth.compareTo(b.depth));

    final drops = <SkyDrop>[];
    if (condition.isPrecipitating) {
      final count =
          (kMaxDrops * (0.25 + 0.75 * condition.intensity)).round().clamp(
                8,
                kMaxDrops,
              );
      for (var i = 0; i < count; i++) {
        drops.add(_buildDrop(random, condition, i, count));
      }
    }

    // Stars only where they would be visible: under cloud they are not, and
    // painting them behind a lid is work nobody sees.
    final stars = <SkyStar>[];
    final palette = skyPalette(condition, night: night);
    if (night && palette.starOpacity > 0 && cover < 0.85) {
      final count = (28 * (1 - cover)).round().clamp(0, 28);
      for (var i = 0; i < count; i++) {
        stars.add(SkyStar(
          x: random.nextDouble(),
          // Kept out of the bottom third: that is where the widget's text sits,
          // and a star behind a temperature reads as a rendering artefact.
          y: random.nextDouble() * 0.55,
          radius: 0.6 + random.nextDouble() * 1.1,
          // A spread rather than a constant: a field of identically bright
          // points is a texture, and a night sky is not one.
          brightness: 0.35 + random.nextDouble() * 0.65,
        ));
      }
    }

    final fogBands = <SkyFogBand>[];
    if (condition.kind == WeatherKind.fog) {
      // Five bands from near the top to near the bottom edge: fog is the one
      // condition where the *air* is the weather, so it has to reach the ground
      // rather than sit in a layer.
      for (var i = 0; i < 5; i++) {
        fogBands.add(SkyFogBand(
          // Separated, with sky between them. Bands wide enough to overlap blur
          // into one flat veil, which is a gradient rather than a picture of fog:
          // what says "fog" is streaks at different heights lying across each
          // other.
          y: 0.16 + i * 0.17 + random.nextDouble() * 0.04,
          height: 0.06 + random.nextDouble() * 0.05,
          // Alternating in sign so the bands lie past each other rather than
          // stacking as one sheet.
          shift: (i.isEven ? 1 : -1) * (0.04 + random.nextDouble() * 0.12),
          opacity: 0.42 + random.nextDouble() * 0.26,
        ));
      }
    }

    return SkyField(
      condition: condition,
      cloudCover: cover,
      night: night,
      clouds: clouds,
      drops: drops,
      stars: stars,
      fogBands: fogBands,
      bolt: condition.lightning ? _buildBolt(random) : null,
    );
  }
}

SkyCloud _buildCloud(
  math.Random random,
  int index,
  int count,
  double cover,
  WeatherCondition condition,
) {
  // Spread across the width by index rather than at random: a handful of random
  // x values clumps often enough to look like a mistake, and with nothing
  // drifting a clump stays a clump.
  final slot = (index + 0.5) / count;
  final jitter = (random.nextDouble() - 0.5) * (0.7 / count);

  final puffCount = 3 + random.nextInt(3);
  final puffs = <Offset>[];
  final radii = <double>[];
  var x = 0.0;
  for (var i = 0; i < puffCount; i++) {
    // Biggest in the middle, varied on top of that. Equal radii draw a row of
    // identical bumps — a caterpillar, which is what this looked like at the
    // sizes a still card is read at.
    final swell = 0.55 + 0.45 * math.sin((i + 1) / (puffCount + 1) * math.pi);
    final radius = (0.34 + random.nextDouble() * 0.30) * swell * 1.35;
    // Each puff sits a little into the last, and the middle ones ride higher —
    // which is the difference between a cloud and a caterpillar.
    final lift = math.sin((i + 1) / (puffCount + 1) * math.pi);
    puffs.add(Offset(x, -lift * 0.28 + (random.nextDouble() - 0.5) * 0.08));
    radii.add(radius);
    x += radius * (1.05 + random.nextDouble() * 0.3);
  }
  // Re-centre, so `x` positions the cloud's middle rather than its left puff.
  final centre = x / 2;
  for (var i = 0; i < puffs.length; i++) {
    puffs[i] = puffs[i].translate(-centre, 0);
  }

  // Heavier weather flies lower and larger; a fair-weather cloud sits high.
  final low =
      condition.isPrecipitating || condition.kind == WeatherKind.overcast;

    // Alternating, so the field always has both a back and a front rather than
    // whatever the seed drew: with only a handful of clouds, three random depths
    // land in the same plane often enough to be noticed.
  final depth =
      ((index % 3) / 2 + (random.nextDouble() - 0.5) * 0.2).clamp(0.0, 1.0);

  return SkyCloud(
    x: slot + jitter,
    // Kept to the top third of the card, near ones lower within it. The band is
    // narrow on purpose: everything below it is the readout, and there is no next
    // frame to move a cloud drifting behind a 38px temperature.
    y: (low ? 0.09 : 0.11) + (0.04 + random.nextDouble() * 0.09) * (0.6 + depth),
    // Scaled by the cover and the depth: at 20% the sky wants a couple of small
    // wisps, and drawing them at overcast size fills the card and calls it
    // "mainly clear". These multipliers put a cloud at roughly a quarter to a
    // third of the card's width; the animated version was set at twice that,
    // which motion made read as scale and a still frame makes read as grey blobs.
    scale: ((low ? 0.070 : 0.055) + random.nextDouble() * 0.028) *
        (0.7 + 0.45 * cover) *
        (0.75 + 0.5 * depth),
    depth: depth,
    // Nearly opaque, which is what stops the sun behind one tinting it: a
    // half-transparent cloud over a yellow disc composites to olive, which reads
    // as a rendering fault rather than as weather.
    opacity: 0.9 + random.nextDouble() * 0.1,
    puffs: puffs,
    radii: radii,
  );
}

SkyDrop _buildDrop(
  math.Random random,
  WeatherCondition condition,
  int index,
  int count,
) {
  final snow = condition.precipitation == Precipitation.snow;
  final hail = condition.precipitation == Precipitation.hail;
  final drizzle = condition.precipitation == Precipitation.drizzle;
  // Sleet is the one mixed case: half of it falls as flakes. Giving the whole
  // field one shape makes freezing rain either a blizzard or a sheet.
  final sleetFlake =
      condition.precipitation == Precipitation.sleet && random.nextBool();

  final shape = snow || sleetFlake
      ? SkyDropShape.flake
      : hail
          ? SkyDropShape.pellet
          : SkyDropShape.streak;

  // Stratified down the box, with jitter inside each band. Purely random y values
  // leave visible gaps and clumps in a picture the eye has all the time in the
  // world to study.
  final y = ((index + random.nextDouble()) / count) * 1.04 - 0.02;

  return SkyDrop(
    x: random.nextDouble(),
    y: y,
    size: switch (shape) {
      // Small, and only a little varied. At the size the animated field used, a
      // still snowfall is a handful of pale bubbles rather than weather — motion
      // was doing the work of saying what they were.
      SkyDropShape.flake => 0.005 + random.nextDouble() * 0.007,
      SkyDropShape.pellet => 0.010 + random.nextDouble() * 0.007,
      SkyDropShape.streak =>
        (drizzle ? 0.035 : 0.07) + random.nextDouble() * 0.05,
    },
    // Near drops are longer *and* brighter, which is what turns a flat field of
    // identical marks into weather with depth in it.
    opacity: 0.35 + random.nextDouble() * 0.65,
    shape: shape,
  );
}

/// One jagged stroke down the left-of-centre of the card.
///
/// Left of centre because the sun and moon are at [kCelestialCentre] and a bolt
/// through the disc reads as a mistake; stopping at 0.52 of the height because
/// below that is the readout.
///
/// The shape is a real zig-zag — each segment crossing back over the last —
/// rather than the wander a random walk produces: a stroke that only drifts is a
/// scratch on the card, and what says *lightning* is the reversal.
SkyBolt _buildBolt(math.Random random) {
  double wobble(double base) => base + (random.nextDouble() - 0.5) * 0.02;
  final x = 0.30 + random.nextDouble() * 0.10;
  return SkyBolt([
    Offset(wobble(x), 0.06),
    Offset(wobble(x - 0.055), 0.20),
    Offset(wobble(x + 0.030), 0.24),
    Offset(wobble(x - 0.035), 0.38),
    Offset(wobble(x + 0.045), 0.41),
    Offset(wobble(x - 0.005), 0.52),
  ]);
}

// --- the widget ------------------------------------------------------------

/// The sky for one set of conditions, painted once.
///
/// Fills its box; the caller clips it. Text drawn over this belongs on a scrim —
/// see [SkyScrim] — because the palettes run from a near-black storm to an
/// almost-white snowfall and nothing legible sits on both.
///
/// There is no ticker behind this and no `animate` flag, so a widget test may
/// `pumpAndSettle` a tree containing one. See the file header.
class WeatherSky extends StatefulWidget {
  const WeatherSky({
    super.key,
    required this.condition,
    required this.cloudCover,
    required this.night,
  });

  final WeatherCondition condition;

  /// 0..1, from the API's `cloud_cover` where there is one.
  final double cloudCover;

  final bool night;

  @override
  State<WeatherSky> createState() => _WeatherSkyState();
}

/// Stateful only to *cache* the field: nothing here ticks.
///
/// Building the layout is a couple of hundred random draws, and this widget's
/// `build` runs on every resize of the card it backs — a `StatelessWidget`
/// building its field inline would redo all of it for every frame of a drag.
class _WeatherSkyState extends State<WeatherSky> {
  late SkyField _field = _buildField();

  @override
  void didUpdateWidget(WeatherSky oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.condition.kind != widget.condition.kind ||
        oldWidget.condition.intensity != widget.condition.intensity ||
        oldWidget.cloudCover != widget.cloudCover ||
        oldWidget.night != widget.night) {
      _field = _buildField();
    }
  }

  SkyField _buildField() => SkyField.build(
        condition: widget.condition,
        cloudCover: widget.cloudCover,
        night: widget.night,
      );

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: SkyPainter(
          field: _field,
          palette: skyPalette(widget.condition, night: widget.night),
        ),
        // A painter with no child paints nothing unless it is given a size, and
        // this one is the background of a card whose size the grid decides.
        size: Size.infinite,
      ),
    );
  }
}

/// Where the sun or the moon sits, as a fraction of the box.
///
/// Named because the card's layout depends on it: the readout is bottom-left
/// precisely so the disc is never behind it, and the bolt is drawn left of centre
/// for the same reason.
const Offset kCelestialCentre = Offset(0.78, 0.27);

/// Paints a [SkyField].
///
/// Public so a golden or paint-counting test can drive it with no widget around
/// it. Immutable and `const`-constructible: there is no clock in it, so two
/// painters over the same field and palette paint the same picture.
class SkyPainter extends CustomPainter {
  const SkyPainter({required this.field, required this.palette});

  final SkyField field;
  final SkyPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    canvas.drawRect(rect, Paint()..shader = palette.gradient.createShader(rect));
    _paintHorizonGlow(canvas, size);
    _paintStars(canvas, size);
    _paintCelestial(canvas, size);
    _paintClouds(canvas, size);
    _paintFog(canvas, size);
    _paintPrecipitation(canvas, size);
    _paintBolt(canvas, size);
    _paintVignette(canvas, size);
  }

  /// The light that collects along the horizon of a real sky.
  ///
  /// The gradient alone runs top-to-bottom in three flat stops, which is the
  /// biggest reason the old card read as paint-by-numbers: a sky is brightest
  /// where it meets the ground, in a band rather than a line.
  void _paintHorizonGlow(Canvas canvas, Size size) {
    final centre = Offset(size.width * 0.5, size.height * 1.06);
    final radius = size.width * 0.95;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(centre, radius, [
          palette.horizon.withValues(alpha: field.night ? 0.30 : 0.45),
          palette.horizon.withValues(alpha: 0.0),
        ]),
    );
  }

  void _paintStars(Canvas canvas, Size size) {
    if (field.stars.isEmpty) return;
    final paint = Paint();
    for (final star in field.stars) {
      final alpha = star.brightness * palette.starOpacity;
      final centre = Offset(star.x * size.width, star.y * size.height);
      // The brightest few get a halo. Every star drawn as a hard dot of one size
      // is the picture of a dust-speck on a lens; a handful blooming is what a
      // night sky actually looks like.
      if (star.brightness > 0.8) {
        canvas.drawCircle(
          centre,
          star.radius * 3.4,
          paint
            ..color = const Color(0xFFFFFFFF).withValues(alpha: alpha * 0.22)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, star.radius * 1.6),
        );
      }
      canvas.drawCircle(
        centre,
        star.radius,
        paint
          ..maskFilter = null
          ..color = const Color(0xFFFFFFFF).withValues(alpha: alpha),
      );
    }
  }

  /// The sun or the moon, with its glow, behind whatever cloud there is.
  ///
  /// Dimmed by **washing out towards haze white**, not by dropping its alpha
  /// towards the sky: a half-transparent yellow disc over a blue sky is *green*,
  /// and so is a yellow lerped halfway to blue. Washed out and faded on a
  /// square-root ramp it goes pale the way a sun behind thin cloud does, and
  /// disappears exactly when [SkyField.celestialOpacity] reaches zero.
  void _paintCelestial(Canvas canvas, Size size) {
    final opacity = field.celestialOpacity;
    if (opacity <= 0.01) return;

    final centre = Offset(
      size.width * kCelestialCentre.dx,
      size.height * kCelestialCentre.dy,
    );
    final radius = math.min(size.width, size.height) * 0.11;

    // Haze, not sky: what thin cloud does to a sun is take the colour out of
    // it, not tint it with what is behind.
    const haze = Color(0xFFF4F6F8);
    final alpha = math.sqrt(opacity);
    Color dim(Color colour) =>
        Color.lerp(colour, haze, 1 - opacity)!.withValues(alpha: alpha);

    final glowColour =
        dim(field.night ? const Color(0xFFB9CFEA) : const Color(0xFFFFE9A8));

    // Two glows rather than one, a tight bright core inside a wide faint halo. A
    // single linear falloff has a visible edge where it reaches zero, which on a
    // flat gradient sky is a ring.
    for (final (reach, strength) in const [(4.0, 0.16), (2.1, 0.30)]) {
      canvas.drawCircle(
        centre,
        radius * reach,
        Paint()
          ..shader = ui.Gradient.radial(centre, radius * reach, [
            glowColour.withValues(alpha: strength * alpha),
            glowColour.withValues(alpha: 0.0),
          ]),
      );
    }

    if (field.night) {
      // The crescent is cut rather than drawn: a filled disc with a
      // background-coloured disc offset into it would need the sky's exact colour
      // at that point, which is a gradient. `difference` works over anything.
      final disc = Path()
        ..addOval(Rect.fromCircle(center: centre, radius: radius));
      final bite = Path()
        ..addOval(Rect.fromCircle(
          center: centre.translate(-radius * 0.62, -radius * 0.34),
          radius: radius * 0.92,
        ));
      canvas.drawPath(
        Path.combine(PathOperation.difference, disc, bite),
        Paint()..color = dim(const Color(0xFFE9F0F8)),
      );
    } else {
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(
            centre.translate(-radius * 0.2, -radius * 0.2),
            radius * 1.4,
            [dim(const Color(0xFFFFF6D8)), dim(const Color(0xFFFFC94A))],
          ),
      );
    }
  }

  /// Three passes per cloud: the mass it casts under itself, the graded body, and
  /// a lit crown clipped back inside its own silhouette.
  ///
  /// A flat fill is the other half of what read as amateurish — a cloud has a
  /// shaded underside and a lit top, and in a still picture that modelling is all
  /// the volume there is.
  void _paintClouds(Canvas canvas, Size size) {
    // A cloud's size is a fraction of the *width*, capped against the height — or
    // a 2x1 card draws clouds half its width and twice its height, which is what
    // the compact layout came out looking like. 1.5 is a little above the widest
    // card's ratio, so on anything squarer the width still decides.
    final reference = math.min(size.width, size.height * 1.5);

    for (final cloud in field.clouds) {
      final origin =
          Offset(cloud.x * size.width, cloud.y * size.height);
      final scale = cloud.scale * reference;
      if (scale <= 0) continue;

      final path = Path()..fillType = PathFillType.nonZero;
      for (var i = 0; i < cloud.puffs.length; i++) {
        path.addOval(Rect.fromCircle(
          center: origin + cloud.puffs[i] * scale,
          radius: cloud.radii[i] * scale,
        ));
      }
      // The body under the puffs — a cloud's underside is one mass, not a row of
      // scallops. An *ellipse* rather than the rounded rect this started as: a
      // rect's ends stay square however large the corner radius, and at a wide
      // span they read as a shelf sticking out from under the cloud.
      final bounds = path.getBounds();
      path.addOval(Rect.fromLTRB(
        bounds.left + scale * 0.10,
        origin.dy - scale * 0.34,
        bounds.right - scale * 0.10,
        origin.dy + scale * 0.36,
      ));

      // Distance haze: a far cloud is not the same cloud drawn smaller, it is
      // one the air in between has washed towards the colour of the sky.
      final haze = (1 - cloud.depth) * 0.5;
      final light = Color.lerp(palette.cloudLight, palette.middle, haze)!;
      final dark = Color.lerp(palette.cloudDark, palette.middle, haze)!;
      final alpha = (cloud.opacity * (0.72 + 0.28 * cloud.depth)).clamp(0.0, 1.0);

      canvas.drawPath(
        path.shift(Offset(0, scale * 0.14)),
        Paint()
          ..color = Color.lerp(dark, const Color(0xFF000000), 0.30)!
              .withValues(alpha: 0.30 * alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * 0.26),
      );

      final shaded = path.getBounds();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            shaded.topCenter,
            shaded.bottomCenter,
            [
              light.withValues(alpha: alpha),
              Color.lerp(light, dark, 0.45)!.withValues(alpha: alpha),
              dark.withValues(alpha: alpha),
            ],
            const [0.0, 0.55, 1.0],
          ),
      );

      canvas.save();
      canvas.clipPath(path);
      canvas.drawPath(
        path.shift(Offset(0, -scale * 0.16)),
        Paint()
          // Lifted towards white rather than set in it, and blurred by more than
          // it is shifted. Any brighter or crisper leaves a hard white wedge where
          // the shifted silhouette crosses one of its own notches, which reads as
          // a clipping bug rather than a lit top.
          ..color = Color.lerp(light, const Color(0xFFFFFFFF), 0.45)!
              .withValues(alpha: 0.5 * alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * 0.28),
      );
      canvas.restore();
    }
  }

  void _paintFog(Canvas canvas, Size size) {
    if (field.fogBands.isEmpty) return;
    // Blurred, not clipped. A band drawn as a rectangle with a horizontal
    // gradient has hard edges along its top and bottom however soft its ends are,
    // and four of those stacked up the card read as venetian blinds.
    for (final band in field.fogBands) {
      final height = band.height * size.height;
      final blur = height * 0.7;
      // Drawn wider than the box by more than it is offset, so a band never
      // uncovers an edge.
      final rect = Rect.fromLTWH(
        size.width * (-0.35 + band.shift),
        band.y * size.height,
        size.width * 1.7,
        height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(height)),
        Paint()
          ..color = palette.cloudLight.withValues(alpha: band.opacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      );
    }
  }

  void _paintPrecipitation(Canvas canvas, Size size) {
    if (field.drops.isEmpty) return;

    // The veil first: a barely-there wash in the precipitation's own colour,
    // heavier towards the bottom. A still frame of rain is mostly this — the
    // streaks say *what* is falling, the wash says the air is full of it.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, size.height),
          [
            palette.precipitation.withValues(alpha: 0.0),
            palette.precipitation
                .withValues(alpha: 0.10 * field.condition.intensity),
          ],
        ),
    );

    final base = palette.precipitation;
    final paint = Paint()..strokeCap = StrokeCap.round;

    for (final drop in field.drops) {
      final x = drop.x * size.width;
      final y = drop.y * size.height;
      switch (drop.shape) {
        case SkyDropShape.streak:
          final length = drop.size * size.height;
          canvas.drawLine(
            Offset(x, y),
            // The same lean for every streak: rain falling at random angles
            // reads as static rather than as weather.
            Offset(x - length * 0.18, y + length),
            paint
              ..maskFilter = null
              ..color = base.withValues(alpha: 0.55 * drop.opacity)
              ..strokeWidth =
                  math.max(0.8, size.width * 0.0035 * (0.6 + drop.opacity)),
          );
        case SkyDropShape.flake:
          final radius = drop.size * size.height;
          canvas.drawCircle(
            Offset(x, y),
            radius,
            paint
              // The near flakes are the ones out of focus, which is the only
              // depth cue a snowfall has when nothing is moving.
              ..maskFilter = drop.opacity > 0.88
                  ? MaskFilter.blur(BlurStyle.normal, radius * 0.4)
                  : null
              ..color = base.withValues(alpha: 0.95 * drop.opacity),
          );
        case SkyDropShape.pellet:
          canvas.drawCircle(
            Offset(x, y),
            drop.size * size.height,
            paint
              ..maskFilter = null
              ..color = base.withValues(alpha: 0.85 * drop.opacity),
          );
      }
    }
  }

  void _paintBolt(Canvas canvas, Size size) {
    final bolt = field.bolt;
    if (bolt == null || bolt.points.length < 2) return;

    final points = [
      for (final point in bolt.points)
        Offset(point.dx * size.width, point.dy * size.height),
    ];
    final width = math.max(1.2, size.width * 0.005);

    // Drawn segment by segment with a falling stroke width rather than as one
    // path: a stroke is uniform, and a bolt that does not taper is a lightning
    // symbol rather than lightning. The glow is a second pass over the whole run
    // — a bare white jag on a dark sky is a scratch on the card.
    for (final (reach, colour, alpha) in [
      (5.0, const Color(0xFF9FC4FF), 0.22),
      (2.4, const Color(0xFFDCEAFF), 0.35),
      (1.0, const Color(0xFFFFFDF2), 0.95),
    ]) {
      for (var i = 0; i < points.length - 1; i++) {
        final taper = 1 - (i / (points.length - 1)) * 0.62;
        canvas.drawLine(
          points[i],
          points[i + 1],
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = width * reach * taper
            ..color = colour.withValues(alpha: alpha)
            ..maskFilter = reach > 1.0
                ? MaskFilter.blur(BlurStyle.normal, width * reach * 0.6)
                : null,
        );
      }
    }
  }

  /// The corner falloff every photograph has and no flat gradient does.
  ///
  /// Slight, and centred a little above the middle so it darkens the bottom
  /// corners — where the readout sits — more than the top.
  void _paintVignette(Canvas canvas, Size size) {
    final centre = Offset(size.width * 0.5, size.height * 0.38);
    final radius = math.max(size.width, size.height) * 0.78;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(centre, radius, [
          const Color(0x00000000),
          const Color(0xFF000000).withValues(alpha: 0.22),
        ], const [0.55, 1.0]),
    );
  }

  @override
  bool shouldRepaint(SkyPainter oldDelegate) =>
      oldDelegate.field != field || oldDelegate.palette != palette;
}

/// The wash that makes text legible over any sky.
///
/// The palettes run from a near-black storm to an almost-white snowfall, so no
/// single text colour sits on all of them — the widget draws its readout in
/// white and this is what guarantees there is something dark behind it.
///
/// Two gradients rather than one. The bottom one is where the reading, the
/// detail row and the forecast strip are, so it carries nearly all of the
/// weight; the top one is a much lighter veil under the place name, which used
/// to sit unprotected on the brightest part of a snow or fog palette. Between
/// them the sky is left alone, because the middle of the card is where the sun,
/// the moon and the clouds are and dimming those is dimming the whole point.
class SkyScrim extends StatelessWidget {
  const SkyScrim({super.key, this.strength = 0.62, this.topStrength = 0.22});

  final double strength;
  final double topStrength;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            const Color(0xFF000000).withValues(alpha: strength),
            const Color(0xFF000000).withValues(alpha: strength * 0.62),
            const Color(0xFF000000).withValues(alpha: strength * 0.16),
            const Color(0xFF000000).withValues(alpha: 0),
            const Color(0xFF000000).withValues(alpha: topStrength),
          ],
          // Eased rather than linear: a straight ramp from black to nothing has
          // a visible band across the middle of the card at these alphas.
          stops: const [0.0, 0.22, 0.45, 0.72, 1.0],
        ),
      ),
    );
  }
}

/// The soft drop shadow every label over the sky carries, so a white readout
/// survives the one palette that is nearly white itself.
///
/// Two shadows: a tight, nearly-opaque one that gives the glyph an edge, and a
/// wide soft one that lifts it off whatever is behind. One shadow has to choose
/// between the two, and the single blurred one this started as left small text
/// on a snow palette looking smudged rather than set.
const List<Shadow> kSkyTextShadows = [
  Shadow(color: Color(0x73000000), blurRadius: 2, offset: Offset(0, 1)),
  Shadow(color: Color(0x59000000), blurRadius: 10),
];

/// White, at the weights the readout uses. The sky is a picture, and text on it
/// takes its colour from the picture rather than from the theme — the call the
/// lock screen makes over a wallpaper.
const Color kSkyForeground = Color(0xFFFFFFFF);
const Color kSkyMutedForeground = Color(0xCCFFFFFF);

/// The hairline the card rules its sections off with, and the dimmest text on it.
/// Both are the sky's white at low alpha rather than a theme colour, for
/// [kSkyForeground]'s reason.
const Color kSkyHairline = Color(0x2EFFFFFF);
const Color kSkyFaintForeground = Color(0x99FFFFFF);
