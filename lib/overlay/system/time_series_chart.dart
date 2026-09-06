import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/scopes.dart';

/// One line on a [TimeSeriesChart].
@immutable
class ChartSeries {
  const ChartSeries({
    required this.values,
    required this.color,
    this.filled = true,
  });

  /// Oldest first.
  final List<double> values;
  final Color color;
  final bool filled;
}

/// A filled line chart over a fixed number of samples.
///
/// [capacity] — not `values.length` — is what maps the x axis. A history buffer
/// that is still filling therefore draws a line growing in from the left at a
/// constant time scale, rather than a full-width line that rescales horizontally
/// on every sample, which reads as the data lurching about.
class TimeSeriesChart extends StatelessWidget {
  const TimeSeriesChart({
    super.key,
    required this.series,
    required this.capacity,
    this.maxY = 100,
    this.height = 96,
    this.gridDivisions = 4,
  });

  final List<ChartSeries> series;
  final int capacity;

  /// Null autoscales to the largest value present — what network throughput
  /// needs, having no natural ceiling.
  final double? maxY;
  final double height;
  final int gridDivisions;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // Size.infinite rather than a LayoutBuilder: a LayoutBuilder reports no
    // intrinsic dimensions, and these charts sit inside the overview's
    // IntrinsicHeight rows, which would then throw during layout.
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _TimeSeriesPainter(
          series: series,
          capacity: capacity,
          maxY: maxY,
          gridColor: theme.divider,
          gridDivisions: gridDivisions,
        ),
      ),
    );
  }
}

class _TimeSeriesPainter extends CustomPainter {
  const _TimeSeriesPainter({
    required this.series,
    required this.capacity,
    required this.maxY,
    required this.gridColor,
    required this.gridDivisions,
  });

  final List<ChartSeries> series;
  final int capacity;
  final double? maxY;
  final Color gridColor;
  final int gridDivisions;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= gridDivisions; i++) {
      final y = size.height * i / gridDivisions;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final scale = _resolveMaxY();
    if (scale <= 0 || capacity < 2) return;

    final dx = size.width / (capacity - 1);

    for (final s in series) {
      if (s.values.length < 2) continue;

      // Right-align: the newest sample sits at the right edge and older ones
      // trail off to the left, so a partial buffer looks like a chart that has
      // not filled yet rather than one squeezed into the left margin.
      final firstIndex = capacity - s.values.length;

      final path = Path();
      for (var i = 0; i < s.values.length; i++) {
        final x = (firstIndex + i) * dx;
        final y = size.height -
            (s.values[i] / scale).clamp(0.0, 1.0) * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      if (s.filled) {
        final fill = Path.from(path)
          ..lineTo((capacity - 1) * dx, size.height)
          ..lineTo(firstIndex * dx, size.height)
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(0, 0),
              Offset(0, size.height),
              [
                s.color.withValues(alpha: 0.30),
                s.color.withValues(alpha: 0.0),
              ],
            ),
        );
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );
    }
  }

  double _resolveMaxY() {
    final fixed = maxY;
    if (fixed != null) return fixed;
    var max = 0.0;
    for (final s in series) {
      for (final v in s.values) {
        if (v > max) max = v;
      }
    }
    // A flat-zero autoscaled chart would divide by zero; give it a nominal
    // ceiling so it draws a flat line along the bottom.
    return max > 0 ? max : 1;
  }

  @override
  bool shouldRepaint(_TimeSeriesPainter old) =>
      old.capacity != capacity ||
      old.maxY != maxY ||
      old.gridColor != gridColor ||
      old.series.length != series.length ||
      !_seriesEqual(old.series, series);

  static bool _seriesEqual(List<ChartSeries> a, List<ChartSeries> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].color != b[i].color) return false;
      if (!listEquals(a[i].values, b[i].values)) return false;
    }
    return true;
  }
}

/// The chart palette, derived from the user's accent so a retheme carries.
///
/// [ThemeConfig] has one accent and no secondary, so a second and third series
/// colour are rotated off it in HSL rather than hardcoded — otherwise a user who
/// themes the shell blue would still get the stock pink on their memory graph.
Color chartPrimary(ThemeConfig theme) => theme.accent;

Color chartSecondary(ThemeConfig theme) => _rotate(theme.accent, 150);

Color chartTertiary(ThemeConfig theme) => _rotate(theme.accent, 250);

Color _rotate(Color base, double degrees) {
  final hsl = HSLColor.fromColor(base);
  return hsl
      .withHue((hsl.hue + degrees) % 360)
      // The stock accent is dark and low-contrast against the panel; a chart
      // line needs to read at 1.5px, so lift it.
      .withLightness((hsl.lightness + 0.12).clamp(0.0, 1.0))
      .toColor();
}
