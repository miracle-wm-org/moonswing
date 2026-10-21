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
  clump(0.045),

  /// A turning branch reaching out of a bar's corner.
  bough(0.08),

  /// One loose leaf on its way down, which flutters about its own middle.
  drift(0.32),

  /// A pumpkin leaf on its stalk, standing up off the vine.
  stalk(0.05),

  /// A pumpkin, or the vine it lies on: too heavy to rustle at all.
  gourd(0.0);

  const SprigKind(this.sway);

  /// The largest rustle, in radians, this kind is swung through.
  final double sway;
}

/// The outline a leaf is drawn in.
enum LeafShape {
  /// A plain pointed blade.
  plain,

  /// Three rounded lobes and a notch at the stalk.
  ivy,

  /// Five pointed, toothed lobes spread like a hand.
  maple,

  /// A long blade with rounded lobes down both sides.
  oak,

  /// Five broad, shallow lobes: a pumpkin's leaf.
  gourd,
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
    this.shape = LeafShape.plain,
  });

  final Offset at;
  final double angle;
  final double length;
  final double width;
  final Color color;
  final LeafShape shape;
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

/// A pumpkin sitting on the ground: [at] is the middle of its base, and
/// [down] is gravity, which is the only way it knows where its stalk goes.
class GourdSpec {
  const GourdSpec({
    required this.at,
    required this.down,
    required this.width,
    required this.height,
    required this.color,
    required this.stemColor,
    required this.ribs,
    required this.lean,
  });

  final Offset at;
  final Offset down;
  final double width;
  final double height;
  final Color color;
  final Color stemColor;

  /// How many lobes show from the side.
  final int ribs;

  /// Which way, and how far, the stalk curls over: −1…1.
  final double lean;

  /// How far the stalk stands above the body.
  double get stalk => height * 0.22 + 3;

  /// Everything the pumpkin paints, its shadow on the ground included.
  Rect get bounds {
    final up = -down;
    final centre = at + up * ((height + stalk) / 2);
    return Rect.fromCircle(
        center: centre,
        radius: math.max(width * 0.62, (height + stalk) / 2 + 4));
  }
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
    this.gourds = const [],
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
  final List<GourdSpec> gourds;

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
    for (final g in gourds) {
      r = r.expandToInclude(g.bounds);
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

  if (style == FoliageStyle.harvest) {
    final sprigs = stands
        ? grower.pumpkinPatches(density)
        : grower.turningCorners(density, endCaps: endCaps, hangs: hangs);
    sprigs.sort((a, b) => b.depth.compareTo(a.depth));
    return FoliagePlan(sprigs);
  }

  // Per hundred pixels of bar, before density.
  final (vines, clumps, moss, blooms, ferns) = switch (style) {
    FoliageStyle.ivy => (1.6, 2.6, 0.0, 0.08, 0),
    FoliageStyle.moss => (0.2, 0.6, 2.4, 0.0, 0),
    FoliageStyle.wildwood => (1.3, 2.4, 0.8, 0.3, 4),
    FoliageStyle.none || FoliageStyle.harvest => (0.0, 0.0, 0.0, 0.0, 0),
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
  ///
  /// [top] is how far onto the bar a stem may go: [_onBar] unless the plant
  /// is meant to cover the bar, which only a harvest's corners are.
  List<Offset> _clip(List<Offset> stem, Offset root,
      {double margin = 6, double? top}) {
    final out = <Offset>[];
    final floor = top ?? _onBar;
    for (final p in stem) {
      final q = root + p;
      if (q.dy > reach - margin || q.dy < floor || q.dx < 2 || q.dx > length - 2) {
        break;
      }
      out.add(p);
    }
    return out.length < 2 ? const [Offset.zero, Offset(0, 0.1)] : out;
  }

  LeafSpec _leafAlong(List<Offset> stem, int i, double side, double size,
      Color color, {LeafShape shape = LeafShape.plain}) {
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
      width: size * _breadth(shape),
      color: color,
      shape: shape,
    );
  }

  /// How wide a leaf of [shape] is for its length.
  double _breadth(LeafShape shape) => switch (shape) {
        LeafShape.ivy => 0.95,
        LeafShape.maple => rng.range(0.9, 1.0),
        LeafShape.gourd => rng.range(0.92, 1.02),
        LeafShape.oak => rng.range(0.5, 0.6),
        LeafShape.plain => rng.range(0.42, 0.55),
      };

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
      leaves.add(_leafAlong(stem, i, side, size, _leafColor(depth),
          shape: ivy ? LeafShape.ivy : LeafShape.plain));
      side = -side;
      if (rng.chance(0.25)) {
        // A second leaf on the same node, the other way.
        leaves.add(_leafAlong(stem, i, side, size * 0.8, _leafColor(depth),
            shape: ivy ? LeafShape.ivy : LeafShape.plain));
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
        shape: ivy ? LeafShape.ivy : LeafShape.plain,
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

  // -------------------------------------------------------------------------
  // Harvest
  // -------------------------------------------------------------------------

  /// A turned leaf: [bloom] is autumn's colour, and every leaf is somewhere on
  /// the way to it or past it — mostly orange, then reds, golds and browns, a
  /// claret now and then, and the odd one still in [leaf]'s green.
  Color _autumnColor(double depth) {
    final pick = rng.nextDouble();
    final Color c;
    if (pick < 0.3) {
      c = tone(bloom, degrees: rng.jitter(7), light: rng.jitter(0.05));
    } else if (pick < 0.52) {
      c = tone(bloom, degrees: -rng.range(20, 32), sat: 1.05, light: -0.04);
    } else if (pick < 0.72) {
      c = tone(bloom, degrees: rng.range(13, 22), light: rng.range(0.03, 0.09));
    } else if (pick < 0.86) {
      c = tone(bloom,
          degrees: -rng.range(0, 10), sat: rng.range(0.55, 0.75), light: -0.13);
    } else if (pick < 0.93) {
      c = tone(bloom, degrees: -rng.range(34, 44), sat: 0.85, light: -0.14);
    } else {
      c = tone(leaf, degrees: -rng.range(0, 25), light: rng.jitter(0.05));
    }
    return tone(c, light: -depth * 0.09);
  }

  /// A pumpkin leaf: mostly still green, some yellowing, a few gone brown.
  Color _vineLeafColor(double depth) {
    final pick = rng.nextDouble();
    final Color c;
    if (pick < 0.55) {
      c = tone(leaf, degrees: rng.jitter(10), light: rng.jitter(0.06));
    } else if (pick < 0.85) {
      c = tone(leaf, degrees: -rng.range(25, 45), light: rng.range(0.02, 0.08));
    } else {
      c = tone(leaf, degrees: -rng.range(48, 58), sat: 0.95, light: 0.0);
    }
    return tone(c, light: -depth * 0.06);
  }

  /// A woody stem: [bloom] with the colour taken out of it, which is brown.
  Color _twigColor(double depth) => tone(bloom,
      degrees: -rng.range(4, 12),
      sat: rng.range(0.35, 0.5),
      light: -0.26 - depth * 0.06);

  /// The species a branch or a clump is made of.
  LeafShape _treeLeaf() {
    final pick = rng.nextDouble();
    if (pick < 0.6) return LeafShape.maple;
    if (pick < 0.88) return LeafShape.oak;
    return LeafShape.plain;
  }

  /// A frame of turning leaves in each of a bar's two corners: an L that
  /// hugs the screen's edges — over the bar's end and along under it, and
  /// down the screen's side as far as the overhang reaches — fullest in the
  /// corner itself and thinning out along both arms, as if a tree off the
  /// edge of the screen were leaning into it. The middle of the bar is left
  /// bare.
  List<Sprig> turningCorners(double density,
      {required double endCaps, required bool hangs}) {
    final cap = endCaps > 0 ? endCaps : math.min(60.0, length * 0.08);
    // The arm down the screen's side, and the arm along the bar.
    final side = math.max(12.0, reach - 6);
    final along = math.min(length * 0.3, math.max(side * 1.6, 220.0));
    final sprigs = <Sprig>[];
    for (final end in [0, 1]) {
      final inward = end == 0 ? 1.0 : -1.0;
      double at(double x) => end == 0 ? x : length - x;

      // Branches coming in from off the screen, in turn: out of the very
      // corner on a diagonal, out of the screen's side edge, and along the
      // bar's edge out of the corner — so both arms have wood in them.
      final boughs = math.max(3, (9 * density).round());
      for (var i = 0; i < boughs; i++) {
        switch (i % 3) {
          case 0:
            sprigs.add(bough(
              Offset(at(rng.range(3, cap * 0.8 + 3)),
                  rng.range(-thickness * 0.15, 0.5)),
              dir: Offset(inward * rng.range(0.7, 2.2), 1),
              len: math.max(side, along * 0.5) * rng.range(0.6, 1.1),
              inward: inward,
              hangs: hangs,
            ));
          case 1:
            sprigs.add(bough(
              Offset(at(3), rng.range(side * 0.1, side * 0.8)),
              dir: Offset(inward, rng.range(-0.3, 0.3)),
              len: along * rng.range(0.3, 0.7),
              inward: inward,
              hangs: hangs,
              sag: 0.4,
            ));
          default:
            sprigs.add(bough(
              Offset(at(rng.range(3, cap + 3)), rng.range(2.0, 14.0)),
              dir: Offset(inward, rng.range(-0.05, 0.12)),
              len: along * rng.range(0.5, 1.0),
              inward: inward,
              hangs: hangs,
              sag: 0.12,
            ));
        }
      }

      // Over the bar itself, from the screen's very edge: the frame is the
      // screen's, not the windows', so its corner is laid over the bar's end
      // and thins out along it. The modules there are covered, but their
      // clicks still reach them — the leaves answer no hits.
      final overBar = math.min(along * 0.5, cap * 2 + 90);
      for (var i = 0; i < (16 * density).round(); i++) {
        final t = math.pow(rng.nextDouble(), 1.6).toDouble();
        sprigs.add(autumnClump(
          Offset(at(t * overBar + 3), rng.range(-thickness, 2.0)),
          anyWay: true,
        ));
      }
      // And a branch or two in from beyond the screen's corner, over the
      // bar's end and down past it.
      for (var i = 0; i < math.max(1, (2 * density).round()); i++) {
        sprigs.add(bough(
          Offset(at(3), -thickness + rng.range(2, thickness * 0.6)),
          dir: Offset(inward * rng.range(0.6, 1.4), 1),
          len: math.max(side, along * 0.5) * rng.range(0.7, 1.1),
          inward: inward,
          hangs: hangs,
        ));
      }

      // The mat: clumps over the L, crowded into the corner, each arm thick
      // where it leaves the corner and ragged towards its end.
      final clumps = (40 * density).round();
      for (var i = 0; i < clumps; i++) {
        final onTop = rng.chance(0.62);
        final t = math.pow(rng.nextDouble(), 1.7).toDouble();
        final across = math.pow(rng.nextDouble(), 1.3).toDouble();
        final Offset spot;
        if (onTop) {
          final deep = side * 0.5 * (1 - t) + 14;
          spot = Offset(t * along, across * deep);
        } else {
          final deep = along * 0.3 * (1 - t) + 12;
          spot = Offset(across * deep, t * side);
        }
        sprigs.add(autumnClump(
          Offset(at(spot.dx + 3),
              math.max(-thickness * 0.18, math.min(spot.dy, side))),
          // Clear of the bar, a clump's leaves may point any way; on its
          // edge they fan away from it, so they overhang it only as a fringe.
          anyWay: spot.dy > 17,
        ));
      }

      // A few loose leaves just outside the frame's ragged edge.
      for (var i = 0; i < (4 * density).round(); i++) {
        final onTop = rng.chance(0.5);
        final t = rng.range(0.3, 1.0);
        sprigs.add(driftingLeaf(Offset(
          at(onTop ? t * along * 1.15 : rng.range(side * 0.2, along * 0.4)),
          onTop
              ? rng.range(side * 0.25, side * 0.9) * (1.1 - t)
              : math.min(side, t * side + 8),
        )));
      }
    }
    return sprigs;
  }

  Sprig bough(Offset root,
      {required Offset dir,
      required double len,
      required double inward,
      required bool hangs,
      double sag = 1.0}) {
    final depth = rng.range(0.2, 1.0);
    const step = 3.0;
    // A branch reaches before it droops, and one held up along an edge
    // ([sag] below 1) hardly droops at all.
    final main = _clip(
      _stem(dir, (len / step).round(), step,
          weight: (hangs ? 0.04 : 0.025) * sag,
          curl: rng.range(0.05, 0.12) * math.max(0.4, sag)),
      root,
      top: -thickness,
    );
    final stems = <List<Offset>>[main];
    // A twig or two off the branch, the way it was already leaning.
    for (var j = 0; j < 1 + rng.nextInt(2) && main.length > 6; j++) {
      final from = main[rng.range(main.length * 0.25, main.length * 0.7).floor()];
      final twigDir = _out * rng.range(0.6, 1.2) +
          Offset(inward * rng.range(-0.4, 1.4), 0);
      final twig = _stem(twigDir, rng.range(4, 9).round(), step,
          weight: hangs ? 0.14 : 0.06, curl: 0.12);
      final placed =
          _clip([for (final p in twig) from + p], root, top: -thickness);
      if (placed.length > 2) stems.add(placed);
    }

    final shape = _treeLeaf();
    // A branch turns together, near enough — but not every leaf on it.
    final own = _autumnColor(depth);
    Color color() => rng.chance(0.35)
        ? _autumnColor(depth)
        : tone(own, degrees: rng.jitter(6), light: rng.jitter(0.05));
    final leaves = <LeafSpec>[];
    for (final stem in stems) {
      var side = rng.chance(0.5) ? 1.0 : -1.0;
      for (var i = 2; i < stem.length; i += rng.range(1.5, 3.2).round()) {
        final t = i / stem.length;
        final size = rng.range(12, 19) * (1 - 0.3 * t);
        leaves.add(_leafAlong(stem, i, side, size, color(), shape: shape));
        side = -side;
      }
      // A spray at the tip.
      final tip = stem.length - 1;
      for (final s in [1.0, -1.0, if (rng.chance(0.5)) 0.3]) {
        leaves.add(_leafAlong(stem, tip, s, rng.range(11, 15), color(),
            shape: shape));
      }
    }
    return Sprig(
      kind: SprigKind.bough,
      root: root,
      depth: depth,
      phase: rng.range(0, math.pi * 2),
      stems: stems,
      stemWidth: rng.range(1.6, 2.4),
      stemColor: _twigColor(depth),
      leaves: leaves,
      blooms: [
        if (rng.chance(0.2) && main.length > 5)
          _bloom(main[main.length ~/ 2], depth),
      ],
    );
  }

  Sprig autumnClump(Offset root, {bool anyWay = false}) {
    final depth = rng.range(0.0, 0.7);
    final shape = _treeLeaf();
    final out = math.atan2(_out.dy, _out.dx);
    final down = math.atan2(gravity.dy, gravity.dx);
    final leaves = <LeafSpec>[];
    for (var i = 0, n = 5 + rng.nextInt(5); i < n; i++) {
      final size = anyWay ? rng.range(13, 22) : rng.range(11, 16);
      leaves.add(LeafSpec(
        at: Offset(rng.jitter(anyWay ? 10 : 7), rng.jitter(anyWay ? 9 : 2)),
        angle: anyWay
            ? rng.range(0, math.pi * 2)
            : out + rng.jitter(1.5) + (down - out) * 0.25,
        length: size,
        width: size * _breadth(shape),
        color: _autumnColor(depth),
        shape: shape,
      ));
    }
    return Sprig(
      kind: SprigKind.clump,
      root: root,
      depth: depth,
      phase: rng.range(0, math.pi * 2),
      leaves: leaves,
    );
  }

  /// A leaf on its own in the air, rooted at its own middle, so its rustle
  /// is a flutter rather than a swing.
  Sprig driftingLeaf(Offset root) {
    final depth = rng.range(0.1, 0.9);
    final size = rng.range(7.5, 11);
    final shape = _treeLeaf();
    final angle = rng.range(-0.9, 0.9) + (rng.chance(0.5) ? 0 : math.pi);
    return Sprig(
      kind: SprigKind.drift,
      root: root,
      depth: depth,
      phase: rng.range(0, math.pi * 2),
      leaves: [
        LeafSpec(
          at: Offset(math.cos(angle), math.sin(angle)) * (-size / 2),
          angle: angle,
          length: size,
          width: size * _breadth(shape),
          color: _autumnColor(depth),
          shape: shape,
        ),
      ],
    );
  }

  /// Pumpkin patches along a bar the plants stand on: one in each corner and
  /// a few between, each a vine along the bar's edge with pumpkins on it,
  /// leaves on stalks behind them and fallen leaves among them.
  List<Sprig> pumpkinPatches(double density) {
    final scale = math.min(1.0, reach / 72);
    final sprigs = <Sprig>[];
    final centres = <(double, double)>[];
    if (length < 320) {
      centres.add((length / 2, math.min(length * 0.4, 70.0)));
    } else {
      final half = rng.range(55, 80) * math.max(0.7, scale);
      centres.add((half * 0.8 + 4, half));
      final between = math.max(0, (density * length / 620).floor() - 1);
      for (var i = 0; i < between; i++) {
        final t = (i + 1) / (between + 1) + rng.jitter(0.05);
        centres.add((t * length, rng.range(40, 65) * math.max(0.7, scale)));
      }
      final last = rng.range(55, 80) * math.max(0.7, scale);
      centres.add((length - last * 0.8 - 4, last));
    }
    for (final (cx, half) in centres) {
      sprigs.addAll(_patch(cx, half, scale, density));
    }
    return sprigs;
  }

  List<Sprig> _patch(double cx, double half, double scale, double density) {
    final sprigs = <Sprig>[];
    final a = math.max(3.0, cx - half);
    final b = math.min(length - 3, cx + half);
    final up = _out;

    // The vine along the bar's edge, with its tendrils curling off it.
    final root = Offset(cx, 0.5);
    final phase = rng.range(0, 10);
    Offset vineAt(double x) =>
        Offset(x - cx, 0.8 + math.sin(x * 0.08 + phase) * 1.1);
    // Two runs out from the patch's middle, so the vine is thickest where it
    // roots and thins towards both ends.
    final vine = <Offset>[for (var x = cx; x <= b; x += 3) vineAt(x)];
    final back = <Offset>[for (var x = cx; x >= a; x -= 3) vineAt(x)];
    final stems = <List<Offset>>[vine, back];
    for (var i = 0; i < 2 + rng.nextInt(3); i++) {
      final run = rng.chance(0.5) ? vine : back;
      final from = run[rng.nextInt(run.length)];
      final turns = rng.range(1.4, 2.4) * math.pi * 2;
      final r0 = rng.range(2.5, 4.0);
      final hand = rng.chance(0.5) ? 1.0 : -1.0;
      const n = 22;
      final rise = rng.range(9, 12) * scale;
      final tendril = <Offset>[];
      for (var k = 0; k <= n; k++) {
        final t = k / n;
        final th = t * turns;
        final r = r0 * (1 - 0.65 * t);
        tendril.add(from +
            up * (t * rise + 1) +
            Offset(hand * (math.cos(th) - 1) * r, math.sin(th) * r * 0.6));
      }
      stems.add(_clip(tendril, root, margin: 2));
    }
    final vineDepth = rng.range(0.9, 1.0);
    sprigs.add(Sprig(
      kind: SprigKind.gourd,
      root: root,
      depth: vineDepth,
      phase: 0,
      stems: stems,
      stemWidth: 1.7,
      stemColor: shade(tone(leaf, degrees: -10, sat: 0.75), -0.08),
    ));

    // Leaves on stalks, mostly behind the pumpkins.
    final leaves = ((7 + rng.nextInt(5)) * density).round();
    for (var i = 0; i < leaves; i++) {
      // Thickest round the pumpkins, in the patch's middle.
      final x = cx + (rng.nextDouble() - rng.nextDouble()) * (b - a) / 2;
      final front = rng.chance(0.25);
      final depth = front ? rng.range(0.1, 0.32) : rng.range(0.5, 0.95);
      final len = (front ? rng.range(4, 10) : rng.range(12, 30)) * scale;
      final stalk = _clip(
        _stem(up + Offset(rng.jitter(0.45), 0), math.max(2, (len / 2.5).round()),
            2.5,
            weight: 0.04, curl: 0.05),
        Offset(x, 1),
        margin: 14,
      );
      final tip = stalk.last;
      final from = stalk[math.max(0, stalk.length - 2)];
      var d = tip - from;
      if (d.distance == 0) d = up;
      final size = (front ? rng.range(12, 16) : rng.range(17, 25)) * scale;
      sprigs.add(Sprig(
        kind: SprigKind.stalk,
        root: Offset(x, 1),
        depth: depth,
        phase: rng.range(0, math.pi * 2),
        stems: [stalk],
        stemWidth: 1.2,
        stemColor: shade(tone(leaf, degrees: -12, sat: 0.6), -0.06),
        leaves: [
          LeafSpec(
            at: tip,
            angle: math.atan2(d.dy, d.dx) + rng.jitter(0.6),
            length: size,
            width: size * _breadth(LeafShape.gourd),
            color: _vineLeafColor(depth),
            shape: LeafShape.gourd,
          ),
        ],
      ));
    }

    // The pumpkins: one big one, and smaller ones either side of it.
    final count = math.max(1, ((2 + rng.nextInt(3)) * density).round());
    final widths = [
      for (var i = 0; i < count; i++)
        (i == 0 ? rng.range(30, 38) : rng.range(15, 27)) * scale,
    ];
    var left = cx + rng.jitter(half * 0.2) - widths[0] / 2;
    var right = left + widths[0];
    for (var i = 0; i < count; i++) {
      final w = widths[i];
      double x;
      if (i == 0) {
        x = (left + right) / 2;
      } else if (i.isOdd) {
        x = right + w * rng.range(0.3, 0.5);
        right = x + w / 2;
      } else {
        x = left - w * rng.range(0.3, 0.5);
        left = x - w / 2;
      }
      if (x - w / 2 < 3 || x + w / 2 > length - 3) continue;
      final depth = i == 0 ? rng.range(0.34, 0.4) : rng.range(0.4, 0.7);
      final h = w * rng.range(0.68, 0.84);
      sprigs.add(Sprig(
        kind: SprigKind.gourd,
        root: Offset(x, 0),
        depth: depth,
        phase: 0,
        gourds: [
          GourdSpec(
            // Sat a little into the bar's edge, and the ones behind a little
            // further back — which, seen from the side, is higher.
            at: up * (-1.5 + (depth - 0.34) * 6),
            down: gravity,
            width: w,
            height: math.min(h, reach - 16),
            color: _pumpkinColor(depth, hero: i == 0),
            stemColor: rng.chance(0.7)
                ? tone(leaf, degrees: -30, sat: 0.55, light: -0.08)
                : tone(bloom, degrees: -8, sat: 0.35, light: -0.22),
            ribs: 5 + rng.nextInt(3),
            lean: rng.jitter(1.0),
          ),
        ],
      ));
    }

    // Fallen leaves lying among them, in front of everything.
    final fallen = <LeafSpec>[];
    for (var i = 0, n = (rng.range(2, 4) * density).round(); i < n; i++) {
      final size = rng.range(7, 10.5) * scale;
      final shape = _treeLeaf();
      fallen.add(LeafSpec(
        at: Offset(rng.jitter(half * 0.9), rng.range(-1.5, 1.5)),
        angle: rng.jitter(0.45) + (rng.chance(0.5) ? 0 : math.pi),
        length: size,
        width: size * _breadth(shape),
        color: _autumnColor(0),
        shape: shape,
      ));
    }
    sprigs.add(Sprig(
      kind: SprigKind.gourd,
      root: Offset(cx, 0),
      depth: 0.02,
      phase: 0,
      leaves: fallen,
    ));
    return sprigs;
  }

  /// Mostly orange, but a patch is never one colour: a deep red-orange, a
  /// golden one, a pale one, and now and then a green squash — though the
  /// [hero] of a patch, its biggest, is always one of the warm ones.
  Color _pumpkinColor(double depth, {bool hero = false}) {
    final pick = rng.nextDouble() * (hero ? 0.84 : 1.0);
    final Color c;
    if (pick < 0.62) {
      c = tone(bloom, degrees: rng.jitter(5), light: rng.jitter(0.04));
    } else if (pick < 0.74) {
      c = tone(bloom, degrees: -rng.range(9, 15), sat: 1.05, light: -0.06);
    } else if (pick < 0.84) {
      c = tone(bloom, degrees: rng.range(10, 16), light: 0.04);
    } else if (pick < 0.94) {
      c = tone(bloom, degrees: 14, sat: 0.3, light: 0.27);
    } else {
      c = tone(leaf, sat: 0.85, light: -0.04);
    }
    return tone(c, light: -depth * 0.08);
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
  for (final gourd in sprig.gourds) {
    _paintGourd(canvas, gourd);
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
  switch (leaf.shape) {
    case LeafShape.ivy:
      // Three lobes about the blade's centre — r(θ) = R(0.7 + 0.3·cos 3θ) —
      // which leaves a notch where the stalk joins, the shape of ivy.
      final r = l * 0.5;
      return _radialPath(Offset(r * 0.75, 0), w * 2 / l,
          (th) => r * (0.68 + 0.32 * math.cos(3 * th)) * (1 + 0.12 * math.cos(th)));
    case LeafShape.maple:
      // Five pointed lobes — the tip, a pair either side, a smaller pair
      // below — each a sharp bump on a small round core, with teeth.
      final r = l * 0.55;
      return _radialPath(Offset(l * 0.42, 0), w * 2 / l, (th) {
        var k = 0.4 + 0.04 * math.pow(math.cos(th * 11).abs(), 6);
        for (final (at, size) in _mapleLobes) {
          k += size * _lobe(th - at, 0.62, 1.25);
        }
        return r * k;
      }, steps: 72);
    case LeafShape.gourd:
      // Five broad lobes, round-shouldered with a point at each, and a deep
      // notch at the stalk.
      final r = l * 0.52;
      return _radialPath(Offset(l * 0.46, 0), w * 2 / l, (th) {
        var k = 0.5 + 0.03 * math.pow(math.cos(th * 9).abs(), 8);
        for (final (at, size) in _mapleLobes) {
          k += size * 0.85 * _lobe(th - at, 0.7, 0.75);
        }
        // The notch: the two lower lobes overlap the stalk's side.
        return r * k * (1 - 0.35 * _lobe(th - math.pi, 0.35, 1));
      }, steps: 60);
    case LeafShape.oak:
      // A long blade whose edge swells into rounded lobes, four a side,
      // narrowing to the stalk and closing in a round tip.
      final path = Path()..moveTo(0, 0);
      const n = 36;
      for (final side in [-1.0, 1.0]) {
        for (var i = 1; i <= n; i++) {
          final t = side < 0 ? i / n : 1 - i / n;
          final envelope = math.pow(math.sin(math.pi * math.min(1, t * 1.05)), 0.7);
          final lobes = 0.55 + 0.45 * math.sin(math.pi * t * 4.5).abs();
          path.lineTo(l * t, side * w * 1.2 * envelope * lobes);
        }
      }
      return path..close();
    case LeafShape.plain:
      return Path()
        ..moveTo(0, 0)
        ..cubicTo(l * 0.22, -w * 1.25, l * 0.72, -w * 0.95, l, 0)
        ..cubicTo(l * 0.72, w * 0.95, l * 0.22, w * 1.25, 0, 0)
        ..close();
  }
}

/// A maple's lobes, as (angle from the tip, size): the tip, the pair either
/// side of it, and the smaller pair beside the stalk.
const _mapleLobes = [
  (0.0, 0.62),
  (1.2, 0.54),
  (-1.2, 0.54),
  (2.25, 0.3),
  (-2.25, 0.3),
];

/// A bump [width] radians either side of its peak; [sharp] above 1 points it.
double _lobe(double d, double width, double sharp) {
  // Angles wrap, so the pair beside the stalk can meet across it.
  final a = (d + math.pi) % (math.pi * 2) - math.pi;
  final x = 1 - a.abs() / width;
  return x <= 0 ? 0 : math.pow(x, sharp).toDouble();
}

/// The closed outline r(θ) about [centre], squashed across the blade by
/// [squash], starting and ending at the stalk's side.
Path _radialPath(Offset centre, double squash, double Function(double) r,
    {int steps = 30}) {
  final path = Path();
  for (var i = 0; i <= steps; i++) {
    final th = -math.pi + i / steps * math.pi * 2;
    final rr = r(th);
    final p = centre + Offset(math.cos(th) * rr, math.sin(th) * rr * squash);
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
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
  final palmate =
      leaf.shape == LeafShape.maple || leaf.shape == LeafShape.gourd;
  final tip = switch (leaf.shape) {
    LeafShape.ivy => l * 0.85,
    LeafShape.maple => l * 0.95,
    LeafShape.gourd => l * 0.8,
    LeafShape.oak || LeafShape.plain => l * 0.92,
  };
  // A palmate leaf's veins start where the blade does, past a bare stalk.
  final base = palmate ? l * 0.22 : 0.0;
  canvas.drawLine(Offset.zero, Offset(tip, 0), rib);
  if (l > 5) {
    rib
      ..strokeWidth = 0.4
      ..color = shade(leaf.color, 0.12).withValues(alpha: 0.45);
    switch (leaf.shape) {
      case LeafShape.ivy:
        // Veins out to the two side lobes.
        for (final s in [-1.0, 1.0]) {
          canvas.drawLine(Offset(l * 0.18, 0),
              Offset(l * 0.42, s * leaf.width * 0.42), rib);
        }
      case LeafShape.maple || LeafShape.gourd:
        // One vein out to every lobe but the tip's, which is the rib.
        final centre = Offset(l * (leaf.shape == LeafShape.maple ? 0.42 : 0.46), 0);
        final reach = l * (leaf.shape == LeafShape.maple ? 0.5 : 0.42);
        final squash = leaf.width / l;
        for (final (at, size) in _mapleLobes.skip(1)) {
          final k = reach * (0.5 + size);
          canvas.drawLine(
              Offset(base, 0),
              centre + Offset(math.cos(at) * k, math.sin(at) * k * squash),
              rib);
        }
      case LeafShape.oak:
        for (var f = 0.2; f < 0.85; f += 0.22) {
          for (final s in [-1.0, 1.0]) {
            canvas.drawLine(Offset(l * f, 0),
                Offset(l * (f + 0.1), s * leaf.width * 0.5), rib);
          }
        }
      case LeafShape.plain:
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

/// Paints a pumpkin standing on its base at [g.at]: a ground shadow, its
/// lobes from the outside in — each a lit oval, with a crease where it meets
/// the next — the well its stalk comes out of, and the stalk.
void _paintGourd(Canvas canvas, GourdSpec g) {
  // A frame whose +y is down, whatever the bar's anchor, so the pumpkin is
  // drawn the right way up: the stalk at −y, the ground at 0.
  final down = g.down / g.down.distance;
  final across = Offset(-down.dy, down.dx);
  canvas.save();
  canvas.transform(Matrix4(
    across.dx, across.dy, 0, 0, //
    down.dx, down.dy, 0, 0, //
    0, 0, 1, 0, //
    g.at.dx, g.at.dy, 0, 1, //
  ).storage);

  final w = g.width;
  final h = g.height;
  canvas.drawOval(
    Rect.fromCenter(center: Offset(w * 0.04, -0.5), width: w * 1.15, height: h * 0.2),
    Paint()
      ..color = const Color(0x66000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
  );

  final k = g.ribs;
  final lobes = <(double, double, double, double)>[];
  for (var i = 0; i < k; i++) {
    final phi = -math.pi / 2 + math.pi * (i + 0.5) / k;
    lobes.add((
      phi,
      w / 2 * math.sin(phi) * 0.7,
      w / 2 * (0.3 + 0.24 * math.cos(phi)),
      h / 2 * (0.9 + 0.1 * math.cos(phi)),
    ));
  }
  // The outside lobes are the furthest round the curve, so they go first.
  lobes.sort((a, b) => b.$1.abs().compareTo(a.$1.abs()));
  final crease = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.7
    ..color = shade(g.color, -0.22).withValues(alpha: 0.7);
  for (final (phi, cx, a, b) in lobes) {
    final rect = Rect.fromCenter(
        center: Offset(cx, -b), width: a * 2, height: b * 2);
    // Turned away from the light, a lobe is a little darker.
    final lit = shade(g.color, -0.05 * phi.abs() + (phi < 0 ? 0.03 : -0.03));
    canvas.drawOval(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx - a * 0.35, -b * 1.35),
          math.max(a, b) * 1.5,
          [shade(lit, 0.12), lit, shade(lit, -0.2)],
          const [0.0, 0.45, 1.0],
        ),
    );
    canvas.drawOval(rect, crease);
  }

  // A soft highlight on the shoulder facing the light.
  canvas.drawOval(
    Rect.fromCenter(
        center: Offset(-w * 0.14, -h * 0.68), width: w * 0.2, height: h * 0.16),
    Paint()
      ..color = const Color(0x2EFFFFFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4),
  );
  // The well the stalk sits in.
  canvas.drawOval(
    Rect.fromCenter(
        center: Offset(0, -h * 0.95), width: w * 0.24, height: h * 0.1),
    Paint()..color = shade(g.color, -0.25).withValues(alpha: 0.8),
  );

  final top = Offset(0, -h * 0.93);
  final end = Offset(g.lean * g.stalk * 0.55, -h - g.stalk);
  final stalk = Path()
    ..moveTo(top.dx, top.dy)
    ..quadraticBezierTo(0, end.dy + g.stalk * 0.3, end.dx, end.dy);
  canvas.drawPath(
    stalk,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2.0, w * 0.1)
      ..color = g.stemColor,
  );
  canvas.drawPath(
    stalk.shift(Offset(-w * 0.015, 0)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.6, w * 0.025)
      ..color = shade(g.stemColor, 0.14).withValues(alpha: 0.8),
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
