/// The procedural materials, each drawn once as a seamless tile.
///
/// A tile is generated at the screen's pixel density, cached as a `ui.Image`
/// ([MaterialTiles]) and painted through an [ImageShader] that repeats it — so
/// the thousands of grain lines, stones and ridges below are walked **once per
/// material and tint**, never per frame and never per surface. Every bar on
/// every monitor, every popup and every root shares the same tile: the shell is
/// one isolate, and an image made in it is good in any of its views.
///
/// Every tile is drawn in one canonical frame: **x runs along the grain** — the
/// length of a plank, the axis of a trunk — and y across it. A surface whose
/// grain runs some other way rotates the shader, never the drawing
/// ([materialShaderTransform]).
///
/// Seamless is a property each painter has to earn: anything near one edge is
/// drawn again one tile over, and anything that wanders (a grain line, a
/// ridge) wanders on [PeriodicNoise1D], whose lattice closes on itself at the
/// tile's edge.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:moonswing/decor/seeded_random.dart';
import 'package:moonswing/theme/surface_material.dart';

/// [color] moved along its lightness ramp by [amount] (−1…1), hue and
/// saturation kept, opaque.
Color shade(Color color, double amount) {
  final hsl = HSLColor.fromColor(color.withValues(alpha: 1));
  return hsl.withLightness(unit(hsl.lightness + amount)).toColor();
}

/// [color] with its hue turned by [degrees] and saturation scaled by [sat].
Color tone(Color color, {double degrees = 0, double sat = 1, double light = 0}) {
  final hsl = HSLColor.fromColor(color.withValues(alpha: 1));
  return hsl
      .withHue((hsl.hue + degrees) % 360)
      .withSaturation(unit(hsl.saturation * sat))
      .withLightness(unit(hsl.lightness + light))
      .toColor();
}

/// A tile's size in logical pixels, in the canonical frame (x along the
/// grain).
Size materialTileSize(SurfaceMaterial material) => switch (material) {
      SurfaceMaterial.wood => const Size(384, 96),
      SurfaceMaterial.stone => const Size(168, 168),
      SurfaceMaterial.bark => const Size(208, 120),
      SurfaceMaterial.moss => const Size(128, 128),
      SurfaceMaterial.none => const Size(1, 1),
    };

/// Draws [material]'s tile, in [tint], into [canvas] over
/// [materialTileSize]. Pure drawing: the caller owns the recorder.
void paintMaterialTile(Canvas canvas, SurfaceMaterial material, Color tint) {
  final size = materialTileSize(material);
  final seed = mixSeed([material.index, 0x5EED]);
  switch (material) {
    case SurfaceMaterial.wood:
      _paintWood(canvas, size, tint, SeededRandom(seed));
    case SurfaceMaterial.stone:
      _paintStone(canvas, size, tint, SeededRandom(seed));
    case SurfaceMaterial.bark:
      _paintBark(canvas, size, tint, SeededRandom(seed));
    case SurfaceMaterial.moss:
      _paintMoss(canvas, size, tint, SeededRandom(seed));
    case SurfaceMaterial.none:
      break;
  }
}

// ---------------------------------------------------------------------------
// Wood
// ---------------------------------------------------------------------------

/// Two boards to a tile, each with its own tone, a butt joint or two, a knot
/// or two that the grain swings round, and forty-odd grain lines wandering on
/// two scales.
void _paintWood(Canvas canvas, Size size, Color tint, SeededRandom rng) {
  final w = size.width;
  final h = size.height;
  canvas.drawRect(Offset.zero & size, Paint()..color = shade(tint, 0));
  const boards = 2;
  final boardH = h / boards;

  for (var b = 0; b < boards; b++) {
    final top = b * boardH;
    final board = Rect.fromLTWH(0, top, w, boardH);
    final boardTone = tone(tint,
        degrees: rng.jitter(4), light: rng.jitter(0.045), sat: rng.range(0.9, 1.1));
    // The board's own sheen: lighter through its middle, as a plank's crown
    // catches more light than its edges.
    canvas.drawRect(
      board,
      Paint()
        ..shader = ui.Gradient.linear(
          board.topCenter,
          board.bottomCenter,
          [shade(boardTone, -0.05), shade(boardTone, 0.035), shade(boardTone, -0.06)],
          const [0.0, 0.45, 1.0],
        ),
    );

    // Knots, wrapped across the tile's long edge.
    final knots = <(double, double, double)>[];
    final knotCount = rng.nextInt(3);
    for (var k = 0; k < knotCount; k++) {
      knots.add((
        rng.range(0, w),
        top + rng.range(boardH * 0.25, boardH * 0.75),
        rng.range(3.2, 6.5),
      ));
    }

    canvas.save();
    canvas.clipRect(board);
    final lines = (boardH / 1.7).round();
    final noise = PeriodicNoise1D(rng.nextUint32(), 12);
    final drift = PeriodicNoise1D(rng.nextUint32(), 5);
    for (var i = 0; i < lines; i++) {
      final y0 = top + (i + rng.range(0.1, 0.9)) * (boardH / lines);
      final amp = rng.range(0.8, 2.6);
      final phase = rng.range(0, 12);
      final path = Path();
      for (var x = 0.0; x <= w + 0.01; x += 3) {
        final u = x / w;
        var y = y0 +
            amp * noise.fbm(u * 12 + phase) +
            1.8 * drift.at(u * 5 + i * 0.05);
        for (final (kx, ky, r) in knots) {
          final dx = _wrapped(x - kx, w);
          final dy = y0 - ky;
          final reach = r * 2.4;
          final fall = math.exp(-(dx * dx) / (2 * reach * reach));
          final near = math.exp(-dy.abs() / (r * 2.2));
          y += (dy >= 0 ? 1 : -1) * r * 1.7 * fall * near;
        }
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final dark = rng.chance(0.7);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rng.range(0.45, 1.25)
          ..color = (dark
                  ? shade(boardTone, -rng.range(0.08, 0.2))
                  : shade(boardTone, rng.range(0.04, 0.1)))
              .withValues(alpha: rng.range(0.35, 0.8)),
      );
    }

    // Pores: short dashes along the grain, the texture under the figure.
    final pores = Float32List(2 * 2 * 260);
    for (var p = 0; p < 260; p++) {
      final x = rng.range(0, w);
      final y = top + rng.range(0, boardH);
      final len = rng.range(1.0, 3.5);
      pores
        ..[p * 4] = x
        ..[p * 4 + 1] = y
        ..[p * 4 + 2] = x + len
        ..[p * 4 + 3] = y;
    }
    canvas.drawRawPoints(
      ui.PointMode.lines,
      pores,
      Paint()
        ..strokeWidth = 0.6
        ..color = shade(boardTone, -0.18).withValues(alpha: 0.35),
    );

    for (final (kx, ky, r) in knots) {
      for (final dx in [0.0, -w, w]) {
        _paintKnot(canvas, Offset(kx + dx, ky), r, boardTone, rng);
      }
    }

    // Butt joints: where one board ends and the next begins along the run.
    final joints = 1;
    for (var j = 0; j < joints; j++) {
      final x = rng.range(20, w - 20);
      canvas.drawLine(Offset(x, top), Offset(x, top + boardH),
          Paint()
            ..strokeWidth = 1.4
            ..color = shade(boardTone, -0.3).withValues(alpha: 0.9));
      canvas.drawLine(Offset(x + 1.2, top), Offset(x + 1.2, top + boardH),
          Paint()
            ..strokeWidth = 0.7
            ..color = shade(boardTone, 0.12).withValues(alpha: 0.5));
      // Nail heads either side of the joint.
      for (final side in [-4.5, 5.5]) {
        for (final f in [0.3, 0.7]) {
          final c = Offset(x + side, top + boardH * f);
          canvas.drawCircle(c, 1.3, Paint()..color = shade(tint, -0.32));
          canvas.drawCircle(c.translate(-0.35, -0.35), 0.6,
              Paint()..color = shade(tint, 0.05).withValues(alpha: 0.6));
        }
      }
    }
    canvas.restore();

    // The seam between this board and the next: a groove, dark above a lit lip.
    final seamY = top + boardH;
    canvas.drawLine(Offset(0, seamY - 0.6), Offset(w, seamY - 0.6),
        Paint()
          ..strokeWidth = 1.3
          ..color = shade(tint, -0.3).withValues(alpha: 0.95));
    canvas.drawLine(Offset(0, (seamY + 0.7) % h), Offset(w, (seamY + 0.7) % h),
        Paint()
          ..strokeWidth = 0.7
          ..color = shade(tint, 0.12).withValues(alpha: 0.45));
  }
}

void _paintKnot(
    Canvas canvas, Offset c, double r, Color tint, SeededRandom rng) {
  final oval = Rect.fromCenter(center: c, width: r * 2.6, height: r * 1.6);
  canvas.drawOval(
    oval,
    Paint()
      ..shader = ui.Gradient.radial(
        c,
        r * 1.3,
        [shade(tint, -0.34), shade(tint, -0.2), shade(tint, -0.06).withValues(alpha: 0)],
        const [0.0, 0.55, 1.0],
      ),
  );
  for (var ring = 1; ring <= 3; ring++) {
    final f = ring / 3.2;
    canvas.drawOval(
      Rect.fromCenter(center: c, width: r * 2.6 * f, height: r * 1.6 * f),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = shade(tint, -0.4).withValues(alpha: 0.55),
    );
  }
  canvas.drawCircle(c, r * 0.28, Paint()..color = shade(tint, -0.45));
}

/// [d] folded into `(-period/2, period/2]`: the shortest way round a tile.
double _wrapped(double d, double period) {
  var v = d % period;
  if (v > period / 2) v -= period;
  if (v <= -period / 2) v += period;
  return v;
}

// ---------------------------------------------------------------------------
// Stone
// ---------------------------------------------------------------------------

/// Coursed stone: rows of uneven height, each laid with stones of uneven
/// length, every one a slightly bowed and rounded block shaded as a lump lit
/// from the upper left, bedded in thin dark mortar, speckled, sometimes
/// cracked, and with moss gathering in the joints below.
void _paintStone(Canvas canvas, Size size, Color tint, SeededRandom rng) {
  final s = size.width;
  final mortar = shade(tint, -0.22);
  canvas.drawRect(Offset.zero & size, Paint()..color = mortar);
  _speckle(canvas, size, shade(tint, -0.3), 500, rng, alpha: 0.5);

  final mossGreen = HSLColor.fromAHSL(
          1, 95, 0.42, unit(HSLColor.fromColor(tint).lightness * 0.7 + 0.1))
      .toColor();

  // Course heights summing exactly to the tile, so it repeats down as well as
  // along.
  final heights = _partition(rng, s, 4, 0.28);
  var y = 0.0;
  for (final rowH in heights) {
    final widths = _partition(rng, s, 3 + rng.nextInt(2), 0.4);
    var x = rng.range(0, s);
    for (final w in widths) {
      final rect = Rect.fromLTWH(x + 1.1, y + 1.1, w - 2.2, rowH - 2.2);
      final shape = _stoneShape(rng, rect);
      final stoneTone = tone(tint,
          degrees: rng.jitter(12),
          light: rng.jitter(0.06),
          sat: rng.range(0.7, 1.3));
      final crack = rng.chance(0.25);
      final mossy = rng.chance(0.5);
      final detail = rng.nextUint32();
      for (final dx in [-s, 0.0]) {
        for (final dy in [-s, 0.0, s]) {
          if (dy != 0 && y + dy > s) continue;
          _paintStoneBlock(canvas, shape.shift(Offset(dx, dy)),
              rect.shift(Offset(dx, dy)), stoneTone, crack, mossy, mossGreen,
              SeededRandom(detail));
        }
      }
      x += w;
    }
    y += rowH;
  }
}

/// [total] split into [parts] pieces of jittered length that sum to it.
List<double> _partition(SeededRandom rng, double total, int parts, double jitter) {
  final raw = [for (var i = 0; i < parts; i++) 1 + rng.range(-jitter, jitter)];
  final sum = raw.fold(0.0, (a, b) => a + b);
  return [for (final r in raw) r / sum * total];
}

/// A block inside [r]: a rounded rectangle whose four sides bow in or out a
/// little and whose corners are cut unevenly, so no two read as a tile.
Path _stoneShape(SeededRandom rng, Rect r) {
  final rad = math.min(r.width, r.height) * rng.range(0.22, 0.4);
  double j(double v) => rng.jitter(v);
  final tl = r.topLeft.translate(j(1.5), j(1.5));
  final tr = r.topRight.translate(j(1.5), j(1.5));
  final br = r.bottomRight.translate(j(1.5), j(1.5));
  final bl = r.bottomLeft.translate(j(1.5), j(1.5));
  final path = Path()..moveTo(tl.dx + rad, tl.dy);
  void side(Offset a, Offset b, Offset corner, Offset next) {
    final mid = (a + b) / 2;
    final normal = Offset(-(b - a).dy, (b - a).dx) / (b - a).distance;
    final bow = mid + normal * j(1.6);
    path.quadraticBezierTo(bow.dx, bow.dy, b.dx, b.dy);
    path.quadraticBezierTo(corner.dx, corner.dy, next.dx, next.dy);
  }
  side(Offset(tl.dx + rad, tl.dy), Offset(tr.dx - rad, tr.dy), tr,
      Offset(tr.dx, tr.dy + rad));
  side(Offset(tr.dx, tr.dy + rad), Offset(br.dx, br.dy - rad), br,
      Offset(br.dx - rad, br.dy));
  side(Offset(br.dx - rad, br.dy), Offset(bl.dx + rad, bl.dy), bl,
      Offset(bl.dx, bl.dy - rad));
  side(Offset(bl.dx, bl.dy - rad), Offset(tl.dx, tl.dy + rad), tl,
      Offset(tl.dx + rad, tl.dy));
  path.close();
  return path;
}

void _paintStoneBlock(Canvas canvas, Path p, Rect r, Color stoneTone,
    bool crack, bool mossy, Color mossGreen, SeededRandom rng) {
  // Its shadow in the mortar, cast down and right.
  canvas.drawPath(
    p.shift(const Offset(0.8, 1.2)),
    Paint()
      ..color = const Color(0x99000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0),
  );
  final c = r.center;
  final reach = r.longestSide * 0.75;
  canvas.drawPath(
    p,
    Paint()
      ..shader = ui.Gradient.radial(
        c.translate(-r.width * 0.22, -r.height * 0.3),
        reach,
        [shade(stoneTone, 0.12), shade(stoneTone, 0.0), shade(stoneTone, -0.13)],
        const [0.0, 0.55, 1.0],
      ),
  );
  canvas.save();
  canvas.clipPath(p);
  final n = (r.width * r.height / 14).round();
  for (var i = 0; i < n; i++) {
    final o = Offset(r.left + rng.range(0, r.width), r.top + rng.range(0, r.height));
    canvas.drawCircle(
      o,
      rng.range(0.3, 0.85),
      Paint()
        ..color = (rng.chance(0.5) ? shade(stoneTone, 0.17) : shade(stoneTone, -0.17))
            .withValues(alpha: rng.range(0.25, 0.6)),
    );
  }
  // Strata: a couple of faint bands across the block.
  for (var i = 0; i < 2; i++) {
    final yy = r.top + rng.range(0.2, 0.8) * r.height;
    canvas.drawLine(
      Offset(r.left, yy),
      Offset(r.right, yy + rng.jitter(3)),
      Paint()
        ..strokeWidth = rng.range(1.5, 3.5)
        ..color = shade(stoneTone, rng.jitter(0.08)).withValues(alpha: 0.25),
    );
  }
  if (crack) {
    final path = Path()..moveTo(r.left + rng.range(0, r.width), r.top);
    var q = Offset(r.left + rng.range(0, r.width), r.top);
    for (var t = 0.25; t <= 1.0; t += 0.25) {
      q = Offset(q.dx + rng.jitter(5), r.top + r.height * t);
      path.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = shade(stoneTone, -0.3).withValues(alpha: 0.85));
  }
  canvas.restore();
  // The lit shoulder on the upper left, and the turned-away edge below.
  canvas.save();
  canvas.clipRect(Rect.fromLTRB(r.left - 2, r.top - 2, r.right, r.top + r.height * 0.4));
  canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = shade(stoneTone, 0.2).withValues(alpha: 0.6));
  canvas.restore();
  if (mossy) {
    final at = Offset(r.left + rng.range(0.1, 0.9) * r.width, r.bottom);
    _mossClump(canvas, at, rng.range(4, 9), mossGreen, rng);
  }
}

void _mossClump(
    Canvas canvas, Offset at, double size, Color green, SeededRandom rng) {
  for (var i = 0; i < 14; i++) {
    final o = at.translate(rng.jitter(size), rng.jitter(size * 0.6));
    canvas.drawCircle(
      o,
      rng.range(0.6, 1.8),
      Paint()
        ..color = tone(green, degrees: rng.jitter(10), light: rng.jitter(0.08))
            .withValues(alpha: rng.range(0.55, 0.95)),
    );
  }
}

void _speckle(Canvas canvas, Size size, Color color, int count,
    SeededRandom rng, {double alpha = 0.6}) {
  final pts = Float32List(count * 2);
  for (var i = 0; i < count; i++) {
    pts[i * 2] = rng.range(0, size.width);
    pts[i * 2 + 1] = rng.range(0, size.height);
  }
  canvas.drawRawPoints(
    ui.PointMode.points,
    pts,
    Paint()
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: alpha),
  );
}

// ---------------------------------------------------------------------------
// Bark
// ---------------------------------------------------------------------------

/// Plates of bark: ridges running along the trunk, each broken into segments
/// that taper into the fissures between them, lit along one flank and shaded
/// along the other, with lichen on a few.
void _paintBark(Canvas canvas, Size size, Color tint, SeededRandom rng) {
  final l = size.width;
  final d = size.height;
  final fissure = shade(tint, -0.16);
  canvas.drawRect(Offset.zero & size, Paint()..color = fissure);
  // Depth in the fissures: a darker core line down each one is drawn by the
  // plates' own shadows, so the ground only needs grain.
  _speckle(canvas, size, shade(tint, -0.24), 300, rng, alpha: 0.6);

  final lichen = HSLColor.fromAHSL(1, 78, 0.22,
          unit(HSLColor.fromColor(tint).lightness + 0.32))
      .toColor();

  const ridges = 5;
  final spacing = d / ridges;
  for (var r = 0; r < ridges; r++) {
    final y0 = (r + 0.5) * spacing + rng.jitter(spacing * 0.12);
    final halfW = spacing * rng.range(0.5, 0.62);
    final wander = PeriodicNoise1D(rng.nextUint32(), 8);
    final girth = PeriodicNoise1D(rng.nextUint32(), 10);
    // Segments along the run, summing to the tile so the ridge closes on
    // itself, each overlapping the next a little so the fissure between two
    // plates is a pinch rather than a gap.
    var x = rng.range(0, l);
    for (final len in _partition(rng, l, 3 + rng.nextInt(2), 0.45)) {
      final segTone = tone(tint, light: rng.jitter(0.06), degrees: rng.jitter(5));
      final hasLichen = rng.chance(0.18);
      final segSeed = rng.nextUint32();
      for (final dy in [-d, 0.0, d]) {
        for (final dx in [-l, 0.0]) {
          _barkPlate(canvas, x + dx - 3, len + 6, y0 + dy, halfW, wander,
              girth, l, segTone, SeededRandom(segSeed));
        }
      }
      if (hasLichen) {
        final m = SeededRandom(segSeed ^ 0x11C);
        final at = Offset((x + len * m.range(0.2, 0.8)) % l, y0 + m.jitter(halfW * 0.5));
        for (final dx in [-l, 0.0, l]) {
          _lichen(canvas, at.translate(dx, 0), m.range(3, 6), lichen, SeededRandom(segSeed));
        }
      }
      x += len;
    }
  }
}

void _barkPlate(
  Canvas canvas,
  double x0,
  double len,
  double y0,
  double halfW,
  PeriodicNoise1D wander,
  PeriodicNoise1D girth,
  double period,
  Color plateTone,
  SeededRandom rng,
) {
  final top = <Offset>[];
  final bottom = <Offset>[];
  const steps = 14;
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final x = x0 + len * t;
    final u = (x % period) / period;
    final centre = y0 + 3.2 * wander.fbm(u * 8);
    // Tapered at both ends, which is what opens the fissure across the ridge.
    final taper = math.sin(math.pi * t);
    final hw = halfW * (0.7 + 0.3 * girth.at(u * 10).abs()) * math.pow(taper, 0.3);
    top.add(Offset(x, centre - hw));
    bottom.add(Offset(x, centre + hw));
  }
  final path = Path()..moveTo(top.first.dx, top.first.dy);
  for (final p in top.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  for (final p in bottom.reversed) {
    path.lineTo(p.dx, p.dy);
  }
  path.close();

  final bounds = path.getBounds();
  canvas.drawPath(
    path,
    Paint()
      ..shader = ui.Gradient.linear(
        bounds.topCenter,
        bounds.bottomCenter,
        [shade(plateTone, 0.12), shade(plateTone, 0.02), shade(plateTone, -0.14)],
        const [0.0, 0.45, 1.0],
      ),
  );
  // Fibres along the plate.
  canvas.save();
  canvas.clipPath(path);
  for (var i = 0; i < 9; i++) {
    final y = bounds.top + rng.range(0, bounds.height);
    final xs = x0 + rng.range(0, len * 0.6);
    canvas.drawLine(
      Offset(xs, y),
      Offset(xs + rng.range(6, len * 0.5), y + rng.jitter(1.0)),
      Paint()
        ..strokeWidth = rng.range(0.4, 0.9)
        ..color = (rng.chance(0.5) ? shade(plateTone, -0.16) : shade(plateTone, 0.12))
            .withValues(alpha: rng.range(0.3, 0.6)),
    );
  }
  canvas.restore();
  // Lit flank and shadowed flank.
  final lit = Path()..moveTo(top.first.dx, top.first.dy);
  for (final p in top.skip(1)) {
    lit.lineTo(p.dx, p.dy + 0.6);
  }
  canvas.drawPath(
      lit,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = shade(plateTone, 0.2).withValues(alpha: 0.6));
  final dark = Path()..moveTo(bottom.first.dx, bottom.first.dy);
  for (final p in bottom.skip(1)) {
    dark.lineTo(p.dx, p.dy);
  }
  canvas.drawPath(
      dark,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = shade(plateTone, -0.2).withValues(alpha: 0.9));
}

void _lichen(Canvas canvas, Offset at, double size, Color color, SeededRandom rng) {
  for (var i = 0; i < 10; i++) {
    final o = at.translate(rng.jitter(size), rng.jitter(size * 0.7));
    canvas.drawCircle(
      o,
      rng.range(0.8, 2.2),
      Paint()
        ..color = tone(color, light: rng.jitter(0.08))
            .withValues(alpha: rng.range(0.35, 0.7)),
    );
  }
}

// ---------------------------------------------------------------------------
// Moss
// ---------------------------------------------------------------------------

/// A moss bed: soft light and dark patches under a few thousand tufts.
void _paintMoss(Canvas canvas, Size size, Color tint, SeededRandom rng) {
  final s = size.width;
  canvas.drawRect(Offset.zero & size, Paint()..color = shade(tint, -0.12));
  for (var i = 0; i < 26; i++) {
    final c = Offset(rng.range(0, s), rng.range(0, s));
    final r = rng.range(10, 26);
    final light = rng.chance(0.5);
    for (final dx in [-s, 0.0, s]) {
      for (final dy in [-s, 0.0, s]) {
        canvas.drawCircle(
          c.translate(dx, dy),
          r,
          Paint()
            ..color = (light ? shade(tint, 0.08) : shade(tint, -0.1))
                .withValues(alpha: 0.35)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.6),
        );
      }
    }
  }
  final tufts = Float32List(2600 * 4);
  final colors = <Color>[
    shade(tint, 0.14),
    shade(tint, 0.06),
    shade(tint, -0.06),
    shade(tint, -0.18),
  ];
  // Four passes, one colour each, so the tufts can still be one raw draw.
  for (var pass = 0; pass < colors.length; pass++) {
    var n = 0;
    for (var i = 0; i < 650; i++) {
      final x = rng.range(0, s);
      final y = rng.range(0, s);
      final a = rng.range(-math.pi, 0);
      final len = rng.range(1.2, 3.4);
      tufts
        ..[n++] = x
        ..[n++] = y
        ..[n++] = (x + math.cos(a) * len)
        ..[n++] = (y + math.sin(a) * len);
    }
    canvas.drawRawPoints(
      ui.PointMode.lines,
      Float32List.sublistView(tufts, 0, n),
      Paint()
        ..strokeWidth = 0.7
        ..strokeCap = StrokeCap.round
        ..color = colors[pass].withValues(alpha: 0.75),
    );
  }
}
