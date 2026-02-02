import 'package:flutter/widgets.dart';

class PanelBackgroundPainter extends CustomPainter {
  const PanelBackgroundPainter({
    this.cornerRadius = 12.0,
  });

  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double inset = h; // 45 degrees: horizontal inset equals height
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

    // Start at top-left
    path.moveTo(0, 0);

    // Top edge
    path.lineTo(w, 0);

    // Right angled edge (45 degrees inward), stop short for rounded corner
    path.lineTo(w - inset + r * 0.707, h - r * 0.707);

    // Smooth bottom-right corner via cubic bezier
    path.cubicTo(
      w - inset + r * 0.15,
      h - r * 0.15, // control point near the geometric corner
      w - inset, h, // control point on the bottom edge
      w - inset - r, h, // end point on the flat bottom
    );

    // Flat bottom edge
    path.lineTo(inset + r, h);

    // Smooth bottom-left corner via cubic bezier
    path.cubicTo(
      inset, h, // control point on the bottom edge
      inset - r * 0.15, h - r * 0.15, // control point near the geometric corner
      inset - r * 0.707, h - r * 0.707, // end point on the angled edge
    );

    // Left angled edge back to top-left
    path.lineTo(0, 0);

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(PanelBackgroundPainter oldDelegate) {
    return oldDelegate.cornerRadius != cornerRadius;
  }
}
