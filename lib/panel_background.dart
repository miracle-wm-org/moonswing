import 'package:flutter/widgets.dart';

class PanelBackgroundPainter extends CustomPainter {
  const PanelBackgroundPainter({
    this.anchor = 'top',
    this.animationValue = 0.0,
  });

  final String anchor;
  final double animationValue;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final bool horizontal = anchor == 'top' || anchor == 'bottom';

    final gradient = LinearGradient(
      begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
      end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
      colors: const [
        Color(0xEE222222),
        Color(0xEE2E2E2E),
        Color(0xEE4A4A4A),
        Color(0xEE2E2E2E),
        Color(0xEE222222),
      ],
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
        oldDelegate.animationValue != animationValue;
  }
}
