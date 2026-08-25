// The picture the fortune is written on: an oil lamp in the dark, and the smoke
// coming out of it.
//
// `weather_sky.dart`'s arrangement, and deliberately so — this is the second
// animated card on the desktop and the two should not be built in two different
// ways:
//
// - **The layout is data, computed once.** [LampField] holds every puff, ember
//   and star as plain numbers built from a *seeded* [math.Random], so "how many
//   puffs" and "the same lamp on every monitor" are plain unit tests with no
//   canvas behind them, and a frame is arithmetic over a fixed list. The seed is
//   fixed for the sky's reason: a plume that reshuffled itself on every rebuild
//   would be the most distracting thing on the desktop.
// - **The ticker repaints the painter, not the tree.** Elapsed time is a
//   [ValueNotifier] handed to [CustomPainter.repaint], so a frame is one
//   `RenderCustomPaint` repaint inside a [RepaintBoundary] — no `setState`, and
//   nothing else on the background surface hears about it.
// - **Motion is derived from the elapsed time, never accumulated.** A per-frame
//   increment drifts by however late each frame was and runs at a different
//   rate on a loaded machine — `lib/timers/`'s rule.
// - **Nothing rendering this may be `pumpAndSettle`ed.** A [Ticker] never
//   settles; `animate: false` paints a still frame and starts nothing.
//
// The lamp itself is *painted*, not photographed — the shell ships no image
// assets at all (no `assets:` section, themes embedded as constants), so a
// picture of a lamp would be the first, in the Flutter bundle and the Makefile
// and the snap alike. Drawing it also buys the two things this card needs from
// it: the flame flickers, and the smoke leaves from exactly where the spout is
// however large the grid made the widget.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart';

// The frame cap the weather sky holds itself to. Borrowed rather than
// re-picked: two animated cards on one desktop running at two different rates
// is a difference somebody would eventually have to explain, and the reasoning
// (a decoration on a machine that may be doing nothing else has no business
// repainting every 16ms) is identical. `weather_sky.dart` documents it.
import 'package:graceful_shell/weather/weather_sky.dart' show kSkyFrameInterval;

/// The night the lamp sits in.
///
/// Deliberately *not* from [ThemeConfig], for the reason [SkyPalette] states:
/// this is a picture, and a genie's lamp lit in the user's accent colour stops
/// being one. The card's text sits on [LampScrim] above it for exactly that
/// reason.
const Color kLampSkyTop = Color(0xFF150E28);
const Color kLampSkyMiddle = Color(0xFF261640);
const Color kLampSkyHorizon = Color(0xFF3B2047);

/// The warm pool of light the flame throws onto the dark.
const Color kLampGlow = Color(0xFFFFB454);

/// Smoke, at the spout and at the top of its climb. It leaves warm — it is lit
/// by the flame it just left — and cools to the violet of everything else in
/// the card as it rises and thins.
const Color kSmokeWarm = Color(0xFFFFD6A0);
const Color kSmokeCool = Color(0xFFC9B6F0);

/// The brass, from the lit edge to the shaded underside.
const Color kBrassLight = Color(0xFFFFE2A8);
const Color kBrassMid = Color(0xFFD9993F);
const Color kBrassDark = Color(0xFF6B3D15);

/// The flame's core and its halo.
const Color kFlameCore = Color(0xFFFFF6DC);
const Color kFlameEdge = Color(0xFFFF9A2E);

/// One rising puff of smoke.
///
/// Every field is dimensionless: [LampPainter] scales them against the lamp and
/// the card, so the same field draws correctly at every size the grid allows.
@immutable
class SmokePuff {
  const SmokePuff({
    required this.phase,
    required this.period,
    required this.rise,
    required this.lean,
    required this.sway,
    required this.swayTurns,
    required this.swayPhase,
    required this.radius,
    required this.growth,
    required this.opacity,
  });

  /// Where in its climb this puff starts, 0..1, so the plume is continuous from
  /// the first frame rather than beginning as a gap.
  final double phase;

  /// Seconds for one climb.
  final double period;

  /// How far up the card the puff gets, as a fraction of the card's height.
  final double rise;

  /// How far the plume leans as it climbs, as a fraction of the card's width.
  /// Negative is towards the spout's side.
  final double lean;

  /// The width of the puff's side-to-side wander, and how many turns of it fit
  /// into one climb.
  final double sway;
  final double swayTurns;
  final double swayPhase;

  /// Starting radius as a fraction of the lamp's width, and what it multiplies
  /// by over the climb — smoke spreads as it cools.
  final double radius;
  final double growth;

  /// Peak alpha, reached early and gone by the top.
  final double opacity;
}

/// A spark riding the plume: brighter, smaller and quicker than the smoke.
@immutable
class LampEmber {
  const LampEmber({
    required this.phase,
    required this.period,
    required this.rise,
    required this.drift,
    required this.size,
  });

  final double phase;
  final double period;
  final double rise;
  final double drift;
  final double size;
}

/// A fixed speck of sky, twinkling.
@immutable
class LampStar {
  const LampStar({
    required this.x,
    required this.y,
    required this.radius,
    required this.period,
    required this.phase,
  });

  /// Normalized position in the card, 0..1.
  final double x;
  final double y;

  final double radius;
  final double period;
  final double phase;
}

/// Everything the scene draws, as numbers.
@immutable
class LampField {
  const LampField({
    required this.puffs,
    required this.embers,
    required this.stars,
  });

  final List<SmokePuff> puffs;
  final List<LampEmber> embers;
  final List<LampStar> stars;

  /// The seed every surface builds with.
  ///
  /// Fixed, so the same smoke curls the same way on both monitors and across a
  /// restart. `SkyField`'s rule, and the reason it is one.
  static const int defaultSeed = 0x1A3DD1;

  /// How many puffs are in the air at once.
  ///
  /// Each one is a blurred circle, so this is the card's per-frame cost and the
  /// number is chosen against that rather than against how a plume looks in
  /// still frames: fourteen overlapping puffs already read as continuous smoke,
  /// and the ones past that are paying full price to be invisible underneath.
  static const int puffCount = 14;

  static const int emberCount = 9;
  static const int starCount = 26;

  static LampField build({int seed = defaultSeed}) {
    final random = math.Random(seed);

    double between(double min, double max) =>
        min + random.nextDouble() * (max - min);

    return LampField(
      puffs: [
        for (var i = 0; i < puffCount; i++)
          SmokePuff(
            // Spread evenly and then jittered, rather than taken at random:
            // uniform random phases clump, and a clump in a plume reads as the
            // lamp coughing.
            phase: (i / puffCount + between(-0.03, 0.03)) % 1.0,
            period: between(9.0, 15.0),
            rise: between(0.62, 1.08),
            lean: between(-0.30, -0.10),
            sway: between(0.04, 0.11),
            swayTurns: between(1.0, 2.2),
            swayPhase: between(0, math.pi * 2),
            radius: between(0.05, 0.11),
            growth: between(2.2, 3.6),
            opacity: between(0.12, 0.24),
          ),
      ],
      embers: [
        for (var i = 0; i < emberCount; i++)
          LampEmber(
            phase: (i / emberCount + between(-0.05, 0.05)) % 1.0,
            period: between(3.5, 7.0),
            rise: between(0.25, 0.6),
            drift: between(-0.14, -0.02),
            size: between(0.6, 1.5),
          ),
      ],
      stars: [
        for (var i = 0; i < starCount; i++)
          LampStar(
            x: between(0.02, 0.98),
            // The top two-thirds only: the bottom of the card is where the lamp
            // and the readout are, and a star behind either is a smudge.
            y: between(0.03, 0.62),
            radius: between(0.5, 1.5),
            period: between(2.5, 6.5),
            phase: between(0, math.pi * 2),
          ),
      ],
    );
  }
}

/// Where the lamp sits inside the card, and where its spout points.
///
/// Pure geometry, separated from the painting for `desktop_layout.dart`'s
/// reason: the widget needs the spout's position to decide how much of the card
/// the text may have, and the tap target for "rub the lamp" is this rect. Both
/// would otherwise be numbers copied out of the painter and left to drift.
@immutable
class LampGeometry {
  const LampGeometry(this.rect);

  /// The lamp's own box, bottom-right of the card.
  final Rect rect;

  /// The lamp's box for a card of [size].
  ///
  /// Sized against **both** edges: a lamp taken from the width alone fills a
  /// short wide card top to bottom and leaves the fortune nowhere to go, and one
  /// taken from the height alone shrinks to a bead on a wide one.
  factory LampGeometry.forCard(Size size) {
    final width = math.min(size.width * 0.42, size.height * 0.78);
    // The lamp drawing is wider than it is tall — a squat body with a spout out
    // to one side — and this ratio is what the paths below are laid out in.
    final height = width * _aspect;
    return LampGeometry(
      Rect.fromLTWH(
        size.width - width - size.width * 0.02,
        size.height - height - size.height * 0.04,
        width,
        height,
      ),
    );
  }

  /// Height over width for the lamp's paths.
  static const double _aspect = 0.72;

  /// The spout's mouth — where the flame burns and the smoke leaves from.
  Offset get spout =>
      Offset(rect.left + rect.width * 0.06, rect.top + rect.height * 0.30);

  /// The pointer target for the lamp, which is a *tap* target rather than a
  /// tight outline: the body is the part anybody aims at, and hit-testing the
  /// spout's horn would be a two-pixel sliver.
  Rect get tapTarget => Rect.fromCenter(
        center: Offset(
          rect.left + rect.width * 0.52,
          rect.top + rect.height * 0.62,
        ),
        width: rect.width * 0.78,
        height: rect.height * 0.62,
      );

  /// The box the fortune is set in: above the lamp where there is room for it,
  /// and beside the lamp where there is not.
  ///
  /// Above is the default because it is the **wider** of the two, and width is
  /// what a paragraph wants: the same fortune set in a 250px measure and in a
  /// 145px one is four comfortable lines against nine narrow ones, and the
  /// narrow column is what the card looks like when it has gone wrong. Picking
  /// by area instead — the obvious rule — chooses the ribbon on nearly every
  /// card, because a full-height column beside the lamp is always the larger
  /// rectangle and never the better one.
  ///
  /// Beside is therefore the *fallback*, for the shape that leaves nothing
  /// above the lamp at all: a one-row widget, or a six-column one left one row
  /// tall. It is chosen on a height threshold rather than a span, because the
  /// two shapes cross over at a different place for every cell size the user
  /// can configure — a 3x2 widget is 312x204 on the default grid and 132x84 on
  /// a 32px one, and the same rule has to be right for both.
  ///
  /// [reserve] is the refresh button's corner, taken off the *above* candidate
  /// only — in the beside layout that corner is over the lamp's own smoke,
  /// where there is no text to collide with.
  Rect textArea(
    Size card, {
    required double padding,
    required double reserve,
  }) {
    Rect box(double left, double top, double right, double bottom) =>
        Rect.fromLTWH(
          left,
          top,
          math.max(0, right - left),
          math.max(0, bottom - top),
        );

    final above = box(
      padding,
      padding,
      card.width - padding - reserve,
      rect.top - padding,
    );
    if (above.width >= minTextWidth && above.height >= minTextHeight) {
      return above;
    }

    final beside = box(
      padding,
      padding,
      rect.left - padding,
      card.height - padding,
    );
    if (beside.width >= minTextWidth && beside.height > above.height) {
      return beside;
    }

    // Neither is really big enough — a card at the widget's own floor. Above
    // keeps the full measure, and `fitFortuneText` ellipsises what will not go.
    return above;
  }

  /// The narrowest column the fortune may be set in. Below this a line holds
  /// two or three words, which is a ribbon rather than a paragraph.
  static const double minTextWidth = 96;

  /// The shortest box worth setting a fortune in above the lamp — three lines
  /// at the text ladder's own floor. Under it the card is a strip, and the
  /// fortune goes beside the lamp instead.
  static const double minTextHeight = 44;
}

/// The shortest gap between repaints, in seconds. See [kSkyFrameInterval].
const double kLampFrameInterval = kSkyFrameInterval;

/// Paints a [LampField].
///
/// Public so a paint-counting test can drive it directly, at a chosen time,
/// with no ticker involved.
class LampPainter extends CustomPainter {
  LampPainter({
    required this.field,
    required this.time,
    this.glow = 0,
  }) : super(repaint: time);

  final LampField field;
  final ValueListenable<double> time;

  /// 0..1, how hard the lamp is being looked at — the pointer resting on it
  /// brightens the flame. A hover cue on a picture rather than on a control:
  /// there is no rim to light up and a cursor change alone does not say that
  /// the lamp is the thing to press.
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = time.value;
    final lamp = LampGeometry.forCard(size);

    _paintSky(canvas, size);
    _paintStars(canvas, size, t);
    _paintGlow(canvas, size, lamp);
    _paintSmoke(canvas, size, lamp, t);
    _paintLamp(canvas, lamp.rect);
    _paintFlame(canvas, lamp, t);
    _paintEmbers(canvas, size, lamp, t);
  }

  void _paintSky(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kLampSkyTop, kLampSkyMiddle, kLampSkyHorizon],
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
  }

  void _paintStars(Canvas canvas, Size size, double t) {
    final paint = Paint();
    for (final star in field.stars) {
      // Between a third and full brightness: a star that goes fully out reads
      // as a dead pixel rather than as twinkling.
      final twinkle =
          0.65 + 0.35 * math.sin(t * (math.pi * 2 / star.period) + star.phase);
      paint.color = kSmokeCool.withValues(alpha: 0.55 * twinkle);
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.radius,
        paint,
      );
    }
  }

  void _paintGlow(Canvas canvas, Size size, LampGeometry lamp) {
    final radius = math.max(size.width, size.height) * 0.55;
    final rect = Rect.fromCircle(center: lamp.spout, radius: radius);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            kLampGlow.withValues(alpha: 0.30 + 0.10 * glow),
            kLampGlow.withValues(alpha: 0.10 + 0.04 * glow),
            kLampGlow.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.35, 1.0],
        ).createShader(rect),
    );
  }

  void _paintSmoke(Canvas canvas, Size size, LampGeometry lamp, double t) {
    final origin = lamp.spout;
    final unit = lamp.rect.width;

    for (final puff in field.puffs) {
      final u = ((t / puff.period) + puff.phase) % 1.0;

      // Alpha in and out over the climb: smoke is densest just above the spout
      // and gone by the top. The curve is `sin(pi*u)` skewed early — a puff that
      // faded symmetrically would be at its most solid halfway up the card,
      // which is where the fortune is.
      final fade = math.sin(math.pi * math.pow(u, 0.75).toDouble());
      final alpha = puff.opacity * fade;
      if (alpha <= 0.004) continue;

      final radius = unit * puff.radius * (1 + (puff.growth - 1) * u);
      final sway = math.sin(u * math.pi * 2 * puff.swayTurns + puff.swayPhase);

      final center = Offset(
        origin.dx + size.width * (puff.lean * u + puff.sway * sway * u),
        origin.dy - size.height * puff.rise * u,
      );

      canvas.drawCircle(
        center,
        radius,
        Paint()
          // Warm at the spout, cooling as it climbs — the puff is lit by the
          // flame it just left, and stops being once it is away from it.
          ..color = Color.lerp(kSmokeWarm, kSmokeCool, math.min(1.0, u * 1.6))!
              .withValues(alpha: alpha)
          // Blurred rather than a radial-gradient shader per puff: one
          // `MaskFilter` on a solid circle is the cheaper of the two and the
          // edge is softer, which is the whole difference between smoke and a
          // bubble.
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.42),
      );
    }
  }

  void _paintEmbers(Canvas canvas, Size size, LampGeometry lamp, double t) {
    final origin = lamp.spout;
    final paint = Paint();

    for (final ember in field.embers) {
      final u = ((t / ember.period) + ember.phase) % 1.0;
      final alpha = math.sin(math.pi * u) * 0.85;
      if (alpha <= 0.01) continue;

      paint
        ..color = Color.lerp(kFlameCore, kFlameEdge, u)!.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, ember.size * 0.8);

      canvas.drawCircle(
        Offset(
          origin.dx + size.width * ember.drift * u,
          origin.dy - size.height * ember.rise * u,
        ),
        ember.size,
        paint,
      );
    }
  }

  /// The lamp, in the normalized coordinates the shapes were laid out in.
  ///
  /// Every number below is a fraction of [rect], so the drawing is the same
  /// picture at 90px and at 400 — which is the range the grid actually hands
  /// this widget.
  void _paintLamp(Canvas canvas, Rect rect) {
    double x(double f) => rect.left + rect.width * f;
    double y(double f) => rect.top + rect.height * f;
    Offset p(double fx, double fy) => Offset(x(fx), y(fy));

    final brass = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [kBrassLight, kBrassMid, kBrassDark],
        stops: [0.0, 0.45, 1.0],
      ).createShader(rect);

    // The foot, then the body, then the lid: back to front, so each sits on
    // the one behind it without a seam.
    canvas.drawOval(
      Rect.fromCenter(center: p(0.52, 0.90), width: rect.width * 0.40,
          height: rect.height * 0.11),
      brass,
    );
    canvas.drawPath(
      Path()
        ..moveTo(x(0.38), y(0.74))
        ..lineTo(x(0.66), y(0.74))
        ..lineTo(x(0.62), y(0.90))
        ..lineTo(x(0.42), y(0.90))
        ..close(),
      brass,
    );

    // The spout: a horn out of the body's left side, tapering to the mouth the
    // smoke leaves by. Drawn before the body so its wide end disappears under
    // the belly instead of ending in a visible join.
    canvas.drawPath(
      Path()
        ..moveTo(x(0.30), y(0.50))
        ..quadraticBezierTo(x(0.16), y(0.36), x(0.045), y(0.27))
        ..lineTo(x(0.09), y(0.40))
        ..quadraticBezierTo(x(0.18), y(0.52), x(0.32), y(0.66))
        ..close(),
      brass,
    );

    // The handle, on the side away from the spout.
    canvas.drawPath(
      Path()
        ..moveTo(x(0.80), y(0.52))
        ..quadraticBezierTo(x(1.00), y(0.56), x(0.92), y(0.74))
        ..quadraticBezierTo(x(0.88), y(0.82), x(0.80), y(0.78)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rect.width * 0.045
        ..strokeCap = StrokeCap.round
        ..shader = brass.shader,
    );

    canvas.drawOval(
      Rect.fromCenter(center: p(0.53, 0.62), width: rect.width * 0.66,
          height: rect.height * 0.42),
      brass,
    );

    // The lid and its knob.
    canvas.drawPath(
      Path()
        ..moveTo(x(0.38), y(0.47))
        ..quadraticBezierTo(x(0.53), y(0.30), x(0.68), y(0.47))
        ..close(),
      brass,
    );
    canvas.drawCircle(p(0.53, 0.29), rect.width * 0.035, brass);

    // The lit edge along the top-left of the belly, and the shaded crescent
    // under it. Two strokes are what turn a filled oval into metal.
    canvas.drawArc(
      Rect.fromCenter(center: p(0.53, 0.62), width: rect.width * 0.56,
          height: rect.height * 0.34),
      math.pi * 1.08,
      math.pi * 0.62,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, rect.width * 0.022)
        ..strokeCap = StrokeCap.round
        ..color = kBrassLight.withValues(alpha: 0.75),
    );
    canvas.drawArc(
      Rect.fromCenter(center: p(0.53, 0.64), width: rect.width * 0.60,
          height: rect.height * 0.36),
      math.pi * 0.10,
      math.pi * 0.62,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, rect.width * 0.026)
        ..strokeCap = StrokeCap.round
        ..color = kBrassDark.withValues(alpha: 0.55),
    );
  }

  void _paintFlame(Canvas canvas, LampGeometry lamp, double t) {
    // Two sine terms at rates that do not divide into each other, so the
    // flicker never falls into a visible loop the way one term does.
    final flicker = 1 +
        0.14 * math.sin(t * 7.3) +
        0.07 * math.sin(t * 11.9 + 1.4) +
        0.10 * glow;
    final height = lamp.rect.height * 0.20 * flicker;
    final width = lamp.rect.width * 0.075 * flicker;
    final base = lamp.spout;

    final flame = Path()
      ..moveTo(base.dx - width, base.dy)
      ..quadraticBezierTo(
          base.dx - width * 0.9, base.dy - height * 0.7, base.dx, base.dy - height)
      ..quadraticBezierTo(
          base.dx + width * 0.9, base.dy - height * 0.7, base.dx + width, base.dy)
      ..quadraticBezierTo(base.dx, base.dy + height * 0.22,
          base.dx - width, base.dy);

    canvas.drawPath(
      flame,
      Paint()
        ..shader = RadialGradient(
          colors: [kFlameCore, kFlameEdge, kFlameEdge.withValues(alpha: 0)],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(
          Rect.fromCircle(center: base, radius: height),
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.35),
    );
  }

  @override
  bool shouldRepaint(LampPainter oldDelegate) =>
      oldDelegate.field != field || oldDelegate.glow != glow;
}

/// The animated scene, sized to whatever it is given.
class LampScene extends StatefulWidget {
  const LampScene({
    super.key,
    this.animate = true,
    this.glow = 0,
    this.field,
  });

  /// Whether the ticker runs. False paints a still frame and starts nothing —
  /// which is what a widget test wants, since a [Ticker] never settles.
  final bool animate;

  /// 0..1; see [LampPainter.glow].
  final double glow;

  /// The field to draw. Defaults to the shared one — built once for the
  /// process, because it is the same numbers on every monitor and rebuilding it
  /// per surface would be the only allocation on this card that scales with
  /// display count.
  final LampField? field;

  static final LampField sharedField = LampField.build();

  @override
  State<LampScene> createState() => _LampSceneState();
}

class _LampSceneState extends State<LampScene>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _time = ValueNotifier(0);
  late final Ticker _ticker = createTicker(_onTick);

  /// The last value published, for the frame cap.
  double _published = -1;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _ticker.start();
  }

  @override
  void didUpdateWidget(LampScene oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    if (_published >= 0 && now - _published < kLampFrameInterval) return;
    _published = now;
    // Wrapped at an hour, for `weather_sky.dart`'s reason: every motion here is
    // periodic in well under that, and an unbounded seconds value loses its
    // fractional bits to float precision after a few days of uptime — which a
    // wallpaper widget certainly sees.
    _time.value = now % 3600;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: LampPainter(
          field: widget.field ?? LampScene.sharedField,
          time: _time,
          glow: widget.glow,
        ),
        // A painter with no child paints nothing unless it is given a size, and
        // this one is the whole background of a card the grid sizes.
        size: Size.infinite,
      ),
    );
  }
}

/// The veil that guarantees the fortune is legible over the picture.
///
/// Diagonal rather than [SkyScrim]'s bottom-up: the readout on this card is set
/// in the *top-left*, away from the lamp, so what has to be darkened is the
/// corner opposite the one with the light in it. Dimming the lamp's own corner
/// would be dimming the point.
class LampScrim extends StatelessWidget {
  const LampScrim({super.key, this.strength = 0.42});

  final double strength;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF120B22).withValues(alpha: strength),
            const Color(0xFF120B22).withValues(alpha: strength * 0.5),
            const Color(0xFF120B22).withValues(alpha: 0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}
