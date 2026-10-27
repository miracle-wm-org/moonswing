// The Moon, drawn.
//
// **Why a painter and not a photograph.** The shell ships no image assets at all
// — no `assets:` section, themes embedded as constants, wallpapers found by path
// — so the first binary asset would mean the Flutter bundle, the Makefile and
// the snap all growing a case for it. And a photograph is one phase: a lunation
// needs thirty of them, or one full disc with a shadow drawn over it, at which
// point the shadow is this file anyway.
//
// So: a vector Moon, with the nearside maria and the recognisable craters laid
// out roughly where they are, lit by the same illuminated fraction the readout
// prints.
//
// Five things a change here has to keep true:
//
// - **The terminator is computed, never approximated by two circles.** The
//   light/dark boundary is the projection of a great circle — an *ellipse* with
//   semi-axis `r × (1 − 2f)`, signed, so one expression covers crescent,
//   quarter and gibbous. Two overlapping discs cannot draw a gibbous Moon.
// - **The dark side is drawn, not left out.** Earthshine genuinely lights the
//   new Moon's disc, which is what "the old Moon in the new Moon's arms"
//   describes; a crescent floating on nothing reads as a clipping bug.
// - **The disc is turned, never mirrored.** Everybody on Earth sees the same
//   face; where they are changes only which way up it is, and the light and the
//   face turn separately (`MoonOrientation`) — which is why the features are
//   held in unit-disc coordinates. A southern observer seeing it "upside down"
//   is the half turn this comes to on the meridian, not a special case.
// - **Nothing here animates.** The picture changes over hours and this painter
//   can be on a desktop for weeks.
// - **A repaint is dear, so it is bought at the resolution the picture has.**
//   This is the most expensive painter in the shell: two clipped passes over the
//   whole disc, nearly every draw carrying a `MaskFilter`, which is a full
//   offscreen blur *each*. So a ray system is one stroked path of nine subpaths
//   rather than nine strokes ([_paintRays]), and the illumination and the
//   orientation reaching a painter are snapped to [kDrawnIlluminationStep] and
//   [kDrawnAngleStep] first.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:moonswing/moon/moon_phase.dart';

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
/// than Frigoris, and drawing every sea at one opacity is most of what makes a
/// painted Moon look like a pattern rather than a face.
class _Mare {
  const _Mare(this.blobs, {this.strength = 1.0});

  final List<_Blob> blobs;
  final double strength;
}

/// The nearside seas, roughly where they are.
///
/// Not a map projection: at 80 pixels across what matters is that the big shapes
/// are in the right corners. Coordinates are the face with the Moon's north up —
/// east (Crisium) to the right — which [MoonPainter] turns to the observer's sky.
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

/// The step the *picture* is drawn at, as a fraction of the disc.
///
/// The reading behind it moves every minute, and every one of those minutes used
/// to be a full repaint of the most expensive painter in the shell, on every
/// monitor, for ever. A thousandth of the disc moves the terminator by `0.002 ×
/// r` — a twentieth of a pixel on the largest Moon the grid allows — so this is
/// not a visible approximation but a repaint the picture could not have shown.
/// It takes the disc from a repaint a minute to one every quarter hour or so.
///
/// Deliberately *not* the printed percentage: agreeing to the whole percent
/// makes the step almost a pixel, and rounds the last sliver of a crescent away
/// to a new Moon drawn as nothing at all.
const double kDrawnIlluminationStep = 0.001;

/// [illumination] snapped to [kDrawnIlluminationStep].
///
/// Applied where a painter is built rather than where a reading is made: the
/// model keeps the number it computed, and only the picture is told the value
/// it is able to draw.
double drawnIllumination(double illumination) =>
    (illumination.clamp(0.0, 1.0) / kDrawnIlluminationStep).roundToDouble() *
        kDrawnIlluminationStep;

/// The step the *orientation* is drawn at, degrees.
///
/// While the Moon is up its orientation turns continuously — a quarter turn
/// between rising and setting, and fastest near the zenith — so it is a reading
/// that moves every minute for the reason the illumination is. A degree moves
/// the limb of the largest Moon the grid allows by under a pixel.
const double kDrawnAngleStep = 1.0;

/// [degrees] snapped to [kDrawnAngleStep], in `[0, 360)`.
double drawnAngle(double degrees) {
  final snapped = (degrees / kDrawnAngleStep).roundToDouble() * kDrawnAngleStep;
  final wrapped = snapped % 360.0;
  return wrapped < 0 ? wrapped + 360.0 : wrapped;
}

/// [orientation] with both of its angles snapped to [kDrawnAngleStep].
MoonOrientation drawnOrientation(MoonOrientation orientation) =>
    MoonOrientation(
      brightLimbDegrees: drawnAngle(orientation.brightLimbDegrees),
      northDegrees: drawnAngle(orientation.northDegrees),
    );

/// The Moon at one phase, filling whatever square it is given.
///
/// [illumination] is the lit fraction; [orientation] says where the light is
/// coming from and which way up the face is. Nothing else — everything this
/// needs is what the readout beside it already shows.
class MoonDisc extends StatelessWidget {
  const MoonDisc({
    super.key,
    required this.illumination,
    this.orientation = const MoonOrientation.upright(),
    this.glow = true,
  });

  final double illumination;
  final MoonOrientation orientation;

  /// The halo around the disc, scaled by how much of it is lit. Off inside a
  /// tight row, where there is no room for it to fall off and it would read as
  /// a smudge.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: MoonPainter(
          illumination: drawnIllumination(illumination),
          orientation: drawnOrientation(orientation),
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
    this.orientation = const MoonOrientation.upright(),
    this.glow = true,
  });

  final double illumination;
  final MoonOrientation orientation;
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

    final disc = Path()
      ..addOval(Rect.fromCircle(center: centre, radius: radius));
    final litPath = moonLitPath(
      centre: centre,
      radius: radius,
      illumination: lit,
      brightLimbDegrees: orientation.brightLimbDegrees,
    );
    final darkPath = Path.combine(ui.PathOperation.difference, disc, litPath);

    // Where the Sun is, on the face as it is drawn before it is turned — which
    // is where the shading has to lean, or a face turned over would be lit
    // from the side the shadow is on.
    final sunward = (orientation.brightLimbDegrees - orientation.northDegrees) *
        math.pi /
        180;
    final light = Offset(math.sin(sunward), -math.cos(sunward));

    canvas.save();
    canvas.clipPath(darkPath);
    // Earthshine comes from where the observer is standing: straight on.
    _paintFace(canvas, centre, radius, _earthlit, Offset.zero);
    canvas.restore();

    canvas.save();
    canvas.clipPath(litPath);
    _paintFace(canvas, centre, radius, _sunlit, light);
    canvas.restore();

    _paintTerminatorSoftening(canvas, centre, radius, lit, disc);

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
  ///
  /// Drawn turned to [MoonOrientation.northDegrees] — the clip it is inside is
  /// not, being already where the light falls. [light] is the unit direction
  /// the light comes from on the unturned face, or zero for light from straight
  /// on.
  void _paintFace(
    Canvas canvas,
    Offset centre,
    double radius,
    _MoonPalette palette,
    Offset light,
  ) {
    // Half a turn about the centre for a southern observer at the meridian,
    // and anything else in between: the disc *and* everything on it. A mirror
    // would be wrong — every observer sees the same face, only at another
    // angle.
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(orientation.northDegrees * math.pi / 180);
    canvas.translate(-centre.dx, -centre.dy);

    // Limb darkening: the disc is brightest a little towards the Sun and falls
    // off towards the rim.
    final body = Paint()
      ..shader = ui.Gradient.radial(
        centre + light * (radius * 0.2),
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
        at + light * (r * 0.17),
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
    canvas.restore();
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
    // One path of nine subpaths, stroked once, rather than nine strokes: a
    // `MaskFilter` is a full offscreen blur per *draw*, and this loop ran twice
    // per crater per repaint — thirty-six blurred draws, the most expensive thing
    // in the disc. The only place a batched stroke composites differently is
    // where two rays overlap, which is under the crater drawn on top of it.
    final path = Path();
    for (var i = 0; i < bearings.length; i++) {
      // Alternating lengths, so the system does not read as a compass rose.
      final length = reach * (i.isEven ? 1.0 : 0.62);
      final angle = bearings[i];
      final cos = math.cos(angle);
      final sin = math.sin(angle);
      path
        ..moveTo(
          at.dx + cos * crater.r * radius,
          at.dy + sin * crater.r * radius,
        )
        ..lineTo(at.dx + cos * length, at.dy + sin * length);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.ray
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(0.5, radius * 0.018)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, math.max(0.1, radius * 0.03)),
    );
  }

  /// A blurred band along the terminator.
  ///
  /// The real one is soft — a sunrise line thrown across mountains, not a cut —
  /// and a hard edge is the single thing that makes a drawn Moon look drawn.
  /// Skipped near the ends of the cycle, where the band would be wider than the
  /// crescent it softens.
  void _paintTerminatorSoftening(
    Canvas canvas,
    Offset centre,
    double radius,
    double lit,
    Path disc,
  ) {
    if (lit <= 0.06 || lit >= 0.94) return;
    // Built lit-on-the-right, as [moonLitPath] is, and turned with the canvas.
    final rx = radius * (1 - 2 * lit);
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
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate((orientation.brightLimbDegrees - 90) * math.pi / 180);
    canvas.translate(-centre.dx, -centre.dy);
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
      oldDelegate.orientation != orientation ||
      oldDelegate.glow != glow;
}

/// The lit region of a disc of [radius] at [centre], with the middle of its lit
/// edge at [brightLimbDegrees] clockwise from straight up — 90, the default, is
/// a waxing Moon as an almanac draws it, lit on the right.
///
/// Public and pure so the geometry is a unit test: at half lit the bounding box
/// is exactly half the disc, a crescent is narrower and a gibbous wider, and
/// nothing is ever wider than the disc.
///
/// The outline is sampled rather than assembled from `arcTo`: the terminator's x
/// semi-axis passes through zero and changes sign at the quarters, and every
/// arc-based formulation needs a special case on each side of it. Sampling is
/// also what makes the turn free — each point is placed lit-on-the-right and
/// turned on the way into the path.
Path moonLitPath({
  required Offset centre,
  required double radius,
  required double illumination,
  double brightLimbDegrees = 90,
}) {
  final lit = illumination.clamp(0.0, 1.0);
  // Signed: positive bulges into the lit side (a crescent), negative away from
  // it (a gibbous), zero at the quarters (a straight terminator).
  final rx = radius * (1 - 2 * lit);

  final turn = (brightLimbDegrees - 90) * math.pi / 180;
  final cos = math.cos(turn);
  final sin = math.sin(turn);
  // The textbook rotation, which turns clockwise on a y-down screen.
  Offset place(double x, double y) =>
      Offset(centre.dx + x * cos - y * sin, centre.dy + x * sin + y * cos);

  const steps = 96;
  final path = Path();
  for (var i = 0; i <= steps; i++) {
    final angle = -math.pi / 2 + math.pi * i / steps;
    final point = place(radius * math.cos(angle), radius * math.sin(angle));
    i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
  }
  for (var i = steps; i >= 0; i--) {
    final angle = -math.pi / 2 + math.pi * i / steps;
    final point = place(rx * math.cos(angle), radius * math.sin(angle));
    path.lineTo(point.dx, point.dy);
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
/// A *seeded* generator and a lazily-built top-level list rather than something
/// the painter rolls per frame: the same field has to come out on every monitor
/// and survive a restart, which is `SkyField`'s rule.
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
/// The dimming is the same fact the widget's "stargazing" line states. A full
/// Moon really does wash the faint stars out, and a card showing the same
/// brilliant field behind a full Moon as behind a new one would contradict the
/// text under it.
class MoonNightSky extends StatelessWidget {
  const MoonNightSky({super.key, this.illumination = 0});

  final double illumination;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: MoonNightSkyPainter(
          illumination: drawnIllumination(illumination),
        ),
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
