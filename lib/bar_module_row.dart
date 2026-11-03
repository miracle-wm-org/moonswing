import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// One section of a bar: its modules in a line along the bar, [gap] apart —
/// except that a module with nothing to show takes no room at all, gap
/// included.
///
/// A module that has nothing to say on this machine (a battery on a desktop
/// tower, a backlight on an external monitor, a tray nothing has registered
/// with, a media player with no player) builds `SizedBox.shrink()`. In a `Row`
/// with a spacer between every pair, that still cost the bar a gap, and a
/// section holding two such modules a double one. Here the gaps are decided at
/// *layout*, from what each module actually measured: a child of zero extent
/// along the bar is skipped, and so is the gap it would have sat beside. So the
/// rule needs no cooperation from the module beyond being empty — and a module
/// that comes and goes (a battery plugged in, a player appearing) takes its gap
/// with it on the same frame, since this lays out again whenever a child's size
/// moves.
///
/// Otherwise laid out as `Row`/`Column` with `mainAxisSize.min` lays out
/// non-flex children: unbounded along the bar, loose up to the incoming maximum
/// across it, each centred across the section.
class BarModuleRow extends MultiChildRenderObjectWidget {
  const BarModuleRow({
    super.key,
    required this.axis,
    this.gap = 8,
    super.children,
  });

  /// [Axis.horizontal] on a top or bottom bar, [Axis.vertical] on a side one.
  final Axis axis;

  /// The space between two modules that both drew something.
  final double gap;

  @override
  RenderBarModuleRow createRenderObject(BuildContext context) =>
      RenderBarModuleRow(axis: axis, gap: gap);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBarModuleRow renderObject,
  ) {
    renderObject
      ..axis = axis
      ..gap = gap;
  }
}

class BarModuleRowParentData extends ContainerBoxParentData<RenderBox> {}

class RenderBarModuleRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, BarModuleRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, BarModuleRowParentData> {
  RenderBarModuleRow({required Axis axis, required double gap})
    : _axis = axis,
      _gap = gap;

  Axis get axis => _axis;
  Axis _axis;
  set axis(Axis value) {
    if (_axis == value) return;
    _axis = value;
    markNeedsLayout();
  }

  double get gap => _gap;
  double _gap;
  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  bool get _horizontal => _axis == Axis.horizontal;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! BarModuleRowParentData) {
      child.parentData = BarModuleRowParentData();
    }
  }

  double _main(Size size) => _horizontal ? size.width : size.height;
  double _cross(Size size) => _horizontal ? size.height : size.width;

  /// What each child is offered: anything along the bar, up to the section's
  /// depth across it.
  BoxConstraints _childConstraints(BoxConstraints constraints) => _horizontal
      ? BoxConstraints(maxHeight: constraints.maxHeight)
      : BoxConstraints(maxWidth: constraints.maxWidth);

  /// Sums [extents] along the bar, with a [gap] between each pair of
  /// non-empty ones. An empty child is not a module that drew something.
  double _sumWithGaps(Iterable<double> extents) {
    var total = 0.0;
    var shown = 0;
    for (final extent in extents) {
      if (extent <= 0) continue;
      if (shown > 0) total += _gap;
      total += extent;
      shown++;
    }
    return total;
  }

  Size _measure(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints constraints) sizeOf,
  ) {
    final inner = _childConstraints(constraints);
    final mains = <double>[];
    var cross = 0.0;
    var child = firstChild;
    while (child != null) {
      final size = sizeOf(child, inner);
      mains.add(_main(size));
      cross = math.max(cross, _cross(size));
      child = childAfter(child);
    }
    final main = _sumWithGaps(mains);
    return constraints.constrain(
      _horizontal ? Size(main, cross) : Size(cross, main),
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _measure(constraints, (child, inner) => child.getDryLayout(inner));

  @override
  void performLayout() {
    size = _measure(constraints, (child, inner) {
      child.layout(inner, parentUsesSize: true);
      return child.size;
    });

    final cross = _cross(size);
    var position = 0.0;
    var shown = 0;
    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData! as BarModuleRowParentData;
      final childMain = _main(child.size);
      if (childMain > 0 && shown > 0) position += _gap;
      final across = (cross - _cross(child.size)) / 2;
      parentData.offset = _horizontal
          ? Offset(position, across)
          : Offset(across, position);
      if (childMain > 0) {
        position += childMain;
        shown++;
      }
      child = parentData.nextSibling;
    }
  }

  double _intrinsicMain(double Function(RenderBox child) extentOf) {
    final extents = <double>[];
    var child = firstChild;
    while (child != null) {
      extents.add(extentOf(child));
      child = childAfter(child);
    }
    return _sumWithGaps(extents);
  }

  double _intrinsicCross(double Function(RenderBox child) extentOf) {
    var cross = 0.0;
    var child = firstChild;
    while (child != null) {
      cross = math.max(cross, extentOf(child));
      child = childAfter(child);
    }
    return cross;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _horizontal
      ? _intrinsicMain((c) => c.getMinIntrinsicWidth(height))
      : _intrinsicCross((c) => c.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) => _horizontal
      ? _intrinsicMain((c) => c.getMaxIntrinsicWidth(height))
      : _intrinsicCross((c) => c.getMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) => _horizontal
      ? _intrinsicCross((c) => c.getMinIntrinsicHeight(width))
      : _intrinsicMain((c) => c.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) => _horizontal
      ? _intrinsicCross((c) => c.getMaxIntrinsicHeight(width))
      : _intrinsicMain((c) => c.getMaxIntrinsicHeight(width));

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
