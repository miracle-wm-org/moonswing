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
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:moonswing/config.dart';

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

bool _isVertical(String anchor) => anchor == 'left' || anchor == 'right';

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

/// Whether any two of [panels] meet: what decides whether [panelSurfaceReach]
/// grows the bars for a fillet at all, so a single bar is never grown for a
/// corner it does not have.
bool panelsJoin(Iterable<PanelConfig> panels) {
  for (final panel in panels) {
    if (!panelJoinsFor(panel, panels).isEmpty) return true;
  }
  return false;
}

/// The fillet [theme] asks for, or 0 when it asks for none — and always 0 on a
/// floating bar, which meets nothing.
double panelJoinRadiusOf(ThemeConfig theme) =>
    theme.panelMargin <= 0 && theme.panelJoinRadius > 0
    ? theme.panelJoinRadius
    : 0.0;

/// [joins] as [theme] draws them: the joins themselves while the theme has a
/// fillet to put in them, and [PanelJoins.none] while it has not — so a theme
/// without the key keeps exactly the corners it always had.
PanelJoins activePanelJoins(ThemeConfig theme, PanelJoins joins) =>
    panelJoinRadiusOf(theme) > 0 ? joins : PanelJoins.none;

/// How far past its bar every panel's surface reaches under [theme]: the
/// foliage's overhang, or room for the fillet when [joined] — any two bars
/// meet — whichever is the larger. The two share the one strip, and the strip
/// is handed back to the windows beneath either way.
int panelSurfaceReach(ThemeConfig theme, {required bool joined}) {
  final join = joined ? panelJoinRadiusOf(theme).ceil() : 0;
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
/// Flat on a flat bar. On a gradient bar the end `panelBackgroundDecoration`
/// starts its fade at is the accent, at the bar's one alpha, and the other end
/// is `panel_background` — and the two bars meeting in a corner are at the
/// same end of their fades there, so the fillet matches both of them.
Color panelJoinFill(ThemeConfig theme, String anchor, {required bool start}) {
  if (!theme.panelGradient) return theme.panelBackground;
  // `panelBackgroundDecoration`'s `begin`: the left end of a top bar, the right
  // of a bottom one, the top of a left one and the bottom of a right one.
  final accentAtStart = switch (_edgeOf(anchor)) {
    'bottom' || 'right' => false,
    _ => true,
  };
  return start == accentAtStart
      ? theme.accent.withValues(alpha: theme.panelBackground.a)
      : theme.panelBackground;
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
/// unless [theme] has a fillet, [joins] meets a bar, and this bar is the one
/// that paints there.
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
  if (radius <= 0 || joins.isEmpty) return null;
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
  final own = panelJoinOwnership(
    joins: joins,
    vertical: vertical,
    length: length,
    screenLength: screen == null
        ? null
        : (vertical ? screen.height : screen.width),
  );
  if (!own.start && !own.end) return null;
  return IgnorePointer(
    child: CustomPaint(
      size: surface,
      painter: PanelJoinPainter(
        anchor: anchor,
        thickness: thickness,
        radius: r,
        atStart: own.start,
        atEnd: own.end,
        startFill: panelJoinFill(theme, anchor, start: true),
        endFill: panelJoinFill(theme, anchor, start: false),
        rimColor: theme.panelBorder,
        rimWidth: theme.panelBorderWidth,
      ),
    ),
  );
}
