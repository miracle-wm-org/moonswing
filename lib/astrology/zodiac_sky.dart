// The picture the astrology card sits on: a night sky with the sign's own
// constellation drawn in it.
//
// `moon_render.dart`'s `MoonNightSky` and `weather_sky.dart`'s field, and it
// keeps both of their rules:
//
// - **Nothing moves.** No `Ticker`, no `ValueNotifier` handed to a painter, no
//   per-frame repaint. The sky changes when the sign does, which is when the
//   user edits their birthday, and costs nothing at all in between — a
//   decoration on a wallpaper, on a machine that may be doing nothing else, has
//   no business repainting. A tree containing this may be `pumpAndSettle`ed.
// - **The layout is data, built once from a fixed seed.** The background field
//   is a top-level list in unit coordinates, so the same sky is drawn on every
//   monitor and across a restart. A field that reshuffled itself on every
//   rebuild would be the most distracting thing on the desktop and — with
//   nothing else moving — the only thing that ever changed.
//
// What is its own: **the figure is not decoration.** Every dot in it is a
// catalogued star at its catalogued position, drawn at a radius taken from its
// magnitude (see `constellation.dart`), so the picture is a star chart of the
// constellation the sign is named for. The scattered field behind it is the
// decoration, and it is deliberately dimmer than the figure so the two never
// compete.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:graceful_shell/astrology/constellation.dart';
import 'package:graceful_shell/astrology/zodiac.dart';

/// The night, top to bottom.
const Color _zenith = Color(0xFF151A35);
const Color _middle = Color(0xFF0C1020);
const Color _horizon = Color(0xFF07080F);

/// How far the element's tint is allowed to move the zenith.
///
/// Decoration, and the one thing on this card that is: the elements are a
/// classical attribution, not a measurement, so tinting the sky by them says
/// nothing the card is not already saying in words. It is kept to a wash
/// because twelve signs that all looked alike is the thing it is fixing, and a
/// sky that looked *invented* is the thing it must not become.
const double _elementTint = 0.22;

Color _tintFor(ZodiacElement element) => switch (element) {
      ZodiacElement.fire => const Color(0xFF3A1E2C),
      ZodiacElement.earth => const Color(0xFF16281F),
      ZodiacElement.air => const Color(0xFF1C2A3E),
      ZodiacElement.water => const Color(0xFF14243A),
    };

/// One star of the scattered field behind the figure.
@immutable
class SkyDust {
  const SkyDust(this.x, this.y, this.radius, this.alpha);

  final double x;
  final double y;
  final double radius;
  final double alpha;
}

/// The number of background stars. Enough to read as a sky, few enough that the
/// figure is still the thing the eye lands on.
const int _dustCount = 78;

/// Fixed, so the same sky is drawn on every monitor and across a restart.
const int _dustSeed = 0x2A17;

/// The scattered field, built once.
final List<SkyDust> kSkyDust = _buildDust();

List<SkyDust> _buildDust() {
  final random = math.Random(_dustSeed);
  return List<SkyDust>.generate(_dustCount, (_) {
    // Cubed, so most of the field is faint and a handful stand out — a uniform
    // brightness reads as a texture rather than as stars.
    final t = random.nextDouble();
    final brightness = t * t * t;
    return SkyDust(
      random.nextDouble(),
      random.nextDouble(),
      0.5 + brightness * 1.1,
      0.14 + brightness * 0.5,
    );
  });
}

/// The card's backdrop: the night, the field, and [sign]'s constellation.
///
/// A null [sign] — no birthday configured — draws the night and the field and
/// no figure. There is no placeholder constellation: drawing somebody else's
/// sign under a "set your birthday" prompt would be the card answering a
/// question it has just said it cannot answer.
class ZodiacSky extends StatelessWidget {
  const ZodiacSky({super.key, required this.sign});

  final ZodiacSign? sign;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: ZodiacSkyPainter(sign: sign),
        size: Size.infinite,
      ),
    );
  }
}

/// Paints [ZodiacSky].
class ZodiacSkyPainter extends CustomPainter {
  const ZodiacSkyPainter({required this.sign});

  final ZodiacSign? sign;

  /// The figure's square, as a fraction of the card's shorter edge, and where
  /// its centre sits.
  ///
  /// Right of centre and a little high, because the readout is set from the top
  /// left and this is what keeps the brightest part of the chart out from under
  /// it. The square is [_figureSquare] of the *shorter* edge so the figure is
  /// never stretched — `constellation.dart` scales both axes by one factor for
  /// the same reason, and letterboxing here is the other half of it.
  static const double _figureSquare = 0.94;
  static const double _figureCentreX = 0.58;
  static const double _figureCentreY = 0.44;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    final sign = this.sign;
    final zenith = sign == null
        ? _zenith
        : Color.lerp(_zenith, _tintFor(sign.element), _elementTint)!;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [zenith, _middle, _horizon],
          const [0.0, 0.6, 1.0],
        ),
    );

    final dust = Paint();
    for (final star in kSkyDust) {
      dust.color = const Color(0xFFF2F5FF).withValues(alpha: star.alpha);
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.radius,
        dust,
      );
    }

    if (sign == null) return;
    final figure = constellationFor(sign.constellationCode);
    if (figure == null) return;
    _paintFigure(canvas, size, figure);
  }

  void _paintFigure(Canvas canvas, Size size, Constellation figure) {
    final side = math.min(size.width, size.height) * _figureSquare;
    final origin = Offset(
      size.width * _figureCentreX - side / 2,
      size.height * _figureCentreY - side / 2,
    );
    Offset at(ConstellationStar star) =>
        origin + Offset(star.x * side, star.y * side);

    // The strokes first, so a star's disc always sits on top of the lines
    // meeting it rather than being cut by them.
    final strokes = Path();
    for (final segment in figure.lines) {
      var first = true;
      for (final index in segment) {
        if (index < 0 || index >= figure.stars.length) continue;
        final point = at(figure.stars[index]);
        if (first) {
          strokes.moveTo(point.dx, point.dy);
          first = false;
        } else {
          strokes.lineTo(point.dx, point.dy);
        }
      }
    }
    canvas.drawPath(
      strokes,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.7, side / 260)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF9FB6E8).withValues(alpha: 0.34),
    );

    // A star's radius comes from its magnitude, which runs *backwards* — 1.0 is
    // bright, 6.0 is at the limit of the eye. Scaled off the figure's own
    // square, so a card twice the size draws the same chart rather than the
    // same chart with bigger gaps.
    final unit = side / 200;
    final disc = Paint();
    final glow = Paint()
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3);
    for (final star in figure.stars) {
      final brightness = ((5.0 - star.magnitude) / 4.0).clamp(0.0, 1.25);
      final radius = unit * (0.9 + 2.3 * brightness);
      final centre = at(star);
      if (brightness > 0.72) {
        // The named stars — Regulus, Antares, Spica, Aldebaran. A halo rather
        // than a bigger disc: a chart whose brightest stars are simply large
        // circles reads as a diagram, and these are the ones somebody standing
        // outside would actually pick out.
        glow.color = const Color(0xFFCFE0FF)
            .withValues(alpha: (0.10 + 0.16 * brightness).clamp(0.0, 1.0));
        canvas.drawCircle(centre, radius * 2.6, glow);
      }
      disc.color = const Color(0xFFFFFFFF)
          .withValues(alpha: (0.52 + 0.42 * brightness).clamp(0.0, 1.0));
      canvas.drawCircle(centre, radius, disc);
    }
  }

  @override
  bool shouldRepaint(ZodiacSkyPainter oldDelegate) => oldDelegate.sign != sign;
}
