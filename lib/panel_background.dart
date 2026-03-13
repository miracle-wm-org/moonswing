import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config.dart';

class PanelBackgroundPainter extends CustomPainter {
  const PanelBackgroundPainter({
    this.anchor = 'top',
    this.animationValue = 0.0,
    this.theme = const ThemeConfig(),
  });

  final String anchor;
  final double animationValue;
  final ThemeConfig theme;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final bool horizontal = anchor == 'top' || anchor == 'bottom';

    final dark = theme.workspaceBackground.withValues(alpha: 0xEE / 0xFF);
    final mid = theme.surfacePressed.withValues(alpha: 0xEE / 0xFF);
    final light = theme.accent.withValues(alpha: 0xEE / 0xFF);

    final gradient = LinearGradient(
      begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
      end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
      colors: [dark, mid, light, mid, dark],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      tileMode: TileMode.repeated,
    );

    final double shift =
        horizontal ? w * animationValue : h * animationValue;

    final Rect shaderRect = horizontal
        ? Rect.fromLTWH(-shift, 0, w, h)
        : Rect.fromLTWH(0, -shift, w, h);

    final paint = Paint()
      ..shader = gradient.createShader(shaderRect)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
  }

  @override
  bool shouldRepaint(PanelBackgroundPainter oldDelegate) {
    return oldDelegate.anchor != anchor ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.theme != theme;
  }
}
