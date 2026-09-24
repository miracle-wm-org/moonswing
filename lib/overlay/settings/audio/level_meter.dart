import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:moonswing/scopes.dart';

// ---------------------------------------------------------------------------
// LevelMeter
// ---------------------------------------------------------------------------

/// A horizontal peak meter.
///
/// [level] is a listenable rather than a value because it moves thirty times a
/// second: the painter repaints off it directly, inside its own boundary, so a
/// reading repaints this bar and not the page around it.
class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.level});

  final ValueListenable<double> level;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return RepaintBoundary(
      child: SizedBox(
        height: 8,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: CustomPaint(
            size: const Size(double.infinity, 8),
            painter: _LevelMeterPainter(
              level: level,
              trackColor: theme.sliderTrack,
              accentColor: theme.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelMeterPainter extends CustomPainter {
  _LevelMeterPainter({
    required this.level,
    required this.trackColor,
    required this.accentColor,
  }) : super(repaint: level);

  final ValueListenable<double> level;
  final Color trackColor;
  final Color accentColor;

  static const _orange = Color(0xFFFF9500);
  static const _red = Color(0xFFFF3333);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = trackColor);
    final level = this.level.value;
    if (level <= 0) return;
    final fillW = (level * size.width).clamp(0.0, size.width);
    const z1 = 0.80, z2 = 0.95;
    final x1 = z1 * size.width;
    final x2 = z2 * size.width;
    if (fillW <= x1) {
      canvas.drawRect(Rect.fromLTWH(0, 0, fillW, size.height),
          Paint()..color = accentColor);
    } else if (fillW <= x2) {
      canvas.drawRect(
          Rect.fromLTWH(0, 0, x1, size.height), Paint()..color = accentColor);
      canvas.drawRect(Rect.fromLTWH(x1, 0, fillW - x1, size.height),
          Paint()..color = _orange);
    } else {
      canvas.drawRect(
          Rect.fromLTWH(0, 0, x1, size.height), Paint()..color = accentColor);
      canvas.drawRect(
          Rect.fromLTWH(x1, 0, x2 - x1, size.height), Paint()..color = _orange);
      canvas.drawRect(
          Rect.fromLTWH(x2, 0, fillW - x2, size.height), Paint()..color = _red);
    }
  }

  @override
  bool shouldRepaint(_LevelMeterPainter old) =>
      !identical(old.level, level) ||
      old.trackColor != trackColor ||
      old.accentColor != accentColor;
}
