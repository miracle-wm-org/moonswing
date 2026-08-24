// The animated sky the weather desktop widget is drawn on: a gradient for the
// conditions, a sun or a moon behind however much cloud there actually is, and
// whatever is falling out of it.
//
// Three things this file is arranged around:
//
// - **The layout is data, and it is computed once.** [SkyField] holds every
//   cloud, star, drop and flake as plain numbers, built from a seeded
//   [math.Random] when the *conditions* change and never per frame. That is
//   what makes "how many clouds at 60% cover" and "nothing falls out of a clear
//   sky" plain unit tests, with no canvas and no ticker; and it is what keeps
//   the per-frame work to arithmetic on a fixed list.
// - **The ticker repaints the painter, not the tree.** The elapsed time is a
//   [ValueNotifier] handed to [CustomPainter.repaint], so a frame costs one
//   `RenderCustomPaint` repaint — no `setState`, no rebuild, and nothing above
//   this widget on the desktop surface hears about it.
// - **The clouds are one path, not a pile of circles.** Overlapping *ovals* in
//   a single non-zero path fill as their union, so a translucent cloud has no
//   seams where its puffs overlap. Drawing them as separate circles is what
//   makes a cloud look like a cluster of bubbles.
//
// The animation is honest about what it knows: the cloud count comes from the
// API's `cloud_cover` percentage, the fall rate from the WMO code's intensity,
// and the sun or moon from the location's own `is_day`. Nothing here is a
// weather *simulation* — it is a reading, drawn.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart';

import 'package:graceful_shell/weather/weather_condition.dart';

/// The colours one condition is drawn in.
///
/// Deliberately *not* from [ThemeConfig]: this is a picture of the sky, and a
/// sky that took its blue from the user's accent colour would stop being one.
/// The widget's text sits on a scrim above it for exactly that reason — see
/// [WeatherSky]'s doc.
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
/// near-black. Pure, so the mapping is a unit test.
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
// in near-white and there has to be something for them to be lighter *than*.
// A palette matched to the fog itself leaves the animation invisible and the
// condition indistinguishable from overcast.
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
/// [x] and [y] are fractions of the painted box, [puffs] and [radii] are
/// relative to [scale], and [speed] is fractions of the width per second — so
/// one field draws correctly at every size the user resizes the widget to,
/// without being rebuilt.
class SkyCloud {
  const SkyCloud({
    required this.x,
    required this.y,
    required this.scale,
    required this.speed,
    required this.opacity,
    required this.puffs,
    required this.radii,
  });

  final double x;
  final double y;
  final double scale;
  final double speed;
  final double opacity;

  /// Puff centres, relative to the cloud's own origin.
  final List<Offset> puffs;

  /// Each puff's radius, in the same units.
  final List<double> radii;
}

/// One falling thing — a raindrop, a flake, a hailstone.
class SkyDrop {
  const SkyDrop({
    required this.x,
    required this.phase,
    required this.speed,
    required this.size,
    required this.sway,
    required this.swayPhase,
  });

  /// Horizontal position, 0..1 of the width.
  final double x;

  /// Where in its fall the drop starts, 0..1. Spreading these is what stops
  /// every drop crossing the top edge on the same frame.
  final double phase;

  /// Falls per second.
  final double speed;

  /// Length (rain) or radius (snow, hail), in fractions of the height.
  final double size;

  /// How far a flake drifts sideways, 0 for rain.
  final double sway;
  final double swayPhase;
}

class SkyStar {
  const SkyStar({
    required this.x,
    required this.y,
    required this.radius,
    required this.twinkleRate,
    required this.twinklePhase,
  });

  final double x;
  final double y;
  final double radius;
  final double twinkleRate;
  final double twinklePhase;
}

/// A drifting band of fog.
class SkyFogBand {
  const SkyFogBand({
    required this.y,
    required this.height,
    required this.speed,
    required this.opacity,
  });

  final double y;
  final double height;
  final double speed;
  final double opacity;
}

/// How many clouds a cover fraction draws.
///
/// Zero at a genuinely clear sky — the one case that has to be exact, because a
/// single stray cloud over a "Clear sky" label is the animation contradicting
/// the reading next to it. [kMaxClouds] at a closed lid, and the count rounds
/// *up* in between so the first wisp appears as soon as there is any cover to
/// speak of.
int cloudsForCover(double cover) {
  final clamped = cover.clamp(0.0, 1.0);
  if (clamped < 0.05) return 0;
  return (clamped * kMaxClouds).ceil().clamp(1, kMaxClouds);
}

/// The cloud ceiling. Past this the sky is a grey wash rather than a set of
/// distinguishable clouds, and each one costs a path fill per frame.
const int kMaxClouds = 7;

/// The particle ceiling, for the same reason. A desktop widget is a few hundred
/// pixels across; a hundred drops in that is already a downpour.
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
    required this.lightningPeriod,
  });

  final WeatherCondition condition;
  final double cloudCover;
  final bool night;

  final List<SkyCloud> clouds;
  final List<SkyDrop> drops;
  final List<SkyStar> stars;
  final List<SkyFogBand> fogBands;

  /// Seconds between lightning flashes, or 0 when there is none.
  final double lightningPeriod;

  /// How visible the sun or moon is through the cloud, 0..1.
  ///
  /// Fully hidden under a closed lid rather than merely dimmed — a sun burning
  /// through an overcast sky is the picture of a *break* in the cloud, which is
  /// the one thing an overcast reading rules out. Everywhere short of that it
  /// stays *mostly* visible, which is why the ramp is steep rather than linear:
  /// the clouds themselves already occlude the disc, so fading it in proportion
  /// to the cover dims it twice over — and a half-alpha yellow disc over a blue
  /// sky composites to green.
  double get celestialOpacity =>
      ((1.0 - cloudCover) * 1.7).clamp(0.0, 1.0).toDouble();

  /// Builds the layout for one set of conditions.
  ///
  /// [seed] is fixed by default, so the same weather draws the same sky on
  /// every monitor and across a restart — a cloud field that reshuffled itself
  /// whenever the widget rebuilt would be the most distracting thing on the
  /// desktop.
  factory SkyField.build({
    required WeatherCondition condition,
    required double cloudCover,
    required bool night,
    int seed = 7,
  }) {
    final random = math.Random(seed);
    final cover = cloudCover.clamp(0.0, 1.0).toDouble();

    final cloudCount = cloudsForCover(cover);
    final clouds = <SkyCloud>[];
    for (var i = 0; i < cloudCount; i++) {
      clouds.add(_buildCloud(random, i, cloudCount, cover, condition));
    }

    final drops = <SkyDrop>[];
    if (condition.isPrecipitating) {
      final snow = condition.precipitation == Precipitation.snow;
      final drizzle = condition.precipitation == Precipitation.drizzle;
      final count =
          (kMaxDrops * (0.25 + 0.75 * condition.intensity)).round().clamp(
                8,
                kMaxDrops,
              );
      for (var i = 0; i < count; i++) {
        drops.add(_buildDrop(random, condition, snow: snow, drizzle: drizzle));
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
          // Kept out of the bottom third: that is where the widget's own text
          // sits, and a star behind a temperature reads as a rendering artefact.
          y: random.nextDouble() * 0.55,
          radius: 0.6 + random.nextDouble() * 1.1,
          twinkleRate: 0.4 + random.nextDouble() * 1.2,
          twinklePhase: random.nextDouble() * math.pi * 2,
        ));
      }
    }

    final fogBands = <SkyFogBand>[];
    if (condition.kind == WeatherKind.fog) {
      // Five bands, spread from near the top to near the bottom edge: fog is
      // the one condition where the *air* is the weather, so it has to reach
      // the ground rather than sit in a layer where every other palette leaves
      // a clear horizon.
      for (var i = 0; i < 5; i++) {
        fogBands.add(SkyFogBand(
          // Separated, with sky between them. Bands wide enough to overlap
          // blur together into one flat veil, which is a gradient rather than
          // an animation: what says "fog" is streaks at different heights
          // sliding across each other.
          y: 0.16 + i * 0.17 + random.nextDouble() * 0.04,
          height: 0.06 + random.nextDouble() * 0.05,
          // A slow oscillation rather than a wrap, and alternating in sign so
          // the bands slide past each other rather than travelling as one
          // sheet. Fog does not have a direction to travel in.
          speed: (i.isEven ? 1 : -1) * (0.012 + random.nextDouble() * 0.02),
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
      lightningPeriod: condition.lightning ? 6.5 : 0,
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
  // Spread across the track by index rather than at random: a handful of
  // random x values clumps often enough to look like a mistake, and a cloud
  // field is the one thing on the card the eye reads as evenly spaced.
  final slot = (index + 0.5) / count;
  final jitter = (random.nextDouble() - 0.5) * (0.7 / count);

  final puffCount = 3 + random.nextInt(3);
  final puffs = <Offset>[];
  final radii = <double>[];
  var x = 0.0;
  for (var i = 0; i < puffCount; i++) {
    final radius = 0.42 + random.nextDouble() * 0.34;
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
  final low = condition.isPrecipitating || condition.kind == WeatherKind.overcast;

  return SkyCloud(
    x: slot + jitter,
    // A wide vertical spread, so the clouds layer at different depths instead
    // of lining up in one band across the top of the card.
    y: (low ? 0.08 : 0.10) + random.nextDouble() * (low ? 0.34 : 0.30),
    // Scaled by the cover as well as by the weather: at 20% the sky wants a
    // couple of small wisps, and drawing them at overcast size fills the card
    // with three clouds and calls it "mainly clear".
    scale: ((low ? 0.13 : 0.10) + random.nextDouble() * 0.06) *
        (0.62 + 0.5 * cover),
    // Slow, and slower for the big ones: parallax, and a cloud that crosses the
    // card in under a minute is a screensaver.
    speed: (0.004 + random.nextDouble() * 0.009) * (low ? 0.8 : 1.0),
    // Nearly opaque, which is what stops the sun behind one from tinting it:
    // a half-transparent cloud over a yellow disc composites to olive, which
    // reads as a rendering fault rather than as weather.
    opacity: 0.9 + random.nextDouble() * 0.1,
    puffs: puffs,
    radii: radii,
  );
}

SkyDrop _buildDrop(
  math.Random random,
  WeatherCondition condition, {
  required bool snow,
  required bool drizzle,
}) {
  if (snow) {
    return SkyDrop(
      x: random.nextDouble(),
      phase: random.nextDouble(),
      speed: 0.10 + random.nextDouble() * 0.10 + condition.intensity * 0.10,
      size: 0.012 + random.nextDouble() * 0.014,
      sway: 0.02 + random.nextDouble() * 0.05,
      swayPhase: random.nextDouble() * math.pi * 2,
    );
  }
  final hail = condition.precipitation == Precipitation.hail;
  return SkyDrop(
    x: random.nextDouble(),
    phase: random.nextDouble(),
    speed: (drizzle ? 0.5 : 0.9) +
        random.nextDouble() * 0.5 +
        condition.intensity * 0.6,
    size: hail
        ? 0.012 + random.nextDouble() * 0.008
        : (drizzle ? 0.035 : 0.07) + random.nextDouble() * 0.05,
    // Sleet is the one mixed case: half of it drifts like snow, and giving the
    // whole field a sway would make freezing rain fall like a blizzard.
    sway: condition.precipitation == Precipitation.sleet && random.nextBool()
        ? 0.02 + random.nextDouble() * 0.03
        : 0,
    swayPhase: random.nextDouble() * math.pi * 2,
  );
}

// --- the widget ------------------------------------------------------------

/// The animated sky for one set of conditions.
///
/// Fills its box; the caller clips it. Text drawn over this belongs on a scrim
/// — see [SkyScrim] — because the palettes run from a near-black storm to an
/// almost-white snowfall and nothing legible sits on both.
///
/// **Nothing that renders this may be `pumpAndSettle`ed**, for the reason
/// `TrackMarquee` documents: a [Ticker] never settles. Pass `animate: false` in
/// a widget test, which paints frame zero and starts nothing.
class WeatherSky extends StatefulWidget {
  const WeatherSky({
    super.key,
    required this.condition,
    required this.cloudCover,
    required this.night,
    this.animate = true,
  });

  final WeatherCondition condition;

  /// 0..1, from the API's `cloud_cover` where there is one.
  final double cloudCover;

  final bool night;

  /// Whether the ticker runs. False paints a still frame.
  final bool animate;

  @override
  State<WeatherSky> createState() => _WeatherSkyState();
}

class _WeatherSkyState extends State<WeatherSky>
    with SingleTickerProviderStateMixin {
  /// Elapsed seconds. A [ValueNotifier] rather than a `setState` value: it is
  /// handed to the painter as its `repaint`, so a frame is one repaint of one
  /// render object and no part of the tree above rebuilds.
  final ValueNotifier<double> _time = ValueNotifier(0);
  late final Ticker _ticker = createTicker(_onTick);
  late SkyField _field = _buildField();

  @override
  void initState() {
    super.initState();
    if (widget.animate) _ticker.start();
  }

  @override
  void didUpdateWidget(WeatherSky oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.condition.kind != widget.condition.kind ||
        oldWidget.condition.intensity != widget.condition.intensity ||
        oldWidget.cloudCover != widget.cloudCover ||
        oldWidget.night != widget.night) {
      _field = _buildField();
    }
    if (widget.animate != oldWidget.animate) {
      widget.animate ? _ticker.start() : _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  SkyField _buildField() => SkyField.build(
        condition: widget.condition,
        cloudCover: widget.cloudCover,
        night: widget.night,
      );

  /// The last value published, for the frame cap below.
  double _published = -1;

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    // Capped at [kSkyFrameInterval]. This painter runs for as long as the
    // widget is on the desktop — which is to say permanently, on a machine
    // that may be doing nothing else — and at the display's own rate it is a
    // repaint every 16ms forever for a decoration. Nothing here moves fast
    // enough to need that: the quickest thing on the card is a raindrop
    // crossing it in about a second, and the slowest is a cloud taking two
    // minutes. This is the same instinct `_cycle` in `pulse_client.dart`
    // states from the other direction — an idle loop spinning at 820Hz was
    // most of the shell's idle CPU.
    if (_published >= 0 && now - _published < kSkyFrameInterval) return;
    _published = now;
    // Wrapped at an hour. Every motion here is periodic in well under that, and
    // an unbounded seconds counter loses its fractional bits to float precision
    // after a few days of uptime — which a wallpaper widget certainly sees.
    _time.value = now % 3600;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: SkyPainter(
          field: _field,
          palette: skyPalette(widget.condition, night: widget.night),
          time: _time,
        ),
        // A painter with no child paints nothing unless it is given a size, and
        // this one is the background of a card whose size the grid decides.
        size: Size.infinite,
      ),
    );
  }
}

/// The shortest gap between repaints, in seconds — 30 per second.
///
/// Deliberately below the display's rate; see [_WeatherSkyState._onTick].
const double kSkyFrameInterval = 1 / 30;

/// Paints a [SkyField].
///
/// Public so a golden or a paint-counting test can drive it directly, at a
/// chosen time, with no ticker involved.
class SkyPainter extends CustomPainter {
  SkyPainter({
    required this.field,
    required this.palette,
    required this.time,
  }) : super(repaint: time);

  final SkyField field;
  final SkyPalette palette;
  final ValueListenable<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = time.value;
    final rect = Offset.zero & size;

    canvas.drawRect(rect, Paint()..shader = palette.gradient.createShader(rect));
    _paintStars(canvas, size, t);
    _paintCelestial(canvas, size, t);
    _paintClouds(canvas, size, t);
    _paintFog(canvas, size, t);
    _paintPrecipitation(canvas, size, t);
    _paintLightning(canvas, size, t);
  }

  void _paintStars(Canvas canvas, Size size, double t) {
    if (field.stars.isEmpty) return;
    final paint = Paint()..color = const Color(0xFFFFFFFF);
    for (final star in field.stars) {
      // Never fully out: a star that blinks off entirely reads as a dead pixel.
      final twinkle =
          0.45 + 0.55 * (0.5 + 0.5 * math.sin(t * star.twinkleRate + star.twinklePhase));
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.radius,
        paint..color = Color.fromRGBO(255, 255, 255, twinkle * palette.starOpacity),
      );
    }
  }

  /// The sun or the moon, with its glow, behind whatever cloud there is.
  ///
  /// Dimmed by **washing out towards haze white**, not by dropping its alpha
  /// towards the sky. A half-transparent yellow disc composited over a blue
  /// sky is *green*, and so is a yellow lerped halfway to blue; either one
  /// reads as a rendering fault rather than as a hazy afternoon. Washed out and
  /// then faded on a square-root ramp, it goes pale the way a sun behind thin
  /// cloud does, and disappears exactly when [SkyField.celestialOpacity]
  /// reaches zero.
  void _paintCelestial(Canvas canvas, Size size, double t) {
    final opacity = field.celestialOpacity;
    if (opacity <= 0.01) return;

    final centre = Offset(size.width * 0.78, size.height * 0.27);
    final radius = math.min(size.width, size.height) * 0.11;
    // A slow breath, so a clear sky is not a still image. Small enough that it
    // reads as light rather than as something moving.
    final pulse = 1 + 0.03 * math.sin(t * 0.6);

    // Haze, not sky: what thin cloud does to a sun is take the colour out of
    // it, not tint it with what is behind.
    const haze = Color(0xFFF4F6F8);
    final alpha = math.sqrt(opacity);
    Color dim(Color colour) =>
        Color.lerp(colour, haze, 1 - opacity)!.withValues(alpha: alpha);

    final glowColour = dim(field.night
        ? const Color(0xFFB9CFEA)
        : const Color(0xFFFFE9A8));
    canvas.drawCircle(
      centre,
      radius * 3.2 * pulse,
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          radius * 3.2 * pulse,
          [
            glowColour.withValues(alpha: 0.34 * alpha),
            glowColour.withValues(alpha: 0.0),
          ],
        ),
    );

    if (field.night) {
      // The crescent is cut rather than drawn: a filled disc with a
      // background-coloured disc offset into it would need the sky's exact
      // colour at that point, which is a gradient. `difference` is the one that
      // works over anything.
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
        radius * pulse,
        Paint()
          ..shader = ui.Gradient.radial(
            centre.translate(-radius * 0.2, -radius * 0.2),
            radius * 1.4 * pulse,
            [dim(const Color(0xFFFFF6D8)), dim(const Color(0xFFFFC94A))],
          ),
      );
    }
  }

  void _paintClouds(Canvas canvas, Size size, double t) {
    for (final cloud in field.clouds) {
      // The track is 1.4 boxes wide, so a cloud is fully off one edge before it
      // reappears at the other; without the slack a cloud pops out of existence
      // at the moment it is still half on screen.
      final travel = (cloud.x + cloud.speed * t) % 1.4 - 0.2;
      final origin = Offset(travel * size.width, cloud.y * size.height);
      final scale = cloud.scale * size.width;

      final path = Path()..fillType = PathFillType.nonZero;
      for (var i = 0; i < cloud.puffs.length; i++) {
        path.addOval(Rect.fromCircle(
          center: origin + cloud.puffs[i] * scale,
          radius: cloud.radii[i] * scale,
        ));
      }
      // The body under the puffs — a cloud's underside is one mass, not a row
      // of scallops. An *ellipse* rather than the rounded rect this started
      // as: a rect's ends stay square however large the corner radius is next
      // to a puff three times its height, and at a wide span they read as a
      // shelf sticking out from under the cloud.
      final bounds = path.getBounds();
      path.addOval(Rect.fromLTRB(
        bounds.left + scale * 0.12,
        origin.dy - scale * 0.30,
        bounds.right - scale * 0.12,
        origin.dy + scale * 0.30,
      ));

      final shaded = path.getBounds();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            shaded.topCenter,
            shaded.bottomCenter,
            [
              palette.cloudLight.withValues(alpha: cloud.opacity.clamp(0.0, 1.0)),
              palette.cloudDark.withValues(alpha: cloud.opacity.clamp(0.0, 1.0)),
            ],
          ),
      );
    }
  }

  void _paintFog(Canvas canvas, Size size, double t) {
    if (field.fogBands.isEmpty) return;
    // Blurred, not clipped. A band drawn as a rectangle with a horizontal
    // gradient has hard edges along its top and bottom however soft its ends
    // are, and four of those stacked up the card read as venetian blinds. A
    // blur is the only thing that makes the edge of fog look like fog.
    for (final band in field.fogBands) {
      final height = band.height * size.height;
      final blur = height * 0.7;
      // Drifts a full width in each direction and is drawn wider than the box
      // by that much, so it never uncovers an edge.
      final shift = math.sin(band.speed * t * math.pi * 2) * size.width * 0.25;
      final rect = Rect.fromLTWH(
        -size.width * 0.35 + shift,
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

  void _paintPrecipitation(Canvas canvas, Size size, double t) {
    if (field.drops.isEmpty) return;
    final snowy = field.condition.precipitation == Precipitation.snow;
    final hail = field.condition.precipitation == Precipitation.hail;

    final paint = Paint()
      ..color = palette.precipitation.withValues(alpha: snowy ? 0.9 : 0.55)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, size.width * 0.004);

    for (final drop in field.drops) {
      // The fall is derived from the elapsed time, never accumulated — the rule
      // `lib/timers/` states: a per-frame increment drifts by however late each
      // frame was, and would run at a different rate on a loaded machine.
      final progress = (drop.phase + drop.speed * t) % 1.0;
      // From above the top edge, so a drop fades in falling rather than
      // materialising at the ceiling.
      final y = (progress * 1.2 - 0.1) * size.height;
      final sway = drop.sway == 0
          ? 0.0
          : math.sin(t * 1.3 + drop.swayPhase) * drop.sway * size.width;
      final x = drop.x * size.width + sway;

      if (snowy || (drop.sway > 0 && !hail)) {
        canvas.drawCircle(Offset(x, y), drop.size * size.height, paint);
      } else if (hail) {
        canvas.drawCircle(Offset(x, y), drop.size * size.height, paint);
      } else {
        // A slight lean, and the same lean for every drop: rain that fell at
        // random angles would read as static.
        final length = drop.size * size.height;
        canvas.drawLine(
          Offset(x, y),
          Offset(x - length * 0.18, y + length),
          paint,
        );
      }
    }
  }

  void _paintLightning(Canvas canvas, Size size, double t) {
    if (field.lightningPeriod <= 0) return;
    final phase = t % field.lightningPeriod;
    // A flash is a fifth of a second of veil with a sharp decay. Anything
    // longer stops reading as lightning and starts reading as the screen
    // flickering.
    const flash = 0.22;
    if (phase > flash) return;

    final strength = math.pow(1 - phase / flash, 2).toDouble();
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFDCE9FF).withValues(alpha: 0.5 * strength),
    );

    // The bolt itself, on the first half of the flash only, and in a different
    // place each time: `t ~/ period` indexes the flash, so the jag is stable
    // for the whole of one flash and different for the next.
    if (phase > flash * 0.6) return;
    final index = (t ~/ field.lightningPeriod).toInt();
    final random = math.Random(index * 977 + 13);
    var x = size.width * (0.2 + random.nextDouble() * 0.6);
    var y = 0.0;
    final path = Path()..moveTo(x, y);
    final segments = 4 + random.nextInt(3);
    for (var i = 0; i < segments; i++) {
      x += (random.nextDouble() - 0.5) * size.width * 0.22;
      y += size.height * (0.5 / segments) * (0.7 + random.nextDouble() * 0.6);
      path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size.width * 0.008)
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFFFFFFF).withValues(alpha: strength),
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
/// white and this is what guarantees there is something dark behind it. Applied
/// as a gradient from the bottom rather than a flat veil, because the top of
/// the card is where the sun, the moon and the clouds are and dimming those is
/// dimming the whole point.
class SkyScrim extends StatelessWidget {
  const SkyScrim({super.key, this.strength = 0.55});

  final double strength;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            const Color(0xFF000000).withValues(alpha: strength),
            const Color(0xFF000000).withValues(alpha: strength * 0.45),
            const Color(0xFF000000).withValues(alpha: 0),
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
    );
  }
}

/// The soft drop shadow every label over the sky carries, so a white readout
/// survives the one palette that is nearly white itself.
const List<Shadow> kSkyTextShadows = [
  Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1)),
];

/// White, at the two weights the readout uses. The sky is a picture, and text
/// on it takes its colour from the picture rather than from the theme — the
/// same call the lock screen makes over a wallpaper.
const Color kSkyForeground = Color(0xFFFFFFFF);
const Color kSkyMutedForeground = Color(0xCCFFFFFF);
