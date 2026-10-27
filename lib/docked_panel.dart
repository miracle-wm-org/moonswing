// A column docked against the left or right edge of an output: the shape the
// clipboard history and the notification panel share.
//
// The window is the root's (`_createDockedWindow` in `main.dart`), and its
// shape is what these two panels are:
//
// - **It never takes the keyboard.** Keyboard mode `none`, like a bar: both
//   panels are read beside the window the user is working in, and a surface
//   that took focus on every click would take it off that window. So there is
//   no Escape; everything is a click or the scroll wheel, both of which reach a
//   surface without focus.
// - **It stays until asked to go.** Its own close button, or whatever opened
//   it. The coordinator registration is non-dismissable, so neither a click
//   elsewhere nor another popup opening takes it down.
// - **It floats over the windows.** No exclusive zone of its own: opening a
//   panel moves nothing, so the window the user is copying into or reading
//   beside stays exactly where it was. It still keeps clear of the bars, which
//   is what an exclusive zone of 0 asks the compositor for. Two panels docked
//   against the same edge are put side by side by the root, with a margin.
// - **It casts a shadow across its inner edge**, the theme's popup shadow
//   ([dockedPanelShadow]), since it now lies over something. The window is
//   grown by the shadow's reach and that strip is cut out of its input region,
//   so a click on the shadow lands on the window beneath it.
//
// This file is the part of that both panels draw: the flyout in and out of the
// docked edge (configurable per panel — [DockedPanelAnimation]), the opaque
// fill with its one inner rule and its shadow, and the header.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:moonswing/config_reader.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay_transition.dart'
    show ClampedCurve, flutterCurve;
import 'package:moonswing/popup.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/overlay_effect.dart';
import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/tokens.dart';

/// Which edge of the output a docked panel is against.
enum DockSide {
  left,
  right;

  /// The config spelling, for the settings row and the round trip.
  String get configName => name;

  /// [raw] as a side, or [fallback] for anything that is not one — a typo
  /// costs the key, never the table.
  static DockSide parse(String? raw, {DockSide fallback = DockSide.left}) =>
      switch (raw?.trim().toLowerCase()) {
        'left' => DockSide.left,
        'right' => DockSide.right,
        _ => fallback,
      };
}

/// The narrowest a docked panel may be configured: room for a line of text on a
/// card. Shared so the two panels' `width` keys clamp alike.
const int kDockedPanelMinWidth = 240;

/// The widest: a typo must not hand the whole output to a panel.
const int kDockedPanelMaxWidth = 1200;

/// How a docked panel arrives — and, reversed, how it leaves.
///
/// The flyout used to be one decision: a slide out of the docked edge on an
/// `easeOutCubic`, 180ms in and 150 out. This names that decision and hands
/// it to `[modules.notifications]` and `[modules.clipboard]`, each its own, the
/// way `overlay_animation` did for the full-screen overlays.
///
/// Every effect is anchored on the docked edge, and that is the one rule this
/// table keeps however it is configured: anything moving the panel *inwards*
/// past its resting place — an overshoot on a slide, a scale about the
/// centre — opens a strip between the panel and the screen edge, through which
/// the wallpaper shows down the full height of the output.
enum DockedPanelEffect {
  /// Nothing: the panel is simply there, and simply gone. No controller and no
  /// ticker, as `OverlayEffect.none` is.
  none('none', 'None', 'The panel appears and disappears with no animation.'),

  /// Out of the docked edge and back into it. The default, and what both
  /// panels did before the key existed.
  slide('slide', 'Slide',
      'The panel slides out of the edge of the screen it is docked against. '
          'The default.'),

  /// Opacity alone, in place.
  fade('fade', 'Fade', 'The panel fades in where it stands, and back out.'),

  /// A wipe from the docked edge: the panel stays put and is uncovered, a
  /// strip at a time, from the screen edge inwards.
  reveal('reveal', 'Reveal',
      'The panel stays where it is and is uncovered from the screen edge '
          'inwards.'),

  /// A horizontal scale about the docked edge: the panel unrolls out of it.
  stretch('stretch', 'Stretch',
      'The panel grows out of the screen edge, squeezed at first and '
          'stretching to its full width.');

  const DockedPanelEffect(this.slug, this.label, this.description);

  /// How `animation` spells this effect in `config.toml`.
  final String slug;

  /// The settings UI's name for it.
  final String label;

  /// One sentence for the settings UI's dropdown.
  final String description;

  /// Whether this effect moves anything — as opposed to [fade] and [none],
  /// which `animation_travel` and `animation_fade` say nothing about.
  bool get moves => this == slide || this == reveal || this == stretch;

  /// The effect [slug] names, or null if this build has no such effect — the
  /// caller holds the fallback, so a typo costs the key.
  static DockedPanelEffect? fromSlug(String? slug) {
    final wanted = slug?.trim().toLowerCase();
    for (final effect in DockedPanelEffect.values) {
      if (effect.slug == wanted) return effect;
    }
    return null;
  }
}

/// How long a docked panel takes to arrive, in milliseconds, when its module
/// names no `animation_duration`.
const int kDockedPanelEnterMs = 180;

/// The longest `animation_duration` may be: a panel taking longer than this to
/// arrive is in the way of the thing it was opened for.
const int kDockedPanelMaxDurationMs = 2000;

/// What fraction of the entrance the exit takes when no `animation_exit_ratio`
/// is given. An exit is the user being done, and does not need the entrance's
/// pace — four fifths, a popup's proportion.
const double kDockedPanelExitRatio = 0.8;

/// The `animation*` keys of a docked panel's `[modules.*]` table, typed.
///
/// Read when the panel's window is created and snapshotted by [DockedPanel]
/// as it mounts, as `side` and `width` are: an edit applies to the next panel,
/// never to one halfway through arriving.
@immutable
class DockedPanelAnimation {
  const DockedPanelAnimation({
    this.effect = DockedPanelEffect.slide,
    this.curve = OverlayCurve.easeOut,
    this.durationMs = kDockedPanelEnterMs,
    this.exitRatio = kDockedPanelExitRatio,
    this.travel = 1.0,
    this.fade = false,
  });

  /// `animation`: what moves.
  final DockedPanelEffect effect;

  /// `animation_curve`: how it is paced — the overlays' table, so the same
  /// word means the same easing on either. The exit plays it backwards.
  final OverlayCurve curve;

  /// `animation_duration`: the entrance, in milliseconds. Zero is [none].
  final int durationMs;

  /// `animation_exit_ratio`: the exit as a proportion of the entrance — a
  /// ratio, never a second duration, so the two cannot drift apart.
  final double exitRatio;

  /// `animation_travel`: how much of the panel's width the movement covers,
  /// from 0.05 to 1. 1 is all the way off the screen (or, for [reveal] and
  /// [stretch], from nothing); less starts the panel part of the way in, and
  /// reads best with [fade] on, since it otherwise appears with a jump.
  final double travel;

  /// `animation_fade`: whether a moving effect fades as well.
  final bool fade;

  /// Whether anything is drawn between shut and open. When not, the panel
  /// builds no controller and is gone on the turn it is closed.
  bool get animates => effect != DockedPanelEffect.none && durationMs > 0;

  Duration get enter => Duration(milliseconds: durationMs);

  Duration get exit => Duration(milliseconds: (durationMs * exitRatio).round());

  /// Reads the `animation*` keys out of a module's table. Every one degrades
  /// on its own: an unknown effect or curve costs that key, an out-of-range
  /// number is clamped.
  factory DockedPanelAnimation.fromMap(Map<String, dynamic>? map) {
    const defaults = DockedPanelAnimation();
    if (map == null) return defaults;
    return DockedPanelAnimation(
      effect: DockedPanelEffect.fromSlug(map.stringOrNull('animation')) ??
          defaults.effect,
      curve: OverlayCurve.fromSlug(
            map.stringOrNull('animation_curve')?.trim().toLowerCase(),
          ) ??
          defaults.curve,
      durationMs: map.intOr(
        'animation_duration',
        defaults.durationMs,
        min: 0,
        max: kDockedPanelMaxDurationMs,
      ),
      exitRatio: map.doubleOr(
        'animation_exit_ratio',
        defaults.exitRatio,
        min: 0.0,
        max: 2.0,
      ),
      travel: map.doubleOr(
        'animation_travel',
        defaults.travel,
        min: 0.05,
        max: 1.0,
      ),
      fade: map.boolOr('animation_fade', defaults.fade),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DockedPanelAnimation &&
          other.effect == effect &&
          other.curve == curve &&
          other.durationMs == durationMs &&
          other.exitRatio == exitRatio &&
          other.travel == travel &&
          other.fade == fade;

  @override
  int get hashCode =>
      Object.hash(effect, curve, durationMs, exitRatio, travel, fade);
}

/// The shadow a docked panel casts across its inner edge: the theme's popup
/// shadow, so a theme that drops its cards onto the desktop drops this column
/// onto the windows the same way, `midnight`'s glow is a glow here too, and
/// `carbon` — whose `popup_shadow_color` alpha is 0 — casts none.
///
/// Undisplaced, whatever the theme's offsets: they are a card's light falling
/// from above, and a full-height column has no bottom edge for one to show
/// under. Null when the theme has no shadow, or one with no reach past the
/// edge (a negative spread eating the whole blur).
BoxShadow? dockedPanelShadow(ThemeConfig theme) {
  final shadow = popupShadow(theme);
  if (shadow == null) return null;
  if (shadow.blurRadius + shadow.spreadRadius <= 0) return null;
  return BoxShadow(
    color: shadow.color,
    blurRadius: shadow.blurRadius,
    spreadRadius: shadow.spreadRadius,
  );
}

/// How far [dockedPanelShadow] reaches past the panel's inner edge, in whole
/// pixels: the strip the window is grown by. The CSS arithmetic
/// `popupShadowInsets` uses — one blur radius past the spread.
int dockedPanelShadowReach(ThemeConfig theme) {
  final shadow = dockedPanelShadow(theme);
  if (shadow == null) return 0;
  return (shadow.blurRadius + shadow.spreadRadius).ceil();
}

/// The panel's frame: it arrives out of [side] on creation and goes back
/// into it once [closingNotifier] flips, then calls [onClosed] — which may
/// tear the window down, so it is called exactly once.
class DockedPanel extends StatefulWidget {
  const DockedPanel({
    super.key,
    required this.side,
    required this.closingNotifier,
    required this.onClosed,
    this.animation = const DockedPanelAnimation(),
    this.shadowReach = 0,
    required this.child,
  });

  /// The edge the window is docked against, which the panel arrives from.
  final DockSide side;

  /// Flipped by whoever wants the panel gone. Starts the exit; [onClosed]
  /// tears the window down after it.
  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  /// How it arrives and leaves. Read once, as the panel mounts.
  final DockedPanelAnimation animation;

  /// How much wider than the panel its window is, on the inner side: the
  /// strip [dockedPanelShadow] is painted in, already cut out of the window's
  /// input region. 0 — a theme with no shadow, a platform that could not set
  /// the region, a test pumping the panel bare — is a panel filling its window
  /// with no shadow, as before there was one.
  final int shadowReach;

  final Widget child;

  @override
  State<DockedPanel> createState() => _DockedPanelState();
}

class _DockedPanelState extends State<DockedPanel>
    with SingleTickerProviderStateMixin {
  /// Snapshotted, so a settings edit while the panel is up cannot change the
  /// exit it is about to play from under it.
  late final DockedPanelAnimation _animation = widget.animation;

  /// Null under [DockedPanelEffect.none], which builds nothing that ticks.
  AnimationController? _controller;

  /// The configured curve, unclamped: what the movement reads. Each effect
  /// clamps it where an overshoot would open a strip at the screen edge.
  Animation<double>? _geometry;

  /// The same progress held in `0..1`, for the fade.
  Animation<double>? _opacity;

  /// Set by the dismissal that started the exit. A second one mid-exit must not
  /// queue a second `onClosed`, which would tear the window down twice.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    if (_animation.animates) {
      final controller = _controller = AnimationController(
        vsync: this,
        duration: _animation.enter,
        reverseDuration: _animation.exit,
      );
      final curve = flutterCurve(_animation.curve);
      // Read backwards on the way out, so the default ease-out entrance leaves
      // on the ease-in it always has.
      _geometry = CurvedAnimation(
        parent: controller,
        curve: curve,
        reverseCurve: curve.flipped,
      );
      final clamped = ClampedCurve(curve);
      _opacity = CurvedAnimation(
        parent: controller,
        curve: clamped,
        reverseCurve: clamped.flipped,
      );
      controller.forward();
    }
    widget.closingNotifier.addListener(_onClosingRequested);
  }

  @override
  void dispose() {
    widget.closingNotifier.removeListener(_onClosingRequested);
    _controller?.dispose();
    super.dispose();
  }

  void _onClosingRequested() {
    if (!widget.closingNotifier.value || _leaving) return;
    _leaving = true;
    final controller = _controller;
    if (controller == null) {
      // Nothing to play, but not from inside the notifier's own dispatch:
      // `onClosed` takes the window off the root, and whoever flipped the flag
      // is still part-way through the call that did it.
      scheduleMicrotask(() {
        if (mounted) widget.onClosed();
      });
      return;
    }
    // Reversing rather than starting over: a close that lands mid-entrance
    // turns the panel around from wherever it had got to.
    controller.reverse().then((_) => widget.onClosed());
  }

  /// [child] as the configured effect has it, at the controller's progress.
  Widget _animated(Widget child) {
    final geometry = _geometry;
    final opacity = _opacity;
    if (geometry == null || opacity == null) return child;
    final travel = _animation.travel;
    final left = widget.side == DockSide.left;
    var moved = switch (_animation.effect) {
      DockedPanelEffect.none || DockedPanelEffect.fade => child,
      // Held at the edge past 1: an overshoot carried on would move the panel
      // inwards and open a strip at the screen edge. Below 0 — the flipped
      // overshoot on the way out — it only goes further off-screen.
      DockedPanelEffect.slide => SlideTransition(
          position: geometry.drive(
            _DockSlide(away: left ? -travel : travel),
          ),
          child: child,
        ),
      DockedPanelEffect.reveal => ClipRect(
          clipper: _RevealClipper(geometry, left: left, travel: travel),
          child: child,
        ),
      // Free to overshoot past full width — the far edge is clipped by the
      // window — but never below zero, which would mirror it.
      DockedPanelEffect.stretch => AnimatedBuilder(
          animation: geometry,
          builder: (context, child) {
            final t = geometry.value;
            final scale = math.max(0.0, 1 - travel + travel * t);
            return Transform(
              alignment:
                  left ? Alignment.centerLeft : Alignment.centerRight,
              transform: Matrix4.diagonal3Values(scale, 1, 1),
              child: child,
            );
          },
          child: child,
        ),
    };
    if (_animation.effect == DockedPanelEffect.fade ||
        (_animation.fade && _animation.effect.moves)) {
      // Bounded by the panel, never the output: the window is the panel's own
      // width, so this layer is that column for the length of the animation
      // and nothing at rest, where `RenderAnimatedOpacity` skips it at 1.
      moved = FadeTransition(opacity: opacity, child: moved);
    }
    return moved;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // The inner edge, the one that faces the windows, gets the divider line;
    // the outer one is the screen edge and a line there would be drawn on
    // nothing.
    final inner = BorderSide(color: theme.divider);
    final left = widget.side == DockSide.left;
    final reach = widget.shadowReach.toDouble();
    // The live theme's, so a switch while the panel is up restyles it; the
    // strip it falls in is the window's and was fixed at creation, and the
    // clip below cuts a shadow that has since outgrown it at the window edge.
    final shadow = reach > 0 ? dockedPanelShadow(theme) : null;
    return PopupDismissArea(
      // A click in the panel is a click elsewhere as far as any bar popup is
      // concerned. The panel's own registration refuses dismissal, so it is
      // the one thing this leaves open.
      child: Directionality(
        // Its own, for the tests that pump a panel bare; on a real window
        // `ShellTextRoot` has already said the same.
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: ShellFontSizes.body,
            color: theme.popupForeground,
          ),
          child: ClipRect(
            child: _animated(
              // The shadow's strip is inside what the effect moves, so a full
              // slide carries the shadow off the screen with the panel rather
              // than leaving it hanging at the edge.
              Padding(
                padding: left
                    ? EdgeInsets.only(right: reach)
                    : EdgeInsets.only(left: reach),
                // Deliberately not a PopupCard: a full-height surface against
                // the screen edge, where rounding would cut wallpaper wedges
                // out of the display's corners and a rim would draw a line
                // down the screen edge.
                child: Container(
                  // Opaque whatever the theme says: this is read over a window
                  // that would otherwise show through it. Only the alpha is
                  // overridden, so a palette still tints it.
                  decoration: BoxDecoration(
                    color: theme.popupBackground.withValues(alpha: 1.0),
                    border: left ? Border(right: inner) : Border(left: inner),
                    // Painted outside the box, into the padding's strip; the
                    // other three sides fall off the window and are clipped.
                    boxShadow: shadow == null ? null : [shadow],
                  ),
                  // Its own layer, so a card's hover tint or a time ticking
                  // re-records the content and leaves the blur's picture be.
                  child: RepaintBoundary(child: widget.child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A slide's offset at progress `t`: [away] widths out at 0, docked at 1, and
/// held docked past it.
class _DockSlide extends Animatable<Offset> {
  const _DockSlide({required this.away});

  /// Signed: negative out of the left edge, positive out of the right.
  final double away;

  @override
  Offset transform(double t) => Offset(away * (1 - math.min(t, 1.0)), 0);
}

/// The visible part of a revealing panel: a strip against the docked edge,
/// [travel] of the width short of the whole at 0 and the whole of it from 1.
class _RevealClipper extends CustomClipper<Rect> {
  _RevealClipper(this.progress, {required this.left, required this.travel})
      : super(reclip: progress);

  final Animation<double> progress;
  final bool left;
  final double travel;

  @override
  Rect getClip(Size size) {
    final t = progress.value.clamp(0.0, 1.0);
    final width = size.width * (1 - travel + travel * t);
    return left
        ? Rect.fromLTWH(0, 0, width, size.height)
        : Rect.fromLTWH(size.width - width, 0, width, size.height);
  }

  @override
  bool shouldReclip(_RevealClipper oldClipper) =>
      oldClipper.progress != progress ||
      oldClipper.left != left ||
      oldClipper.travel != travel;
}

/// The title, a line saying what is in the panel, whatever acts on the whole
/// of it, and the close button.
class DockedPanelHeader extends StatelessWidget {
  const DockedPanelHeader({
    super.key,
    required this.title,
    required this.summary,
    required this.onClose,
    this.actions = const [],
  });

  final String title;
  final String summary;
  final VoidCallback onClose;

  /// Between the title and the close button — a [DockedPanelTextButton] or an
  /// icon. Each is followed by a small gap.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: ShellFontSizes.heading,
                    fontWeight: FontWeight.bold,
                    color: theme.popupForeground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    color: theme.popupForeground.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          for (final action in actions) ...[action, const SizedBox(width: 6)],
          SettingsIconButton(
            icon: ShellGlyph.close,
            box: ShellSizes.iconButton + 6,
            size: ShellFontSizes.title,
            color: theme.popupForeground,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

/// A bordered word in the header — the destructive act on the whole panel
/// ("Clear"), which is why it is a word and not an icon.
///
/// A tint of the accent it is lettered in when hovered, never `surface_hover`
/// at full strength: that key is the accent itself in the shipped palette, so
/// the word would disappear into its own button under the pointer.
class DockedPanelTextButton extends StatelessWidget {
  const DockedPanelTextButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => Container(
        height: ShellSizes.iconButton + 4,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? theme.accent.withValues(alpha: 0.18) : null,
          border: Border.all(
            color: theme.accent.withValues(alpha: hovered ? 0.9 : 0.5),
          ),
          borderRadius: BorderRadius.circular(ShellRadii.control),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: ShellFontSizes.body,
            color: theme.accentText,
          ),
        ),
      ),
    );
  }
}

/// A card on a docked panel: the control surface, a hover tint, and a hairline
/// border — or [ring], for the one card the panel is drawing attention to.
BoxDecoration dockedPanelCardDecoration(
  BuildContext context, {
  required bool hovered,
  Color? ring,
}) {
  final theme = ThemeScope.of(context);
  return BoxDecoration(
    color: hovered
        ? theme.surfaceHover.atMostAlpha(0.14)
        : theme.controlSurface,
    borderRadius: BorderRadius.circular(ShellRadii.card),
    border: Border.all(color: ring ?? theme.divider),
  );
}

/// The empty state, which is also the panel's instructions.
class DockedPanelEmpty extends StatelessWidget {
  const DockedPanelEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final ShellGlyph icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShellIcon(
              icon,
              size: 40,
              color: theme.popupForeground.withValues(alpha: 0.28),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ShellFontSizes.label,
                fontWeight: FontWeight.w600,
                color: theme.popupForeground.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                height: 1.4,
                color: theme.popupForeground.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
