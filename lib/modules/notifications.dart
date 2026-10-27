import 'package:flutter/widgets.dart';
import 'package:moonswing/bar_button.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/config_reader.dart';
import 'package:moonswing/docked_panel.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/popup_coordinator.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/notification_badge.dart';
import 'package:moonswing/notification_panel_controller.dart';
import 'package:moonswing/notification_service.dart';
import 'package:moonswing/notification_sound.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_provider.dart';
import 'package:moonswing/theme/tokens.dart';

/// `[modules.notifications]`.
///
/// Two keys are about the chime, two about where the panel docks and the
/// `animation*` set about how it gets there. The panel
/// itself is the root's, the daemon is the shell's, and the silence switch is a
/// `[notifications]` key because it is a decision about the machine rather than
/// about a bar module.
@immutable
class NotificationsConfig {
  const NotificationsConfig({
    this.sound = kDefaultNotificationSound,
    this.soundVolume = kDefaultNotificationSoundVolume,
    this.side = kDefaultNotificationPanelSide,
    this.width = kDefaultNotificationPanelWidth,
    this.animation = const DockedPanelAnimation(),
  });

  /// A shipped voice's slug, a sound-theme name, a path, or `none`.
  /// See `lib/notification_sound.dart`.
  final String sound;

  /// 0 to 1. Clamped rather than trusted: this key is hand-edited, and a
  /// volume of 40 handed to mpv is a different kind of surprise.
  final double soundVolume;

  /// The edge of the output the panel docks against. Right by default.
  final DockSide side;

  /// How wide the panel is, in logical pixels — and so how much of the windows
  /// beneath it the panel covers, since it floats over them.
  final int width;

  /// The `animation*` keys: how the panel flies out of its edge and back.
  final DockedPanelAnimation animation;

  factory NotificationsConfig.fromMap(Map<String, dynamic>? map) {
    const defaults = NotificationsConfig();
    if (map == null) return defaults;
    return NotificationsConfig(
      sound: map.stringOrNull('sound') ?? defaults.sound,
      soundVolume: map.doubleOr('sound_volume', defaults.soundVolume,
          min: 0.0, max: 1.0),
      side: DockSide.parse(
        map.stringOrNull('side'),
        fallback: defaults.side,
      ),
      width: map.intOr(
        'width',
        defaults.width,
        min: kDockedPanelMinWidth,
        max: kDockedPanelMaxWidth,
      ),
      animation: DockedPanelAnimation.fromMap(map),
    );
  }

  /// What the sound layer reads off this.
  NotificationSoundConfig get soundConfig =>
      NotificationSoundConfig(sound: sound, volume: soundVolume);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationsConfig &&
          other.sound == sound &&
          other.soundVolume == soundVolume &&
          other.side == side &&
          other.width == width &&
          other.animation == animation;

  @override
  int get hashCode => Object.hash(sound, soundVolume, side, width, animation);
}

/// Bell icon widget that lives in the bar. Lights up and shakes when
/// notifications arrive, and asks for the notification panel on click.
///
/// It no longer *owns* that panel: the floating badge asks for the same one from
/// a root-owned surface of its own, and two hosts cannot share a
/// `LayerShellHost` window — so both go through [NotificationPanelController].
///
/// It is also what holds the chime's lease. The sound is leased rather than
/// started with the shell for the reason every other shared worker here is: one
/// FlutterView per panel per monitor means two bars would otherwise be two
/// players, chiming a frame apart. Holding it *here* is what ties the sound to
/// the module — a user with no `notifications` module in any panel has asked
/// for no notification furniture, and `[modules.notifications]` is where the
/// key that configures it lives.
class Notifications extends StatefulWidget {
  const Notifications({super.key, this.config = const NotificationsConfig()});

  final NotificationsConfig config;

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

    _prevCount = NotificationStore.instance.unreadCount;
    NotificationStore.instance.addListener(_onStoreChanged);
    // Config first, lease second: the store resolves the configured sound
    // lazily, but seeding it before the listener is attached means the first
    // notification of the session is never the one that discovers a typo.
    NotificationSoundStore.instance.configure(widget.config.soundConfig);
    NotificationSoundStore.instance.acquire();
  }

  @override
  void didUpdateWidget(Notifications oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `Module.loadAll` mutates the module's config in place and
    // `Module.configChanges` is what rebuilds this widget with it, so this is
    // the one place a `[modules.notifications]` edit reaches the player.
    // `configure` is a no-op when nothing moved.
    NotificationSoundStore.instance.configure(widget.config.soundConfig);
  }

  @override
  void dispose() {
    NotificationStore.instance.removeListener(_onStoreChanged);
    NotificationSoundStore.instance.release();
    _shakeController.dispose();
    closePopup();
    super.dispose();
  }

  void _onStoreChanged() {
    final store = NotificationStore.instance;
    final newCount = store.unreadCount;
    // Silenced is about interruption, so the shake is the first thing it takes
    // away: the notification is still collected, and the bell still counts it,
    // but nothing moves in the corner of the user's eye to fetch them.
    //
    // Unread rather than the list's length, so the shake follows the same
    // number the bubble shows: marking everything read and then clearing the
    // list must not read as three more notifications arriving.
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
    // Unread, not the list's length: the bell is one of the three surfaces
    // that *ask* for the user's attention, and the panel's check-all button
    // exists to stop all three asking without emptying the list.
    final count = store.unreadCount;
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
          ShellIcon(
            silenced ? ShellGlyph.bellSlash : ShellGlyph.bell,
            size: 16,
            color: silenced
                ? theme.foreground.withValues(alpha: 0.55)
                : hasUnread
                    ? theme.notificationBadge
                    : theme.foreground,
          ),
          if (hasUnread)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  // The one colour in the shell that is allowed to be louder
                  // than the palette, and the same one the floating card and
                  // the unread dot wear — see `ThemeConfig.notificationBadge`.
                  color: theme.notificationBadge,
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
                    color: theme.notificationBadgeForeground,
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
        onTapDown: (_) => NotificationPanelController.instance.toggle(
          // The connector, so the panel docks against the screen whose bar
          // was clicked; null while outputs are still being enumerated, and
          // the compositor then picks the focused output — where the click
          // just happened.
          output: DisplayScope.of(context)?.name,
        ),
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

/// The notification panel: a column docked against one edge of the output,
/// listing what has arrived. Shaped like the clipboard history and drawn by the
/// same frame (`lib/docked_panel.dart`) — it flies out of its edge, takes no
/// keyboard, floats over the windows rather than moving them, and stays until
/// its close button, the bell or the shortcut takes it down.
///
/// Owned by `_MoonswingRootState` rather than the bell module — both things
/// that ask for it (the bell and the floating badge) ask the root, which is what
/// makes there be exactly one.
///
/// Public, unlike the rest of the panel's parts, because in its one real home it
/// is a layer-shell window no widget test can pump.
class NotificationPanel extends StatefulWidget {
  const NotificationPanel({
    super.key,
    this.side = kDefaultNotificationPanelSide,
    this.animation = const DockedPanelAnimation(),
    this.shadowReach = 0,
    required this.closingNotifier,
    required this.onClosed,
  });

  /// The edge the window is docked against, which the panel arrives from.
  final DockSide side;

  /// How it arrives and leaves, `[modules.notifications] animation*`.
  final DockedPanelAnimation animation;

  /// The window's strip for the panel's shadow — [DockedPanel.shadowReach].
  final int shadowReach;

  /// Flipped by whoever wants the panel gone — the bell, the header's close
  /// button, the shortcut, or a notification opening what it is about.
  /// Flipping it starts the exit; [onClosed] is what tears the window down
  /// once that is over.
  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  @override
  State<NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<NotificationPanel> {
  @override
  void initState() {
    super.initState();
    NotificationStore.instance.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    NotificationStore.instance.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _close() => widget.closingNotifier.value = true;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final store = NotificationStore.instance;
    final items = store.items;

    return DockedPanel(
      side: widget.side,
      animation: widget.animation,
      shadowReach: widget.shadowReach,
      closingNotifier: widget.closingNotifier,
      onClosed: widget.onClosed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme, items.length),
          Container(height: 1, color: theme.divider),
          // Above the list, not inside it: with the daemon down the list is
          // empty, and an empty state reading "all caught up" is a lie the
          // user would act on.
          if (store.daemonUnavailable) ...[
            NotificationDaemonBanner(theme: theme),
            Container(height: 1, color: theme.divider),
          ],
          NotificationSilenceRow(theme: theme),
          Container(height: 1, color: theme.divider),
          Expanded(
            child: items.isEmpty
                ? const DockedPanelEmpty(
                    // A plain bell, not a crossed-out one: on this surface the
                    // crossed bell is the silence switch's glyph, and an empty
                    // inbox is not the same claim as a silenced one.
                    icon: ShellGlyph.bell,
                    title: 'You are all caught up',
                    message: 'Notifications from your applications appear '
                        'here. Click one to open what it is about.',
                  )
                : _buildList(items),
          ),
          // At the foot, out of the way of the list: it is a setting checked
          // now and then, not something read on every opening the way the
          // notifications are.
          Container(height: 1, color: theme.divider),
          NotificationSoundRow(theme: theme),
        ],
      ),
    );
  }

  /// The header: what this panel is, how much is in it, and the ways to act on
  /// all of it.
  ///
  /// The two acts are deliberately not the same weight. Marking everything read
  /// is reversible in the only sense that matters — nothing is removed — so it
  /// is an icon; "Clear all" destroys every item on the list, so it keeps its
  /// border and its word.
  Widget _buildHeader(ThemeConfig theme, int count) {
    final store = NotificationStore.instance;
    final unread = store.unreadCount;
    return DockedPanelHeader(
      title: 'Notifications',
      summary: _countLabel(count, unread),
      onClose: _close,
      actions: [
        if (count > 0)
          DockedPanelTextButton(label: 'Clear all', onTap: store.dismissAll),
        // Only when there is something to mark. A permanently-present button
        // that does nothing on most presses is how a user learns not to trust
        // the pair of them.
        if (unread > 0)
          SettingsIconButton(
            icon: ShellGlyph.checkDouble,
            box: ShellSizes.iconButton + 6,
            size: ShellFontSizes.label,
            color: theme.notificationBadge,
            onTap: store.markAllRead,
          ),
      ],
    );
  }

  /// The line under the title: how much is on the list, and how much of it is
  /// still asking.
  ///
  /// Both numbers, because they answer different questions and the check-all
  /// button makes them come apart: "4 notifications" over a panel the user has
  /// just silenced the count on would read as the button not having worked.
  static String _countLabel(int count, int unread) {
    if (count == 0) return 'Nothing waiting';
    final total = count == 1 ? '1 notification' : '$count notifications';
    if (unread == 0) return '$total, all read';
    if (unread == count) return total;
    return '$total, $unread unread';
  }

  /// The list. Cards are separated by a gap rather than by a hairline, the
  /// clipboard history's spacing: a stack of separate messages, not a table.
  Widget _buildList(List<NotificationItem> items) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _NotificationCard(
        key: ValueKey(items[i].id),
        item: items[i],
        // Out of the way of whatever the notification just opened.
        onActivated: _close,
      ),
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
          color: hovered ? theme.surfaceHover.atMostAlpha(0.16) : null,
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              ShellIcon(
                silenced ? ShellGlyph.bellSlash : ShellGlyph.bell,
                size: ShellFontSizes.label,
                color: silenced
                    ? theme.accentText
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
                        fontSize: ShellFontSizes.body,
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

/// What the shell plays when a notification arrives, and the one control that
/// proves it.
///
/// The panel is where a user looks when they want to know why they were not
/// told about something, so this is where the chime reports itself. It renders
/// three states and they are not variations on one another:
///
/// - **A sound, with a preview.** The speaker button plays it, bypassing the
///   rate limit — a preview a user pressed twice in a second must make a sound
///   both times, or the button is what looks broken.
/// - **A reason.** A path that is not there, or an mpv that would not open it.
///   `[modules.notifications] sound` is named, because the fix is a config key
///   and a row that only says "no sound" does not say where to go.
/// - **Nothing is listening.** No `notifications` module in any panel means
///   nothing holds the chime's lease, so a configured sound will never play.
///   That is a real answer to "why did it not chime", and the only surface that
///   can give it is this one — the panel is reachable from the floating card,
///   which is exactly the shell a user with no bell module has.
///
/// Public, like the rest of the panel's parts, because in its one real home it
/// is inside a layer-shell window no widget test can pump.
class NotificationSoundRow extends StatelessWidget {
  const NotificationSoundRow({super.key, required this.theme});

  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    // Its own subscription, unlike the silence row: the flag that row renders
    // lives on the store the panel already listens to, and this one does not.
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: NotificationSoundStore.instance,
        builder: (context, _) => _build(context),
      ),
    );
  }

  Widget _build(BuildContext context) {
    final sound = NotificationSoundStore.instance;
    final choice = sound.choice;
    final error = sound.error;
    final silent = choice.isSilent;
    final broken = error != null || choice.missing != null;

    final String detail;
    if (broken) {
      detail = error ??
          'No sound called “${choice.missing}” was found. '
              'Set [modules.notifications] sound to one of the shipped '
              'sounds, or to a path.';
    } else if (silent) {
      detail = 'Notifications arrive without a sound. '
          '[modules.notifications] sound turns one on.';
    } else if (!sound.armed) {
      detail = '“${choice.label}” is set, but no notifications '
          'module is in a panel, so nothing plays it.';
    } else {
      detail = choice.label;
    }

    return HoverRegion(
      // The whole row previews, like the silence row toggles from anywhere
      // along it: the button is the discoverable half, not the only half.
      onTap: () => sound.playNow(force: true),
      builder: (context, hovered) => Container(
        color: hovered ? theme.surfaceHover.atMostAlpha(0.16) : null,
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            ShellIcon(
              silent
                  ? ShellGlyph.volumeMuted
                  : ShellGlyph.volumeHigh,
              size: ShellFontSizes.label,
              color: broken
                  ? kErrorColor
                  : silent
                      ? theme.popupForeground.withValues(alpha: 0.45)
                      : theme.notificationBadge,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notification sound',
                    style: TextStyle(
                      fontSize: ShellFontSizes.body,
                      color: theme.popupForeground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: ShellFontSizes.secondary,
                      height: 1.35,
                      color: broken
                          ? kErrorColor
                          : theme.popupForeground.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Offered even while silent: pressing it then is how a user finds
            // out that "none" is what they have, rather than a broken speaker.
            SettingsIconButton(
              icon: ShellGlyph.play,
              box: ShellSizes.iconButton,
              size: ShellFontSizes.secondary,
              color: theme.popupForeground.withValues(alpha: 0.55),
              onTap: () => sound.playNow(force: true),
            ),
          ],
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
            child: ShellIcon(
              ShellGlyph.warning,
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
                    fontSize: ShellFontSizes.body,
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
            fontSize: ShellFontSizes.body,
            color: kErrorColor,
          ),
        ),
      ),
    );
  }
}

/// One notification, as a card — the clipboard history's card: the control
/// surface, a hover tint, a hairline border, and its own repaint boundary.
///
/// An unread card is ringed in the badge colour rather than tinted, where the
/// clipboard rings the entry on the clipboard now in the accent: the body text
/// is the thing the user came to read, and a wash under prose is the one place
/// this palette's loudest colour must not go.
///
/// Clicking the card itself is clicking the notification: it takes the
/// sender's default action, or opens the application it came from — see
/// [NotificationStore.activate]. The X and the action buttons are nested
/// detectors inside it, and the innermost recognizer wins a tap, so pressing
/// either does only what it says.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    super.key,
    required this.item,
    required this.onActivated,
  });

  final NotificationItem item;

  /// Called when a click on the card opened something, so the panel can get
  /// out of its way.
  final VoidCallback onActivated;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // Built outside the hover builder, so a pointer crossing the card moves a
    // decoration rather than re-shaping the summary and body.
    final content = _cardContent(theme);
    // Its own boundary: a hover tints one card, and without this the whole
    // panel would be re-recorded for it.
    return RepaintBoundary(
      child: HoverRegion(
        onTap: () {
          if (NotificationStore.instance.activate(item.id)) onActivated();
        },
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 10),
          decoration: dockedPanelCardDecoration(
            context,
            hovered: hovered,
            ring: item.read
                ? null
                : theme.notificationBadge.withValues(alpha: 0.75),
          ),
          child: content,
        ),
      ),
    );
  }

  Widget _cardContent(ThemeConfig theme) {
    final muted = theme.popupForeground.withValues(alpha: 0.6);
    final actions = <Widget>[
      for (var i = 0; i + 1 < item.actions.length; i += 2)
        if (item.actions[i] != 'default')
          _ActionChip(
            label: item.actions[i + 1],
            onTap: () => NotificationStore.instance.invokeAction(
              item.id,
              item.actions[i],
            ),
          ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The meta row, the clipboard card's: who sent it, and the one button
        // that acts on the card rather than through it.
        SizedBox(
          height: ShellSizes.iconButton,
          child: Row(
            children: [
              if (!item.read) ...[
                // The same dot the rest of the shell means by unread, and the
                // same colour the bell and the floating card wear. It is what
                // survives the card being read over a photograph, where a
                // border alone can vanish.
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: theme.notificationBadge,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Text(
                  item.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.caption,
                    color: muted,
                  ),
                ),
              ),
              SettingsIconButton(
                icon: ShellGlyph.close,
                size: ShellFontSizes.caption,
                color: muted,
                onTap: () => NotificationStore.instance.dismiss(item.id),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.summary,
                style: TextStyle(
                  fontSize: ShellFontSizes.label,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: theme.popupForeground,
                ),
              ),
              if (item.body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.body,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.body,
                    height: 1.3,
                    color: theme.popupForeground.withValues(alpha: 0.85),
                  ),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: actions),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One of a notification's own actions, as a real button.
///
/// The accent's own tint at two strengths, like "Clear all" and every other
/// accent-lettered chip in the shell. The resting fill used to be
/// `surface_hover`, which in the shipped palette is exactly the accent this
/// label is drawn in — the action read as a blank slab until the pointer
/// reached it.
class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, required this.onTap});

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
          color: theme.accent.withValues(alpha: hovered ? 0.22 : 0.1),
          border: Border.all(
            color: theme.accent.withValues(alpha: hovered ? 0.9 : 0.4),
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

final Module notificationsModule = Module.simple<NotificationsConfig>(
  configKey: 'notifications',
  fromMap: (map) {
    final config = NotificationsConfig.fromMap(map);
    // The controller, not the bell, owns where the panel docks: the root reads
    // it when it creates the panel, and the floating badge opens that panel on
    // a shell with no bell in any bar.
    NotificationPanelController.instance.configure(
      side: config.side,
      width: config.width,
      animation: config.animation,
    );
    return config;
  },
  builder: (_, config) => Notifications(config: config),
);
