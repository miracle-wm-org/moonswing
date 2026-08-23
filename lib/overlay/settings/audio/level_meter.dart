import 'package:flutter/widgets.dart';
import 'package:graceful_shell/scopes.dart';

// ---------------------------------------------------------------------------
// LevelMeter
// ---------------------------------------------------------------------------

class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return SizedBox(
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
    );
  }
}

class _LevelMeterPainter extends CustomPainter {
  const _LevelMeterPainter({
    required this.level,
    required this.trackColor,
    required this.accentColor,
  });

  final double level;
  final Color trackColor;
  final Color accentColor;

  static const _orange = Color(0xFFFF9500);
  static const _red = Color(0xFFFF3333);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = trackColor);
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
      old.level != level ||
      old.trackColor != trackColor ||
      old.accentColor != accentColor;
}
