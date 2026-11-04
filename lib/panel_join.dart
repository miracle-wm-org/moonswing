/// Where two flush bars meet, and the fillet that rounds the inside of that
/// corner (`panel_join_radius`).
///
/// A top or bottom bar and a left or right one meet in a corner of the screen,
/// and their two inner edges meet in a right angle at the corner of the work
/// area. The fillet fills that right angle with a quarter round in the bar's
/// own colour, so the pair reads as one frame round the screen rather than two
/// strips butted together. It lies outside *both* bars — that is what an inside
/// corner is — so it is painted in the strip a bar's surface reaches past the
/// bar, the strip `panel_overhang` grows for foliage and hands back to the
/// windows beneath through the input region (`setPanelReach`).
///
/// Three questions, each answered here and nowhere else:
///
/// - **Which bars meet** ([panelJoinsFor]) is read off the `[panels]` geometry
///   alone: a bar meets the bar on the edge at either of its ends, and only when
///   each is the *only* bar on its edge. Two bars stacked on one edge would put
///   each one's corner inside the other, and which of them is innermost is the
///   compositor's to decide and nobody's to report.
/// - **How far every bar's surface reaches** ([panelSurfaceReach]) is one number
///   for every bar, as the foliage's reach always was, so the theme switch that
///   moves it still goes through one `PanelReachSequencer`.
/// - **Which of the two bars paints a fillet** ([panelJoinOwnership]) is the
///   hard one. The corner square belongs to whichever bar the compositor
///   stretched across it, and that is a placement decision no client is told
///   of: Mir places full-width bars first and fits the side bars between them;
///   sway goes by the order the surfaces were made in. The bar that was *not*
///   stretched across the corner stops at the other's inner edge, so the
///   fillet sits exactly at its own end — that bar paints it, and the one that
///   spans the corner paints nothing. A bar tells which it is by its length
///   against the screen's: a bar that stops short of a corner is short by the
///   other bar's depth.
///
/// Under `panel_join` ([ThemeConfig.panelJoin]) the bars are one frame and the
/// theme's margins no longer decide whether two of them meet: every pair
/// [panelJoinsFor] finds is joined, and [panelScreenMargins] places them so
/// they do. That needs the compositor's corner placement *known*, not
/// measured, since a margin is what decides it: the top or bottom bar runs
/// across the corner ([panelCrossesCorners]) and the side bar's end stops
/// against it. That is Mir's own rule, and the root creates the top and bottom
/// bars before the side ones (`_createSurfaces`, `_syncPanels`) so that sway,
/// which places in the order surfaces were made, agrees.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/theme/panel_gradient.dart';

/// The bars a bar meets at its two ends, by their depth: 0 is no bar there.
///
/// A bar's *start* is its left end on a top or bottom bar and its top end on a
/// left or right one, so [start] and [end] read in the bar's own coordinates.
@immutable
class PanelJoins {
  const PanelJoins({this.start = 0, this.end = 0});

  /// The depth of the bar this one meets at its start, or 0.
  final double start;

  /// The depth of the bar this one meets at its end, or 0.
  final double end;

  static const PanelJoins none = PanelJoins();

  bool get isEmpty => start <= 0 && end <= 0;

  @override
  bool operator ==(Object other) =>
      other is PanelJoins && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'PanelJoins(start: $start, end: $end)';
}

/// The screen edge [anchor] names, with anything unrecognised read as `top` —
/// which is what an unknown anchor gets everywhere else
/// (`panelInsetsFor`, `anchorEdgesForPosition`).
String _edgeOf(String anchor) => switch (anchor) {
  'bottom' || 'left' || 'right' => anchor,
  _ => 'top',
};

bool _isVertical(String anchor) => isVerticalAnchor(anchor);

/// The bars [panel] meets at its ends, among [panels] — which includes [panel]
/// itself, and is the geometry the bars' windows were built from.
///
/// [PanelJoins.none] unless [panel] is the only bar on its edge; and an end
/// meets a bar only when exactly one bar is on the edge there.
PanelJoins panelJoinsFor(PanelConfig panel, Iterable<PanelConfig> panels) {
  final own = _edgeOf(panel.anchor);
  List<PanelConfig> on(String edge) => [
    for (final p in panels)
      if (_edgeOf(p.anchor) == edge) p,
  ];
  if (on(own).length != 1) return PanelJoins.none;
  double depthOn(String edge) {
    final there = on(edge);
    if (there.length != 1) return 0;
    final depth = there.single.height.toDouble();
    return depth > 0 ? depth : 0;
  }

  final vertical = _isVertical(own);
  return PanelJoins(
    start: depthOn(vertical ? 'top' : 'left'),
    end: depthOn(vertical ? 'bottom' : 'right'),
  );
}

/// The screen corners in which two of [panels] meet, read off the geometry
/// alone: what decides, against the theme's margins, whether
/// [panelSurfaceReach] grows the bars for a fillet at all — so a single bar is
/// never grown for a corner it does not have, nor a pair for a corner the theme
/// floats them apart in.
Set<PanelCorner> panelJoinCorners(Iterable<PanelConfig> panels) => {
  for (final panel in panels)
    ..._cornersOf(panel.anchor, panelJoinsFor(panel, panels)),
};

/// Whether any two of [panels] meet; see [panelJoinCorners].
bool panelsJoin(Iterable<PanelConfig> panels) =>
    panelJoinCorners(panels).isNotEmpty;

/// The screen corners a bar anchored to [anchor] meets [joins] in. A joined end
/// lies in the screen corner its own edge shares with the edge at that end.
Iterable<PanelCorner> _cornersOf(String anchor, PanelJoins joins) => [
  if (joins.start > 0) PanelCorner.of(anchor, outer: true, start: true),
  if (joins.end > 0) PanelCorner.of(anchor, outer: true, start: false),
];

/// Whether a bar anchored to [anchor] runs across the corner at a joined end —
/// whether the bar it meets there stops against this one's inner edge.
///
/// A top or bottom bar does and a side bar does not: Mir places the full-width
/// bars first and fits the side ones between them, and the root makes the
/// surfaces in that order for every other compositor's sake. Under
/// `panel_join` this is a rule the margins are built on rather than a
/// measurement ([panelScreenMargins]); the fillet still measures which bar is
/// short ([panelJoinOwnership]), because it can.
bool panelCrossesCorners(String anchor) => !isVerticalAnchor(anchor);

/// The fillet [theme] asks for, or 0 when it asks for none — and, unless the
/// theme joins its bars ([ThemeConfig.panelJoin]), always 0 when its margins
/// leave no corner of the screen where both bars would be flush, since bars
/// floating apart meet nowhere.
double panelJoinRadiusOf(ThemeConfig theme) {
  if (theme.panelJoinRadius <= 0) return 0.0;
  return theme.panelJoin || theme.panelMargin.anyFlushCorner
      ? theme.panelJoinRadius
      : 0.0;
}

/// [joins] as [theme] draws them on a bar anchored to [anchor].
///
/// Under `panel_join` every join, whatever the margins and whether or not
/// there is a fillet: the frame is closed by construction
/// ([panelScreenMargins]).
///
/// Otherwise each end's join while the theme has a fillet to put in it and the
/// screen corner at that end is flush for *both* bars that meet in it
/// ([PanelMargins.flushAt]) — this bar against its own edge and at that end,
/// and the bar across the corner likewise — and nothing otherwise. The two
/// read the corner from different keys, since margins are in each bar's own
/// frame, so this bar's margins alone cannot answer it. A theme without the
/// key keeps exactly the corners it always had, and a bar that floats off one
/// end can still meet its neighbour at the other.
PanelJoins activePanelJoins(
  ThemeConfig theme,
  PanelJoins joins, {
  String anchor = 'top',
}) {
  if (joins.isEmpty) return PanelJoins.none;
  if (theme.panelJoin) return joins;
  if (panelJoinRadiusOf(theme) <= 0) return PanelJoins.none;
  final margin = theme.panelMargin;
  bool flush(bool start) =>
      margin.flushAt(PanelCorner.of(anchor, outer: true, start: start));
  final active = PanelJoins(
    start: flush(true) ? joins.start : 0,
    end: flush(false) ? joins.end : 0,
  );
  return active.isEmpty ? PanelJoins.none : active;
}

/// The margins a bar anchored to [anchor] is given on the screen under
/// [theme], meeting [joins] (the geometry's, from [panelJoinsFor]) — what its
/// layer-shell surface is floated by, as the screen reads them.
///
/// Without `panel_join`, the theme's margins in the bar's own frame turned onto
/// the screen ([PanelMargins.onScreen]), exactly as they always were.
///
/// Under `panel_join` the margins are the frame's, in the screen's frame: the
/// bar stands off its own edge by that edge's margin, and off the screen's side
/// at either end by that side's — except at an end that meets another bar
/// where the other bar runs across the corner ([panelCrossesCorners]). A side
/// bar's end there is 0, because the compositor has already stopped it at the
/// other bar's exclusive zone, and that zone includes the other bar's margin
/// off its own edge. So a `bottom` margin lifts the bottom bar alone, and the
/// side bars' ends follow it up; and a `left` margin floats the left bar and
/// the top and bottom bars' left ends together, which is what keeps the corner
/// closed.
///
/// The side facing the middle of the screen is not anchored and never read.
PanelMargins panelScreenMargins(
  ThemeConfig theme,
  String anchor, {
  PanelJoins joins = PanelJoins.none,
}) {
  if (!theme.panelJoin) return theme.panelMargin.onScreen(anchor);
  final frame = theme.panelMargin;
  if (panelCrossesCorners(anchor)) return frame;
  final active = activePanelJoins(theme, joins, anchor: anchor);
  final (startEdge, endEdge) = panelEndEdges(anchor);
  var margin = frame;
  if (active.start > 0) margin = margin.withEdge(startEdge, 0);
  if (active.end > 0) margin = margin.withEdge(endEdge, 0);
  return margin;
}

/// How far a bar on the screen edge [edge] stands off it under [theme]: the
/// margin that edge's exclusive zone includes. The same for every bar on that
/// edge, joined or not.
int panelOuterMargin(ThemeConfig theme, String edge) =>
    panelScreenMargins(theme, edge).of(edge);

/// How far past its bar every panel's surface reaches under [theme]: the
/// foliage's overhang, or room for the fillet when the bars meet in any of the
/// screen corners [joined] that the theme leaves flush (any of them at all,
/// under `panel_join`) — whichever is the larger. The two share the one strip,
/// and the strip is handed back to the windows beneath either way.
int panelSurfaceReach(ThemeConfig theme, {required Set<PanelCorner> joined}) {
  final meets = theme.panelJoin
      ? joined.isNotEmpty
      : joined.any(theme.panelMargin.flushAt);
  final join = meets ? panelJoinRadiusOf(theme).ceil() : 0;
  return math.max(theme.panelReach, join);
}

/// How far two lengths may differ and still be read as the same: GDK reports a
/// monitor in whole logical pixels and a view under a fractional scale is laid
/// out in fractions of one.
const double _kLengthTolerance = 1.0;

/// Which of a bar's joined ends it paints the fillet at.
///
/// [length] is the bar's own length, along its axis, and [screenLength] the
/// screen's along the same axis. A bar the compositor stopped short of a
/// corner is short by the depth of the bar across that corner, and that bar is
/// the one whose end sits in the corner of the work area — so it paints there,
/// and the bar that spans the corner does not. Short by both neighbours, it
/// paints at both ends.
///
/// Two cases cannot be told apart and paint nothing rather than guess: short
/// by one neighbour's depth when the bars at its two ends are equally deep, and
/// a length that matches no arrangement at all (a compositor still configuring
/// the surface, or another client's bar reserving space too). A fillet painted
/// at the wrong end would lie over the other bar's modules.
///
/// With no [screenLength] — nothing to measure against — this falls back to
/// Mir's own rule, the compositor the shell is built for: full-width bars are
/// placed first and span the corners, so a side bar paints at both its ends and
/// a top or bottom bar at neither.
({bool start, bool end}) panelJoinOwnership({
  required PanelJoins joins,
  required bool vertical,
  required double length,
  required double? screenLength,
}) {
  if (screenLength == null) {
    return (start: vertical && joins.start > 0, end: vertical && joins.end > 0);
  }
  final short = screenLength - length;
  bool near(double a, double b) => (a - b).abs() < _kLengthTolerance;
  bool stoppedBy(double here, double there) {
    if (here <= 0) return false;
    if (there > 0 && near(short, here + there)) return true;
    if (!near(short, here)) return false;
    // Short by one bar's depth, and both bars are that deep: it is short at
    // one end or the other, and nothing says which.
    return !(there > 0 && (here - there).abs() < 2 * _kLengthTolerance);
  }

  return (
    start: stoppedBy(joins.start, joins.end),
    end: stoppedBy(joins.end, joins.start),
  );
}

/// The colour the bar is at its [start] (or its end): what the fillet there is
/// filled with, so it continues the bar rather than standing out of it.
///
/// Follows [ThemeConfig.panelGradient]:
///
/// - [PanelGradient.none]: `panel_background`, flat.
/// - [PanelGradient.accent]: the end `panelBackgroundDecoration` starts its
///   fade at is the accent, at the bar's one alpha, and the other end is
///   `panel_background` — and the two bars meeting in a corner are at the same
///   end of their fades there, so the fillet matches both of them.
/// - [PanelGradient.corners]: the corner colour at the bar's *inner* corner at
///   that end, which is the corner the fillet grows out of. The corners are the
///   bar's own as it sits on the screen, so this is exact for the bar painting
///   it; the bar across the corner blends its own corners and may differ.
Color panelJoinFill(ThemeConfig theme, String anchor, {required bool start}) {
  final edge = _edgeOf(anchor);
  switch (theme.panelGradient) {
    case PanelGradient.none:
      return theme.panelBackground;
    case PanelGradient.corners:
      return switch (edge) {
        'bottom' =>
          start ? theme.panelGradientTopLeft : theme.panelGradientTopRight,
        'left' =>
          start ? theme.panelGradientTopRight : theme.panelGradientBottomRight,
        'right' =>
          start ? theme.panelGradientTopLeft : theme.panelGradientBottomLeft,
        _ =>
          start
              ? theme.panelGradientBottomLeft
              : theme.panelGradientBottomRight,
      };
    case PanelGradient.accent:
      // `panelBackgroundDecoration`'s `begin`: the left end of a top bar, the
      // right of a bottom one, the top of a left one and the bottom of a right
      // one.
      final accentAtStart = switch (edge) {
        'bottom' || 'right' => false,
        _ => true,
      };
      return start == accentAtStart
          ? theme.accent.withValues(alpha: theme.panelBackground.a)
          : theme.panelBackground;
  }
}

/// Where a fillet sits in a bar's surface of [size]: the [corner] of the work
/// area, the unit vector [out] of the bar into the screen, and the unit vector
/// [along] the bar away from the end.
({Offset corner, Offset out, Offset along}) _filletFrame({
  required String anchor,
  required Size size,
  required double thickness,
  required bool start,
}) {
  final step = start ? 1.0 : -1.0;
  return switch (_edgeOf(anchor)) {
    'left' => (
      corner: Offset(thickness, start ? 0 : size.height),
      out: const Offset(1, 0),
      along: Offset(0, step),
    ),
    'right' => (
      corner: Offset(size.width - thickness, start ? 0 : size.height),
      out: const Offset(-1, 0),
      along: Offset(0, step),
    ),
    'bottom' => (
      corner: Offset(start ? 0 : size.width, size.height - thickness),
      out: const Offset(0, -1),
      along: Offset(step, 0),
    ),
    _ => (
      corner: Offset(start ? 0 : size.width, thickness),
      out: const Offset(0, 1),
      along: Offset(step, 0),
    ),
  };
}

/// The fillet at a bar's [start] (or end) in a surface of [size], as a closed
/// path: the corner of the work area, [radius] out along the other bar's inner
/// edge, the quarter round back to [radius] along this bar's own, and closed.
///
/// [rim] widens the round by half a rim either side and leaves it open — the
/// arc a rim of that width is stroked along, which picks up the two bars'
/// inner rims (each stroked inside its own bar) and turns the corner with them.
Path panelJoinPath({
  required String anchor,
  required Size size,
  required double thickness,
  required double radius,
  required bool start,
  double? rim,
}) {
  final f = _filletFrame(
    anchor: anchor,
    size: size,
    thickness: thickness,
    start: start,
  );
  final centre = f.corner + f.out * radius + f.along * radius;
  // From the point on the other bar's edge round to the point on this one's:
  // the quarter of the circle nearest the corner. A positive sweep is
  // clockwise on screen, which is the way round when `along` turns into `out`
  // clockwise.
  final cross = f.along.dx * f.out.dy - f.along.dy * f.out.dx;
  final sweep = cross > 0 ? math.pi / 2 : -math.pi / 2;
  final from = math.atan2(-f.along.dy, -f.along.dx);
  if (rim != null) {
    return Path()..addArc(
      Rect.fromCircle(center: centre, radius: radius + rim / 2),
      from,
      sweep,
    );
  }
  return Path()
    ..moveTo(f.corner.dx, f.corner.dy)
    ..lineTo(f.corner.dx + f.out.dx * radius, f.corner.dy + f.out.dy * radius)
    ..arcTo(Rect.fromCircle(center: centre, radius: radius), from, sweep, false)
    ..close();
}

/// Paints a bar's fillets: [atStart] and [atEnd] say which ends are this bar's
/// to fill (see [panelJoinOwnership]).
///
/// Painted over the whole surface — the bar and the strip past it — with the
/// bar [thickness] deep against the screen edge [anchor] names, so the fillet
/// lies entirely in the strip. Answers no hits: the strip belongs to the
/// windows beneath it, and the input region already says so.
///
/// The fillet continues the bar's colour, and a rimmed bar's rim round the
/// corner; it does not continue a material or picture, which are drawn per bar
/// and have no notion of the bar next door.
class PanelJoinPainter extends CustomPainter {
  const PanelJoinPainter({
    required this.anchor,
    required this.thickness,
    required this.radius,
    required this.atStart,
    required this.atEnd,
    required this.startFill,
    required this.endFill,
    required this.rimColor,
    required this.rimWidth,
  });

  final String anchor;
  final double thickness;
  final double radius;
  final bool atStart;
  final bool atEnd;
  final Color startFill;
  final Color endFill;

  /// [ThemeConfig.panelBorder] and [ThemeConfig.panelBorderWidth]; nothing is
  /// stroked at a width of 0.
  final Color rimColor;
  final double rimWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0) return;
    for (final (start, wanted, fill) in [
      (true, atStart, startFill),
      (false, atEnd, endFill),
    ]) {
      if (!wanted) continue;
      canvas.drawPath(
        panelJoinPath(
          anchor: anchor,
          size: size,
          thickness: thickness,
          radius: radius,
          start: start,
        ),
        Paint()..color = fill,
      );
      if (rimWidth > 0) {
        canvas.drawPath(
          panelJoinPath(
            anchor: anchor,
            size: size,
            thickness: thickness,
            radius: radius,
            start: start,
            rim: rimWidth,
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = rimWidth
            ..color = rimColor,
        );
      }
    }
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(PanelJoinPainter old) =>
      old.anchor != anchor ||
      old.thickness != thickness ||
      old.radius != radius ||
      old.atStart != atStart ||
      old.atEnd != atEnd ||
      old.startFill != startFill ||
      old.endFill != endFill ||
      old.rimColor != rimColor ||
      old.rimWidth != rimWidth;
}

/// A bar's fillets, for a surface laid out in [constraints]: nothing at all
/// unless [theme] has a fillet, [joins] meets a bar at an end the theme leaves
/// flush ([activePanelJoins]), and this bar is the one that paints there.
///
/// [screenSize] is read here, per layout, rather than handed in: a monitor
/// reconfigured under a bar resizes the bar's view, which re-runs the layout
/// this is called from.
Widget? panelJoinLayer({
  required ThemeConfig theme,
  required String anchor,
  required double thickness,
  required PanelJoins joins,
  required Size surface,
  required Size? Function()? screenSize,
}) {
  final radius = panelJoinRadiusOf(theme);
  final active = activePanelJoins(theme, joins, anchor: anchor);
  if (radius <= 0 || active.isEmpty) return null;
  final vertical = _isVertical(_edgeOf(anchor));
  final length = vertical ? surface.height : surface.width;
  final depth = vertical ? surface.width : surface.height;
  // The strip the surface was actually given: none at all when the shell could
  // not set an input region, and then no fillet rather than one that swallows
  // the clicks under it — `setPanelReach`'s rule.
  final strip = depth - thickness;
  final r = math.min(radius, math.min(strip, length / 2));
  if (r <= 0) return null;
  final screen = screenSize?.call();
  // Measured as though no margin had been taken off: a bar's own margin at an
  // end shortens it by that much, and a neighbour's zone there includes that
  // neighbour's margin off its own edge — which is the screen edge at this
  // bar's end, though without `panel_join` the two read it from different keys
  // (margins are in each bar's own frame). Without `panel_join` all are 0 at a
  // joined end, so this only keeps a floating far end from reading as a stop.
  final own = panelScreenMargins(theme, anchor, joins: joins);
  final (startEdge, endEdge) = panelEndEdges(anchor);
  final startMargin = own.of(startEdge).toDouble();
  final endMargin = own.of(endEdge).toDouble();
  final startZone = panelOuterMargin(theme, startEdge).toDouble();
  final endZone = panelOuterMargin(theme, endEdge).toDouble();
  final owns = panelJoinOwnership(
    joins: PanelJoins(
      start: joins.start > 0 ? joins.start + startZone : 0,
      end: joins.end > 0 ? joins.end + endZone : 0,
    ),
    vertical: vertical,
    length: length + startMargin + endMargin,
    screenLength: screen == null
        ? null
        : (vertical ? screen.height : screen.width),
  );
  final atStart = owns.start && active.start > 0;
  final atEnd = owns.end && active.end > 0;
  if (!atStart && !atEnd) return null;
  return IgnorePointer(
    child: CustomPaint(
      size: surface,
      painter: PanelJoinPainter(
        anchor: anchor,
        thickness: thickness,
        radius: r,
        atStart: atStart,
        atEnd: atEnd,
        startFill: panelJoinFill(theme, anchor, start: true),
        endFill: panelJoinFill(theme, anchor, start: false),
        rimColor: theme.panelBorder,
        rimWidth: theme.panelBorderWidth,
      ),
    ),
  );
}
