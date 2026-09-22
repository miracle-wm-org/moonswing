import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:moonswing/osd/osd_store.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';

/// Logical size of the OSD *card*. The window is kept tight around it because the
/// shell has no input-region support — a larger surface would swallow clicks
/// meant for whatever is underneath.
///
/// The window itself is this grown by `popupShadowInsets`, because the card's Row
/// has an [Expanded] and fills the surface edge to edge. `_createOsd` in
/// `main.dart` does that inflation and takes the extra height back off the bottom
/// margin.
const Size kOsdWindowSize = Size(340, 96);

/// The card that appears when volume, microphone volume, or brightness changes.
///
/// Renders whatever [OsdStore] holds and drives the fade. When the store stops
/// being [OsdStore.visible] the card plays its exit animation and calls
/// [OsdStore.onFadeOutComplete], the host's signal to destroy the window.
class OsdWindow extends StatefulWidget {
  const OsdWindow({super.key, required this.store});

  final OsdStore store;

  @override
  State<OsdWindow> createState() => _OsdWindowState();
}

class _OsdWindowState extends State<OsdWindow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    widget.store.addListener(_onStoreChanged);
    _controller.forward();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    if (widget.store.visible) {
      // A fresh change arrived — re-enter if the exit had already started.
      _controller.forward();
    } else if (_controller.status != AnimationStatus.reverse) {
      _controller.reverse().then((_) {
        if (mounted && !widget.store.visible) {
          widget.store.onFadeOutComplete();
        }
      });
    }
    setState(() {});
  }

  FaIconData _icon(OsdRequest request) {
    switch (request.kind) {
      case OsdKind.brightness:
        return FontAwesomeIcons.sun;
      case OsdKind.microphone:
        return request.muted || request.value <= 0.0
            ? FontAwesomeIcons.microphoneSlash
            : FontAwesomeIcons.microphone;
      case OsdKind.volume:
        if (request.muted) return FontAwesomeIcons.volumeXmark;
        if (request.value <= 0.0) return FontAwesomeIcons.volumeOff;
        if (request.value <= 0.5) return FontAwesomeIcons.volumeLow;
        return FontAwesomeIcons.volumeHigh;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final request = widget.store.current;

    // The window outlives the request only for the frame between the fade-out
    // finishing and the host tearing it down.
    if (request == null) return const SizedBox.shrink();

    // A muted device still has a level, but showing it filled would contradict
    // the crossed-out icon.
    final fill = request.muted ? 0.0 : request.value;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: theme.fontFamily,
          fontSize: 13,
          color: theme.popupForeground,
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Opacity(
            opacity: _opacity.value,
            child: Transform.translate(
              offset: Offset(0, _slide.value),
              child: child,
            ),
          ),
          child: Center(
            // The window was created this much larger than [kOsdWindowSize]; this
            // hands that margin back to the shadow instead of to the card.
            // `_createOsd` makes the same call with no `attachEdge`, and the two
            // have to stay the same call — an OSD card is attached to nothing.
            child: Padding(
              padding: popupShadowInsets(theme),
              child: PopupCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Center(
                        child: FaIcon(
                          _icon(request),
                          size: 18,
                          color: theme.popupForeground,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: _OsdBar(value: fill)),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 38,
                      child: Text(
                        '${(request.value * 100).round()}%',
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Read-only level bar. The value animates between changes so holding a volume
/// key reads as one continuous movement rather than a series of jumps.
class _OsdBar extends StatelessWidget {
  const _OsdBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: theme.sliderTrack,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: value, end: value),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          builder: (context, animated, _) => FractionallySizedBox(
            widthFactor: animated.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: theme.accent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
