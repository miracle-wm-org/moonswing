import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Spinning notch shown while an operation is in flight.
class LoadingIndicator extends StatefulWidget {
  const LoadingIndicator({super.key, required this.color, this.size = 16.0});

  final Color color;
  final double size;

  @override
  State<LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<LoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.rotate(
        angle: _ctrl.value * 2 * math.pi,
        child: FaIcon(
          FontAwesomeIcons.circleNotch,
          size: widget.size,
          color: widget.color,
        ),
      ),
    );
  }
}
