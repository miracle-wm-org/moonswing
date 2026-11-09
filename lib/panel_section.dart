import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/panel_background.dart';

/// One section of a bar — its left, centre or right group of modules — and,
/// under `panel_sections`, the island that section is drawn on.
///
/// The island is drawn *tightly* round what the section holds: along the bar
/// it is the modules' own extent plus `panel_section_padding` at either end,
/// and across it takes the whole depth it is given (the bar's, inside its
/// rim), so every island on a bar is one height whatever its modules measure.
/// The modules sit inside the island's rim a couple of pixels clear
/// ([panelSectionInnerInset]), as they sit inside the bar's, and are clipped
/// to its rounding so a hover fill at either end follows the curve.
///
/// Decided at *layout*, from what the section measured, for the reason
/// `BarModuleRow` decides its gaps there: a section whose every module is
/// empty on this machine (a tray nothing has registered with, a battery on a
/// tower) measures nothing along the bar, and then draws no island and takes
/// no room — an empty capsule would be exactly the placeholder an empty
/// module is not allowed to leave. A module appearing later brings the island
/// back on the same frame.
///
/// Always in the tree, whatever the theme: with `panel_sections` off ([theme]
/// null) it lays its child out exactly as the bar always did and paints
/// nothing of its own, so a theme switch that turns islands on or off moves no
/// module to a new depth — which would dispose every one of them
/// (`PanelContentFrame` has the history).
///
/// Answers no hits itself: a click on an island's padding falls through to
/// the bar beneath, whose right-click menu is the one that belongs there.
class PanelSection extends SingleChildRenderObjectWidget {
  const PanelSection({
    super.key,
    required this.axis,
    required this.theme,
    this.anchor = 'top',
    super.child,
  });

  /// [Axis.horizontal] on a top or bottom bar, [Axis.vertical] on a side one.
  final Axis axis;

  /// The theme the island is drawn from, or null for no island — pass
  /// [PanelSection.themeFor]'s answer.
  final ThemeConfig? theme;

  /// The bar's anchor, which an accent fade reads its direction from.
  final String anchor;

  /// [theme] when it draws islands, and null otherwise — so a theme without
  /// them hands every section the same null and nothing repaints.
  static ThemeConfig? themeFor(ThemeConfig theme) =>
      theme.panelSections ? theme : null;

  @override
  RenderPanelSection createRenderObject(BuildContext context) =>
      RenderPanelSection(axis: axis, theme: theme, anchor: anchor);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPanelSection renderObject,
  ) {
    renderObject
      ..axis = axis
      ..theme = theme
      ..anchor = anchor;
  }
}

class RenderPanelSection extends RenderShiftedBox {
  RenderPanelSection({
    required Axis axis,
    ThemeConfig? theme,
    String anchor = 'top',
    RenderBox? child,
  }) : _axis = axis,
       _theme = theme,
       _anchor = anchor,
       super(child);

  Axis get axis => _axis;
  Axis _axis;
  set axis(Axis value) {
    if (_axis == value) return;
    _axis = value;
    markNeedsLayout();
  }

  ThemeConfig? get theme => _theme;
  ThemeConfig? _theme;
  set theme(ThemeConfig? value) {
    if (_theme == value) return;
    final old = _theme;
    _theme = value;
    _dropPainter();
    // A palette moving (a theme switch blends colours every frame) is a
    // repaint; anything that moves the modules is a relayout.
    if (old == null ||
        value == null ||
        old.panelSectionPadding != value.panelSectionPadding ||
        panelSectionInnerInset(old) != panelSectionInnerInset(value)) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  String get anchor => _anchor;
  String _anchor;
  set anchor(String value) {
    if (_anchor == value) return;
    _anchor = value;
    _dropPainter();
    markNeedsPaint();
  }

  /// Whether the last layout found anything to draw an island round.
  bool _shown = false;

  /// Whether an island is drawn this frame — [theme] on, and the section
  /// holding something. Exposed for tests.
  bool get showsIsland => _theme != null && _shown;

  bool get _horizontal => _axis == Axis.horizontal;

  double _main(Size size) => _horizontal ? size.width : size.height;
  double _cross(Size size) => _horizontal ? size.height : size.width;

  Size _oriented(double main, double cross) =>
      _horizontal ? Size(main, cross) : Size(cross, main);

  double get _padding => _theme?.panelSectionPadding ?? 0;
  double get _inset => _theme == null ? 0 : panelSectionInnerInset(_theme!);

  /// What the modules are offered: the island's inside, which is the whole
  /// incoming box with the theme off.
  BoxConstraints _innerConstraints(BoxConstraints constraints) {
    if (_theme == null) return constraints;
    final along = 2 * _padding;
    final across = 2 * _inset;
    return constraints.deflate(
      _horizontal
          ? EdgeInsets.symmetric(horizontal: along / 2, vertical: across / 2)
          : EdgeInsets.symmetric(horizontal: across / 2, vertical: along / 2),
    );
  }

  /// The section's size, given what the modules measured.
  Size _outerSize(BoxConstraints constraints, Size inner) {
    if (_theme == null) return constraints.constrain(inner);
    // Nothing to show is no island, and no room.
    if (_main(inner) <= 0) return constraints.constrain(Size.zero);
    final main = _main(inner) + 2 * _padding;
    // The whole depth, so every island on a bar is one height; outside a bar
    // (unbounded across), the modules' own and the inset.
    final maxCross = _horizontal ? constraints.maxHeight : constraints.maxWidth;
    final cross = maxCross.isFinite ? maxCross : _cross(inner) + 2 * _inset;
    return constraints.constrain(_oriented(main, cross));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final inner =
        child?.getDryLayout(_innerConstraints(constraints)) ?? Size.zero;
    return _outerSize(constraints, inner);
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      _shown = false;
      size = constraints.smallest;
      return;
    }
    child.layout(_innerConstraints(constraints), parentUsesSize: true);
    size = _outerSize(constraints, child.size);
    _shown = _main(child.size) > 0;
    final parentData = child.parentData! as BoxParentData;
    if (_theme == null) {
      parentData.offset = Offset.zero;
      return;
    }
    // Centred both ways in the island: the padding along, the depth across.
    parentData.offset = Offset(
      (size.width - child.size.width) / 2,
      (size.height - child.size.height) / 2,
    );
  }

  double _intrinsicMain(double childExtent) =>
      _theme == null || childExtent <= 0 ? childExtent : childExtent + 2 * _padding;

  double _intrinsicCross(double childExtent) =>
      _theme == null ? childExtent : childExtent + 2 * _inset;

  @override
  double computeMinIntrinsicWidth(double height) {
    final w = child?.getMinIntrinsicWidth(height) ?? 0;
    return _horizontal ? _intrinsicMain(w) : _intrinsicCross(w);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final w = child?.getMaxIntrinsicWidth(height) ?? 0;
    return _horizontal ? _intrinsicMain(w) : _intrinsicCross(w);
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final h = child?.getMinIntrinsicHeight(width) ?? 0;
    return _horizontal ? _intrinsicCross(h) : _intrinsicMain(h);
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final h = child?.getMaxIntrinsicHeight(width) ?? 0;
    return _horizontal ? _intrinsicCross(h) : _intrinsicMain(h);
  }

  /// The island's rounding at [size]: the theme's, clamped to half the
  /// island's shorter side, so a large radius is a capsule rather than a
  /// shape the border painter has to scale down on its own.
  BorderRadius _radiusFor(Size size) {
    final r = math.min(
      _theme!.panelSectionRadius,
      math.min(size.width, size.height) / 2,
    );
    return r > 0 ? BorderRadius.circular(r) : BorderRadius.zero;
  }

  /// The island's decoration at [size]; see [panelSectionDecoration].
  Decoration _decorationFor(Size size) =>
      panelSectionDecoration(_theme!, anchor: _anchor, radius: _radiusFor(size));

  BoxPainter? _painter;
  Size? _painterSize;

  void _dropPainter() {
    _painter?.dispose();
    _painter = null;
    _painterSize = null;
  }

  @override
  void detach() {
    _dropPainter();
    super.detach();
  }

  @override
  void dispose() {
    _dropPainter();
    _clip.layer = null;
    super.dispose();
  }

  final LayerHandle<ClipRRectLayer> _clip = LayerHandle<ClipRRectLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!showsIsland) {
      _clip.layer = null;
      super.paint(context, offset);
      return;
    }
    // Kept across paints, because a bar repaints far more often than an
    // island changes size — every hover and every clock tick re-records it.
    if (_painter == null || _painterSize != size) {
      _painter?.dispose();
      _painter = _decorationFor(size).createBoxPainter(markNeedsPaint);
      _painterSize = size;
    }
    _painter!.paint(
      context.canvas,
      offset,
      ImageConfiguration(size: size, textDirection: TextDirection.ltr),
    );

    final child = this.child;
    if (child == null) return;
    final childOffset = (child.parentData! as BoxParentData).offset;
    final radius = _radiusFor(size);
    if (radius == BorderRadius.zero) {
      _clip.layer = null;
      context.paintChild(child, offset + childOffset);
      return;
    }
    // Inside the rim, so nothing a module paints can cover the line.
    final rim = _theme!.panelSectionBorderWidth;
    final clip = radius
        .toRRect(Offset.zero & size)
        .deflate(rim > 0 ? rim : 0);
    _clip.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      clip.outerRect,
      clip,
      (context, offset) => context.paintChild(child, offset + childOffset),
      oldLayer: _clip.layer,
    );
  }
}

/// A section's island under `panel_sections`: `panel_section_background` in the
/// shape `panel_section_gradient` names, under its own rim and [radius].
///
/// The same fill the bar is painted with ([panelFillDecoration]) — an accent
/// fade runs the way the bar's does on that edge, and the four corner colours
/// are the bar's — spanning the island rather than the bar.
BoxDecoration panelSectionDecoration(
  ThemeConfig theme, {
  String anchor = 'top',
  BorderRadius radius = BorderRadius.zero,
}) => panelFillDecoration(
  theme: theme,
  gradient: theme.panelSectionGradient,
  base: theme.panelSectionBackground,
  anchor: anchor,
  borderRadius: radius == BorderRadius.zero ? null : radius,
  border: theme.panelSectionBorderWidth > 0
      ? Border.all(
          color: theme.panelSectionBorder,
          width: theme.panelSectionBorderWidth,
        )
      : null,
);
