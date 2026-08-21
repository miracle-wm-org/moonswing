import 'package:flutter/widgets.dart';

import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/config_reader.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/modules/app_directory.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/popup_coordinator.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/theme_provider.dart';

class DockConfig {
  final List<String> apps;
  final int iconSize;

  /// Whether the app-directory button (and its divider) is shown at the end of
  /// the dock.
  final bool showAppDirectory;

  const DockConfig({
    this.apps = const [],
    this.iconSize = 24,
    this.showAppDirectory = true,
  });

  factory DockConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const DockConfig();
    return DockConfig(
      apps: map.stringListOr('apps'),
      iconSize: map.intOr('icon_size', 24),
      showAppDirectory: map.boolOr('show_app_directory', true),
    );
  }
}

// Data model

class _DockApp {
  /// The config id (as stored in `[modules.dock].apps`), used for unpinning.
  final String appId;
  final AppEntry entry;

  const _DockApp({required this.appId, required this.entry});
}

// Reorder geometry / bookkeeping (pure; unit-tested in test/dock_reorder_test.dart)

/// Horizontal gap between dock buttons, and the [Row.spacing] the buttons are
/// laid out with. The slot arithmetic below assumes every icon is the same
/// width, which holds because they all render at `icon_size`.
const double kDockSpacing = 4;

/// Which slot a button whose left edge sits at [left] should drop into, given
/// [count] slots each [step] apart. Slot `i` starts at `i * step`.
int dockDropIndex(double left, double step, int count) {
  if (count <= 1 || step <= 0) return 0;
  final i = (left / step).round();
  return i < 0
      ? 0
      : i > count - 1
          ? count - 1
          : i;
}

/// Moves the element at [from] to [to], shifting the rest along.
List<T> moveDockItem<T>(List<T> items, int from, int to) {
  final out = [...items];
  final item = out.removeAt(from);
  out.insert(to, item);
  return out;
}

/// Rewrites `[modules.dock].apps` for a new on-screen order.
///
/// [configIds] can name apps that failed to resolve (an id whose `.desktop`
/// file is gone), which never appear in the dock and so are absent from
/// [newOrder]. Those keep their original index; the resolved ids fill the
/// slots around them, so a reorder cannot silently drop or move an entry the
/// user cannot see.
List<String> mergeDockOrder(List<String> configIds, List<String> newOrder) {
  final resolved = newOrder.toSet();
  final slots = <String?>[
    for (final id in configIds) resolved.contains(id) ? null : id,
  ];
  if (slots.where((s) => s == null).length != newOrder.length) return newOrder;
  var next = 0;
  for (var i = 0; i < slots.length; i++) {
    if (slots[i] == null) slots[i] = newOrder[next++];
  }
  return slots.cast<String>();
}

// Dock widget

class Dock extends StatefulWidget {
  const Dock({super.key, required this.config});

  final DockConfig config;

  @override
  DockState createState() => DockState();
}

class DockState extends State<Dock> {
  List<_DockApp> _apps = [];

  /// The pinned-apps row, measured to derive the drag slot pitch.
  final _appsKey = GlobalKey();

  // --- Drag-to-reorder state -------------------------------------------------
  //
  // Dragging is hand-rolled for the same reason the desktop grid's is: Flutter's
  // [Draggable] needs an [Overlay] ancestor, and a panel has none. Nothing here
  // reaches [ConfigStore] until the drop — every `set` notifies synchronously
  // and rebuilds every panel on every monitor, so writing pointer positions
  // through the config would rebuild the shell dozens of times per gesture.

  /// Index into [_apps] of the button being dragged, or null when idle. The
  /// list is reordered live as the pointer crosses slot boundaries, so this
  /// follows the button rather than naming its origin.
  int? _dragIndex;

  /// Where the press started, in global coordinates, before the drag threshold
  /// is met.
  double? _pressGlobalX;

  /// Slot pitch (icon width + [kDockSpacing]) and the pointer's grab offset
  /// within the dragged button, both in the apps row's local space.
  double _slotStep = 0;
  double _grabDx = 0;

  /// Current pointer x in the apps row's local space.
  double _pointerX = 0;

  bool get _dragging => _dragIndex != null;

  @override
  void initState() {
    super.initState();
    _loadApps(widget.config);
  }

  @override
  void didUpdateWidget(Dock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A live config edit (e.g. pin/unpin writing to `[modules.dock].apps`)
    // rebuilds this widget with a fresh DockConfig. Reload only when the pinned
    // set actually changed so unrelated edits don't thrash the GIO lookups.
    if (!_sameList(oldWidget.config.apps, widget.config.apps)) {
      _loadApps(widget.config);
    }
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _loadApps(DockConfig config) {
    final apps = <_DockApp>[];
    for (final appId in config.apps) {
      final entry = loadAppById(appId);
      if (entry == null) continue;
      apps.add(_DockApp(appId: appId, entry: entry));
    }
    // Release the previously-resolved GAppInfo pointers before swapping.
    final previous = _apps;
    setState(() {
      _apps = apps;
    });
    disposeAppEntries(previous.map((a) => a.entry));
  }

  @override
  void dispose() {
    disposeAppEntries(_apps.map((a) => a.entry));
    super.dispose();
  }

  void _launch(_DockApp app) => launchApp(app.entry.appInfo);

  // --- Drag to reorder -------------------------------------------------------

  /// Pointer x in the apps row's local space, or null before it has laid out.
  double? _localX(double globalX) {
    final box = _appsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.globalToLocal(Offset(globalX, 0)).dx;
  }

  void _onDragStart(double globalX) {
    _pressGlobalX = globalX;
  }

  /// Returns the dragged button's offset from its slot, in logical pixels.
  double _dragOffset(int index) =>
      (_pointerX - _grabDx) - index * _slotStep;

  void _onDragUpdate(_DockApp app, double globalX) {
    if (_apps.length < 2) return;

    if (!_dragging) {
      final press = _pressGlobalX;
      if (press == null) return;
      // A mouse wins the pan arena after a single pixel, so hold the drag back
      // until the pointer has clearly travelled — a jittery click must still
      // launch the app (see [_DockButton.onDragEnd]).
      if ((globalX - press).abs() < 6) return;
      final box = _appsKey.currentContext?.findRenderObject() as RenderBox?;
      final index = _apps.indexOf(app);
      final local = _localX(globalX);
      if (box == null || index < 0 || local == null) return;
      // Every icon is the same width, so the pitch follows from the row's own
      // width and needs no per-button measurement.
      final n = _apps.length;
      final itemWidth = (box.size.width - kDockSpacing * (n - 1)) / n;
      _slotStep = itemWidth + kDockSpacing;
      _grabDx = local - index * _slotStep;
      setState(() {
        _pointerX = local;
        _dragIndex = index;
      });
      return;
    }

    final local = _localX(globalX);
    if (local == null) return;
    final from = _dragIndex!;
    final to = dockDropIndex(local - _grabDx, _slotStep, _apps.length);
    setState(() {
      _pointerX = local;
      if (to != from) {
        _apps = moveDockItem(_apps, from, to);
        _dragIndex = to;
      }
    });
  }

  /// Ends the gesture. Returns true when it was a drag (so the caller must not
  /// also treat it as a click).
  bool _onDragEnd() {
    _pressGlobalX = null;
    if (!_dragging) return false;
    setState(() => _dragIndex = null);
    _persistOrder();
    return true;
  }

  void _onDragCancel() {
    _pressGlobalX = null;
    if (!_dragging) return;
    setState(() => _dragIndex = null);
    _persistOrder();
  }

  void _persistOrder() {
    final store = ConfigStore.instance;
    final current = store.getList<String>(['modules', 'dock', 'apps']);
    final merged =
        mergeDockOrder(current, _apps.map((a) => a.appId).toList());
    if (_sameList(current, merged)) return;
    store.set(['modules', 'dock', 'apps'], merged);
  }

  @override
  Widget build(BuildContext context) {
    final showDirectory = widget.config.showAppDirectory;
    if (_apps.isEmpty && !showDirectory) return const SizedBox.shrink();

    final size = widget.config.iconSize;
    final foreground = ThemeScope.of(context).foreground;

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: kDockSpacing,
      children: [
        Row(
          key: _appsKey,
          mainAxisSize: MainAxisSize.min,
          spacing: kDockSpacing,
          children: [
            for (var i = 0; i < _apps.length; i++)
              _buildButton(_apps[i], i, size, foreground),
          ],
        ),
        if (showDirectory) ...[
          _DockDivider(height: size.toDouble()),
          AppDirectoryButton(iconSize: size),
        ],
      ],
    );
  }

  Widget _buildButton(_DockApp app, int index, int size, Color foreground) {
    final dragging = index == _dragIndex;
    // Keyed by identity: the list is reordered mid-gesture, and without a key
    // each button's state (hover, pressed, open tooltip) would stay behind at
    // its old position and reattach to a different app.
    final Widget button = _DockButton(
      key: ObjectKey(app),
      appId: app.appId,
      appName: app.entry.name,
      dragging: dragging,
      onPressed: () => _launch(app),
      onDragStart: _onDragStart,
      onDragUpdate: (globalX) => _onDragUpdate(app, globalX),
      onDragEnd: _onDragEnd,
      onDragCancel: _onDragCancel,
      child: AppIconImage(
        iconName: app.entry.iconName,
        name: app.entry.name,
        size: size,
        foreground: foreground,
      ),
    );
    if (!dragging) return button;
    // The dragged button follows the pointer by painting outside its slot;
    // nothing here clips, and its siblings have already shifted into the order
    // the drop will persist.
    return Transform.translate(
      offset: Offset(_dragOffset(index), 0),
      child: button,
    );
  }
}

/// Thin vertical rule separating the pinned apps from the directory button.
class _DockDivider extends StatelessWidget {
  const _DockDivider({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: ThemeScope.of(context).divider,
    );
  }
}

class _DockButton extends StatefulWidget {
  const _DockButton({
    super.key,
    required this.appId,
    required this.appName,
    required this.onPressed,
    required this.dragging,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.child,
  });

  final String appId;
  final String appName;
  final VoidCallback onPressed;

  /// True while this button is the one being dragged.
  final bool dragging;

  final void Function(double globalX) onDragStart;
  final void Function(double globalX) onDragUpdate;

  /// Ends the gesture; true when it resolved as a drag, in which case this
  /// button must not launch its app.
  final bool Function() onDragEnd;
  final VoidCallback onDragCancel;

  final Widget child;

  @override
  State<_DockButton> createState() => _DockButtonState();
}

class _DockButtonState extends State<_DockButton> with PopupHost<_DockButton> {
  bool _hovered = false;
  bool _pressed = false;
  // Which of the two things this host's one popup slot is currently holding.
  // A tooltip follows the pointer out; a context menu must not, or it could
  // never be reached — the menu is its own surface, so travelling towards it
  // reads as leaving the icon.
  bool _menuOpen = false;

  @override
  void dispose() {
    closePopup();
    super.dispose();
  }

  @override
  void closePopup() {
    // Every close path funnels through here, including the ones this module
    // does not drive: the coordinator holds this method as its `onDismiss`,
    // and a compositor destroy routes through PopupDelegate to it as well.
    _menuOpen = false;
    super.closePopup();
  }

  @override
  void didUpdateWidget(_DockButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The pointer is captured for the whole gesture, so no exit event arrives
    // to take the tooltip down with it.
    if (widget.dragging && !oldWidget.dragging) closePopup();
  }

  void _openTooltip(BuildContext context) {
    if (isPopupOpen || widget.dragging) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    openBarPopup(
      context,
      child: ThemeProvider(child: TooltipLabel(text: widget.appName)),
      preferredConstraints: const BoxConstraints(maxWidth: 120, maxHeight: 32),
      // A hover label must not take down the menu the pointer is travelling
      // towards. It is still dismissed by anything else opening, and by a click.
      policy: TransientPolicy.tooltip,
    );
  }

  void _openUnpinMenu(BuildContext context) {
    // Replace any open tooltip with the context menu.
    closePopup();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      openBarPopup(
        context,
        // Loose: the menu sizes to its content (see [ContextMenuCard]).
        preferredConstraints: const BoxConstraints(maxWidth: 260, maxHeight: 200),
        // Its own reopen-guard slot, so a primary click that dismisses the menu
        // does not leave a guard armed under the *tooltip*'s identity and eat
        // the next hover label.
        ownerKey: (this, 'menu'),
        child: ThemeProvider(
          child: PopupBounceIn(
            child: ContextMenuCard(
              items: [
                ContextMenuItem(
                  label: 'Unpin from dock',
                  onTap: () {
                    // Close first: _unpin writes through ConfigStore, which
                    // notifies synchronously and rebuilds the dock without
                    // this button — disposing this State mid-callback.
                    closePopup();
                    _unpin();
                  },
                ),
              ],
            ),
          ),
        ),
      );
      // Only if it really opened — openBarPopup declines a re-open, and a flag
      // set with no popup behind it would strand the *next* tooltip.
      _menuOpen = isPopupOpen;
    });
  }

  void _unpin() {
    final store = ConfigStore.instance;
    final list = store.getList<String>(['modules', 'dock', 'apps']);
    if (!list.contains(widget.appId)) return;
    store.set(
      ['modules', 'dock', 'apps'],
      [...list]..remove(widget.appId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    Color color = const Color(0x00000000);
    if (_pressed) {
      color = theme.surfacePressed;
    } else if (_hovered) {
      color = theme.surfaceHover;
    }

    if (widget.dragging) color = theme.surfacePressed;

    return MouseRegion(
      cursor: widget.dragging
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovered = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _hovered) _openTooltip(context);
        });
      },
      onExit: (_) {
        setState(() {
          _hovered = false;
          _pressed = false;
        });
        // Only the hover label follows the pointer out. The context menu stays
        // until something dismisses it: its own item, a click elsewhere
        // (PopupDismissArea), or another popup opening.
        if (!_menuOpen) closePopup();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _pressed = false),
        onSecondaryTapDown: (_) => _openUnpinMenu(context),
        // Pan and tap share this detector's arena, so exactly one of them wins:
        // a pan that never passed the drag threshold launches from onPanEnd,
        // which is the click a 1px mouse wobble would otherwise have eaten.
        onPanStart: (d) {
          setState(() => _pressed = true);
          widget.onDragStart(d.globalPosition.dx);
        },
        onPanUpdate: (d) => widget.onDragUpdate(d.globalPosition.dx),
        onPanEnd: (_) {
          setState(() => _pressed = false);
          if (!widget.onDragEnd()) widget.onPressed();
        },
        onPanCancel: () {
          setState(() => _pressed = false);
          widget.onDragCancel();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class DockModule extends Module {
  DockConfig _config = const DockConfig();

  @override
  String get configKey => 'dock';

  @override
  void loadConfig(Map<String, dynamic>? map) {
    _config = DockConfig.fromMap(map);
  }

  @override
  WidgetBuilder get builder => (context) => Dock(config: _config);
}
