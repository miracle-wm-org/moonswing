import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// The scale-and-fade scaffold every full-screen overlay plays: scrim, a centred
/// card that scales in, and the closing-notifier handshake.
///
/// The handshake is the load-bearing part: nothing tears the window down
/// directly. The root flips [closing]; this scaffold plays the reverse animation
/// and only then calls [onClosed], which unregisters and destroys the native
/// window.
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
    final scrim = ThemeScope.of(context).scrim;

    // No BackdropFilter here, deliberately. A filter reaches only what Flutter
    // has already painted beneath it, and this scaffold *is* the first thing
    // painted into its window: the scrim is this widget's own child, and under
    // that is a transparent layer-shell surface whose contents belong to the
    // compositor. So the backdrop is empty, the filter resolves to nothing, and
    // every animated frame paid for a full-output Gaussian that changed no pixel.
    //
    // **And no `Opacity` across the whole of it either, for the same
    // arithmetic.** Every overlay window calls `spanFullOutput`, so an opacity
    // layer here is bounded by the output: `RenderOpacity` skips the layer at
    // exactly 1.0, so it cost nothing at rest and then allocated and blended a
    // full-output offscreen on every frame in and out — thirty-odd megabytes a
    // frame at 4K. The scrim is a flat fill and fades by its own alpha instead;
    // only the card keeps a real layer, because a card is a stack of overlapping
    // pieces and fading them one at a time shows it through itself.
    Widget backdrop = Stack(
      // Non-directional, so this does not depend on an ambient
      // `Directionality` for a stack whose one unpositioned child is centred.
      alignment: Alignment.center,
      // `Positioned.fill` and the default loose fit, never `StackFit.expand`:
      // that tightens *every* child, which would stretch the card to the
      // output instead of centring it.
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _opacity,
            builder: (context, _) => ColoredBox(
              color: scrim.withValues(alpha: scrim.a * _opacity.value),
            ),
          ),
        ),
        // Built outside the AnimatedBuilder, and driven by transition widgets
        // rather than by a rebuild: `ScaleTransition` and `FadeTransition`
        // tick their own render objects, so the card, the `Center` and the
        // transform stop being rebuilt on every frame of the animation.
        Center(
          child: FadeTransition(
            opacity: _opacity,
            child: ScaleTransition(scale: _scale, child: widget.child),
          ),
        ),
      ],
    );
    if (widget.onBackdropTap != null) {
      // An ancestor of both, as it has always been: the card's own opaque
      // detector is deeper in the tree, so it enters the arena first and
      // wins, and a tap on the card still does not dismiss through this one.
      backdrop = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onBackdropTap,
        child: backdrop,
      );
    }
    return backdrop;
  }
}
