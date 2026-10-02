// The 0..1 slider the bar's level popups share — the volume and the
// brightness — and the scroll-step arithmetic both apply over the bar button
// and over the track.

import 'package:flutter/widgets.dart';
import 'package:moonswing/scroll_steps.dart';
import 'package:moonswing/scopes.dart';

/// How far one scroll step moves a level, as a fraction of full scale.
const _kScrollStepsPerFullScale = 20;

/// [level] moved by [steps] scroll steps, landing on the step grid.
///
/// Snapped rather than added, so a level the slider left at 53% goes to 55%
/// and not 58%, and the bar's percentage reads in round numbers from the first
/// notch on. Capped at 100%: PulseAudio will amplify past it, but a wheel is
/// too easy to over-roll for that to be where scrolling ends up.
double scrolledLevel(double level, int steps) {
  const n = _kScrollStepsPerFullScale;
  return ((level * n).round() + steps).clamp(0, n) / n;
}

/// A themed 0..1 slider for a bar popup.
///
/// [onChanged] follows the pointer; [onChangeEnd] is the write — on release,
/// on a tap, and per scroll step — so whatever the level drives is not asked
/// to move on every pixel of a drag. It has no intrinsic length along [axis]:
/// it paints through a `CustomPaint` sized `double.infinity` that way, so the
/// caller gives it one.
class LevelSlider extends StatelessWidget {
  const LevelSlider({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
    this.axis = Axis.horizontal,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final Axis axis;

  /// Scrolling over the track steps the level, and writes it as a tap does.
  /// Off while muted, like the drag: the track reads 0% then.
  ValueChanged<int>? get _onScrollSteps => !enabled
      ? null
      : (steps) {
          final v = scrolledLevel(value, steps);
          if (v == value) return;
          onChanged(v);
          onChangeEnd(v);
        };

  double _valueFromPosition(BuildContext context, Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPosition);
    if (axis == Axis.vertical) {
      return (1.0 - local.dy / box.size.height).clamp(0.0, 1.0);
    }
    return (local.dx / box.size.width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final painter = _LevelSliderPainter(
      value: value,
      enabled: enabled,
      axis: axis,
      trackColor: theme.sliderTrack,
      activeFillColor: theme.accent,
      inactiveFillColor: theme.sliderTrack,
      activeThumbColor: theme.popupForeground,
      inactiveThumbColor: theme.sliderTrack,
    );

    if (axis == Axis.vertical) {
      return ScrollSteps(
        onSteps: _onScrollSteps,
        child: GestureDetector(
          onVerticalDragUpdate: !enabled
              ? null
              : (d) => onChanged(_valueFromPosition(context, d.globalPosition)),
          onVerticalDragEnd: !enabled ? null : (d) => onChangeEnd(value),
          onTapDown: !enabled
              ? null
              : (d) {
                  final v = _valueFromPosition(context, d.globalPosition);
                  onChanged(v);
                  onChangeEnd(v);
                },
          child: CustomPaint(
            size: const Size(20, double.infinity),
            painter: painter,
          ),
        ),
      );
    }
    return ScrollSteps(
      onSteps: _onScrollSteps,
      child: GestureDetector(
        onHorizontalDragUpdate: !enabled
            ? null
            : (d) => onChanged(_valueFromPosition(context, d.globalPosition)),
        onHorizontalDragEnd: !enabled ? null : (d) => onChangeEnd(value),
        onTapDown: !enabled
            ? null
            : (d) {
                final v = _valueFromPosition(context, d.globalPosition);
                onChanged(v);
                onChangeEnd(v);
              },
        child: CustomPaint(
          size: const Size(double.infinity, 20),
          painter: painter,
        ),
      ),
    );
  }
}

class _LevelSliderPainter extends CustomPainter {
  const _LevelSliderPainter({
    required this.value,
    required this.enabled,
    required this.trackColor,
    required this.activeFillColor,
    required this.inactiveFillColor,
    required this.activeThumbColor,
    required this.inactiveThumbColor,
    this.axis = Axis.horizontal,
  });

  final double value;
  final bool enabled;
  final Axis axis;
  final Color trackColor;
  final Color activeFillColor;
  final Color inactiveFillColor;
  final Color activeThumbColor;
  final Color inactiveThumbColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (axis == Axis.vertical) {
      final trackX = size.width / 2;
      final thumbY = (1.0 - value) * size.height;

      // Track background
      canvas.drawLine(
        Offset(trackX, 0),
        Offset(trackX, size.height),
        Paint()
          ..color = trackColor
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );

      // Track fill (bottom up)
      if (thumbY < size.height) {
        canvas.drawLine(
          Offset(trackX, size.height),
          Offset(trackX, thumbY),
          Paint()
            ..color = enabled ? activeFillColor : inactiveFillColor
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      }

      // Thumb
      canvas.drawCircle(
        Offset(trackX, thumbY),
        6,
        Paint()..color = enabled ? activeThumbColor : inactiveThumbColor,
      );
      return;
    }

    final trackY = size.height / 2;
    final thumbX = value * size.width;

    // Track background
    canvas.drawLine(
      Offset(0, trackY),
      Offset(size.width, trackY),
      Paint()
        ..color = trackColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Track fill
    if (thumbX > 0) {
      canvas.drawLine(
        Offset(0, trackY),
        Offset(thumbX, trackY),
        Paint()
          ..color = enabled ? activeFillColor : inactiveFillColor
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    // Thumb
    canvas.drawCircle(
      Offset(thumbX, trackY),
      6,
      Paint()..color = enabled ? activeThumbColor : inactiveThumbColor,
    );
  }

  @override
  bool shouldRepaint(_LevelSliderPainter old) =>
      old.value != value ||
      old.enabled != enabled ||
      old.axis != axis ||
      old.trackColor != trackColor ||
      old.activeFillColor != activeFillColor ||
      old.activeThumbColor != activeThumbColor;
}

