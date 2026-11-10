// The workspace row's container: one pill — the pod — holding a dot per
// workspace, with the selection sliding between them.
//
// A render object rather than a `Stack` over a `Row`, because the indicator has
// to be painted *at the selected dot*, and where that dot is is only known once
// the row has been laid out. Measuring it from a post-frame callback is a frame
// late and a `setState` per move; here it is read in `paint`, so it tracks a dot
// that is itself still growing (the selected one is longer) on the same frame.

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays [children] — one dot per workspace — out along [axis] inside a pill of
/// [background], and paints [indicatorColor] behind the [selected] one.
///
/// **The indicator moves on [progress], which the owner restarts.** Whenever
/// [selected] or [indicatorColor] changes, the render object takes the rect and
/// colour it last *painted* as where the move starts, and lerps from there to
/// the selected dot's current rect as [progress] runs 0 → 1. Taking the painted
/// values rather than recomputing them is what makes a switch landing mid-slide
/// carry on from where the indicator visibly is, and what lets the owner reset
/// [progress] before or after this widget updates without the order mattering.
///
/// **Each dot is hit across its whole slot.** A dot is a few pixels across, far
/// under `ShellSizes.minTapTarget`, so a press anywhere in the pod's depth, and
/// up to halfway into the gap either side, is handed to the nearest dot at the
/// point inside it closest to the press. The slots tile the pod with no gap, so
/// the pod has no dead space and needs no hit of its own.
///
/// Draws nothing and takes no room with no children; the caller is expected to
/// build `SizedBox.shrink()` instead, so `BarModuleRow` drops the gap too.
class WorkspacePod extends MultiChildRenderObjectWidget {
  const WorkspacePod({
    super.key,
    required this.axis,
    required this.selected,
    required this.indicatorColor,
    required this.background,
    required this.progress,
    this.curve = Curves.easeOutCubic,
    this.spacing = 4,
    this.padding = 3,
    super.children,
  });

  /// Which way the dots run: along the bar.
  final Axis axis;

  /// The index of the dot the indicator sits behind, or null for none.
  final int? selected;

  /// The indicator's colour.
  final Color indicatorColor;

  /// The pod's own fill.
  final Color background;

  /// How far the indicator has moved from where it was painted when [selected]
  /// last changed, 0 → 1.
  final Animation<double> progress;

  /// The shape of that move.
  final Curve curve;

  /// The gap between two dots.
  final double spacing;

  /// The pod's rim: how far its pill reaches past the dots on every side.
  final double padding;

  @override
  RenderWorkspacePod createRenderObject(BuildContext context) =>
      RenderWorkspacePod(
        axis: axis,
        selected: selected,
        indicatorColor: indicatorColor,
        background: background,
        progress: progress,
        curve: curve,
        spacing: spacing,
        padding: padding,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderWorkspacePod renderObject,
  ) {
    renderObject
      ..axis = axis
      ..selected = selected
      ..indicatorColor = indicatorColor
      ..background = background
      ..progress = progress
      ..curve = curve
      ..spacing = spacing
      ..padding = padding;
  }
}

class WorkspacePodParentData extends ContainerBoxParentData<RenderBox> {}

class RenderWorkspacePod extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, WorkspacePodParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, WorkspacePodParentData> {
  RenderWorkspacePod({
    required Axis axis,
    required int? selected,
    required Color indicatorColor,
    required Color background,
    required Animation<double> progress,
    required Curve curve,
    required double spacing,
    required double padding,
  })  : _axis = axis,
        _selected = selected,
        _indicatorColor = indicatorColor,
        _background = background,
        _progress = progress,
        _curve = curve,
        _spacing = spacing,
        _padding = padding;

  Axis _axis;
  Axis get axis => _axis;
  set axis(Axis value) {
    if (value == _axis) return;
    _axis = value;
    markNeedsLayout();
  }

  int? _selected;
  int? get selected => _selected;
  set selected(int? value) {
    if (value == _selected) return;
    _beginMove();
    _selected = value;
    markNeedsPaint();
  }

  Color _indicatorColor;
  Color get indicatorColor => _indicatorColor;
  set indicatorColor(Color value) {
    if (value == _indicatorColor) return;
    _beginMove();
    _indicatorColor = value;
    markNeedsPaint();
  }

  Color _background;
  set background(Color value) {
    if (value == _background) return;
    _background = value;
    markNeedsPaint();
  }

  Animation<double> _progress;
  set progress(Animation<double> value) {
    if (identical(value, _progress)) return;
    if (attached) _progress.removeListener(markNeedsPaint);
    _progress = value;
    if (attached) _progress.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  Curve _curve;
  set curve(Curve value) {
    if (value == _curve) return;
    _curve = value;
    markNeedsPaint();
  }

  double _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  double _padding;
  set padding(double value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  /// Where the indicator was last painted, and in what colour — null before the
  /// first paint and while nothing is selected.
  Rect? _paintedRect;
  Color? _paintedColor;

  /// Where the current move started from; null draws the indicator straight at
  /// its target.
  Rect? _fromRect;
  Color? _fromColor;

  /// The far end of the pill along the bar, from the last layout.
  double _podMain = 0;

  /// The pill's depth across the bar, from the last layout.
  double _podCross = 0;

  void _beginMove() {
    _fromRect = _paintedRect;
    _fromColor = _paintedColor;
  }

  bool get _horizontal => _axis == Axis.horizontal;
  double _main(Size size) => _horizontal ? size.width : size.height;
  double _cross(Size size) => _horizontal ? size.height : size.width;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! WorkspacePodParentData) {
      child.parentData = WorkspacePodParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsPaint);
    super.detach();
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) {
    final crossMax =
        _horizontal ? constraints.maxHeight : constraints.maxWidth;
    final inner = crossMax.isFinite
        ? math.max(0.0, crossMax - 2 * _padding)
        : double.infinity;
    return _horizontal
        ? BoxConstraints(maxHeight: inner)
        : BoxConstraints(maxWidth: inner);
  }

  /// The pill's extent along and across the bar, for children of [sizes].
  (double, double) _podExtent(List<Size> sizes) {
    if (sizes.isEmpty) return (0, 0);
    var main = 2 * _padding + _spacing * (sizes.length - 1);
    var cross = 0.0;
    for (final size in sizes) {
      main += _main(size);
      cross = math.max(cross, _cross(size));
    }
    return (main, cross + 2 * _padding);
  }

  Size _sizeFor(BoxConstraints constraints, double main, double cross) {
    if (main == 0) return constraints.smallest;
    // Across the bar the pod takes the bar's whole depth when it is offered —
    // that is the hit slot every dot is given — and paints its pill centred in
    // it.
    final crossMax =
        _horizontal ? constraints.maxHeight : constraints.maxWidth;
    final across = crossMax.isFinite ? math.max(crossMax, cross) : cross;
    return constraints.constrain(
      _horizontal ? Size(main, across) : Size(across, main),
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final inner = _childConstraints(constraints);
    final sizes = <Size>[];
    var child = firstChild;
    while (child != null) {
      sizes.add(child.getDryLayout(inner));
      child = childAfter(child);
    }
    final (main, cross) = _podExtent(sizes);
    return _sizeFor(constraints, main, cross);
  }

  @override
  void performLayout() {
    final inner = _childConstraints(constraints);
    final sizes = <Size>[];
    var child = firstChild;
    while (child != null) {
      child.layout(inner, parentUsesSize: true);
      sizes.add(child.size);
      child = childAfter(child);
    }
    final (main, cross) = _podExtent(sizes);
    size = _sizeFor(constraints, main, cross);
    _podMain = math.min(main, _main(size));
    _podCross = math.min(cross, _cross(size));

    final across = _cross(size);
    var position = _padding;
    child = firstChild;
    while (child != null) {
      final parentData = child.parentData! as WorkspacePodParentData;
      final offsetAcross = (across - _cross(child.size)) / 2;
      parentData.offset = _horizontal
          ? Offset(position, offsetAcross)
          : Offset(offsetAcross, position);
      position += _main(child.size) + _spacing;
      child = parentData.nextSibling;
    }
  }

  double _intrinsicMain(double Function(RenderBox child) extentOf) {
    var total = 0.0;
    var count = 0;
    var child = firstChild;
    while (child != null) {
      total += extentOf(child);
      count++;
      child = childAfter(child);
    }
    return count == 0 ? 0 : total + _spacing * (count - 1) + 2 * _padding;
  }

  double _intrinsicCross(double Function(RenderBox child) extentOf) {
    var cross = 0.0;
    var child = firstChild;
    while (child != null) {
      cross = math.max(cross, extentOf(child));
      child = childAfter(child);
    }
    return firstChild == null ? 0 : cross + 2 * _padding;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _horizontal
      ? _intrinsicMain((c) => c.getMinIntrinsicWidth(double.infinity))
      : _intrinsicCross((c) => c.getMinIntrinsicWidth(double.infinity));

  @override
  double computeMaxIntrinsicWidth(double height) => _horizontal
      ? _intrinsicMain((c) => c.getMaxIntrinsicWidth(double.infinity))
      : _intrinsicCross((c) => c.getMaxIntrinsicWidth(double.infinity));

  @override
  double computeMinIntrinsicHeight(double width) => _horizontal
      ? _intrinsicCross((c) => c.getMinIntrinsicHeight(double.infinity))
      : _intrinsicMain((c) => c.getMinIntrinsicHeight(double.infinity));

  @override
  double computeMaxIntrinsicHeight(double width) => _horizontal
      ? _intrinsicCross((c) => c.getMaxIntrinsicHeight(double.infinity))
      : _intrinsicMain((c) => c.getMaxIntrinsicHeight(double.infinity));

  /// The rect of the child at [index], in this box's coordinates.
  Rect? _childRect(int? index) {
    if (index == null || index < 0) return null;
    var i = 0;
    var child = firstChild;
    while (child != null) {
      if (i == index) {
        final parentData = child.parentData! as WorkspacePodParentData;
        return parentData.offset & child.size;
      }
      i++;
      child = childAfter(child);
    }
    return null;
  }

  /// The indicator's rect, in this box's coordinates, as last painted — for
  /// tests, which have no other way to see where it is mid-move.
  @visibleForTesting
  Rect? get debugIndicatorRect => _paintedRect;

  /// The indicator's colour as last painted.
  @visibleForTesting
  Color? get debugIndicatorColor => _paintedColor;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (firstChild == null) {
      _paintedRect = null;
      _paintedColor = null;
      return;
    }
    final canvas = context.canvas;
    final across = (_cross(size) - _podCross) / 2;
    final pod = _horizontal
        ? Rect.fromLTWH(0, across, _podMain, _podCross)
        : Rect.fromLTWH(across, 0, _podCross, _podMain);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        pod.shift(offset),
        Radius.circular(_podCross / 2),
      ),
      Paint()..color = _background,
    );

    final target = _childRect(_selected);
    if (target == null) {
      _paintedRect = null;
      _paintedColor = null;
    } else {
      final t = _curve.transform(_progress.value.clamp(0.0, 1.0));
      final from = _fromRect;
      final rect = from == null ? target : Rect.lerp(from, target, t)!;
      final fromColor = _fromColor;
      final color = fromColor == null
          ? _indicatorColor
          : Color.lerp(fromColor, _indicatorColor, t)!;
      _paintedRect = rect;
      _paintedColor = color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.shift(offset),
          Radius.circular(math.min(rect.width, rect.height) / 2),
        ),
        Paint()..color = color,
      );
    }

    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final along = _horizontal ? position.dx : position.dy;
    final half = _spacing / 2;
    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData! as WorkspacePodParentData;
      final start = _horizontal ? parentData.offset.dx : parentData.offset.dy;
      final end = start + _main(child.size);
      final first = child == firstChild;
      final last = child == lastChild;
      // The slot: from halfway into the gap before to halfway into the gap
      // after, the first and last running out to the pod's own ends.
      if ((first || along >= start - half) && (last || along < end + half)) {
        if (child.size.isEmpty) return false;
        final box = parentData.offset & child.size;
        // The nearest point inside the dot, so the press lands on it whatever
        // the dot's own size — a hair inside the far edges, which
        // `Size.contains` treats as outside.
        final inside = Offset(
          position.dx.clamp(box.left, box.right - 0.01),
          position.dy.clamp(box.top, box.bottom - 0.01),
        );
        final target = child;
        return result.addWithPaintOffset(
          offset: parentData.offset,
          position: inside,
          hitTest: (result, transformed) =>
              target.hitTest(result, position: transformed),
        );
      }
      child = parentData.nextSibling;
    }
    return false;
  }
}
