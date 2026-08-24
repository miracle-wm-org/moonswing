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
        child: _NotificationPanel(
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
    );
  }

  void _beginClosePanel() {
    _closingNotifier.value = true;
    // _NotificationPanel plays its slide-out animation then calls _onPanelClosed.
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

/// Full-height Layer Shell panel anchored to the right side of the screen.
/// Slides in from the right on creation and slides out before being destroyed.
class _NotificationPanel extends StatefulWidget {
  const _NotificationPanel({
    required this.closingNotifier,
    required this.onClosed,
  });

  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  @override
  _NotificationPanelState createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<_NotificationPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));

    _slideController.forward();
    widget.closingNotifier.addListener(_onClosingRequested);
    NotificationStore.instance.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.closingNotifier.removeListener(_onClosingRequested);
    NotificationStore.instance.removeListener(_onStoreChanged);
    _slideController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _onClosingRequested() {
    if (!widget.closingNotifier.value) return;
    _slideController.reverse().then((_) => widget.onClosed());
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final items = NotificationStore.instance.items;

    return Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: theme.fontFamily,
            fontSize: 13,
            color: theme.popupForeground,
          ),
          child: SlideTransition(
            position: _slideAnimation,
            // The slide is the whole entrance: no PopupBounceIn. Its scale
            // pivots on the centre, which on a full-height edge-anchored
            // surface pulls the panel away from the screen edge it is anchored
            // to and shows a gap that closes as it settles — the bounce reads
            // as a floating card, which this deliberately is not.
            //
            // Deliberately not a PopupCard either. This is a full-height
            // surface anchored to the screen's right edge, not a floating
            // card: rounding it would cut wallpaper wedges out of the
            // display's own corners — the case panelCornerRadius refuses for a
            // flush bar — and a rim would draw a line down the screen edge.
            child: Container(
              color: theme.popupBackground,
              child: Column(
                children: [
                  _buildHeader(theme, items.isNotEmpty),
                  Container(height: 1, color: theme.divider),
                  // Above the list, not inside it: with the daemon down the
                  // list is empty, and an empty state reading "No
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
        ));
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
            GestureDetector(
              onTap: () => NotificationStore.instance.dismissAll(),
              child: Text(
                'Clear all',
                style: TextStyle(fontSize: 12, color: theme.accent),
              ),
            ),
            const SizedBox(width: 12),
          ],
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => widget.closingNotifier.value = true,
              child: FaIcon(
                FontAwesomeIcons.xmark,
                size: 14,
                color: theme.popupForeground,
              ),
            ),
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
/// Public, unlike the rest of the panel's parts, because the panel itself is a
/// layer-shell window and cannot be pumped in a widget test — this is the piece
/// with behaviour worth pinning, so `test/notification_daemon_test.dart` builds
/// it directly.
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
      builder: (context, hovered) => GestureDetector(
        onTap: () => store.retryDaemon(),
        child: Container(
          width: 58,
          height: 24,
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
        GestureDetector(
          onTap: () => NotificationStore.instance.invokeAction(item.id, key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.accent.withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: theme.accent),
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
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => NotificationStore.instance.dismiss(item.id),
              child: FaIcon(
                FontAwesomeIcons.xmark,
                size: 12,
                color: theme.popupForeground.withValues(alpha: 0.5),
              ),
            ),
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
