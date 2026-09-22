import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:moonswing/scopes.dart';

/// An analog dial for [time].
///
/// The widget reads the theme and hands the painter plain colours — the painter
/// never touches a [BuildContext], the `time_series_chart.dart` convention.
class AnalogClock extends StatelessWidget {
  const AnalogClock({super.key, required this.time, this.size = 128});

  final DateTime time;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AnalogClockPainter(
          // Ints, not the DateTime: this makes shouldRepaint a three-field
          // compare, so a rebuild within the same second — a theme notify, a
          // keystroke in the settings tab — repaints nothing.
          hour: time.hour,
          minute: time.minute,
          second: time.second,
          dial: theme.controlSurface,
          rim: theme.divider,
          tick: theme.popupForeground.withValues(alpha: 0.35),
          hand: theme.popupForeground.withValues(alpha: 0.9),
          sweep: theme.accent,
        ),
      ),
    );
  }
}

class _AnalogClockPainter extends CustomPainter {
  const _AnalogClockPainter({
    required this.hour,
    required this.minute,
    required this.second,
    required this.dial,
    required this.rim,
    required this.tick,
    required this.hand,
    required this.sweep,
  });

  final int hour;
  final int minute;
  final int second;
  final Color dial;
  final Color rim;
  final Color tick;
  final Color hand;
  final Color sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 1;
    if (radius <= 0) return;

    canvas.drawCircle(centre, radius, Paint()..color = dial);
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = rim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi / 6 - math.pi / 2;
      final quarter = i % 3 == 0;
      final outer = radius * 0.88;
      final inner = outer - radius * (quarter ? 0.16 : 0.09);
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        centre + direction * inner,
        centre + direction * outer,
        Paint()
          ..color = tick
          ..strokeWidth = quarter ? 2 : 1
          ..strokeCap = StrokeCap.round,
      );
    }

    // Fractional units throughout, so the hour hand creeps between the numerals
    // and the minute hand does not step once a minute.
    _drawHand(
      canvas,
      centre,
      angle: (((hour % 12) + minute / 60) / 12) * 2 * math.pi - math.pi / 2,
      length: radius * 0.50,
      width: 3,
      color: hand,
    );
    _drawHand(
      canvas,
      centre,
      angle: ((minute + second / 60) / 60) * 2 * math.pi - math.pi / 2,
      length: radius * 0.72,
      width: 2.2,
      color: hand,
    );
    _drawHand(
      canvas,
      centre,
      angle: (second / 60) * 2 * math.pi - math.pi / 2,
      length: radius * 0.80,
      width: 1,
      color: sweep,
      tail: radius * 0.16,
    );

    canvas.drawCircle(centre, 2.5, Paint()..color = sweep);
  }

  void _drawHand(
    Canvas canvas,
    Offset centre, {
    required double angle,
    required double length,
    required double width,
    required Color color,
    double tail = 0,
  }) {
    final direction = Offset(math.cos(angle), math.sin(angle));
    canvas.drawLine(
      centre - direction * tail,
      centre + direction * length,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_AnalogClockPainter old) =>
      old.hour != hour ||
      old.minute != minute ||
      old.second != second ||
      old.dial != dial ||
      old.rim != rim ||
      old.tick != tick ||
      old.hand != hand ||
      old.sweep != sweep;
}
