import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// The round button itself — the part the pointer aims at.
const double kNotificationBadgeDiameter = 48;

/// The gap between the badge's surface and the edges it is anchored to.
///
/// Deliberately *only* a gap. The badge does not inset itself past the bars: its
/// layer surface keeps gtk-layer-shell's default exclusive zone of 0, which means
/// "move me so I don't occlude surfaces that reserved space" — so the compositor
/// has already placed it clear of the bars, their margins included. Adding
/// `panelInsetsFor` would count every bar twice and hang the badge a bar's height
/// out into the middle of the screen. It is also why the badge must never call
/// `spanFullOutput`: a zone of -1 asks the compositor to stop doing that.
const double kNotificationBadgeGap = 14;

/// Room for the button's shadow, on every side.
///
/// The surface is bigger than the button because a `BoxShadow` paints *outside*
/// its box and this window clips at its edge — `popupShadowInsets`' problem one
/// layer down. Kept as tight as that allows: with no input-region support, every
/// pixel of this surface is a pixel of the output that swallows clicks.
const double kNotificationBadgeShadowInset = 12;

/// The extra room the count bubble needs on the two sides it hangs over.
const double kNotificationBadgeBubbleInset = 4;

/// The padding [NotificationBadge] lays itself out under. Top and right carry
/// the bubble's overhang as well as the shadow's.
const EdgeInsets kNotificationBadgeInsets = EdgeInsets.fromLTRB(
  kNotificationBadgeShadowInset,
  kNotificationBadgeShadowInset + kNotificationBadgeBubbleInset,
  kNotificationBadgeShadowInset + kNotificationBadgeBubbleInset,
  kNotificationBadgeShadowInset,
);

/// The surface size those imply. Read by the root when it creates the window
/// and by [NotificationBadge] when it lays itself out inside it, so the button
/// lands where the margins say it does.
const Size kNotificationBadgeWindowSize = Size(
  kNotificationBadgeDiameter +
      2 * kNotificationBadgeShadowInset +
      kNotificationBadgeBubbleInset,
  kNotificationBadgeDiameter +
      2 * kNotificationBadgeShadowInset +
      kNotificationBadgeBubbleInset,
);

/// How long the badge takes to arrive, and how long a bump lasts.
const Duration kNotificationBadgeEnter = Duration(milliseconds: 260);
const Duration kNotificationBadgeBump = Duration(milliseconds: 240);

/// The number the bubble shows for [count] — three characters at the most, so
/// a machine that has been left alone all weekend does not widen the surface
/// the badge was sized for.
String notificationBadgeLabel(int count) => count > 99 ? '99+' : '$count';

/// The floating "you have notifications" button.
///
/// One per monitor, in a small root-owned overlay window that exists only while
/// there is something to report — the OSD's rule and its reason: a permanently
/// mapped surface would sit in the corner of every output eating clicks.
///
/// Three things a change here has to keep true:
///
/// - **It is the same count the bell shows, from the same store, and it opens the
///   same panel.** The badge exists because the bell may not: a user with no
///   `notifications` module in any panel would otherwise have a shell that
///   silently swallows every notification. It is not a second inbox.
/// - **Nothing on it animates at rest.** The entrance plays once and a bump plays
///   when the count goes up; both settle, so a surface that may be on screen for
///   hours costs nothing per frame after that.
/// - **The button is the whole box.** [HoverRegion] emits the opaque detector, so
///   the 48px circle is the hover box and the tap box alike.
class NotificationBadge extends StatefulWidget {
  const NotificationBadge({super.key, required this.onTap});

  /// Asks for the notification panel. The root supplies this rather than the
  /// badge poking [NotificationPanelController] itself, because the root knows
  /// which monitor this badge is on and can open the panel on that one.
  final VoidCallback onTap;

  @override
  State<NotificationBadge> createState() => _NotificationBadgeState();
}

class _NotificationBadgeState extends State<NotificationBadge>
    with TickerProviderStateMixin {
  late final AnimationController _enterController;
  late final Animation<double> _enterScale;

  late final AnimationController _bumpController;
  late final Animation<double> _bumpScale;

  int _prevCount = 0;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: kNotificationBadgeEnter,
    );
    // Overshoot on the way in: the badge appears with no warning in a corner
    // the user was not looking at, and a plain fade there is easy to miss.
    _enterScale = CurvedAnimation(
      parent: _enterController,
      curve: Curves.easeOutBack,
    );

    _bumpController = AnimationController(
      vsync: this,
      duration: kNotificationBadgeBump,
    );
    _bumpScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.14)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.14, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 60,
      ),
    ]).animate(_bumpController);

    _prevCount = NotificationStore.instance.items.length;
    NotificationStore.instance.addListener(_onStoreChanged);
    _enterController.forward();
  }

  @override
  void dispose() {
    NotificationStore.instance.removeListener(_onStoreChanged);
    _enterController.dispose();
    _bumpController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    final count = NotificationStore.instance.items.length;
    // Only *more* notifications bump it. A dismissal moving the number down is
    // the user tidying up, and re-animating for that would draw the eye back
    // to the thing they are in the middle of clearing.
    if (count > _prevCount) _bumpController.forward(from: 0.0);
    _prevCount = count;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final count = NotificationStore.instance.items.length;

    return Padding(
      padding: kNotificationBadgeInsets,
      child: ScaleTransition(
        scale: _enterScale,
        child: FadeTransition(
          opacity: _enterController,
          child: ScaleTransition(
            scale: _bumpScale,
            child: HoverRegion(
              // Tap-down, not tap: `PopupDismissArea`'s ancestor `Listener`
              // fires before any descendant recognizer, so every popup toggle
              // in the shell opens on the down edge and is guarded there.
              onTapDown: (_) => widget.onTap(),
              builder: (context, hovered) => Stack(
                clipBehavior: Clip.none,
                children: [
                  _BadgeButton(theme: theme, hovered: hovered),
                  if (count > 0)
                    Positioned(
                      top: -8,
                      right: -10,
                      child: _BadgeCount(theme: theme, count: count),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The round button under the count.
class _BadgeButton extends StatelessWidget {
  const _BadgeButton({required this.theme, required this.hovered});

  final ThemeConfig theme;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    // Opaque whatever the theme says, the settings panel's rule at a much
    // smaller size and for the same reason: this floats over the wallpaper
    // rather than over a surface of the shell's own, and a translucent fill
    // puts whatever photograph the user chose behind a 20px glyph.
    final fill = (hovered ? theme.surfaceHover : theme.popupBackground)
        .withValues(alpha: 1.0);
    return Container(
      width: kNotificationBadgeDiameter,
      height: kNotificationBadgeDiameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(
          color: theme.accent.withValues(alpha: hovered ? 0.9 : 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: FaIcon(
        FontAwesomeIcons.bell,
        size: 20,
        color: theme.accent,
      ),
    );
  }
}

/// The count bubble, drawn over the button's rim.
///
/// Ringed in the button's own fill so it reads as punched out of it rather than
/// as a blob resting on top — `_BrokenDot`'s trick on the bell, which is what
/// keeps a small filled shape legible over any theme.
class _BadgeCount extends StatelessWidget {
  const _BadgeCount({required this.theme, required this.count});

  final ThemeConfig theme;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.accent,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: theme.popupBackground.withValues(alpha: 1.0),
          width: 2,
        ),
      ),
      child: Text(
        notificationBadgeLabel(count),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: ShellFontSizes.caption,
          height: 1.0,
          fontWeight: FontWeight.bold,
          color: kOnAccent,
        ),
      ),
    );
  }
}
