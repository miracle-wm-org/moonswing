// The crawl: a strip of content sliding sideways through a fixed window, the
// way the ticker runs along the bottom of a financial news channel.
//
// It is the one thing on a bar that moves continuously, so it is built around
// what that costs:
//
// - **A frame moves a layer; it does not repaint the strip.** The strip sits
//   under its own `RepaintBoundary`, so its picture — every symbol, price and
//   arrow — is recorded once per *quote change* and reused. A frame only
//   repaints [_RenderCrawl], whose own picture is nothing but the clip and the
//   offset it composites that layer at. And [_RenderCrawl] is a repaint
//   boundary itself, so that repaint stops here rather than re-recording the
//   panel's whole surface and damaging the whole output — the panels have no
//   boundary of their own (CLAUDE.md, "Repaint discipline").
// - **The offset is snapped to device pixels, and only a new one repaints.**
//   At forty pixels a second most vsyncs move the strip less than a pixel;
//   those frames change nothing, and text drawn at a fractional offset is
//   blurred besides.
// - **It is still when it fits.** A strip narrower than its window sits there,
//   sized to itself, with no ticker; a ticker exists only while there is
//   something to scroll *and* nobody is reading it (hover pauses).
// - **Position is derived, not accumulated.** Offset is the ticker's elapsed
//   time times the speed, from a reference point re-taken at each resume, so a
//   late frame is a longer step rather than a lost one.
//
// The strip is laid out twice, end to end, so the second copy arrives as the
// first leaves and the loop has no seam; the render object knows the period
// from its child's width and reports whether it overflows, which is how the
// state learns whether to run a ticker at all.

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

class TickerCrawl extends StatefulWidget {
  const TickerCrawl({
    super.key,
    required this.child,
    required this.maxWidth,
    this.speed = 40,
    this.gap = 28,
    this.paused = false,
  });

  /// One pass of the strip. Built twice; keep it free of keys and state.
  final Widget child;

  /// The window the strip crawls through, and the widest this ever is.
  final double maxWidth;

  /// Logical pixels a second.
  final double speed;

  /// The blank run between the end of one pass and the start of the next.
  final double gap;

  /// Holds the strip where it is — while the pointer is over it, so a price
  /// can be read without chasing it.
  final bool paused;

  @override
  State<TickerCrawl> createState() => _TickerCrawlState();
}

class _TickerCrawlState extends State<TickerCrawl>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _offset = ValueNotifier(0);

  /// From the last layout: one pass plus the gap, and whether a pass is wider
  /// than the window.
  double _period = 0;
  bool _overflows = false;

  /// Where the strip was when the ticker last started, so a resume carries on
  /// from the pause rather than jumping to where it would have been.
  double _startOffset = 0;

  @override
  void didUpdateWidget(TickerCrawl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paused != widget.paused || oldWidget.speed != widget.speed) {
      _sync();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _offset.dispose();
    super.dispose();
  }

  void _onMetrics(double period, bool overflows) {
    if (!mounted) return;
    _period = period;
    _overflows = overflows;
    if (!overflows && _offset.value != 0) _offset.value = 0;
    _sync();
  }

  /// Runs the ticker exactly when there is something to scroll and nobody is
  /// holding it, and re-bases it whenever that changes.
  void _sync() {
    final run = _overflows && !widget.paused && widget.speed > 0;
    if (run == _ticker.isActive) {
      if (run) {
        // A speed change mid-run: restart from here at the new pace.
        _ticker.stop();
        _startOffset = _offset.value;
        _ticker.start();
      }
      return;
    }
    if (run) {
      _startOffset = _offset.value;
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (_period <= 0) return;
    final travelled =
        _startOffset + elapsed.inMicroseconds / 1e6 * widget.speed;
    final dpr = View.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final snapped = ((travelled % _period) * dpr).roundToDouble() / dpr;
    if (snapped != _offset.value) _offset.value = snapped;
  }

  @override
  Widget build(BuildContext context) {
    return _Crawl(
      offset: _offset,
      maxWidth: widget.maxWidth,
      gap: widget.gap,
      onMetrics: _onMetrics,
      child: RepaintBoundary(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.child,
            SizedBox(width: widget.gap),
            widget.child,
          ],
        ),
      ),
    );
  }
}

class _Crawl extends SingleChildRenderObjectWidget {
  const _Crawl({
    required this.offset,
    required this.maxWidth,
    required this.gap,
    required this.onMetrics,
    required super.child,
  });

  final ValueListenable<double> offset;
  final double maxWidth;
  final double gap;
  final void Function(double period, bool overflows) onMetrics;

  @override
  _RenderCrawl createRenderObject(BuildContext context) => _RenderCrawl(
        offset: offset,
        maxWidth: maxWidth,
        gap: gap,
        onMetrics: onMetrics,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderCrawl renderObject) {
    renderObject
      ..offset = offset
      ..maxWidth = maxWidth
      ..gap = gap
      ..onMetrics = onMetrics;
  }
}

class _RenderCrawl extends RenderProxyBox {
  _RenderCrawl({
    required ValueListenable<double> offset,
    required double maxWidth,
    required double gap,
    required this.onMetrics,
  })  : _offset = offset,
        _maxWidth = maxWidth,
        _gap = gap;

  ValueListenable<double> _offset;
  set offset(ValueListenable<double> value) {
    if (identical(value, _offset)) return;
    if (attached) _offset.removeListener(markNeedsPaint);
    _offset = value;
    if (attached) _offset.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double _maxWidth;
  set maxWidth(double value) {
    if (value == _maxWidth) return;
    _maxWidth = value;
    markNeedsLayout();
  }

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  void Function(double period, bool overflows) onMetrics;

  double _reportedPeriod = -1;
  bool? _reportedOverflow;

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _offset.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _offset.removeListener(markNeedsPaint);
    super.detach();
  }

  /// One pass's width, from the doubled strip's: two passes and one gap.
  double _single(double doubled) => ((doubled - _gap) / 2).clamp(0.0, doubled);

  @override
  double computeMinIntrinsicWidth(double height) =>
      computeMaxIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) {
    final child = this.child;
    if (child == null) return 0;
    final single = _single(child.getMaxIntrinsicWidth(height));
    return single < _maxWidth ? single : _maxWidth;
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    // Unbounded across: the strip is as long as the watchlist, and the
    // window, not the constraint, is what clips it.
    child.layout(
      BoxConstraints(maxHeight: constraints.maxHeight),
      parentUsesSize: true,
    );
    final single = _single(child.size.width);
    final overflows = single > _maxWidth;
    size = constraints.constrain(
      Size(overflows ? _maxWidth : single, child.size.height),
    );

    final period = single + _gap;
    if (period != _reportedPeriod || overflows != _reportedOverflow) {
      _reportedPeriod = period;
      _reportedOverflow = overflows;
      // After the frame: this is layout, and the answer starts or stops a
      // ticker in a State.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (attached) onMetrics(period, overflows);
      });
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final shift = (_reportedOverflow ?? false) ? _offset.value : 0.0;
    // The clip is the window; the child is a repaint boundary, so painting
    // it at a new place composites its existing layer there. A handle of its
    // own, because this is a repaint boundary and [layer] is the framework's.
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) => context.paintChild(child, offset - Offset(shift, 0)),
      oldLayer: _clip.layer,
    );
  }

  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  /// Where the strip is drawn, for anything asking where a piece of it is —
  /// a test, the semantics tree. Paint moves it; this says so.
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = (_reportedOverflow ?? false) ? _offset.value : 0.0;
    transform.translateByDouble(-shift, 0, 0, 1);
  }

  /// The strip is a picture; taps are the module's, around it.
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;

  @override
  bool hitTestSelf(Offset position) => true;
}
