import 'package:flutter/widgets.dart';
import 'package:moonswing/scopes.dart';

// ---------------------------------------------------------------------------
// AudioSlider + _AudioSliderPainter
// ---------------------------------------------------------------------------

class AudioSlider extends StatelessWidget {
  const AudioSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    this.min = 0.0,
    this.max = 1.0,
    this.warningThreshold,
    this.enabled = true,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final double min;
  final double max;
  final double? warningThreshold;
  final bool enabled;

  double _clampedFromGlobal(BuildContext context, Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPosition);
    final fraction = (local.dx / box.size.width).clamp(0.0, 1.0);
    return min + fraction * (max - min);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return GestureDetector(
      onHorizontalDragUpdate: enabled
          ? (d) => onChanged(_clampedFromGlobal(context, d.globalPosition))
          : null,
      onHorizontalDragEnd: enabled ? (_) => onChangeEnd(value) : null,
      onTapDown: enabled
          ? (d) {
              final v = _clampedFromGlobal(context, d.globalPosition);
              onChanged(v);
              onChangeEnd(v);
            }
          : null,
      child: CustomPaint(
        size: const Size(double.infinity, 20),
        painter: _AudioSliderPainter(
          value: value,
          min: min,
          max: max,
          warningThreshold: warningThreshold,
          enabled: enabled,
          trackColor: theme.sliderTrack,
          fillColor: theme.accent,
          thumbColor: theme.popupForeground,
        ),
      ),
    );
  }
}

class _AudioSliderPainter extends CustomPainter {
  const _AudioSliderPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.trackColor,
    required this.fillColor,
    required this.thumbColor,
    this.warningThreshold,
  });

  final double value;
  final double min;
  final double max;
  final double? warningThreshold;
  final bool enabled;
  final Color trackColor;
  final Color fillColor;
  final Color thumbColor;

  static const _warningColor = Color(0xFFFF9500);

  @override
  void paint(Canvas canvas, Size size) {
    final trackY = size.height / 2;
    final range = max - min;
    final fraction = range > 0 ? ((value - min) / range).clamp(0.0, 1.0) : 0.0;
    final thumbX = fraction * size.width;

    canvas.drawLine(
      Offset(0, trackY),
      Offset(size.width, trackY),
      Paint()
        ..color = trackColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    if (thumbX > 0) {
      final threshold = warningThreshold;
      if (threshold != null && enabled) {
        final thFraction = ((threshold - min) / range).clamp(0.0, 1.0);
        final thX = thFraction * size.width;
        if (thumbX <= thX) {
          canvas.drawLine(
              Offset(0, trackY),
              Offset(thumbX, trackY),
              Paint()
                ..color = fillColor
                ..strokeWidth = 3
                ..strokeCap = StrokeCap.round);
        } else {
          canvas.drawLine(
              Offset(0, trackY),
              Offset(thX, trackY),
              Paint()
                ..color = fillColor
                ..strokeWidth = 3
                ..strokeCap = StrokeCap.round);
          canvas.drawLine(
              Offset(thX, trackY),
              Offset(thumbX, trackY),
              Paint()
                ..color = _warningColor
                ..strokeWidth = 3
                ..strokeCap = StrokeCap.round);
        }
      } else {
        canvas.drawLine(
          Offset(0, trackY),
          Offset(thumbX, trackY),
          Paint()
            ..color = enabled ? fillColor : trackColor
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    canvas.drawCircle(
      Offset(thumbX, trackY),
      6,
      Paint()..color = enabled ? thumbColor : trackColor,
    );
  }

  @override
  bool shouldRepaint(_AudioSliderPainter old) =>
      old.value != value ||
      old.min != min ||
      old.max != max ||
      old.enabled != enabled ||
      old.warningThreshold != warningThreshold ||
      old.trackColor != trackColor ||
      old.fillColor != fillColor ||
      old.thumbColor != thumbColor;
}
