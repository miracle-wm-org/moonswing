import 'package:flutter/widgets.dart';

class PanelBackgroundPainter extends CustomPainter {
  const PanelBackgroundPainter({
    this.cornerRadius = 12.0,
    this.anchor = 'top',
  });

  final double cornerRadius;
  final String anchor;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double r = cornerRadius;

    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0xEE222222),
          Color(0xEE2B2B2B),
          Color(0xEE383838),
          Color(0xEE4A4A4A),
          Color(0xEE3D3D3D),
        ],
        stops: [0.0, 0.15, 0.4, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    final path = Path();

    if (anchor == 'bottom') {
      // Mirrored trapezoid: flat bottom, angled top edges
      final double inset = h;

      // Start at bottom-left
      path.moveTo(0, h);

      // Bottom edge
      path.lineTo(w, h);

      // Right angled edge going up, stop short for rounded corner
      path.lineTo(w - inset + r * 0.707, r * 0.707);

      // Smooth top-right corner via cubic bezier
      path.cubicTo(
        w - inset + r * 0.15,
        r * 0.15,
        w - inset,
        0,
        w - inset - r,
        0,
      );

      // Flat top edge
      path.lineTo(inset + r, 0);

      // Smooth top-left corner via cubic bezier
      path.cubicTo(
        inset,
        0,
        inset - r * 0.15,
        r * 0.15,
        inset - r * 0.707,
        r * 0.707,
      );

      // Left angled edge back to bottom-left
      path.lineTo(0, h);
    } else {
      // Default 'top' (and fallback for left/right): original trapezoid
      final double inset = h;

      // Start at top-left
      path.moveTo(0, 0);

      // Top edge
      path.lineTo(w, 0);

      // Right angled edge (45 degrees inward), stop short for rounded corner
      path.lineTo(w - inset + r * 0.707, h - r * 0.707);

      // Smooth bottom-right corner via cubic bezier
      path.cubicTo(
        w - inset + r * 0.15,
        h - r * 0.15,
        w - inset,
        h,
        w - inset - r,
        h,
      );

      // Flat bottom edge
      path.lineTo(inset + r, h);

      // Smooth bottom-left corner via cubic bezier
      path.cubicTo(
        inset,
        h,
        inset - r * 0.15,
        h - r * 0.15,
        inset - r * 0.707,
        h - r * 0.707,
      );

      // Left angled edge back to top-left
      path.lineTo(0, 0);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(PanelBackgroundPainter oldDelegate) {
    return oldDelegate.cornerRadius != cornerRadius ||
        oldDelegate.anchor != anchor;
  }
}
