import 'package:flutter/widgets.dart';

/// A horizontal fill bar, 0..1.
///
/// Lives at the root rather than in `overlay/settings/controls.dart` because the
/// bar module uses it too, outside the overlay — and unlike the settings controls
/// it depends only on `flutter/widgets`.
class UsageBar extends StatelessWidget {
  const UsageBar({
    super.key,
    required this.value,
    required this.fillColor,
    required this.trackColor,
    this.height = 6,
  });

  final double value;
  final Color fillColor;
  final Color trackColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Deliberately not a LayoutBuilder: one reports no intrinsic dimensions, so
    // a bar nested anywhere under an IntrinsicHeight (as the overview's cards
    // are) would throw during layout and blank the whole subtree. Size.infinite
    // lets the parent's constraints decide the width instead.
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: UsageBarPainter(
          value: value.clamp(0.0, 1.0),
          fillColor: fillColor,
          trackColor: trackColor,
        ),
      ),
    );
  }
}

class UsageBarPainter extends CustomPainter {
  const UsageBarPainter({
    required this.value,
    required this.fillColor,
    required this.trackColor,
  });

  final double value;
  final Color fillColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(3);
    final trackRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()..color = trackColor,
    );
    if (value > 0) {
      final fillRect = Rect.fromLTWH(0, 0, size.width * value, size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, radius),
        Paint()..color = fillColor,
      );
    }
  }

  @override
  bool shouldRepaint(UsageBarPainter old) =>
      old.value != value ||
      old.fillColor != fillColor ||
      old.trackColor != trackColor;
}
