/// The one animation a popup plays, in both directions.
///
/// [PopupTransition] replaced `PopupBounceIn`, which fifteen popup content widgets
/// wrapped themselves in by hand. Three things changed with it:
///
///  * **The effect is the theme's**, not the widget's — `popup_animation`.
///  * **It plays out as well as in.** The exit is the entrance *reversed* on the
///    same controller, so an effect cannot describe an opening it has no closing
///    for. Whoever owns the window flips [closing] and waits for [onClosed].
///  * **`PopupHost` wraps the card itself.** A call site that spelled the
///    animation by hand could forget it, and — worse, once there is an exit —
///    could route its close around it.
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/popup_effect.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// How far a sliding popup travels, in logical pixels.
///
/// Deliberately small. The card is translated *inside* a window sized to its own
/// content plus the shadow's reach, and GTK3 resolves `gdk_window_move_to_rect`
/// once at map time — so a long travel would be clipped at the surface edge on
/// the frames it needed most. The fade makes the residue unobservable rather than
/// merely small: opacity and travel move together, so the half of the journey
/// nearest the clip is drawn at half opacity or less.
const double kPopupSlideDistance = 10.0;

/// The scale a [PopupEffect.scale] card starts from.
const double _kScaleFrom = 0.94;

/// The cross-axis scale a [PopupEffect.grow] card starts from.
const double _kGrowFrom = 0.55;

/// The angle, in radians, a [PopupEffect.flip] card is hinged open through.
const double _kFlipRadians = 1.05; // ~60°.

/// The angle, in radians, a [PopupEffect.spin] card turns through.
const double _kSpinRadians = 0.14; // ~8°.

/// Plays [effect] over [child] on mount, and the same effect backwards when
/// [closing] turns true.
///
/// [edge] is the panel anchor the popup is attached to and is what makes the
/// directional effects directional. A popup with no bar behind it — a context
/// menu at the pointer — passes null and is treated as hanging below its anchor,
/// which is where the compositor puts it.
///
/// [effect] null means "whatever the theme says", read from the enclosing
/// [ThemeScope]. `PopupHost` passes it explicitly instead, because it wraps the
/// card from *outside* the `ThemeProvider` the call site built.
class PopupTransition extends StatefulWidget {
  const PopupTransition({
    super.key,
    required this.child,
    this.effect,
    this.edge,
    this.closing,
    this.onClosed,
  });

  final Widget child;

  /// The effect to play, or null to read `popup_animation` off the theme.
  final PopupEffect? effect;

  /// The panel edge the popup is anchored to, for the directional effects.
  final String? edge;

  /// Flipped true by the window's owner to ask for the exit animation.
  final ValueListenable<bool>? closing;

  /// Called once the exit animation has finished and the window may be torn
  /// down. Never called for an entrance.
  final VoidCallback? onClosed;

  @override
  State<PopupTransition> createState() => _PopupTransitionState();
}

class _PopupTransitionState extends State<PopupTransition>
    with SingleTickerProviderStateMixin {
  /// Null until the effect is resolved, and null for good under
  /// [PopupEffect.none] — which is what makes that value a real off switch
  /// rather than a zero-length animation: no controller, no ticker, no
  /// `AnimatedBuilder`, and no save layer over the card.
  AnimationController? _ctrl;

  PopupEffect? _effect;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    widget.closing?.addListener(_onClosingChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The theme cannot be read from initState, and the effect has to be
    // resolved before the first frame is built or the card would flash at full
    // size on the way to being drawn at none of it.
    if (_effect != null) return;
    final effect = widget.effect ??
        ThemeScope.maybeOf(context)?.popupEffect ??
        PopupEffect.slide;
    _effect = effect;
    if (effect.animates) {
      _ctrl = AnimationController(
        vsync: this,
        duration: ShellDurations.popupIn,
        // Shorter on the way out, and only on the way out: an entrance is
        // paced to be followed, a dismissal is the user saying they are done.
        // The *shape* is still the entrance reversed, which is the promise
        // this widget makes.
        reverseDuration: ShellDurations.popupOut,
      )..forward();
    }
    // A close requested before this ever built — a popup displaced in the same
    // turn it opened — still has to be answered.
    if (widget.closing?.value ?? false) _onClosingChanged();
  }

  @override
  void didUpdateWidget(PopupTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.closing, widget.closing)) {
      oldWidget.closing?.removeListener(_onClosingChanged);
      widget.closing?.addListener(_onClosingChanged);
      if (widget.closing?.value ?? false) _onClosingChanged();
    }
  }

  @override
  void dispose() {
    widget.closing?.removeListener(_onClosingChanged);
    _ctrl?.dispose();
    super.dispose();
  }

  void _onClosingChanged() {
    if (_exiting || !(widget.closing?.value ?? false)) return;
    // Before the effect is resolved there is nothing to reverse and no frame
    // has been drawn; didChangeDependencies re-asks the moment there is.
    if (_effect == null) return;
    _exiting = true;
    final ctrl = _ctrl;
    if (ctrl == null) {
      widget.onClosed?.call();
      return;
    }
    ctrl.reverse().whenComplete(() {
      // Deliberately not gated on `mounted`: this callback is what destroys
      // the window, and a controller disposed mid-reverse never completes its
      // future at all — which is the case the owner's fallback timer exists
      // for, not this one.
      widget.onClosed?.call();
    });
  }

  /// Which way the card travels or hinges: away from the bar it belongs to.
  ///
  /// A popup below a top bar comes down out of it, one above a bottom bar rises
  /// out of it. Null — a menu at the pointer — reads as the top case.
  Offset get _direction {
    switch (widget.edge) {
      case 'bottom':
        return const Offset(0, 1);
      case 'left':
        return const Offset(-1, 0);
      case 'right':
        return const Offset(1, 0);
      default: // 'top', and every unanchored menu.
        return const Offset(0, -1);
    }
  }

  /// The corner or edge a [PopupEffect.grow] or [PopupEffect.flip] card is
  /// pinned to: the one it shares with the bar.
  Alignment get _joinAlignment {
    switch (widget.edge) {
      case 'bottom':
        return Alignment.bottomCenter;
      case 'left':
        return Alignment.centerLeft;
      case 'right':
        return Alignment.centerRight;
      default:
        return Alignment.topCenter;
    }
  }

  bool get _horizontal => widget.edge == 'left' || widget.edge == 'right';

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (ctrl == null) return widget.child;
    return AnimatedBuilder(
      animation: ctrl,
      // The card is built once and handed through: nothing inside it depends
      // on the animation, and a popup's content is among the most expensive
      // trees in the shell to rebuild — the weather card measures every row it
      // might draw.
      child: widget.child,
      builder: (context, child) => _apply(
        // Eased on the way in, and on the way out by the same token:
        // [Curves.easeOutCubic] read backwards *is* an ease-in, which is the
        // deceleration/acceleration pair a card entering and leaving wants.
        Curves.easeOutCubic.transform(ctrl.value.clamp(0.0, 1.0)),
        child!,
      ),
    );
  }

  Widget _apply(double t, Widget child) {
    switch (_effect ?? PopupEffect.slide) {
      case PopupEffect.none:
        return child;
      case PopupEffect.fade:
        return Opacity(opacity: t, child: child);
      case PopupEffect.slide:
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: _direction * ((1 - t) * kPopupSlideDistance),
            child: child,
          ),
        );
      case PopupEffect.scale:
        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: _kScaleFrom + (1 - _kScaleFrom) * t,
            child: child,
          ),
        );
      case PopupEffect.grow:
        final s = _kGrowFrom + (1 - _kGrowFrom) * t;
        return Opacity(
          opacity: t,
          child: Transform.scale(
            // Only across the join: a card unrolling out of a horizontal bar
            // keeps its width, or it reads as a scale that happens to be
            // off-centre rather than as the bar opening.
            scaleX: _horizontal ? s : 1.0,
            scaleY: _horizontal ? 1.0 : s,
            alignment: _joinAlignment,
            child: child,
          ),
        );
      case PopupEffect.flip:
        final angle = (1 - t) * _kFlipRadians;
        final matrix = Matrix4.identity()..setEntry(3, 2, 0.0016);
        // Hinged on the shared edge, so the far side of the card swings and
        // the joined side stays put. A bottom bar and a right-hand one hinge
        // the opposite way round from their counterparts, hence the sign.
        if (_horizontal) {
          matrix.rotateY(widget.edge == 'right' ? -angle : angle);
        } else {
          matrix.rotateX(widget.edge == 'bottom' ? -angle : angle);
        }
        return Opacity(
          opacity: t,
          child: Transform(
            transform: matrix,
            alignment: _joinAlignment,
            child: child,
          ),
        );
      case PopupEffect.spin:
        return Opacity(
          opacity: t,
          child: Transform.rotate(
            angle: (1 - t) * _kSpinRadians,
            child: Transform.scale(
              scale: _kScaleFrom + (1 - _kScaleFrom) * t,
              child: child,
            ),
          ),
        );
    }
  }
}
