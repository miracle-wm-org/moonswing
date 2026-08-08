import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:layer_shell/layer_shell.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/theme_provider.dart';

/// Bell icon widget that lives in the bar. Lights up and shakes when
/// notifications arrive, and opens/closes the notification panel on click.
class Notifications extends StatefulWidget {
  const Notifications({super.key});

  @override
  _NotificationsState createState() => _NotificationsState();
}

class _NotificationsState extends State<Notifications>
    with SingleTickerProviderStateMixin, LayerShellHost<Notifications> {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  final ValueNotifier<bool> _closingNotifier = ValueNotifier(false);
  int _prevCount = 0;

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
      // exclusiveZone omitted: no space reservation per requirements.
    );

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
    final count = NotificationStore.instance.items.length;
    final hasUnread = count > 0;
    final isOpen = isLayerWindowOpen;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _togglePanel(context),
        child: Container(
          decoration: BoxDecoration(
            color: isOpen ? const Color(0x28FFFFFF) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              ],
            ),
          ),
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
            child: PopupBounceIn(
              child: Container(
                color: theme.popupBackground,
                child: Column(
                  children: [
                    _buildHeader(theme, items.isNotEmpty),
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

class NotificationsModule extends Module {
  @override
  String get configKey => 'notifications';

  @override
  void loadConfig(Map<String, dynamic>? map) {}

  @override
  WidgetBuilder get builder => (_) => const Notifications();
}
