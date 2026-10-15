/// What grows off a bar: the plan (pure geometry) and its painting.
///
/// **Gravity is the bar's anchor.** Everything here is grown in one canonical
/// frame — x along the bar, y *away from it* into the overhang, so y = 0 is the
/// bar's inner edge and a negative y is on the bar itself — and the only thing
/// the anchor changes is which way is down in that frame. Under a top bar down
/// is +y, so a vine grown with any stiffness at all simply hangs; above a bottom
/// bar down is −y, so the same integrator grows a stem that stands up and arcs
/// over at the tip; beside a side bar down is along x, so a tendril leaves the
/// bar sideways and droops. One grower, three habits, no special cases.
///
/// **Every plant is its own picture, rooted where it leaves the bar**, so a
/// rustle is one rotation per plant about its root — a vine swings from where
/// it hangs — and never a re-record. At rest nothing animates and the whole
/// canopy is one cached layer.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart' show Matrix4;

import 'package:moonswing/decor/material_tiles.dart' show shade, tone;
import 'package:moonswing/decor/seeded_random.dart';
import 'package:moonswing/theme/surface_material.dart';

/// The kinds of plant a recipe is made of. Each sways by its own amount: a
/// long vine swings, a clump of leaves pinned to the bar barely stirs.
enum SprigKind {
  vine(0.13),
  moss(0.17),
  fern(0.08),
  clump(0.045);

  const SprigKind(this.sway);

  /// The largest rustle, in radians, this kind is swung through.
  final double sway;
}

/// One leaf, in its plant's frame: where its stalk meets the stem, which way
/// it points, how long it is, and how it is drawn.
class LeafSpec {
  const LeafSpec({
    required this.at,
    required this.angle,
    required this.length,
    required this.width,
    required this.color,
    this.ivy = false,
  });

  final Offset at;
  final double angle;
  final double length;
  final double width;
  final Color color;

  /// A three-lobed ivy leaf rather than a plain pointed one.
  final bool ivy;
}

/// A berry cluster or a flower.
class BloomSpec {
  const BloomSpec({
    required this.at,
    required this.radius,
    required this.flower,
    required this.color,
    required this.seed,
  });

  final Offset at;
  final double radius;
  final bool flower;
  final Color color;
  final int seed;
}

/// One plant, in coordinates relative to its [root].
class Sprig {
  Sprig({
    required this.kind,
    required this.root,
    required this.depth,
    required this.phase,
    this.stems = const [],
    this.stemWidth = 1.2,
    this.stemColor = const Color(0xFF2E4A26),
    this.leaves = const [],
    this.blooms = const [],
  });

  final SprigKind kind;

  /// Where the plant leaves the bar, in the canonical frame.
  final Offset root;

  /// 0 at the front, 1 at the back: what draws first, and what is shaded.
  final double depth;

  /// Where in its swing this plant starts, so a rustle is not a parade.
  final double phase;

  /// Each stem as a polyline from the root outward (strands, for moss).
  final List<List<Offset>> stems;
  final double stemWidth;
  final Color stemColor;
  final List<LeafSpec> leaves;
  final List<BloomSpec> blooms;

  /// How far this plant reaches from its root, for tests and for culling.
  Rect get bounds {
    var r = Rect.fromCircle(center: Offset.zero, radius: 1);
    for (final s in stems) {
      for (final p in s) {
        r = r.expandToInclude(Rect.fromCircle(center: p, radius: 1));
      }
    }
    for (final l in leaves) {
      r = r.expandToInclude(Rect.fromCircle(center: l.at, radius: l.length));
    }
    for (final b in blooms) {
      r = r.expandToInclude(Rect.fromCircle(center: b.at, radius: b.radius * 3));
    }
    return r;
  }
}

/// Which way is down in the canonical frame, for a bar on [anchor].
Offset foliageGravity(String anchor) => switch (anchor) {
      'bottom' => const Offset(0, -1),
      'left' || 'right' => const Offset(1, 0),
      _ => const Offset(0, 1),
    };

/// Everything that grows off one bar.
class FoliagePlan {
  FoliagePlan(this.sprigs);

  /// Back to front.
  final List<Sprig> sprigs;

  static final FoliagePlan empty = FoliagePlan(const []);
}

/// Grows [style] along a bar [length] long and [thickness] deep, into an
/// overhang of [reach], on [anchor].
///
/// Deterministic in every argument: the same bar grows the same plants on every
/// monitor and every start, which is what lets a mirrored pair of bars, or a
/// restart, show the same picture. [endCaps] is how far the bar's end caps
/// reach, which is where ferns root.
FoliagePlan growFoliage({
  required FoliageStyle style,
  required double length,
  required double thickness,
  required double reach,
  required String anchor,
  required Color leaf,
  required Color bloom,
  double density = 1.0,
  double endCaps = 0.0,
  int seed = 0,
}) {
  if (!style.grows || length <= 0 || reach <= 0 || density <= 0) {
    return FoliagePlan.empty;
  }
  final rng = SeededRandom(
      mixSeed([style.index, length.round(), reach.round(), seed, anchor.hashCode]));
  final g = foliageGravity(anchor);
  final hangs = g.dy > 0.5;
  final stands = g.dy < -0.5;
  final grower = _Grower(
    rng: rng,
    gravity: g,
    reach: reach,
    thickness: thickness,
    length: length,
    leaf: leaf,
    bloom: bloom,
  );

  // Per hundred pixels of bar, before density.
  final (vines, clumps, moss, blooms, ferns) = switch (style) {
    FoliageStyle.ivy => (1.6, 2.6, 0.0, 0.08, 0),
    FoliageStyle.moss => (0.2, 0.6, 2.4, 0.0, 0),
    FoliageStyle.wildwood => (1.3, 2.4, 0.8, 0.3, 4),
    FoliageStyle.none => (0.0, 0.0, 0.0, 0.0, 0),
  };
  int count(double perHundred) {
    final n = perHundred * density * length / 100;
    return n.floor() + (rng.chance(n - n.floor()) ? 1 : 0);
  }

  final sprigs = <Sprig>[];
  // Ferns first and at the back: they spring from the bar's ends.
  if (ferns > 0) {
    final cap = endCaps > 0 ? endCaps : math.min(60.0, length * 0.08);
    for (final end in [0, 1]) {
      final n = (ferns * density).round();
      for (var i = 0; i < n; i++) {
        final along = rng.range(cap * 0.15, cap * 0.95);
        final x = end == 0 ? along : length - along;
        // Fronds lean away from the bar's middle, so the ends frame it.
        final lean = end == 0 ? -1.0 : 1.0;
        sprigs.add(grower.fern(Offset(x, rng.range(-thickness * 0.2, 1.0)),
            lean: lean * rng.range(0.15, 0.7), stands: stands));
      }
    }
  }
  for (var i = 0; i < count(moss); i++) {
    sprigs.add(grower.moss(Offset(grower.place(), rng.range(-1.0, 1.5))));
  }
  for (var i = 0; i < count(vines); i++) {
    sprigs.add(grower.vine(
      Offset(grower.place(), rng.range(-thickness * 0.15, 0.5)),
      ivy: style != FoliageStyle.moss,
      hangs: hangs,
      bloomChance: blooms,
      short: style == FoliageStyle.moss,
    ));
  }
  for (var i = 0; i < count(clumps); i++) {
    sprigs.add(grower.clump(
      Offset(grower.place(), rng.range(-thickness * 0.18, 1.0)),
      ivy: style == FoliageStyle.ivy || rng.chance(0.4),
      bloomChance: blooms * 1.6,
    ));
  }
  sprigs.sort((a, b) => b.depth.compareTo(a.depth));
  return FoliagePlan(sprigs);
}

/// The grower: one integrator for every stem, and the leaf, bloom and colour
/// rules every plant shares.
class _Grower {
  _Grower({
    required this.rng,
    required this.gravity,
    required this.reach,
    required this.thickness,
    required this.length,
    required this.leaf,
    required this.bloom,
  });

  final SeededRandom rng;
  final Offset gravity;
  final double reach;
  final double thickness;
  final double length;
  final Color leaf;
  final Color bloom;

  /// The outward direction: away from the bar.
  static const Offset _out = Offset(0, 1);

  /// How far onto the bar any leaf may reach: a fringe on its edge, never a
  /// curtain over the modules.
  double get _onBar => -thickness * 0.32;

  /// A place along the bar, crowded a little towards the ends, which is where
  /// growth gathers on anything that has ends.
  double place() {
    if (rng.chance(0.35)) {
      final t = math.pow(rng.nextDouble(), 1.8) * 0.22;
      return (rng.chance(0.5) ? t : 1 - t) * length;
    }
    return rng.range(0.02, 0.98) * length;
  }

  double get _depth => rng.nextDouble();

  Color _leafColor(double depth) {
    var c = tone(leaf,
        degrees: rng.jitter(14),
        light: rng.jitter(0.07) - depth * 0.1,
        sat: rng.range(0.8, 1.15));
    // The odd turning leaf, which is what makes a canopy read as alive.
    if (rng.chance(0.06)) {
      c = tone(c, degrees: -rng.range(35, 70), light: 0.05, sat: 1.1);
    }
    return c;
  }

  /// Integrates a stem from [start] in direction [dir] for [steps] of [step],
  /// bent by gravity at [weight] and wandering by [curl].
  List<Offset> _stem(Offset dir, int steps, double step,
      {double weight = 0.12, double curl = 0.25, double stiffness = 1.0}) {
    final pts = <Offset>[Offset.zero];
    var p = Offset.zero;
    var d = dir / dir.distance;
    final wander = rng.range(0, 1000);
    for (var i = 0; i < steps; i++) {
      final perp = Offset(-d.dy, d.dx);
      final w = math.sin(wander + i * 0.45) * curl;
      d = d * stiffness + gravity * weight + perp * w;
      d = d / d.distance;
      p += d * step;
      pts.add(p);
    }
    return pts;
  }

  /// Keeps a stem inside the room it has: the overhang ahead and the fringe of
  /// bar behind, and the bar's own length. A point past either is dropped
  /// along with everything after it.
  List<Offset> _clip(List<Offset> stem, Offset root, {double margin = 6}) {
    final out = <Offset>[];
    for (final p in stem) {
      final q = root + p;
      if (q.dy > reach - margin || q.dy < _onBar || q.dx < 2 || q.dx > length - 2) {
        break;
      }
      out.add(p);
    }
    return out.length < 2 ? const [Offset.zero, Offset(0, 0.1)] : out;
  }

  LeafSpec _leafAlong(List<Offset> stem, int i, double side, double size,
      Color color, {bool ivy = false}) {
    final p = stem[i];
    final q = stem[math.min(i + 1, stem.length - 1)];
    final p0 = stem[math.max(i - 1, 0)];
    var d = q - p0;
    if (d.distance == 0) d = _out;
    d = d / d.distance;
    final perp = Offset(-d.dy, d.dx) * side;
    // Leaves turn out from the stem, droop under their own weight and lean a
    // little the way the stem grows.
    final dir = perp * 0.85 + gravity * 0.55 + d * 0.3;
    return LeafSpec(
      at: p,
      angle: math.atan2(dir.dy, dir.dx) + rng.jitter(0.35),
      length: size,
      width: size * (ivy ? 0.95 : rng.range(0.42, 0.55)),
      color: color,
      ivy: ivy,
    );
  }

  Sprig vine(Offset root,
      {required bool ivy,
      required bool hangs,
      required double bloomChance,
      bool short = false}) {
    final depth = _depth;
    final maxLen = reach * (short ? rng.range(0.15, 0.4) : math.sqrt(rng.nextDouble()) * 0.7 + 0.3);
    const step = 3.0;
    final steps = math.max(4, (maxLen / step).round());
    // Out of the bar, sideways a little; whatever the anchor, a vine *leaves*
    // the bar before gravity takes it.
    final dir = _out + Offset(rng.jitter(0.9), 0);
    final stem = _clip(
      _stem(dir, steps, step,
          weight: hangs ? 0.2 : 0.07,
          curl: rng.range(0.08, 0.22),
          stiffness: hangs ? 0.9 : 1.0),
      root,
    );
    final leaves = <LeafSpec>[];
    final blooms = <BloomSpec>[];
    final spacing = rng.range(2, 4).round();
    var side = rng.chance(0.5) ? 1.0 : -1.0;
    for (var i = 1; i < stem.length; i += spacing) {
      final t = i / stem.length;
      final size = (ivy ? rng.range(9, 13.5) : rng.range(6.5, 10)) * (1 - 0.4 * t);
      leaves.add(_leafAlong(stem, i, side, size, _leafColor(depth), ivy: ivy));
      side = -side;
      if (rng.chance(0.25)) {
        // A second leaf on the same node, the other way.
        leaves.add(_leafAlong(stem, i, side, size * 0.8, _leafColor(depth), ivy: ivy));
      }
    }
    if (rng.chance(bloomChance) && stem.length > 4) {
      blooms.add(_bloom(stem[stem.length * 2 ~/ 3], depth));
    }
    return Sprig(
      kind: SprigKind.vine,
      root: root,
      depth: depth,
      phase: rng.range(0, math.pi * 2),
      stems: [stem],
      stemWidth: rng.range(0.9, 1.5),
      stemColor: shade(tone(leaf, degrees: 25, sat: 0.6), -0.18 - depth * 0.08),
      leaves: leaves,
      blooms: blooms,
    );
  }

  Sprig moss(Offset root) {
    final depth = _depth;
    final strands = <List<Offset>>[];
    final n = 3 + rng.nextInt(5);
    final len = reach * rng.range(0.15, 0.55);
    for (var i = 0; i < n; i++) {
      final dir = _out + Offset(rng.jitter(0.6), 0);
      strands.add(_clip(
        _stem(dir, math.max(3, (len * rng.range(0.5, 1.0) / 2.5).round()), 2.5,
            weight: 0.4, curl: rng.range(0.15, 0.45), stiffness: 0.8),
        root.translate(rng.jitter(3), 0),
        margin: 2,
      ));
    }
    final leaves = <LeafSpec>[
      for (var i = 0; i < 2 + rng.nextInt(3); i++)
        LeafSpec(
          at: Offset(rng.jitter(4), rng.range(-1, 2)),
          angle: math.atan2(gravity.dy, gravity.dx) + rng.jitter(1.2),
          length: rng.range(3, 5.5),
          width: rng.range(1.8, 2.6),
          color: _leafColor(depth),
        ),
    ];
    return Sprig(
      kind: SprigKind.moss,
      root: root,
      depth: depth,
      phase: rng.range(0, math.pi * 2),
      stems: strands,
      stemWidth: rng.range(0.55, 0.9),
      stemColor: tone(leaf, degrees: 18, sat: 0.35, light: 0.1 - depth * 0.08)
          .withValues(alpha: 0.85),
      leaves: leaves,
    );
  }

  Sprig fern(Offset root, {required double lean, required bool stands}) {
    final depth = rng.range(0.3, 1.0);
    final len = math.min(reach * rng.range(0.5, 0.95), 70.0);
    const step = 2.5;
    final dir = _out + Offset(lean, 0);
    final stem = _clip(
      _stem(dir, (len / step).round(), step,
          weight: stands ? 0.06 : 0.1, curl: 0.04, stiffness: 1.0),
      root,
      margin: 3,
    );
    final leaves = <LeafSpec>[];
    final color = _leafColor(depth);
    for (var i = 2; i < stem.length; i += 2) {
      final t = i / stem.length;
      final size = 11 * (1 - t) + 2.5;
      for (final side in [1.0, -1.0]) {
        final p = stem[i];
        final q = stem[math.min(i + 1, stem.length - 1)];
        var d = q - stem[i - 1];
        d = d / (d.distance == 0 ? 1 : d.distance);
        final perp = Offset(-d.dy, d.dx) * side;
        final a = perp * 0.9 + d * 0.45 + gravity * 0.15;
        leaves.add(LeafSpec(
          at: p,
          angle: math.atan2(a.dy, a.dx),
          length: size,
          width: size * 0.32,
          color: tone(color, light: rng.jitter(0.03)),
        ));
      }
    }
    return Sprig(
      kind: SprigKind.fern,
      root: root,
      depth: depth,
      phase: rng.range(0, math.pi * 2),
      stems: [stem],
      stemWidth: 1.1,
      stemColor: shade(color, -0.12),
      leaves: leaves,
    );
  }

  Sprig clump(Offset root, {required bool ivy, required double bloomChance}) {
    final depth = rng.range(0.0, 0.7);
    final leaves = <LeafSpec>[];
    final n = 5 + rng.nextInt(7);
    final down = math.atan2(gravity.dy, gravity.dx);
    final outAngle = math.atan2(_out.dy, _out.dx);
    for (var i = 0; i < n; i++) {
      // Fanned around the outward direction, pulled a little towards down.
      final spread = rng.jitter(1.5);
      final angle = outAngle + spread + (down - outAngle) * 0.25;
      final size = ivy ? rng.range(9, 15) : rng.range(8, 13);
      leaves.add(LeafSpec(
        at: Offset(rng.jitter(6), rng.jitter(2)),
        angle: angle,
        length: size,
        width: size * (ivy ? 0.95 : rng.range(0.42, 0.55)),
        color: _leafColor(depth),
        ivy: ivy,
      ));
    }
    final blooms = <BloomSpec>[
      if (rng.chance(bloomChance))
        _bloom(Offset(rng.jitter(3), rng.range(2, 5)), depth),
    ];
    return Sprig(
      kind: SprigKind.clump,
      root: root,
      depth: depth,
      phase: rng.range(0, math.pi * 2),
      leaves: leaves,
      blooms: blooms,
    );
  }

  BloomSpec _bloom(Offset at, double depth) => BloomSpec(
        at: at,
        radius: rng.range(1.6, 2.4),
        flower: rng.chance(0.45),
        color: tone(bloom, degrees: rng.jitter(10), light: rng.jitter(0.05) - depth * 0.06),
        seed: rng.nextUint32(),
      );
}

// ---------------------------------------------------------------------------
// Painting
// ---------------------------------------------------------------------------

/// Records [sprig] into a picture drawn around its own root, so a rustle is a
/// rotation about the origin.
ui.Picture recordSprig(Sprig sprig) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paintSprig(canvas, sprig);
  return recorder.endRecording();
}

/// Paints [sprig] about the origin: shadows first, then stems, leaves and
/// blooms.
void paintSprig(Canvas canvas, Sprig sprig) {
  const shadowOffset = Offset(1.2, 1.8);
  final shadow = Paint()
    ..color = const Color(0x55000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.3);

  // Shadows of everything, as one pass, so a leaf's shadow never lands on a
  // leaf in front of it in the same plant.
  for (final stem in sprig.stems) {
    if (stem.length < 2) continue;
    canvas.drawPath(
      _polyline(stem).shift(shadowOffset),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sprig.stemWidth
        ..color = const Color(0x44000000),
    );
  }
  for (final leaf in sprig.leaves) {
    canvas.save();
    canvas.translate(leaf.at.dx + shadowOffset.dx, leaf.at.dy + shadowOffset.dy);
    canvas.rotate(leaf.angle);
    canvas.drawPath(_leafPath(leaf), shadow);
    canvas.restore();
  }

  for (final stem in sprig.stems) {
    if (stem.length < 2) continue;
    _taperedStroke(canvas, stem, sprig.stemWidth, sprig.stemColor);
  }
  for (final leaf in sprig.leaves) {
    _paintLeaf(canvas, leaf);
  }
  for (final bloom in sprig.blooms) {
    _paintBloom(canvas, bloom);
  }
}

Path _polyline(List<Offset> pts) {
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1];
    final b = pts[i];
    final m = (a + b) / 2;
    p.quadraticBezierTo(a.dx, a.dy, m.dx, m.dy);
  }
  p.lineTo(pts.last.dx, pts.last.dy);
  return p;
}

/// A stem drawn thick at the root and fine at the tip, in segments.
void _taperedStroke(Canvas canvas, List<Offset> pts, double width, Color color) {
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..color = color;
  for (var i = 1; i < pts.length; i++) {
    final t = i / pts.length;
    paint.strokeWidth = math.max(0.35, width * (1 - 0.7 * t));
    canvas.drawLine(pts[i - 1], pts[i], paint);
  }
}

/// A leaf's outline in its own frame: the stalk at the origin, the tip along
/// +x.
Path _leafPath(LeafSpec leaf) {
  final l = leaf.length;
  final w = leaf.width / 2;
  if (leaf.ivy) {
    // Three lobes about the blade's centre — r(θ) = R(0.7 + 0.3·cos 3θ) —
    // which leaves a notch where the stalk joins, the shape of ivy.
    final r = l * 0.5;
    final c = Offset(r * 0.75, 0);
    final path = Path();
    const n = 30;
    for (var i = 0; i <= n; i++) {
      final th = -math.pi + i / n * math.pi * 2;
      final rr = r * (0.68 + 0.32 * math.cos(3 * th)) * (1 + 0.12 * math.cos(th));
      final p = c + Offset(math.cos(th) * rr, math.sin(th) * rr * (w * 2 / l));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    return path;
  }
  return Path()
    ..moveTo(0, 0)
    ..cubicTo(l * 0.22, -w * 1.25, l * 0.72, -w * 0.95, l, 0)
    ..cubicTo(l * 0.72, w * 0.95, l * 0.22, w * 1.25, 0, 0)
    ..close();
}

void _paintLeaf(Canvas canvas, LeafSpec leaf) {
  canvas.save();
  canvas.translate(leaf.at.dx, leaf.at.dy);
  canvas.rotate(leaf.angle);
  final path = _leafPath(leaf);
  final l = leaf.length;
  canvas.drawPath(
    path,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(l, -leaf.width * 0.4),
        [shade(leaf.color, -0.09), leaf.color, shade(leaf.color, 0.1)],
        const [0.0, 0.5, 1.0],
      ),
  );
  // A sheen across one half of the blade, as light catches its fold.
  canvas.save();
  canvas.clipPath(path);
  canvas.drawRect(
    Rect.fromLTRB(0, -leaf.width, l, 0),
    Paint()..color = const Color(0x1AFFFFFF),
  );
  canvas.restore();
  final rib = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.55
    ..color = shade(leaf.color, 0.16).withValues(alpha: 0.75);
  final tip = leaf.ivy ? l * 0.85 : l * 0.92;
  canvas.drawLine(Offset.zero, Offset(tip, 0), rib);
  if (l > 5) {
    rib
      ..strokeWidth = 0.4
      ..color = shade(leaf.color, 0.12).withValues(alpha: 0.45);
    if (leaf.ivy) {
      // Veins out to the two side lobes.
      for (final s in [-1.0, 1.0]) {
        canvas.drawLine(Offset(l * 0.18, 0),
            Offset(l * 0.42, s * leaf.width * 0.42), rib);
      }
    } else {
      for (final f in [0.3, 0.55]) {
        for (final s in [-1.0, 1.0]) {
          canvas.drawLine(Offset(l * f, 0),
              Offset(l * (f + 0.18), s * leaf.width * 0.36), rib);
        }
      }
    }
  }
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.45
      ..color = shade(leaf.color, -0.2).withValues(alpha: 0.55),
  );
  canvas.restore();
}

void _paintBloom(Canvas canvas, BloomSpec bloom) {
  final rng = SeededRandom(bloom.seed);
  if (bloom.flower) {
    final petals = 5;
    final start = rng.range(0, math.pi);
    for (var i = 0; i < petals; i++) {
      final a = start + i / petals * math.pi * 2;
      canvas.save();
      canvas.translate(bloom.at.dx, bloom.at.dy);
      canvas.rotate(a);
      canvas.drawOval(
        Rect.fromLTWH(0, -bloom.radius * 0.55, bloom.radius * 1.7, bloom.radius * 1.1),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(bloom.radius * 1.7, 0),
            [shade(bloom.color, -0.08), shade(bloom.color, 0.12)],
          ),
      );
      canvas.restore();
    }
    canvas.drawCircle(bloom.at, bloom.radius * 0.5,
        Paint()..color = tone(bloom.color, degrees: -25, light: -0.25));
    return;
  }
  // Berries: a small cluster, each lit from the upper left with a fleck of
  // highlight.
  final n = 3 + rng.nextInt(3);
  for (var i = 0; i < n; i++) {
    final c = bloom.at.translate(rng.jitter(bloom.radius * 1.4),
        rng.jitter(bloom.radius * 1.4));
    final r = bloom.radius * rng.range(0.75, 1.05);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c.translate(-r * 0.35, -r * 0.35),
          r * 1.3,
          [shade(bloom.color, 0.15), bloom.color, shade(bloom.color, -0.25)],
          const [0.0, 0.5, 1.0],
        ),
    );
    canvas.drawCircle(c.translate(-r * 0.35, -r * 0.4), r * 0.28,
        Paint()..color = const Color(0xB3FFFFFF));
  }
}

/// Maps the canonical frame onto a surface of [surface] size whose bar is
/// [thickness] deep on [anchor]: x along the bar, y away from it.
///
/// Built as a 4×4 for [Canvas.transform]. Two of the four maps reflect, which
/// is harmless — leaves are symmetric, and a reflected rotation still swings.
Matrix4 foliageFrame({
  required String anchor,
  required Size surface,
  required double thickness,
}) {
  final m = Matrix4.identity();
  switch (anchor) {
    case 'bottom':
      // y up the screen from the bar's top edge.
      m.setEntry(1, 1, -1.0);
      m.setEntry(1, 3, surface.height - thickness);
    case 'left':
      // x down the screen, y rightward from the bar's right edge.
      m.setEntry(0, 0, 0.0);
      m.setEntry(0, 1, 1.0);
      m.setEntry(0, 3, thickness);
      m.setEntry(1, 0, 1.0);
      m.setEntry(1, 1, 0.0);
    case 'right':
      // x down the screen, y leftward from the bar's left edge.
      m.setEntry(0, 0, 0.0);
      m.setEntry(0, 1, -1.0);
      m.setEntry(0, 3, surface.width - thickness);
      m.setEntry(1, 0, 1.0);
      m.setEntry(1, 1, 0.0);
    default: // 'top'
      m.setEntry(1, 3, thickness);
  }
  return m;
}
