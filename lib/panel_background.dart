import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:moonswing/config.dart';
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
/// The bar's corner rounding, from [ThemeConfig.panelRadius].
///
/// A floating bar rounds all four corners. A flush one rounds only the two facing
/// the screen's interior: rounding the pair against the screen edge would cut
/// wallpaper wedges out of the display's own corners.
///
/// Returns [BorderRadius.zero] for a radius of 0, which callers use to skip the
/// clip layer.
BorderRadius panelCornerRadius({
  String anchor = 'top',
  required ThemeConfig theme,
}) {
  if (theme.panelRadius <= 0) return BorderRadius.zero;
  final r = Radius.circular(theme.panelRadius);
  if (theme.panelMargin > 0) return BorderRadius.all(r);

  switch (anchor) {
    case 'bottom':
      return BorderRadius.only(topLeft: r, topRight: r);
    case 'left':
      return BorderRadius.only(topRight: r, bottomRight: r);
    case 'right':
      return BorderRadius.only(topLeft: r, bottomLeft: r);
    case 'top':
    default:
      return BorderRadius.only(bottomLeft: r, bottomRight: r);
  }
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
double panelModuleInset(ThemeConfig theme) =>
    (theme.panelBorderWidth > 0 ? theme.panelBorderWidth : 0) +
    kPanelModuleGap;

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
/// which is a bar whose theme attaches its popups and carries a rim, because
/// that rim has to be interrupted across the mouth of an open menu and no
/// [Border] can have a gap in it. `panelPaintsOwnRim` (`panel_rim.dart`) is the
/// predicate, [PanelRimPainter] draws what this then leaves out, and the two
/// agree on the outline: `Border.all` strokes it deflated by half its width and
/// so does the painter.
BoxDecoration panelBackgroundDecoration({
  String anchor = 'top',
  required ThemeConfig theme,
  bool includeRim = true,
}) {
  final radius = panelCornerRadius(anchor: anchor, theme: theme);
  // Normalised to null rather than BorderRadius.zero so that an untouched
  // theme produces exactly the decoration it did before corners were themable.
  final BorderRadius? borderRadius =
      radius == BorderRadius.zero ? null : radius;
  final border = includeRim ? _panelBorder(theme) : null;

  if (theme.panelGradient == PanelGradient.corners) {
    return PanelCornerDecoration(
      corners: PanelCorners.of(theme),
      borderRadius: borderRadius,
      border: border,
    );
  }

  if (theme.panelGradient == PanelGradient.none) {
    return BoxDecoration(
      color: theme.panelBackground,
      borderRadius: borderRadius,
      border: border,
    );
  }

  final alpha = theme.panelBackground.a;
  final dark = theme.panelBackground;
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
