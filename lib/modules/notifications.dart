import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/bar_button.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/popup_coordinator.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/notification_badge.dart';
import 'package:graceful_shell/notification_panel_controller.dart';
import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/theme_provider.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// How wide the panel is on an output [screenWidth] logical pixels across.
///
/// A fraction of the screen clamped at both ends, rather than the bare
/// `width / 5` this was: a fifth of a 1366px laptop is 273px, which wraps a
/// two-word summary and stacks the action buttons one per row, while a fifth of
/// an ultrawide covers what the user was reading.
///
/// Pure, so `test/notification_panel_test.dart` can pin both ends.
int notificationPanelWidth(double screenWidth) =>
    (screenWidth / 4).round().clamp(360, 560);

/// Bell icon widget that lives in the bar. Lights up and shakes when
/// notifications arrive, and asks for the notification panel on click.
///
/// It no longer *owns* that panel: the floating badge asks for the same one from
/// a root-owned surface of its own, and two hosts cannot share a
/// `LayerShellHost` window — so both go through [NotificationPanelController].
class Notifications extends StatefulWidget {
  const Notifications({super.key});

  @override
  State<Notifications> createState() => _NotificationsState();
}

class _NotificationsState extends State<Notifications>
    with SingleTickerProviderStateMixin, PopupHost<Notifications> {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  int _prevCount = 0;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0), weight: 1),
    ]).animate(_shakeController);

    _prevCount = NotificationStore.instance.items.length;
    NotificationStore.instance.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    NotificationStore.instance.removeListener(_onStoreChanged);
    _shakeController.dispose();
    closePopup();
    super.dispose();
  }

  void _onStoreChanged() {
    final store = NotificationStore.instance;
    final newCount = store.items.length;
    // Silenced is about interruption, so the shake is the first thing it takes
    // away: the notification is still collected, and the bell still counts it,
    // but nothing moves in the corner of the user's eye to fetch them.
    if (newCount > _prevCount && !store.silenced) {
      _shakeController.forward(from: 0.0);
    }
    _prevCount = newCount;
    if (mounted) setState(() {});
  }

  /// What the hover label says, or null when a plain working bell has nothing
  /// to explain.
  ///
  /// Two states earn one, and the broken one wins: a bell that is silenced
  /// *and* has lost the daemon is not silencing anything, so saying so would be
  /// the more reassuring of two answers and the wrong one.
  static String? _statusMessage(NotificationStore store) {
    if (store.daemonUnavailable) {
      return 'Notifications are not working — the shell could not claim the '
          'notification service. Click to open the panel and retry.';
    }
    if (store.silenced) {
      return 'Notifications are silenced. They still collect in the panel — '
          'right-click to let them interrupt again.';
    }
    return null;
  }

  /// The hover label that explains the glyph the bell is currently wearing.
  ///
  /// The crossed-out bell and the exclamation dot each say *something* is up;
  /// this is where it says what, without making the user open the panel to find
  /// out — and, for the silenced bell, where the right-click that undoes it is
  /// named, since nothing about a glyph advertises a gesture.
  void _openStatusTooltip(BuildContext context, String message) {
    if (isPopupOpen) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    openBarPopup(
      context,
      child: ThemeProvider(
        child: TooltipLabel(text: message),
      ),
      preferredConstraints: const BoxConstraints(maxWidth: 260, maxHeight: 96),
      // A hover label must not take down whatever the pointer is travelling
      // towards, and must be dismissed by anything else opening.
      policy: TransientPolicy.tooltip,
      // Its own reopen-guard slot. The panel is registered with the
      // coordinator by the root rather than under this `State`, but the bell
      // still opens two different surfaces from one element, so the tooltip
      // keeps a slot of its own.
      ownerKey: (this, 'status-tooltip'),
      // A floating card, never glued to the bar — see the dock's tooltip.
      attach: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final store = NotificationStore.instance;
    final count = store.items.length;
    final hasUnread = count > 0;
    final broken = store.daemonUnavailable;
    final silenced = store.silenced;
    final status = _statusMessage(store);

    final glyph = AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shakeAnimation.value, 0),
          child: child,
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The glyph *is* the status: a crossed-out bell is what every
          // other shell means by silenced, so it needs no legend. It is also
          // deliberately never the accent colour, unread items or not —
          // accent is the bar's "look at this", which is the one thing a
          // silenced bell has been told not to say. The count bubble below
          // keeps its own colour, so "silenced, and three waiting" is still
          // one glance.
          FaIcon(
            silenced ? FontAwesomeIcons.bellSlash : FontAwesomeIcons.bell,
            size: 16,
            color: silenced
                ? theme.foreground.withValues(alpha: 0.55)
                : hasUnread
                    ? theme.accent
                    : theme.foreground,
          ),
          if (hasUnread)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: theme.accent,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(
                  minWidth: 12,
                  minHeight: 12,
                ),
                child: Text(
                  notificationBadgeLabel(count),
                  style: TextStyle(
                    fontSize: 8,
                    color: theme.popupBackground,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          // Bottom-right, so it never lands on the unread count. The two
          // are independent — a daemon that lost the name at start-up
          // leaves the bell at zero, but one that had notifications
          // before something else took the name would show both.
          if (broken)
            Positioned(
              right: -3,
              bottom: -3,
              child: _BrokenDot(theme: theme),
            ),
        ],
      ),
    );

    // The pressed state follows the root's window, not a field here: the panel
    // this opens may equally have been opened (or closed) from the floating
    // badge on another monitor.
    final bell = ValueListenableBuilder<bool>(
      valueListenable: NotificationPanelController.instance.isOpen,
      builder: (context, isOpen, child) => BarButton(
        active: isOpen,
        // Tap-down, like every other popup toggle in the shell: the ancestor
        // `PopupDismissArea` Listener fires before any descendant recognizer.
        onTapDown: (_) => NotificationPanelController.instance.toggle(),
        // Right-click silences and unsilences. A gesture rather than a menu
        // because it is one boolean with one obvious inverse, and the panel's
        // own switch is the discoverable half of the pair — the tooltip on a
        // silenced bell names this one.
        onSecondaryTapDown: (_) => NotificationStore.instance.toggleSilenced(),
        child: child!,
      ),
      child: glyph,
    );

    // Only a bell with something to explain carries a hover label, so the
    // MouseRegion is only worth its callbacks then; an ordinary one is the
    // plain BarButton it always was.
    if (status == null) return bell;

    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        // Post-frame, the dock's pattern: the label is placed against this
        // element's render box, which the hover itself may still be resizing.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_hovered) return;
          // Re-read rather than closing over `status`: a frame is long enough
          // for the daemon to come back or for a right-click to land.
          final current = _statusMessage(NotificationStore.instance);
          if (current == null) return;
          _openStatusTooltip(context, current);
        });
      },
      onExit: (_) {
        _hovered = false;
        closePopup();
      },
      child: bell,
    );
  }
}

/// The exclamation dot on the bell: "notifications are broken right now".
///
/// A ring in the bar's own colour rather than a bare circle, so the dot reads as
/// punched out of the bell rather than as part of the glyph — the trick an unread
/// badge plays, and what keeps 10 logical pixels legible at any theme.
class _BrokenDot extends StatelessWidget {
  const _BrokenDot({required this.theme});

  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kErrorColor,
        shape: BoxShape.circle,
        border: Border.all(color: theme.panelBackground, width: 1),
      ),
      child: const Text(
        '!',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 7,
          height: 1.0,
          fontWeight: FontWeight.bold,
          color: kOnAccent,
        ),
      ),
    );
  }
}

/// How long the panel takes to arrive.
const Duration kNotificationPanelEnter = Duration(milliseconds: 300);

/// How long it takes to leave — deliberately a little over half that.
///
/// The way out is not the way in played backwards: an entrance presents a surface
/// the user has not read yet and is paced to be followed, while a dismissal is
/// the user saying they are done.
const Duration kNotificationPanelExit = ShellDurations.overlayFade;

/// Full-height Layer Shell panel anchored to the right side of the screen.
///
/// Slides in from the right on creation; leaves by a *different* animation (see
/// [_NotificationPanelState]) before being destroyed.
///
/// Owned by `_GracefulShellRootState` rather than the bell module — both things
/// that ask for it (the bell and the floating badge) ask the root, which is what
/// makes there be exactly one.
///
/// Public, unlike the rest of the panel's parts, because in its one real home it
/// is a layer-shell window no widget test can pump.
class NotificationPanel extends StatefulWidget {
  const NotificationPanel({
    super.key,
    required this.closingNotifier,
    required this.onClosed,
  });

  /// Flipped by whoever wants the panel gone — the bell, the header's close
  /// button, Escape, or the [PopupCoordinator] on a click elsewhere. Flipping
  /// it starts the exit animation; [onClosed] is what tears the window down
  /// once that animation is over.
  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  @override
  State<NotificationPanel> createState() => _NotificationPanelState();
}

/// The two animations, and why they are two.
///
/// The entrance is the `SlideTransition` it always was — never a centre-pivoted
/// scale, for [build]'s reason. The exit is its own controller rather than that
/// one reversed, which is what lets it be shorter *and* a different animation: a
/// beat of wind-up, then the panel takes off to the right, shrinking towards and
/// fading into the edge it is anchored to.
///
/// Every part of that exit is pinned to `Alignment.centerRight` or moves the
/// panel further *off* the screen. This surface is butted against the output's
/// right edge, so anything moving the content left — an overshoot, an
/// anticipation dip, a centre-pivoted scale — opens a transparent strip along the
/// screen edge that reads as the panel having detached from it.
class _NotificationPanelState extends State<NotificationPanel>
    with TickerProviderStateMixin {
  late final AnimationController _enterController;
  late final Animation<Offset> _enterSlide;

  late final AnimationController _exitController;
  late final Animation<Offset> _exitSlide;
  late final Animation<double> _exitScale;
  late final Animation<double> _exitFade;

  @override
  void initState() {
    super.initState();

    _enterController = AnimationController(
      vsync: this,
      duration: kNotificationPanelEnter,
    );
    _enterSlide = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _enterController,
      curve: Curves.easeOut,
    ));

    _exitController = AnimationController(
      vsync: this,
      duration: kNotificationPanelExit,
    );
    // Held in place through the wind-up, then thrown clear. A full panel
    // width is more than enough to clear the surface, because the scale below
    // is pulling it towards that edge at the same time.
    _exitSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(1.0, 0.0),
    ).animate(CurvedAnimation(
      parent: _exitController,
      curve: const Interval(0.22, 1.0, curve: Curves.easeInCubic),
    ));
    // Squash and stretch: a short swell against the edge, then away. The
    // swell is clipped by the surface rather than drawn outside it, so it
    // reads as the panel gathering itself rather than as it growing.
    _exitScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.04)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.04, end: 0.86)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 78,
      ),
    ]).animate(_exitController);
    // Late, so the panel is visibly *leaving* rather than merely dissolving
    // where it stood.
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(
      parent: _exitController,
      curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
    ));

    _enterController.forward();
    widget.closingNotifier.addListener(_onClosingRequested);
    NotificationStore.instance.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.closingNotifier.removeListener(_onClosingRequested);
    NotificationStore.instance.removeListener(_onStoreChanged);
    _enterController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _onClosingRequested() {
    if (!widget.closingNotifier.value) return;
    // A second dismissal mid-exit must not restart the animation — and must
    // not queue a second `onClosed`, which would tear the window down twice.
    if (_exitController.status != AnimationStatus.dismissed) return;
    _exitController.forward().then((_) => widget.onClosed());
  }

  /// Escape is a dismissal like any other: it flips the notifier and lets the
  /// exit animation run, rather than closing the window from under itself.
  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.closingNotifier.value = true;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final items = NotificationStore.instance.items;

    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Directionality(
        textDirection: TextDirection.ltr,
        // The panel's own text root, one tier up from the shell's body size: this
        // surface is read at arm's length rather than scanned like a bar module,
        // and every size below is a ratio to this one, so a theme's `font_size`
        // still moves all of it together.
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: theme.fontFamily,
            fontSize: ShellFontSizes.label,
            color: theme.popupForeground,
          ),
          child: SlideTransition(
            position: _enterSlide,
            // The slide is the whole entrance: never a centre-pivoted scale,
            // which on a full-height edge-anchored surface pulls the panel away
            // from the edge it is anchored to and shows a gap that closes as it
            // settles. The exit's scale is the same widget with the pivot moved
            // to the edge, which is the whole difference between a flourish and
            // that gap.
            child: SlideTransition(
              position: _exitSlide,
              child: ScaleTransition(
                scale: _exitScale,
                alignment: Alignment.centerRight,
                child: FadeTransition(
                  opacity: _exitFade,
                  // Deliberately not a PopupCard. This is a full-height surface
                  // anchored to the screen's right edge, not a floating card:
                  // rounding it would cut wallpaper wedges out of the display's
                  // corners and a rim would draw a line down the screen edge.
                  //
                  // Opaque whatever the theme says, the settings overlay's
                  // `overlayPanelFill` rule: this is a column of prose read over
                  // whatever window is behind it, and a translucent fill puts that
                  // window's text straight through it. Only the alpha is
                  // overridden, so a palette still tints the panel.
                  child: Container(
                    color: theme.popupBackground.withValues(alpha: 1.0),
                    child: Column(
                      children: [
                        _buildHeader(theme, items.length),
                        Container(height: 1, color: theme.divider),
                        // Above the list, not inside it: with the daemon down
                        // the list is empty, and an empty state reading "No
                        // notifications" is a lie the user would act on.
                        if (NotificationStore.instance.daemonUnavailable) ...[
                          NotificationDaemonBanner(theme: theme),
                          Container(height: 1, color: theme.divider),
                        ],
                        NotificationSilenceRow(theme: theme),
                        Container(height: 1, color: theme.divider),
                        Expanded(
                          child: items.isEmpty
                              ? _buildEmpty(theme)
                              : _buildList(theme, items),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The header: what this panel is, how much is in it, and the two ways out.
  ///
  /// Set at [ShellFontSizes.heading] with a count under it: a bold 15px word over
  /// a list of unlabelled cards said what the surface was called and nothing
  /// about what was in it. "Clear all" is a bordered button rather than a tinted
  /// word, because it destroys every item on the list.
  Widget _buildHeader(ThemeConfig theme, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: ShellFontSizes.heading,
                    fontWeight: FontWeight.bold,
                    color: theme.popupForeground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count == 0
                      ? 'Nothing waiting'
                      : count == 1
                          ? '1 notification'
                          : '$count notifications',
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    color: theme.popupForeground.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          if (count > 0) ...[
            HoverRegion(
              onTap: () => NotificationStore.instance.dismissAll(),
              builder: (context, hovered) => Container(
                height: ShellSizes.iconButton + 6,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hovered ? theme.surfaceHover : null,
                  border: Border.all(
                    color: theme.accent.withValues(alpha: hovered ? 0.9 : 0.5),
                  ),
                  borderRadius: BorderRadius.circular(ShellRadii.control),
                ),
                child: Text(
                  'Clear all',
                  style: TextStyle(
                    fontSize: ShellFontSizes.label,
                    color: theme.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          SettingsIconButton(
            icon: FontAwesomeIcons.xmark,
            box: ShellSizes.iconButton + 6,
            size: ShellFontSizes.title,
            color: theme.popupForeground,
            onTap: () => widget.closingNotifier.value = true,
          ),
        ],
      ),
    );
  }

  /// The empty state, which is also the panel's instructions.
  ///
  /// A greyed glyph over a greyed line reads as the panel having failed rather
  /// than as there being nothing to show. The second line is what makes it a
  /// statement: notifications *will* appear here.
  Widget _buildEmpty(ThemeConfig theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A plain bell, not a crossed-out one: on this surface the crossed
            // bell is the silence switch's glyph, and an empty inbox is not the
            // same claim as a silenced one — a user who had just silenced
            // notifications would read the big version of that glyph as the
            // panel reporting the switch back to them.
            FaIcon(
              FontAwesomeIcons.bell,
              size: 44,
              color: theme.popupForeground.withValues(alpha: 0.28),
            ),
            const SizedBox(height: 18),
            Text(
              'You are all caught up',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ShellFontSizes.title,
                fontWeight: FontWeight.bold,
                color: theme.popupForeground.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Notifications from your applications appear here. '
              'Press Escape to close this panel.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ShellFontSizes.label,
                height: 1.45,
                color: theme.popupForeground.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The list. Cards are separated by a gap rather than by a hairline: at the
  /// sizes they are now set in, a rule between two three-line blocks reads as
  /// a table, and what is wanted is a stack of separate messages.
  Widget _buildList(ThemeConfig theme, List<NotificationItem> items) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) =>
          _NotificationCard(item: items[i], theme: theme),
    );
  }
}

/// The panel's "do not disturb" switch — the discoverable half of the pair the
/// bell's right-click is the quick half of.
///
/// It sits under the header rather than in it, with a sentence saying what
/// silencing *does not* do: the one thing a user has to know before flipping a
/// switch called "silence" is whether the notifications it silences are lost,
/// and the answer is that they are all still here.
///
/// Rebuilt by `_NotificationPanelState`'s store listener, like
/// [NotificationDaemonBanner] and for the same reason — the flag it renders and
/// the flag it writes are the same store the panel already listens to.
///
/// Public because in its one real home it is inside a layer-shell window no
/// widget test can pump.
class NotificationSilenceRow extends StatelessWidget {
  const NotificationSilenceRow({super.key, required this.theme});

  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    final store = NotificationStore.instance;
    final silenced = store.silenced;

    return RepaintBoundary(
      child: HoverRegion(
        // The whole row, not just the 44px switch: the label is the biggest
        // thing on it and pointing at a label that does nothing reads as the
        // control being disabled. The switch is a `HoverRegion` of its own and
        // wins the arena as the deeper one, so a tap on it toggles once.
        onTap: store.toggleSilenced,
        builder: (context, hovered) => Container(
          color: hovered ? theme.surfaceHover.withValues(alpha: 0.16) : null,
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
          child: Row(
            children: [
              FaIcon(
                silenced ? FontAwesomeIcons.bellSlash : FontAwesomeIcons.bell,
                size: ShellFontSizes.label,
                color: silenced
                    ? theme.accent
                    : theme.popupForeground.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Silence notifications',
                      style: TextStyle(
                        fontSize: ShellFontSizes.label,
                        color: theme.popupForeground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      silenced
                          ? 'New notifications wait here quietly. '
                              'Nothing is lost.'
                          : 'New notifications announce themselves as they '
                              'arrive.',
                      style: TextStyle(
                        fontSize: ShellFontSizes.secondary,
                        height: 1.35,
                        color: theme.popupForeground.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SettingsToggle(
                value: silenced,
                onChanged: store.setSilenced,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Why the panel is empty, and the one control that can change it.
///
/// Shown whenever the shell does not own `org.freedesktop.Notifications` —
/// another daemon claimed it first, or the request errored. Both are recoverable
/// without restarting the shell, which is what Retry is for; the shell cannot
/// detect either happening, so the user has to say when.
///
/// Rebuilt by `_NotificationPanelState`'s store listener, so both the reason text
/// and the button's in-flight state follow the store with no listener of its own.
///
/// Public, like [NotificationPanel] itself, because in its one real home it is
/// inside a layer-shell window no widget test can pump.
class NotificationDaemonBanner extends StatelessWidget {
  const NotificationDaemonBanner({super.key, required this.theme});

  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    final store = NotificationStore.instance;
    return Container(
      color: kErrorColor.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: FaIcon(
              FontAwesomeIcons.triangleExclamation,
              size: 14,
              color: kErrorColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications are not working',
                  style: TextStyle(
                    fontSize: ShellFontSizes.label,
                    fontWeight: FontWeight.bold,
                    color: theme.popupForeground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  store.daemonReason ??
                      'The shell could not claim the notification service.',
                  style: TextStyle(
                    fontSize: ShellFontSizes.body,
                    height: 1.4,
                    color: theme.popupForeground.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _RetryButton(theme: theme),
        ],
      ),
    );
  }
}

/// The Retry button, which re-runs the name request.
///
/// While an attempt is in flight it becomes a loader rather than a disabled
/// button: `retryDaemon` refuses a second attempt anyway, and a control that
/// still looks pressable but does nothing reads as the retry having failed.
class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.theme});

  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    final store = NotificationStore.instance;
    if (store.daemonRetrying) {
      return const SizedBox(
        width: 68,
        height: ShellSizes.iconButton + 6,
        child: Center(child: LoadingIndicator(size: 14, color: kErrorColor)),
      );
    }

    return HoverRegion(
      onTap: () => store.retryDaemon(),
      builder: (context, hovered) => Container(
        width: 68,
        height: ShellSizes.iconButton + 6,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? kErrorColor.withValues(alpha: 0.18) : null,
          border: Border.all(color: kErrorColor.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(ShellRadii.control),
        ),
        child: const Text(
          'Retry',
          style: TextStyle(
            fontSize: ShellFontSizes.label,
            color: kErrorColor,
          ),
        ),
      ),
    );
  }
}

/// One notification, as a card.
///
/// A card rather than a row on a ruled list, and everything below follows from
/// that. The list is what the user came to read, so the summary is set at
/// [ShellFontSizes.title] and the body at the panel's own body size, with the
/// app name a caption above them rather than the same weight as the message.
/// The whole card is the dismiss target's neighbour, and the actions are real
/// buttons: at the sizes this used, a "Reply" the size of a footnote was a
/// control the pointer had to be aimed at.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.theme,
  });

  final NotificationItem item;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    final actionWidgets = <Widget>[];
    for (int i = 0; i + 1 < item.actions.length; i += 2) {
      final key = item.actions[i];
      final label = item.actions[i + 1];
      if (key == 'default') continue;
      actionWidgets.add(
        HoverRegion(
          onTap: () => NotificationStore.instance.invokeAction(item.id, key),
          builder: (context, hovered) => Container(
            height: ShellSizes.minTapTarget + 6,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hovered
                  ? theme.accent.withValues(alpha: 0.18)
                  : theme.surfaceHover,
              border: Border.all(
                color: theme.accent.withValues(alpha: hovered ? 0.9 : 0.4),
              ),
              borderRadius: BorderRadius.circular(ShellRadii.control),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: ShellFontSizes.label,
                color: theme.accent,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      decoration: BoxDecoration(
        color: theme.workspaceBackground.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(ShellRadii.card),
        border: Border.all(color: theme.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.caption,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.bold,
                    color: theme.accent.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.summary,
                  style: TextStyle(
                    fontSize: ShellFontSizes.title,
                    height: 1.25,
                    fontWeight: FontWeight.bold,
                    color: theme.popupForeground,
                  ),
                ),
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.body,
                    // Six lines rather than four: the point of a wider panel
                    // set in a larger type is that the message is readable
                    // here instead of only in the application it came from.
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ShellFontSizes.label,
                      height: 1.45,
                      color: theme.popupForeground.withValues(alpha: 0.85),
                    ),
                  ),
                ],
                if (actionWidgets.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: actionWidgets),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SettingsIconButton(
            icon: FontAwesomeIcons.xmark,
            box: ShellSizes.iconButton,
            size: ShellFontSizes.label,
            color: theme.popupForeground.withValues(alpha: 0.55),
            onTap: () => NotificationStore.instance.dismiss(item.id),
          ),
        ],
      ),
    );
  }
}

final Module notificationsModule = Module.plain(
  configKey: 'notifications',
  builder: (_) => const Notifications(),
);
