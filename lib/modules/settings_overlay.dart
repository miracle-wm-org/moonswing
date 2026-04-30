// ignore_for_file: library_private_types_in_public_api

import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/scopes.dart';

class SettingsOverlay extends StatefulWidget {
  const SettingsOverlay({
    super.key,
    required this.closingNotifier,
    required this.onClosed,
  });

  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  @override
  _SettingsOverlayState createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends State<SettingsOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
    widget.closingNotifier.addListener(_onClosingChanged);
  }

  void _onClosingChanged() {
    if (widget.closingNotifier.value) {
      _controller.reverse().then((_) => widget.onClosed());
    }
  }

  @override
  void dispose() {
    widget.closingNotifier.removeListener(_onClosingChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              color: const Color(0x882C2C2C),
              child: Center(
                child: Transform.scale(
                  scale: _scale.value,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: _buildPanel(theme),
    );
  }

  Widget _buildPanel(ThemeConfig theme) {
    return Container(
      width: 800,
      height: 560,
      decoration: BoxDecoration(
        color: theme.popupBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.divider),
              ),
            ),
            child: Text(
              'General Settings',
              style: TextStyle(
                fontSize: 18,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Settings coming soon',
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
