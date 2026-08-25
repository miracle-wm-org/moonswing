// The Moon, drawn.
//
// **Why a painter and not a photograph.** The obvious answer to "show what the
// Moon looks like tonight" is one of NASA's public-domain LRO renders, and it
// is the wrong one here twice over. The shell ships no image assets at all —
// `pubspec.yaml` declares no `assets:` section, the themes are embedded as
// constants for exactly this reason (`theme/builtin_themes.dart` says why), and
// the wallpapers the Makefile installs are found by path at runtime rather than
// bundled. Adding the first binary asset would mean the Flutter bundle, the
// Makefile, and the snap all growing a case for it. And a photograph is one
// phase: covering a lunation means thirty of them, or one full-disc image with
// a shadow drawn over it — at which point the shadow is this file anyway, and
// the illuminated fraction it is drawn from is not a photograph.
//
// So: a vector Moon, with the nearside maria and the half-dozen craters anyone
// would recognise laid out roughly where they are, lit by the same illuminated
// fraction the readout prints.
//
// Four things a change here has to keep true:
//
// - **The terminator is computed, never approximated by two circles.** The
//   boundary between light and dark is the projection of a great circle, which
//   is an *ellipse* with a semi-axis of `r × (1 − 2f)` — signed, so the same
//   expression gives a crescent below half lit and a gibbous above it, and
//   passes through a straight line at the quarters. Two overlapping discs, the
//   usual shortcut, cannot draw a gibbous Moon at all.
// - **The dark side is drawn, not left out.** Earthshine — sunlight off the
//   Earth's oceans and cloud — genuinely lights the new Moon's disc enough to
//   see the maria on it, which is what "the old Moon in the new Moon's arms"
//   describes. A crescent floating on nothing reads as a clipping bug.
// - **The southern hemisphere sees the whole disc rotated half a turn**, not
//   mirrored. Rotating the canvas is what makes that one line rather than a
//   sign on every feature, and it is why the features are held in unit-disc
//   coordinates.
// - **Nothing here animates.** There is no ticker, which is deliberate and
//   worth keeping: the picture changes over hours, this painter can be on a
//   desktop for weeks, and the widget that draws it is the one surface in the
//   shell that a test can `pumpAndSettle` — the trap `WeatherSky` and
//   `TrackMarquee` both carry.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// One oval of one mare. A sea is several of these fused into a single path:
/// overlapping ovals in one non-zero path fill as their union, so a translucent
/// mare has no seams where its lobes overlap — the trick `weather_sky.dart`
/// documents for clouds.
class _Blob {
  const _Blob(this.x, this.y, this.r, [this.squash = 1.0]);

  /// Centre, in unit-disc coordinates: −1..1, x to the right, y down.
  final double x;
  final double y;

  /// Radius as a fraction of the disc's radius.
  final double r;

  /// Vertical squash, for the seas that are visibly oval.
  final double squash;
}

/// A crater worth naming.
class _Crater {
  const _Crater(this.x, this.y, this.r, {this.bright = false, this.rays = 0});

  final double x;
  final double y;
  final double r;

  /// Whether the floor is brighter than the surroundings rather than darker —
  /// Aristarchus is the brightest feature on the nearside.
  final bool bright;

  /// The reach of the ray system, in disc radii. Only Tycho and Copernicus
  /// have one worth drawing.
  final double rays;
}

/// One of the nearside seas: several overlapping ovals, and how dark it is
/// relative to the others.
///
/// The strengths are not decoration — Crisium and Serenitatis really are darker
/// than Frigoris and the western edge of Procellarum, and drawing every sea at
/// one opacity is most of what makes a painted Moon look like a pattern rather
/// than a face.
class _Mare {
  const _Mare(this.blobs, {this.strength = 1.0});

  final List<_Blob> blobs;
  final double strength;
}

/// The nearside seas, roughly where they are.
///
/// Not a map projection: the point of them is that the pattern on the disc is
/// the one people have been looking at all their lives, and at 80 pixels across
/// that is a matter of the big shapes being in the right corners. Coordinates
/// are the view from the northern hemisphere — east (Crisium) to the right —
/// which is what [MoonPainter] rotates for a southern observer.
const List<_Mare> _maria = [
  // Oceanus Procellarum — the vast one down the western limb, and the palest.
  _Mare(
    [
      _Blob(-0.56, -0.04, 0.25, 1.45),
      _Blob(-0.47, 0.24, 0.19),
      _Blob(-0.50, -0.34, 0.16),
    ],
    strength: 0.82,
  ),
  // Mare Imbrium, the big circular one at the upper left.
  _Mare([
    _Blob(-0.24, -0.40, 0.24),
    _Blob(-0.06, -0.45, 0.15),
    _Blob(-0.38, -0.29, 0.14),
  ]),
  // Mare Frigoris — the thin band along the top, and the faintest.
  _Mare(
    [
      _Blob(-0.31, -0.60, 0.10, 0.45),
      _Blob(-0.10, -0.65, 0.10, 0.45),
      _Blob(0.11, -0.62, 0.09, 0.45),
    ],
    strength: 0.7,
  ),
  // Mare Serenitatis.
  _Mare([_Blob(0.17, -0.31, 0.17, 0.95)], strength: 1.05),
  // Mare Tranquillitatis, running down and east from it.
  _Mare([
    _Blob(0.33, -0.05, 0.18),
    _Blob(0.21, -0.16, 0.12),
  ]),
  // Mare Crisium — the detached oval near the eastern limb, and the darkest
  // thing on the disc.
  _Mare([_Blob(0.61, -0.25, 0.12, 0.82)], strength: 1.15),
  // Mare Fecunditatis.
  _Mare([_Blob(0.47, 0.14, 0.13, 1.2)], strength: 0.95),
  // Mare Nectaris.
  _Mare([_Blob(0.30, 0.30, 0.09)], strength: 0.95),
  // Mare Nubium.
  _Mare([_Blob(-0.17, 0.42, 0.14, 0.85)], strength: 0.9),
  // Mare Humorum.
  _Mare([_Blob(-0.39, 0.32, 0.10)], strength: 0.9),
];

const List<_Crater> _craters = [
  _Crater(-0.12, 0.60, 0.055, rays: 0.55), // Tycho
  _Crater(-0.28, 0.03, 0.050, rays: 0.22), // Copernicus
  _Crater(-0.50, 0.01, 0.034), // Kepler
  _Crater(-0.20, -0.63, 0.040), // Plato
  _Crater(-0.62, -0.14, 0.026, bright: true), // Aristarchus
  _Crater(0.10, 0.52, 0.036), // Clavius-ish, southern highlands
  _Crater(0.44, -0.44, 0.030), // Aristoteles
  _Crater(0.30, 0.50, 0.028), // Stevinus
];

/// The two colour sets the same disc is drawn in: sunlit, and earthlit.
class _MoonPalette {
  const _MoonPalette({
    required this.centre,
    required this.limb,
    required this.mare,
    required this.craterFloor,
    required this.craterRim,
    required this.ray,
  });

  final Color centre;
  final Color limb;
  final Color mare;
  final Color craterFloor;
  final Color craterRim;
  final Color ray;
}

const _MoonPalette _sunlit = _MoonPalette(
  centre: Color(0xFFFBF7EC),
  limb: Color(0xFFCFC6B2),
  mare: Color(0x8C5C6579),
  craterFloor: Color(0x59655D4E),
  craterRim: Color(0x73FFFFFF),
  ray: Color(0x4DFFFFFF),
);

/// The earthlit side. Not black: a new Moon's disc is visibly there, in a cold
/// blue an order of magnitude fainter than the sunlit half.
const _MoonPalette _earthlit = _MoonPalette(
  centre: Color(0xFF1C2233),
  limb: Color(0xFF10141F),
  mare: Color(0x4D0B0F19),
  craterFloor: Color(0x330A0E17),
  craterRim: Color(0x1AFFFFFF),
  ray: Color(0x0DFFFFFF),
);

/// The Moon at one phase, filling whatever square it is given.
///
/// [illumination] is the lit fraction, 0..1; [waxing] says which limb it is on;
/// [southernView] rotates the disc half a turn for an observer below the
/// equator. Nothing else — everything this needs is what the readout beside it
/// already shows.
class MoonDisc extends StatelessWidget {
  const MoonDisc({
    super.key,
    required this.illumination,
    required this.waxing,
    this.southernView = false,
    this.glow = true,
  });

  final double illumination;
  final bool waxing;
  final bool southernView;

  /// The halo around the disc, scaled by how much of it is lit. Off inside a
  /// tight row, where there is no room for it to fall off and it would read as
  /// a smudge.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: MoonPainter(
          illumination: illumination,
          waxing: waxing,
          southernView: southernView,
          glow: glow,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// Paints [MoonDisc]. Public so a golden or a paint-counting test can drive it
/// at a chosen phase with no widget around it.
class MoonPainter extends CustomPainter {
  const MoonPainter({
    required this.illumination,
    required this.waxing,
    this.southernView = false,
    this.glow = true,
  });

  final double illumination;
  final bool waxing;
  final bool southernView;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final centre = Offset(size.width / 2, size.height / 2);
    // The glow needs room, so the disc is a little smaller than the box.
    final radius = math.min(size.width, size.height) / 2 * (glow ? 0.86 : 0.98);
    if (radius <= 0) return;

    final lit = illumination.clamp(0.0, 1.0);

    // The glow reaches past the disc, and a `CustomPaint` does not clip itself
    // — on a grid of widgets, painting outside the box is painting on the
    // neighbour.
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    if (glow) _paintGlow(canvas, centre, size);

    canvas.save();
    if (southernView) {
      // Half a turn about the centre: the disc *and* everything on it. A mirror
      // would be wrong — a southern observer sees the same face upside down,
      // not reversed.
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(math.pi);
      canvas.translate(-centre.dx, -centre.dy);
    }

    final disc = Path()
      ..addOval(Rect.fromCircle(center: centre, radius: radius));
    final litPath = moonLitPath(
      centre: centre,
      radius: radius,
      illumination: lit,
      waxing: waxing,
    );
    final darkPath = Path.combine(ui.PathOperation.difference, disc, litPath);

    canvas.save();
    canvas.clipPath(darkPath);
    _paintFace(canvas, centre, radius, _earthlit);
    canvas.restore();

    canvas.save();
    canvas.clipPath(litPath);
    _paintFace(canvas, centre, radius, _sunlit);
    canvas.restore();

    _paintTerminatorSoftening(canvas, centre, radius, lit, disc);
    canvas.restore();

    canvas.restore();
  }

  void _paintGlow(Canvas canvas, Offset centre, Size size) {
    // Scaled by the lit fraction *and* floored: even a crescent has a little
    // halo, and a new Moon has none.
    final strength = 0.10 + 0.30 * illumination.clamp(0.0, 1.0);
    // The halo has to reach zero exactly at the edge of the box, not somewhere
    // past it: the painter clips to its own bounds, and a gradient still
    // carrying alpha when it meets that clip draws a visible square around the
    // Moon — which is what happened when this was sized to the disc instead.
    final reach = math.min(size.width, size.height) / 2;
    final paint = Paint()
      ..shader = ui.Gradient.radial(centre, reach, [
        const Color(0xFFDDE6FF).withValues(alpha: strength * 0.50),
        const Color(0xFFDDE6FF).withValues(alpha: strength * 0.20),
        const Color(0x00DDE6FF),
      ], const [
        0.55,
        0.82,
        1.0,
      ]);
    canvas.drawCircle(centre, reach, paint);
  }

  /// The disc's surface, in one palette. Called twice — once clipped to the
  /// shadow, once to the light — so the maria run straight across the
  /// terminator the way they do on the sky.
  void _paintFace(
    Canvas canvas,
    Offset centre,
    double radius,
    _MoonPalette palette,
  ) {
    // Limb darkening: the disc is brightest a little up and left of centre,
    // where the Sun is, and falls off towards the rim.
    final body = Paint()
      ..shader = ui.Gradient.radial(
        centre.translate(-radius * 0.15, -radius * 0.15),
        radius * 1.25,
        [palette.centre, palette.limb],
        const [0.0, 1.0],
      );
    canvas.drawCircle(centre, radius, body);

    // Rays first: they run *under* the craters that threw them and over the
    // maria they cross.
    for (final crater in _craters) {
      if (crater.rays <= 0) continue;
      _paintRays(canvas, centre, radius, crater, palette);
    }

    // Blurred hard: the lobes have to fuse into one irregular region. At a
    // tighter sigma the union still reads as the circles it is made of, which
    // is the same failure `weather_sky.dart` describes for clouds drawn as
    // separate discs.
    final marePaint = Paint()
      ..maskFilter =
          MaskFilter.blur(BlurStyle.normal, math.max(0.3, radius * 0.028));
    for (final sea in _maria) {
      marePaint.color = palette.mare.withValues(
        alpha: (palette.mare.a * sea.strength).clamp(0.0, 1.0),
      );
      final path = Path();
      for (final blob in sea.blobs) {
        path.addOval(Rect.fromCenter(
          center: centre.translate(blob.x * radius, blob.y * radius),
          width: blob.r * 2 * radius,
          height: blob.r * 2 * radius * blob.squash,
        ));
      }
      canvas.drawPath(path, marePaint);
    }

    for (final crater in _craters) {
      final at = centre.translate(crater.x * radius, crater.y * radius);
      final r = crater.r * radius;
      if (r < 0.8) continue;
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..color = crater.bright
              ? palette.craterRim
              : palette.craterFloor,
      );
      // A rim is a lit arc on the side the Sun is on and a shadow opposite;
      // one stroke offset by a fraction of the radius reads as both.
      canvas.drawCircle(
        at.translate(-r * 0.12, -r * 0.12),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.6, r * 0.22)
          ..color = palette.craterRim,
      );
    }

    // A soft inner shadow around the rim, so the disc reads as a sphere rather
    // than a sticker.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(centre, radius, [
          const Color(0x00000000),
          const Color(0x00000000),
          const Color(0x33000000),
        ], const [
          0.0,
          0.82,
          1.0,
        ]),
    );
  }

  void _paintRays(
    Canvas canvas,
    Offset centre,
    double radius,
    _Crater crater,
    _MoonPalette palette,
  ) {
    final at = centre.translate(crater.x * radius, crater.y * radius);
    final reach = crater.rays * radius;
    // A fixed set of bearings rather than a random one: the rays must not
    // reshuffle between the two calls that draw the two halves of the disc.
    const bearings = [0.2, 0.9, 1.5, 2.2, 2.9, 3.6, 4.3, 5.1, 5.8];
    final paint = Paint()
      ..color = palette.ray
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.1, radius * 0.03));
    for (var i = 0; i < bearings.length; i++) {
      // Alternating lengths, so the system does not read as a compass rose.
      final length = reach * (i.isEven ? 1.0 : 0.62);
      final angle = bearings[i];
      paint.strokeWidth = math.max(0.5, radius * 0.018);
      canvas.drawLine(
        at.translate(
          math.cos(angle) * crater.r * radius,
          math.sin(angle) * crater.r * radius,
        ),
        at.translate(math.cos(angle) * length, math.sin(angle) * length),
        paint,
      );
    }
  }

  /// A blurred band along the terminator.
  ///
  /// The real one is soft — it is a sunrise line thrown across mountains, not a
  /// cut — and a hard edge is the single thing that makes a drawn Moon look
  /// drawn. Skipped near the ends of the cycle, where the band would be wider
  /// than the crescent it is meant to soften.
  void _paintTerminatorSoftening(
    Canvas canvas,
    Offset centre,
    double radius,
    double lit,
    Path disc,
  ) {
    if (lit <= 0.06 || lit >= 0.94) return;
    final rx = radius * (1 - 2 * lit) * (waxing ? 1 : -1);
    final path = Path();
    const steps = 48;
    for (var i = 0; i <= steps; i++) {
      final angle = -math.pi / 2 + math.pi * i / steps;
      final point = Offset(
        centre.dx + rx * math.cos(angle),
        centre.dy + radius * math.sin(angle),
      );
      i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
    }
    canvas.save();
    canvas.clipPath(disc);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.10
        ..color = const Color(0x59101522)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.1, radius * 0.06)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(MoonPainter oldDelegate) =>
      oldDelegate.illumination != illumination ||
      oldDelegate.waxing != waxing ||
      oldDelegate.southernView != southernView ||
      oldDelegate.glow != glow;
}

/// The lit region of a disc of [radius] at [centre].
///
/// Public and pure so the geometry is a unit test: at half lit the path's
/// bounding box is exactly half the disc, a crescent is narrower than that and
/// a gibbous wider, and nothing is ever wider than the disc itself
/// (`test/moon_render_test.dart`).
///
/// The outline is sampled rather than assembled from `arcTo`: the terminator is
/// half an ellipse whose x semi-axis passes through zero and changes sign at
/// the quarters, and every arc-based formulation of that needs a special case
/// on each side of it.
Path moonLitPath({
  required Offset centre,
  required double radius,
  required double illumination,
  required bool waxing,
}) {
  final lit = illumination.clamp(0.0, 1.0);
  final direction = waxing ? 1.0 : -1.0;
  // Signed: positive bulges into the lit side (a crescent), negative away from
  // it (a gibbous), zero at the quarters (a straight terminator).
  final rx = radius * (1 - 2 * lit) * direction;
  final limbX = radius * direction;

  const steps = 96;
  final path = Path();
  for (var i = 0; i <= steps; i++) {
    final angle = -math.pi / 2 + math.pi * i / steps;
    final point = Offset(
      centre.dx + limbX * math.cos(angle),
      centre.dy + radius * math.sin(angle),
    );
    i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
  }
  for (var i = steps; i >= 0; i--) {
    final angle = -math.pi / 2 + math.pi * i / steps;
    path.lineTo(
      centre.dx + rx * math.cos(angle),
      centre.dy + radius * math.sin(angle),
    );
  }
  return path..close();
}

// ---------------------------------------------------------------------------
// The sky behind it
// ---------------------------------------------------------------------------

/// One star of the backdrop, in unit coordinates.
class _Star {
  const _Star(this.x, this.y, this.radius, this.alpha);

  final double x;
  final double y;
  final double radius;
  final double alpha;
}

/// The backdrop's stars, laid out once.
///
/// A *seeded* generator, and a lazily-built top-level list rather than
/// something the painter rolls per frame: the same field has to come out on
/// every monitor and survive a restart, which is `SkyField`'s rule in
/// `weather_sky.dart` — a star field that reshuffled itself on every repaint
/// would be the most distracting thing on the desktop.
final List<_Star> _starField = _buildStarField();

List<_Star> _buildStarField() {
  final random = math.Random(0x1F0);
  return List.generate(90, (_) {
    final magnitude = random.nextDouble();
    return _Star(
      random.nextDouble(),
      random.nextDouble(),
      0.4 + magnitude * magnitude * 1.4,
      0.25 + magnitude * 0.55,
    );
  });
}

/// The night the Moon is drawn on: a gradient and a scatter of stars, dimmed by
/// how much of the Moon is lit.
///
/// The dimming is not decoration — it is the same fact the widget's own
/// "stargazing" line states. A full Moon really does wash the faint stars out
/// of the sky, and a card that showed the same brilliant field behind a full
/// Moon as behind a new one would be contradicting the text under it.
class MoonNightSky extends StatelessWidget {
  const MoonNightSky({super.key, this.illumination = 0});

  final double illumination;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: MoonNightSkyPainter(illumination: illumination),
        size: Size.infinite,
      ),
    );
  }
}

/// Paints [MoonNightSky].
class MoonNightSkyPainter extends CustomPainter {
  const MoonNightSkyPainter({required this.illumination});

  final double illumination;

  /// The colours of the night, top to bottom.
  static const Color _zenith = Color(0xFF141B33);
  static const Color _middle = Color(0xFF0D1222);
  static const Color _horizon = Color(0xFF080A13);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          const [_zenith, _middle, _horizon],
          const [0.0, 0.6, 1.0],
        ),
    );

    // Two-thirds of the field is gone under a full Moon; none of it under a new
    // one.
    final wash = 1.0 - 0.65 * illumination.clamp(0.0, 1.0);
    final paint = Paint()..color = const Color(0xFFFFFFFF);
    for (final star in _starField) {
      final alpha = star.alpha * wash;
      if (alpha < 0.04) continue;
      paint.color = const Color(0xFFF2F5FF).withValues(alpha: alpha);
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(MoonNightSkyPainter oldDelegate) =>
      oldDelegate.illumination != illumination;
}
