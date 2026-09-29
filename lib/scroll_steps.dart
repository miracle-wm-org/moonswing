import 'package:flutter/gestures.dart' show GestureBinding;
import 'package:flutter/widgets.dart';

/// Turns scrolling into whole steps: a mouse wheel's notches, or a touchpad's
/// two-finger pan, into "up by N" / "down by N".
///
/// Wheels do not all report the same thing. A notched wheel arrives as one
/// [PointerScrollEvent] per notch, which GTK's embedder scales to 53 logical
/// pixels; a high-resolution wheel sends a fraction of that per event, many
/// times over; and a touchpad is not a scroll signal at all on Linux but a
/// pan/zoom gesture. Counting *events* would make the second a hundred times as
/// fast as the first and ignore the third, so this counts *distance*, carrying
/// the remainder between events so a slow roll still arrives.
class ScrollStepAccumulator {
  ScrollStepAccumulator({this.pixelsPerStep = 50.0})
    : assert(pixelsPerStep > 0);

  /// The distance one step costs. Just under a notch, so a notched wheel moves
  /// exactly one step per notch.
  final double pixelsPerStep;

  double _pending = 0.0;

  /// Adds [upward] logical pixels — positive for scrolling up, away from the
  /// user — and answers the whole steps that crossed, positive for up.
  int add(double upward) {
    if (!upward.isFinite) return 0;
    // A reversal drops what was owed the other way, or the first stretch of a
    // change of mind would be spent paying off the old direction.
    if (_pending != 0 && _pending.sign != upward.sign) _pending = 0.0;
    _pending += upward;
    final steps = (_pending / pixelsPerStep).truncate();
    _pending -= steps * pixelsPerStep;
    return steps;
  }

  /// Forgets any partial step, at the start of a new gesture.
  void reset() => _pending = 0.0;
}

/// Reports scrolling over [child] as whole steps, positive for up.
///
/// Both a wheel and a touchpad pan count: see [ScrollStepAccumulator]. A wheel
/// event goes through the [PointerSignalResolver], so a scrollable around this
/// does not also scroll with it. The vertical axis wins; a purely sideways
/// scroll counts too, right as up, which is what a tilt wheel or a sideways
/// swipe over a horizontal slider means.
class ScrollSteps extends StatefulWidget {
  const ScrollSteps({super.key, required this.onSteps, required this.child});

  /// Null disables it, the way a null tap callback does.
  final ValueChanged<int>? onSteps;
  final Widget child;

  @override
  State<ScrollSteps> createState() => _ScrollStepsState();
}

class _ScrollStepsState extends State<ScrollSteps> {
  final _accumulator = ScrollStepAccumulator();

  static double _upward(Offset delta) =>
      delta.dy != 0 ? -delta.dy : delta.dx;

  void _report(double upward) {
    final onSteps = widget.onSteps;
    if (onSteps == null) return;
    final steps = _accumulator.add(upward);
    if (steps != 0) onSteps(steps);
  }

  void _onSignal(PointerSignalEvent event) {
    if (widget.onSteps == null || event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      _report(_upward((resolved as PointerScrollEvent).scrollDelta));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _onSignal,
      onPointerPanZoomStart: (_) => _accumulator.reset(),
      // A pan's delta is the fingers' movement, which has the opposite sign to
      // the scroll delta a wheel would send for the same motion — `Scrollable`
      // negates it the same way.
      onPointerPanZoomUpdate: (event) => _report(_upward(-event.localPanDelta)),
      child: widget.child,
    );
  }
}
