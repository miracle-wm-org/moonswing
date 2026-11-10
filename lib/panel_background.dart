import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/panel_join.dart';
import 'package:moonswing/theme/panel_gradient.dart';

/// The background drawn behind a panel's modules.
///
/// The bar's colour is [ThemeConfig.panelBackground] and its alpha is honoured as
/// written, so a translucent theme can see through the surface that sits directly
/// on the desktop.
///
/// [ThemeConfig.panelGradient] decides its shape:
///
/// - [PanelGradient.none] is that colour, flat.
/// - [PanelGradient.accent] fades from `accent` through `surfacePressed` to that
///   colour, with the bright end against the panel's own edge: top →
///   left-aligned, bottom → right, left → top, right → bottom. Every stop takes
///   its alpha from `panelBackground`, not from its own colour, so the bar has
///   exactly one opacity and no stop can read as a band across it.
/// - [PanelGradient.corners] blends the theme's four corner colours across the
///   bar ([PanelCornerDecoration]), each at its own alpha, with the corners
///   read as the bar sits on the screen.
///
/// Both shapes carry the bar's rim and its corner rounding
/// ([panelCornerRadius]); a theme that sets neither gets the decoration it
/// always did.
///
/// The bar's corner rounding, from [ThemeConfig.panelRadius], at the corners
/// [ThemeConfig.panelCorners] picks ([panelRoundedCorners]).
///
/// Both keys name their corners in the bar's own frame (`panel_shape.dart`),
/// so each screen corner a side bar rounds takes the radius its own frame names
/// it by ([PanelCorner.onBar]) — except under `panel_join`, where the bars are
/// one frame and each key names a corner of the screen, one radius for each
/// corner of the frame. The [BorderRadius] answered is the screen's either way.
///
/// Returns [BorderRadius.zero] when no corner rounds, which callers use to skip
/// the clip layer.
BorderRadius panelCornerRadius({
  String anchor = 'top',
  required ThemeConfig theme,
  PanelJoins joins = PanelJoins.none,
}) {
  final radii = theme.panelRadius;
  if (radii.isZero) return BorderRadius.zero;
  final corners = panelRoundedCorners(anchor: anchor, theme: theme, joins: joins);
  if (corners.isEmpty) return BorderRadius.zero;
  Radius at(PanelCorner corner) {
    if (!corners.contains(corner)) return Radius.zero;
    final r = radii.of(theme.panelJoin ? corner : corner.onBar(anchor));
    return r > 0 ? Radius.circular(r) : Radius.zero;
  }

  return BorderRadius.only(
    topLeft: at(PanelCorner.topLeft),
    topRight: at(PanelCorner.topRight),
    bottomRight: at(PanelCorner.bottomRight),
    bottomLeft: at(PanelCorner.bottomLeft),
  );
}

/// The *screen* corners of a bar anchored to [anchor] that `panel_corners`
/// lets round.
///
/// Under [PanelCornerChoice.auto] the two corners facing the screen's interior
/// round, and each corner against the screen edge rounds only where the bar is
/// off the display's own corner there — a margin on its own edge, or at that
/// end — because rounding one flush in the display's corner would cut a
/// wallpaper wedge out of it. A bar floating on every side therefore rounds
/// all four, a flush one the inner two, and one flush at one end and floating
/// at the other rounds both corners at the floating end. A chosen set of
/// corners is named in the bar's own frame and turned onto the screen
/// ([PanelCorner.onScreen]); under `panel_join` it is the screen's already.
/// The margins read are the ones the bar is actually given
/// ([panelScreenMargins]).
///
/// Either way, the inner corner at an end that meets another bar ([joins],
/// while the theme joins them — [activePanelJoins]) is square: the two bars are
/// one frame across that corner, and a rounded one would cut a notch out of it
/// — the fillet is what turns it now (`panel_join.dart`). A side bar squares
/// its outer corner there too, since its end butts against the inner edge of
/// the bar running across the corner ([panelCrossesCorners]), which holds the
/// frame's corner itself.
///
/// Under `panel_square_flush_corners` a corner lying on a screen edge the bar
/// touches — anchored there with no margin between them — is square as well.
Set<PanelCorner> panelRoundedCorners({
  String anchor = 'top',
  required ThemeConfig theme,
  PanelJoins joins = PanelJoins.none,
}) {
  final margin = panelScreenMargins(theme, anchor, joins: joins);
  final (startEdge, endEdge) = panelEndEdges(anchor);
  final floats = margin.of(anchor) > 0;
  final chosen = theme.panelCorners.corners;
  final rounded = chosen != null
      ? {
          for (final corner in chosen)
            theme.panelJoin ? corner : corner.onScreen(anchor),
        }
      : {
          PanelCorner.of(anchor, outer: false, start: true),
          PanelCorner.of(anchor, outer: false, start: false),
          if (floats || margin.of(startEdge) > 0)
            PanelCorner.of(anchor, outer: true, start: true),
          if (floats || margin.of(endEdge) > 0)
            PanelCorner.of(anchor, outer: true, start: false),
        };
  final joined = activePanelJoins(theme, joins, anchor: anchor);
  final butts = !panelCrossesCorners(anchor);
  for (final (start, depth) in [(true, joined.start), (false, joined.end)]) {
    if (depth <= 0) continue;
    rounded.remove(PanelCorner.of(anchor, outer: false, start: start));
    if (butts) rounded.remove(PanelCorner.of(anchor, outer: true, start: start));
  }
  if (theme.panelSquareFlushCorners) {
    final touching = {
      for (final edge in [screenEdgeOf(anchor), startEdge, endEdge])
        if (margin.of(edge) == 0) edge,
    };
    rounded.removeWhere((corner) {
      final (across, along) = corner.edges;
      return touching.contains(across) || touching.contains(along);
    });
  }
  return rounded;
}

/// The screen edges a bar anchored to [anchor] lies flush against, meeting
/// [joins] (the geometry's, from `panelJoinsFor`): the sides of the bar its
/// rim leaves out.
///
/// A rim is a boundary between the bar and what is beside it, and along a
/// screen edge there is nothing beside it — the line would only draw the edge
/// of the display a second time, a pixel in. So a side of the bar is left
/// unrimmed exactly where there is no margin between it and the screen edge:
/// its outer side when the margin off its own edge is 0, and an end when the
/// margin off that side of the screen is 0. A margin above zero floats that
/// side off the edge and it keeps its rim.
///
/// An end that butts against another bar rather than the screen is not flush,
/// whatever its margin says: a side bar's end stops at the inner edge of the
/// bar running across the corner ([panelCrossesCorners]), so there is a bar
/// beside it, not the screen's edge. Its seam, where the theme joins the two,
/// is `panelJoinSeams`' (`panel_rim.dart`) to leave out. The inner side,
/// facing the middle of the screen, is never flush.
///
/// The margins read are the ones the bar is actually given
/// ([panelScreenMargins]), and the edges are the screen's.
Set<String> panelFlushEdges({
  String anchor = 'top',
  required ThemeConfig theme,
  PanelJoins joins = PanelJoins.none,
}) {
  final margin = panelScreenMargins(theme, anchor, joins: joins);
  final (startEdge, endEdge) = panelEndEdges(anchor);
  final crosses = panelCrossesCorners(anchor);
  return {
    if (margin.of(anchor) == 0) screenEdgeOf(anchor),
    if (margin.of(startEdge) == 0 && (crosses || joins.start <= 0)) startEdge,
    if (margin.of(endEdge) == 0 && (crosses || joins.end <= 0)) endEdge,
  };
}

/// The breathing room between a module's fill and the bar's edge.
const double kPanelModuleGap = 2;

/// How far the modules sit in from each long edge of the bar: the rim's width,
/// then [kPanelModuleGap].
///
/// A module's hover or active fill takes the bar's whole depth (`BarFill`), and
/// laid out across the bar's full box it ran over the rim — both the
/// decoration's `Border` and `PanelRimPainter` stroke *inside* the bar's box —
/// so a highlighted workspace sat flush against, and on top of, the line around
/// it. The panel insets its module area by this across its depth, and anything
/// that sizes itself to `BarScope.thickness` subtracts it twice.
///
/// Under `panel_sections` the modules sit inside a section's island as well,
/// which is a bar in miniature: its rim, then the same gap
/// ([panelSectionInnerInset]).
double panelModuleInset(ThemeConfig theme) =>
    panelContentInset(theme) + panelSectionInnerInset(theme);

/// How far the bar's content — its sections, and under `panel_sections` the
/// islands they are drawn on — sits in from each long edge of the bar: the
/// rim's width, then [kPanelModuleGap].
double panelContentInset(ThemeConfig theme) =>
    (theme.panelBorderWidth > 0 ? theme.panelBorderWidth : 0) +
    kPanelModuleGap;

/// How far a section's modules sit in from each long edge of its island under
/// `panel_sections`: the island's rim, then [kPanelModuleGap] — so a hover fill
/// stops short of the island's edge exactly as it stops short of the bar's.
/// Zero with `panel_sections` off, where there is no island.
double panelSectionInnerInset(ThemeConfig theme) => theme.panelSections
    ? (theme.panelSectionBorderWidth > 0 ? theme.panelSectionBorderWidth : 0) +
          kPanelModuleGap
    : 0;

/// The bar's rim, or null when [ThemeConfig.panelBorderWidth] is 0.
///
/// Width is the off switch rather than alpha, and null rather than a zero-width
/// [Border] on purpose: a `Border` in the decoration carries a non-zero
/// [BoxDecoration.padding], which a [Container] would apply to the bar's content.
Border? _panelBorder(ThemeConfig theme) => theme.panelBorderWidth > 0
    ? Border.all(color: theme.panelBorder, width: theme.panelBorderWidth)
    : null;

/// [theme] is required on purpose: a defaulted palette here would silently
/// paint the built-in colours over whatever theme is actually active.
///
/// [includeRim] false leaves the border out for a bar that paints its own —
/// which is a rimmed bar whose rim has to be interrupted somewhere, and no
/// [Border.all] can have a gap in it: across the mouth of an open menu when the
/// theme attaches its popups, and along every side that lies flush against the
/// screen ([panelFlushEdges]). `panelPaintsOwnRim` (`panel_rim.dart`) is the
/// predicate, [PanelRimPainter] draws what this then leaves out, and the two
/// agree on the outline: `Border.all` strokes it deflated by half its width and
/// so does the painter.
///
/// [joins] squares the corners [panelCornerRadius] squares.
BoxDecoration panelBackgroundDecoration({
  String anchor = 'top',
  required ThemeConfig theme,
  bool includeRim = true,
  PanelJoins joins = PanelJoins.none,
}) {
  final radius = panelCornerRadius(anchor: anchor, theme: theme, joins: joins);
  // Normalised to null rather than BorderRadius.zero so that an untouched
  // theme produces exactly the decoration it did before corners were themable.
  final BorderRadius? borderRadius =
      radius == BorderRadius.zero ? null : radius;
  final border = includeRim ? _panelBorder(theme) : null;
  return panelFillDecoration(
    theme: theme,
    gradient: theme.panelGradient,
    base: theme.panelBackground,
    anchor: anchor,
    borderRadius: borderRadius,
    border: border,
  );
}

/// A bar-shaped fill: [base] in the shape [gradient] names, under [border]
/// and [borderRadius] — the bar's own ([panelBackgroundDecoration]), and under
/// `panel_sections` each section's island's (`panel_section.dart`), which is
/// why the colour and the shape are parameters rather than read off [theme].
///
/// [theme] supplies what a shape borrows from the rest of the palette: the
/// accent fade's `accent` and `surfacePressed`, and the four corner colours.
BoxDecoration panelFillDecoration({
  required ThemeConfig theme,
  required PanelGradient gradient,
  required Color base,
  String anchor = 'top',
  BorderRadius? borderRadius,
  BoxBorder? border,
}) {
  if (gradient == PanelGradient.corners) {
    return PanelCornerDecoration(
      corners: PanelCorners.of(theme),
      borderRadius: borderRadius,
      border: border,
    );
  }

  if (gradient == PanelGradient.none) {
    return BoxDecoration(
      color: base,
      borderRadius: borderRadius,
      border: border,
    );
  }

  final alpha = base.a;
  final dark = base;
  final mid = theme.surfacePressed.withValues(alpha: alpha);
  final light = theme.accent.withValues(alpha: alpha);

  late final Alignment begin;
  late final Alignment end;
  switch (anchor) {
    case 'bottom':
      begin = Alignment.centerRight;
      end = Alignment.centerLeft;
      break;
    case 'left':
      begin = Alignment.topCenter;
      end = Alignment.bottomCenter;
      break;
    case 'right':
      begin = Alignment.bottomCenter;
      end = Alignment.topCenter;
      break;
    case 'top':
    default:
      begin = Alignment.centerLeft;
      end = Alignment.centerRight;
      break;
  }

  return BoxDecoration(
    gradient: LinearGradient(
      begin: begin,
      end: end,
      colors: [light, mid, dark],
      stops: const [0.0, 0.5, 1.0],
    ),
    borderRadius: borderRadius,
    border: border,
  );
}

/// The four colours of a [PanelGradient.corners] bar, as it sits on the screen.
@immutable
class PanelCorners {
  const PanelCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// The corners [theme] names.
  factory PanelCorners.of(ThemeConfig theme) => PanelCorners(
    topLeft: theme.panelGradientTopLeft,
    topRight: theme.panelGradientTopRight,
    bottomRight: theme.panelGradientBottomRight,
    bottomLeft: theme.panelGradientBottomLeft,
  );

  final Color topLeft;
  final Color topRight;
  final Color bottomRight;
  final Color bottomLeft;

  /// The colour at ([u], [v]) across the bar, each from 0 at the left or top
  /// edge to 1 at the right or bottom: the two along the top and the two along
  /// the bottom blended across, then those two blended down — bilinear, so
  /// every straight line parallel to an edge is a straight fade, and an edge
  /// is exactly the fade between its own two corners.
  Color at(double u, double v) => Color.lerp(
    Color.lerp(topLeft, topRight, u),
    Color.lerp(bottomLeft, bottomRight, u),
    v,
  )!;

  @override
  bool operator ==(Object other) =>
      other is PanelCorners &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);

  @override
  String toString() =>
      'PanelCorners($topLeft, $topRight, $bottomRight, $bottomLeft)';
}

/// A bar's background under [PanelGradient.corners]: [corners] blended across
/// the box, under the same rim and rounding as every other bar.
///
/// A [BoxDecoration] so it is everything the plain bar's is — its padding, its
/// hit test, its clip path, the [border] and [borderRadius] the rim painter and
/// the tests read — with only the fill replaced. The fill cannot be a
/// [Gradient]: a gradient is a shader, and `dart:ui` has no shader that
/// interpolates in two directions at once. The two ways to make one are a
/// fragment program (an asset, and the shell ships none) or a 2×2 image drawn
/// with bilinear filtering — which has to be rasterized, and `toImageSync`
/// is what crashed the engine for the materials (`MaterialTextures`), while
/// an asynchronous one paints the bar the wrong colour for a frame. So the
/// fill is a mesh: a grid of triangles with a colour at every vertex, which
/// the rasterizer blends across each triangle in one draw call, with no layer
/// and no image.
///
/// A triangle blends linearly, not bilinearly, so a single quad would show a
/// crease along its diagonal wherever the four corners do not lie on one
/// plane. [_kMeshCells] cells a side keeps the difference under one 8-bit
/// step for any four colours whatever.
class PanelCornerDecoration extends BoxDecoration {
  const PanelCornerDecoration({
    required this.corners,
    super.borderRadius,
    super.border,
  });

  final PanelCorners corners;

  @override
  PanelCornerDecoration scale(double factor) => PanelCornerDecoration(
    corners: PanelCorners(
      topLeft: Color.lerp(null, corners.topLeft, factor)!,
      topRight: Color.lerp(null, corners.topRight, factor)!,
      bottomRight: Color.lerp(null, corners.bottomRight, factor)!,
      bottomLeft: Color.lerp(null, corners.bottomLeft, factor)!,
    ),
    borderRadius: borderRadius,
    border: border?.scale(factor) as BoxBorder?,
  );

  // BoxDecoration's own lerp would hand back a plain BoxDecoration and drop
  // the fill halfway through. Nothing animates a bar's decoration — a theme
  // switch rebuilds it from a blended palette instead — so between two of
  // these the corners blend, from or to nothing they fade, and against any
  // other decoration this answers null, which `Decoration.lerp` takes as
  // "snap at the halfway mark".
  @override
  BoxDecoration? lerpFrom(Decoration? a, double t) {
    if (a == null) return scale(t);
    if (a is PanelCornerDecoration) return _lerp(a, this, t);
    return null;
  }

  @override
  BoxDecoration? lerpTo(Decoration? b, double t) {
    if (b == null) return scale(1.0 - t);
    if (b is PanelCornerDecoration) return _lerp(this, b, t);
    return null;
  }

  static PanelCornerDecoration _lerp(
    PanelCornerDecoration a,
    PanelCornerDecoration b,
    double t,
  ) => PanelCornerDecoration(
    corners: PanelCorners(
      topLeft: Color.lerp(a.corners.topLeft, b.corners.topLeft, t)!,
      topRight: Color.lerp(a.corners.topRight, b.corners.topRight, t)!,
      bottomRight: Color.lerp(a.corners.bottomRight, b.corners.bottomRight, t)!,
      bottomLeft: Color.lerp(a.corners.bottomLeft, b.corners.bottomLeft, t)!,
    ),
    borderRadius: BorderRadiusGeometry.lerp(a.borderRadius, b.borderRadius, t),
    border: BoxBorder.lerp(a.border, b.border, t),
  );

  @override
  bool operator ==(Object other) =>
      other is PanelCornerDecoration &&
      other.corners == corners &&
      other.borderRadius == borderRadius &&
      other.border == border;

  @override
  int get hashCode => Object.hash(corners, borderRadius, border);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<PanelCorners>('corners', corners));
  }

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _PanelCornerPainter(this, onChanged);
}

/// Cells along each side of the mesh. The crease a triangle leaves is at most
/// a quarter of the four corners' departure from a plane times the cell's
/// share of each side, so twelve keeps it to 1/288 of the widest swing any
/// channel can make — under one step of 255. A bar has a few thousand pixels
/// of length and a few dozen of depth, so cells the same count each way are
/// long and flat; the arithmetic is in proportions, not pixels.
const int _kMeshCells = 12;

/// The mesh's triangle indices, which depend only on [_kMeshCells].
final Uint16List _meshIndices = () {
  const side = _kMeshCells + 1;
  final indices = Uint16List(_kMeshCells * _kMeshCells * 6);
  var i = 0;
  for (var row = 0; row < _kMeshCells; row++) {
    for (var col = 0; col < _kMeshCells; col++) {
      final a = row * side + col;
      final b = a + 1;
      final c = a + side;
      final d = c + 1;
      indices
        ..[i++] = a
        ..[i++] = b
        ..[i++] = d
        ..[i++] = a
        ..[i++] = d
        ..[i++] = c;
    }
  }
  return indices;
}();

/// The mesh's vertex colours for [corners], which depend on nothing else.
Int32List _meshColors(PanelCorners corners) {
  const side = _kMeshCells + 1;
  final colors = Int32List(side * side);
  for (var row = 0; row < side; row++) {
    for (var col = 0; col < side; col++) {
      colors[row * side + col] = corners
          .at(col / _kMeshCells, row / _kMeshCells)
          .toARGB32()
          .toSigned(32);
    }
  }
  return colors;
}

class _PanelCornerPainter extends BoxPainter {
  _PanelCornerPainter(this._decoration, super.onChanged)
    : _colors = _meshColors(_decoration.corners);

  final PanelCornerDecoration _decoration;

  /// Computed once: a decoration is immutable, so a new palette is a new
  /// painter.
  final Int32List _colors;

  /// The mesh for [_meshRect], kept because a bar repaints far more often
  /// than it is resized — every hover and every clock tick re-records it.
  ui.Vertices? _mesh;
  Rect? _meshRect;

  ui.Vertices _meshFor(Rect rect) {
    final cached = _mesh;
    if (cached != null && rect == _meshRect) return cached;
    cached?.dispose();
    const side = _kMeshCells + 1;
    final positions = Float32List(side * side * 2);
    var i = 0;
    for (var row = 0; row < side; row++) {
      final y = rect.top + rect.height * row / _kMeshCells;
      for (var col = 0; col < side; col++) {
        positions[i++] = rect.left + rect.width * col / _kMeshCells;
        positions[i++] = y;
      }
    }
    _meshRect = rect;
    return _mesh = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      colors: _colors,
      indices: _meshIndices,
    );
  }

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final rect = offset & size;
    final textDirection = configuration.textDirection;
    final radius = _decoration.borderRadius?.resolve(textDirection);

    final rounded = radius != null && radius != BorderRadius.zero;
    if (rounded) {
      canvas
        ..save()
        ..clipRRect(radius.toRRect(rect));
    }
    // BlendMode.dst: the vertices' own colours, untouched by the paint's —
    // the paint carries no colour of its own to combine them with.
    canvas.drawVertices(_meshFor(rect), BlendMode.dst, Paint());
    if (rounded) canvas.restore();

    _decoration.border?.paint(
      canvas,
      rect,
      borderRadius: radius,
      textDirection: textDirection,
    );
  }

  @override
  void dispose() {
    _mesh?.dispose();
    _mesh = null;
    super.dispose();
  }
}
