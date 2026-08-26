import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/bar_button.dart';
import 'package:graceful_shell/config.dart';
import 'package:layer_shell/layer_shell.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/popup_coordinator.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/theme_provider.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// Bell icon widget that lives in the bar. Lights up and shakes when
/// notifications arrive, and opens/closes the notification panel on click.
class Notifications extends StatefulWidget {
  const Notifications({super.key});

  @override
  _NotificationsState createState() => _NotificationsState();
}

class _NotificationsState extends State<Notifications>
    with
        SingleTickerProviderStateMixin,
        LayerShellHost<Notifications>,
        PopupHost<Notifications> {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  final ValueNotifier<bool> _closingNotifier = ValueNotifier(false);
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
    _closingNotifier.dispose();
    closeLayerWindow();
    closePopup();
    super.dispose();
  }

  void _onStoreChanged() {
    final newCount = NotificationStore.instance.items.length;
    if (newCount > _prevCount) {
      _shakeController.forward(from: 0.0);
    }
    _prevCount = newCount;
    if (mounted) setState(() {});
  }

  void _togglePanel(BuildContext context) {
    if (isLayerWindowOpen) {
      _beginClosePanel();
    } else {
      _openPanel(context);
    }
  }

  void _openPanel(BuildContext context) {
    final panelWidth = (getScreenSize().width / 5).round();

    _closingNotifier.value = false;

    final controller = LayershellWindowController(
      layer: LayerShellLayer.overlay,
      anchorEdges: [
        LayerShellEdge.right,
        LayerShellEdge.top,
        LayerShellEdge.bottom,
      ],
      width: panelWidth,
      // height omitted: top+bottom anchoring makes this full-height.
      //
      // On-demand keyboard focus, the settings overlay's mode, is what makes
      // Escape reach the panel at all: a layer surface with no keyboard
      // interactivity never sees a key event, so the panel's own handler
      // would never fire. Not `exclusive` — this is a panel the user glances
      // at, and taking the keyboard off whatever they were typing in for as
      // long as it is open costs more than a dismissal shortcut is worth.
      keyboardMode: LayerShellKeyboardMode.onDemand,
    );
    // The panel spans the whole output edge-to-edge and draws over the bars.
    // Without this the compositor honours their exclusive zones and shrinks
    // the surface to the gap *between* them, so the slide-in would start and
    // end short of the screen edges; `overlay` above then puts it over them
    // rather than under.
    spanFullOutput(controller);

    openLayerWindow(
      context,
      controller: controller,
      // The slide-out, not the teardown — see [_beginClosePanel].
      onDismissRequested: _beginClosePanel,
      child: ThemeProvider(
        child: NotificationPanel(
          closingNotifier: _closingNotifier,
          onClosed: _onPanelClosed,
        ),
      ),
    );
  }

  /// The hover label that explains the exclamation dot.
  ///
  /// The dot says *something* is wrong; this is where it says what, without
  /// making the user open the panel to find out. Only shown while the daemon is
  /// actually unavailable — a working bell has nothing to explain.
  void _openBrokenTooltip(BuildContext context) {
    if (isPopupOpen) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    openBarPopup(
      context,
      child: ThemeProvider(
        child: const TooltipLabel(
          text: 'Notifications are not working — the shell could not claim '
              'the notification service. Click to open the panel and retry.',
        ),
      ),
      preferredConstraints: const BoxConstraints(maxWidth: 260, maxHeight: 96),
      // A hover label must not take down whatever the pointer is travelling
      // towards, and must be dismissed by anything else opening.
      policy: TransientPolicy.tooltip,
      // Its own reopen-guard slot. The panel registers with the coordinator
      // under this same `State`, so a click that dismissed the panel would
      // otherwise leave a guard armed under the tooltip's identity and eat the
      // next hover label.
      ownerKey: (this, 'broken-tooltip'),
      // A floating card, never glued to the bar — see the dock's tooltip.
      attach: false,
    );
  }

  void _beginClosePanel() {
    _closingNotifier.value = true;
    // NotificationPanel plays its exit animation then calls _onPanelClosed.
  }

  void _onPanelClosed() {
    closeLayerWindow();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final store = NotificationStore.instance;
    final count = store.items.length;
    final hasUnread = count > 0;
    final broken = store.daemonUnavailable;
    final isOpen = isLayerWindowOpen;

    final bell = BarButton(
      active: isOpen,
      onTapDown: (_) => _togglePanel(context),
      child: AnimatedBuilder(
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
                FaIcon(
                  FontAwesomeIcons.bell,
                  size: 16,
                  color: hasUnread ? theme.accent : theme.foreground,
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
                        count > 99 ? '99+' : '$count',
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
          ),
    );

    // Only the broken state has a hover label, so the MouseRegion is only worth
    // its callbacks then; a working bell is the plain BarButton it always was.
    if (!broken) return bell;

    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        // Post-frame, the dock's pattern: the label is placed against this
        // element's render box, which the hover itself may still be resizing.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_hovered) return;
          if (!NotificationStore.instance.daemonUnavailable) return;
          _openBrokenTooltip(context);
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
/// A ring in the bar's own colour rather than a bare circle, so the dot reads
/// as punched out of the bell rather than as part of the glyph — the same trick
/// an unread badge plays, and it is what keeps 10 logical pixels legible over
/// an icon at any theme.
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
/// The way out is not the way in played backwards. An entrance is the shell
/// presenting a surface the user has not read yet, so it is paced to be
/// followed; a dismissal is the user saying they are done with it, and every
/// millisecond after that is the shell arguing. `overlayFade` is the token the
/// rest of the shell's overlays leave on.
const Duration kNotificationPanelExit = ShellDurations.overlayFade;

/// Full-height Layer Shell panel anchored to the right side of the screen.
///
/// Slides in from the right on creation; leaves by a *different* animation
/// (see [_NotificationPanelState]) before being destroyed.
///
/// Public, unlike the rest of the panel's parts, because in its one real home
/// it is a layer-shell window no widget test can pump — the animation
/// handshake and the Escape binding are behaviour worth pinning, so
/// `test/notification_panel_test.dart` builds it directly.
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
/// The entrance is the `SlideTransition` it always was — no `PopupBounceIn`,
/// for the reason [build] states. The exit is its own controller rather than
/// that one reversed, which is what lets it be shorter *and* be a different
/// animation: a beat of wind-up, then the panel takes off to the right,
/// shrinking towards and fading into the edge it is anchored to.
///
/// Every part of that exit is pinned to `Alignment.centerRight` or moves the
/// panel further *off* the screen, and that is the constraint the fun has to
/// live inside. This surface is exactly as wide as the panel and butted
/// against the output's right edge, so anything that moves the content left —
/// an overshoot, an anticipation dip, a centre-pivoted scale — opens a
/// transparent strip along the screen edge that reads as the panel having
/// detached from it. Scaling towards the right edge keeps it glued there.
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
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: theme.fontFamily,
            fontSize: 13,
            color: theme.popupForeground,
          ),
          child: SlideTransition(
            position: _enterSlide,
            // The slide is the whole entrance: no PopupBounceIn. Its scale
            // pivots on the centre, which on a full-height edge-anchored
            // surface pulls the panel away from the screen edge it is anchored
            // to and shows a gap that closes as it settles — the bounce reads
            // as a floating card, which this deliberately is not. The exit's
            // scale is the same widget with the pivot moved to the edge, which
            // is the whole difference between a flourish and that gap.
            child: SlideTransition(
              position: _exitSlide,
              child: ScaleTransition(
                scale: _exitScale,
                alignment: Alignment.centerRight,
                child: FadeTransition(
                  opacity: _exitFade,
                  // Deliberately not a PopupCard. This is a full-height
                  // surface anchored to the screen's right edge, not a
                  // floating card: rounding it would cut wallpaper wedges out
                  // of the display's own corners — the case
                  // panelCornerRadius refuses for a flush bar — and a rim
                  // would draw a line down the screen edge.
                  child: Container(
                    color: theme.popupBackground,
                    child: Column(
                      children: [
                        _buildHeader(theme, items.isNotEmpty),
                        Container(height: 1, color: theme.divider),
                        // Above the list, not inside it: with the daemon down
                        // the list is empty, and an empty state reading "No
                        // notifications" is a lie the user would act on.
                        if (NotificationStore.instance.daemonUnavailable) ...[
                          NotificationDaemonBanner(theme: theme),
                          Container(height: 1, color: theme.divider),
                        ],
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

  Widget _buildHeader(ThemeConfig theme, bool hasItems) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            'Notifications',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: theme.popupForeground,
            ),
          ),
          const Spacer(),
          if (hasItems) ...[
            HoverRegion(
              onTap: () => NotificationStore.instance.dismissAll(),
              builder: (context, hovered) => Padding(
                // A label with no box is a target as tall as its glyphs; the
                // padding is what lifts it over `ShellSizes.minTapTarget`.
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Text(
                  'Clear all',
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    color: hovered
                        ? theme.accent
                        : theme.accent.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          SettingsIconButton(
            icon: FontAwesomeIcons.xmark,
            size: ShellFontSizes.label,
            color: theme.popupForeground,
            onTap: () => widget.closingNotifier.value = true,
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeConfig theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(
            FontAwesomeIcons.bellSlash,
            size: 32,
            color: theme.popupForeground.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'No notifications',
            style: TextStyle(
              color: theme.popupForeground.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ThemeConfig theme, List<NotificationItem> items) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => Container(height: 1, color: theme.divider),
      itemBuilder: (context, i) =>
          _NotificationCard(item: items[i], theme: theme),
    );
  }
}

/// Why the panel is empty, and the one control that can change it.
///
/// Shown whenever the shell does not own `org.freedesktop.Notifications` —
/// another daemon claimed it first, or the request errored. Both are recoverable
/// without restarting the shell (the other daemon can be stopped, the bus can
/// come back), which is what the Retry button is for; the shell cannot detect
/// either happening, so the user has to say when.
///
/// Rebuilt by `_NotificationPanelState`'s store listener, so both the reason
/// text and the in-flight state of the button follow the store with no
/// listener of its own.
///
/// Public, like [NotificationPanel] itself and unlike the rest of the panel's
/// parts, because in its one real home it is inside a layer-shell window no
/// widget test can pump — this is the piece with behaviour worth pinning, so
/// `test/notification_daemon_test.dart` builds it directly.
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
                    fontSize: ShellFontSizes.secondary,
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
/// still looks pressable but does nothing reads as the retry having failed
/// instantly.
class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.theme});

  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    final store = NotificationStore.instance;
    if (store.daemonRetrying) {
      return const SizedBox(
        width: 58,
        height: 24,
        child: Center(child: LoadingIndicator(size: 14, color: kErrorColor)),
      );
    }

    return HoverRegion(
      onTap: () => store.retryDaemon(),
      builder: (context, hovered) => Container(
        width: 58,
        height: ShellSizes.minTapTarget,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? kErrorColor.withValues(alpha: 0.18) : null,
          border: Border.all(color: kErrorColor.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(ShellRadii.control),
        ),
        child: const Text(
          'Retry',
          style: TextStyle(
            fontSize: ShellFontSizes.secondary,
            color: kErrorColor,
          ),
        ),
      ),
    );
  }
}

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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: hovered ? theme.surfaceHover : null,
              border: Border.all(
                color: theme.accent.withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(ShellRadii.barButton),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                color: theme.accent,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.appName,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.popupForeground.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.summary,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: theme.popupForeground,
                  ),
                ),
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.body,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.popupForeground.withValues(alpha: 0.85),
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (actionWidgets.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 4, children: actionWidgets),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SettingsIconButton(
            icon: FontAwesomeIcons.xmark,
            size: ShellFontSizes.secondary,
            color: theme.popupForeground.withValues(alpha: 0.5),
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
