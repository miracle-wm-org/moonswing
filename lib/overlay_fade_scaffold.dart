import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// The scale-and-fade scaffold every full-screen overlay plays: scrim, a
/// centred card that scales in, and the closing-notifier handshake.
///
/// The handshake is the load-bearing part (see the dismissal section of
/// CLAUDE.md): nothing tears the window down directly. The root flips
/// [closing]; this scaffold plays the reverse animation and only then calls
/// [onClosed], which is what unregisters and destroys the native window. The
/// settings, launcher and screencast overlays each used to hand-roll the
/// whole quartet — controller, curves, listener, dispose pairing.
class FadeOverlayScaffold extends StatefulWidget {
  const FadeOverlayScaffold({
    super.key,
    required this.closing,
    required this.onClosed,
    this.duration = ShellDurations.overlayFade,
    this.beginScale = 0.96,
    this.onBackdropTap,
    required this.child,
  });

  /// Flipped true by the owner to request the fade-out.
  final ValueListenable<bool> closing;

  /// Called once the fade-out has finished — the cue to tear the window down.
  final VoidCallback onClosed;

  final Duration duration;
  final double beginScale;

  /// Tap on the scrim. The shell has no input-region support, so a
  /// full-screen surface swallows every click on the monitor — without
  /// dismiss-on-backdrop a mouse-only user has no way out. Null for overlays
  /// that handle (or refuse) backdrop clicks themselves.
  final VoidCallback? onBackdropTap;

  /// The centred card.
  final Widget child;

  @override
  State<FadeOverlayScaffold> createState() => _FadeOverlayScaffoldState();
}

class _FadeOverlayScaffoldState extends State<FadeOverlayScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _scale = Tween<double>(begin: widget.beginScale, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
    widget.closing.addListener(_onClosingChanged);
  }

  @override
  void didUpdateWidget(FadeOverlayScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.closing, widget.closing)) {
      oldWidget.closing.removeListener(_onClosingChanged);
      widget.closing.addListener(_onClosingChanged);
    }
  }

  @override
  void dispose() {
    widget.closing.removeListener(_onClosingChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onClosingChanged() {
    if (widget.closing.value) {
      _controller.reverse().then((_) => widget.onClosed());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // No BackdropFilter here, deliberately — see the note on
        // [ThemeConfig.blur]. A filter reaches only what Flutter has already
        // painted beneath it, and this scaffold *is* the first thing painted
        // into its window: the scrim below is this widget's own child, and
        // under that is a transparent layer-shell surface whose contents
        // belong to the compositor. So the backdrop is empty, the filter
        // resolves to nothing, and every frame the overlay animates paid for
        // a full-output Gaussian blur that changed no pixel — which is what
        // the settings page transitions were spending their frame budget on.
        Widget backdrop = Container(
          color: theme.scrim,
          child: Center(
            child: Transform.scale(scale: _scale.value, child: child),
          ),
        );
        if (widget.onBackdropTap != null) {
          backdrop = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onBackdropTap,
            child: backdrop,
          );
        }
        return Opacity(opacity: _opacity.value, child: backdrop);
      },
      child: widget.child,
    );
  }
}
