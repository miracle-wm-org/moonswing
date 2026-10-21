import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/hover_region.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/overlay_effect.dart';
import 'package:moonswing/theme/tokens.dart';

/// One segment of a [SegmentedTabBar].
class SegmentedTab {
  const SegmentedTab({required this.label, this.icon});

  final String label;
  final FaIconData? icon;
}

/// A segmented control: a recessed track of tabs, with the selected one lifted
/// onto a pill that slides to whichever tab is picked next.
///
/// The overview's top-level switcher. [UnderlineTab] stays the treatment for a
/// strip *inside* a tab — the monitor's sub-tabs, the audio page — so the two
/// levels read apart rather than as one ladder of underlines.
///
/// Each segment is as wide as its own label, so the pill is measured rather than
/// placed on a grid: [_RenderSegmentTrack] paints it under the segments between
/// two of their rects. The slide only repaints the track — the segments sit
/// behind their own boundaries, and the animation drives the paint directly
/// instead of rebuilding anything. The label weight never changes with the
/// selection, which would move every segment after it as the pill arrived.
///
/// The slide is the overlay's motion, so a theme whose `overlay_animation` is
/// `none` gets a pill that jumps.
class SegmentedTabBar extends StatefulWidget {
  const SegmentedTabBar({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<SegmentedTab> tabs;

  /// The index into [tabs] of the selected segment; -1 draws no pill.
  final int selected;

  final ValueChanged<int> onSelected;

  @override
  State<SegmentedTabBar> createState() => _SegmentedTabBarState();
}

class _SegmentedTabBarState extends State<SegmentedTabBar>
    with SingleTickerProviderStateMixin {
  // At rest at 1: an idle controller holds no active ticker.
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: ShellDurations.slow,
    value: 1,
  );
  late final Animation<double> _progress = _slide.drive(
    CurveTween(curve: Curves.easeOutCubic),
  );

  late double _from = widget.selected.toDouble();
  late double _to = widget.selected.toDouble();

  @override
  void didUpdateWidget(SegmentedTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected == oldWidget.selected) return;
    final animate =
        ThemeScope.of(context).overlayEffect != OverlayEffect.none &&
        oldWidget.selected >= 0 &&
        widget.selected >= 0;
    // From wherever the pill is now, so a second pick mid-slide turns it
    // around instead of snapping it back to where the first one started.
    _from = animate
        ? lerpDouble(_from, _to, _progress.value)!
        : widget.selected.toDouble();
    _to = widget.selected.toDouble();
    if (animate) {
      _slide.forward(from: 0);
    } else {
      _slide.value = 1;
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.all(_kTrackInset),
      decoration: BoxDecoration(
        color: theme.popupForeground.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(_kPillRadius + _kTrackInset),
        border: Border.all(color: theme.divider),
      ),
      child: RepaintBoundary(
        child: _SegmentTrack(
          from: _from,
          to: _to,
          progress: _progress,
          fill: theme.accent.withValues(alpha: 0.25),
          rim: theme.accent.withValues(alpha: 0.45),
          radius: _kPillRadius,
          children: [
            for (var i = 0; i < widget.tabs.length; i++)
              RepaintBoundary(
                child: _Segment(
                  tab: widget.tabs[i],
                  selected: i == widget.selected,
                  onTap: () => widget.onSelected(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The gap between the track's edge and a pill.
const double _kTrackInset = 3;

/// A pill's corners — the track's are this plus [_kTrackInset], so the two
/// curves are concentric.
const double _kPillRadius = ShellRadii.control;

class _Segment extends StatelessWidget {
  const _Segment({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final SegmentedTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) {
        final Color foreground;
        if (selected) {
          foreground = theme.accentText;
        } else if (hovered) {
          foreground = theme.popupForeground;
        } else {
          foreground = theme.popupForeground.withValues(alpha: 0.65);
        }
        return AnimatedContainer(
          duration: ShellDurations.fast,
          constraints: const BoxConstraints(minHeight: ShellSizes.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            // The pill is the track's; a hover wash only where it is not.
            color: hovered && !selected
                ? theme.surfaceHover.atMostAlpha(0.5)
                : const Color(0x00000000),
            borderRadius: BorderRadius.circular(_kPillRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tab.icon != null) ...[
                FaIcon(tab.icon, size: 12, color: foreground),
                const SizedBox(width: 8),
              ],
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: ShellFontSizes.body,
                  fontFamily: theme.fontFamily,
                  fontWeight: FontWeight.w500,
                  color: foreground,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The segments in a row, with the pill painted beneath them.
class _SegmentTrack extends MultiChildRenderObjectWidget {
  const _SegmentTrack({
    required this.from,
    required this.to,
    required this.progress,
    required this.fill,
    required this.rim,
    required this.radius,
    required super.children,
  });

  /// The pill travels from segment [from] to segment [to] as [progress] runs
  /// 0 → 1; fractional, since a slide can be turned around mid-way.
  final double from;
  final double to;
  final Animation<double> progress;

  final Color fill;
  final Color rim;
  final double radius;

  @override
  _RenderSegmentTrack createRenderObject(BuildContext context) =>
      _RenderSegmentTrack(
        from: from,
        to: to,
        progress: progress,
        fill: fill,
        rim: rim,
        radius: radius,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSegmentTrack renderObject,
  ) {
    renderObject
      ..from = from
      ..to = to
      ..progress = progress
      ..fill = fill
      ..rim = rim
      ..radius = radius;
  }
}

class _SegmentParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSegmentTrack extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SegmentParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SegmentParentData> {
  _RenderSegmentTrack({
    required double from,
    required double to,
    required Animation<double> progress,
    required Color fill,
    required Color rim,
    required double radius,
  }) : _from = from,
       _to = to,
       _progress = progress,
       _fill = fill,
       _rim = rim,
       _radius = radius;

  double _from;
  set from(double value) {
    if (value == _from) return;
    _from = value;
    markNeedsPaint();
  }

  double _to;
  set to(double value) {
    if (value == _to) return;
    _to = value;
    markNeedsPaint();
  }

  Animation<double> _progress;
  set progress(Animation<double> value) {
    if (value == _progress) return;
    if (attached) _progress.removeListener(markNeedsPaint);
    _progress = value;
    if (attached) _progress.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  Color _fill;
  set fill(Color value) {
    if (value == _fill) return;
    _fill = value;
    markNeedsPaint();
  }

  Color _rim;
  set rim(Color value) {
    if (value == _rim) return;
    _rim = value;
    markNeedsPaint();
  }

  double _radius;
  set radius(double value) {
    if (value == _radius) return;
    _radius = value;
    markNeedsPaint();
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

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SegmentParentData) {
      child.parentData = _SegmentParentData();
    }
  }

  List<RenderBox> get _children {
    final out = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      out.add(child);
      child = childAfter(child);
    }
    return out;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _children.fold(
    0.0,
    (sum, child) => sum + child.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) => _children.fold(
    0.0,
    (sum, child) => sum + child.getMaxIntrinsicWidth(height),
  );

  @override
  double computeMinIntrinsicHeight(double width) => _children.fold(
    0.0,
    (h, child) => math.max(h, child.getMinIntrinsicHeight(double.infinity)),
  );

  @override
  double computeMaxIntrinsicHeight(double width) => _children.fold(
    0.0,
    (h, child) => math.max(h, child.getMaxIntrinsicHeight(double.infinity)),
  );

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final loose = BoxConstraints(maxHeight: constraints.maxHeight);
    var height = 0.0;
    for (final child in _children) {
      height = math.max(height, child.getDryLayout(loose).height);
    }
    final row = BoxConstraints.tightFor(height: height);
    var width = 0.0;
    for (final child in _children) {
      width += child.getDryLayout(row).width;
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  void performLayout() {
    final children = _children;
    // Twice: once to find the tallest, then every segment at that height, so
    // each one's hover and tap box is the whole height of the track.
    final loose = BoxConstraints(maxHeight: constraints.maxHeight);
    var height = 0.0;
    for (final child in children) {
      child.layout(loose, parentUsesSize: true);
      height = math.max(height, child.size.height);
    }
    final row = BoxConstraints.tightFor(height: height);
    var x = 0.0;
    for (final child in children) {
      child.layout(row, parentUsesSize: true);
      (child.parentData! as _SegmentParentData).offset = Offset(x, 0);
      x += child.size.width;
    }
    size = constraints.constrain(Size(x, height));
  }

  Rect _rectOf(RenderBox child) =>
      (child.parentData! as _SegmentParentData).offset & child.size;

  /// The pill's rect at fractional segment [position].
  Rect? _pillAt(List<RenderBox> children, double position) {
    if (children.isEmpty || position < 0) return null;
    final last = children.length - 1;
    final lower = position.floor().clamp(0, last);
    final upper = math.min(lower + 1, last);
    return Rect.lerp(
      _rectOf(children[lower]),
      _rectOf(children[upper]),
      (position - lower).clamp(0.0, 1.0),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final children = _children;
    final position = lerpDouble(_from, _to, _progress.value)!;
    final pill = _pillAt(children, position);
    if (pill != null) {
      final rrect = RRect.fromRectAndRadius(
        pill.shift(offset),
        Radius.circular(_radius),
      );
      context.canvas
        ..drawRRect(rrect, Paint()..color = _fill)
        ..drawRRect(
          rrect.deflate(0.5),
          Paint()
            ..color = _rim
            ..style = PaintingStyle.stroke,
        );
    }
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
