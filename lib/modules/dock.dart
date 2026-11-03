// `widgets.dart` re-exports foundation with a `show` list that carries
// ValueNotifier but not ValueListenable, which is what a dock slot takes.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:moonswing/bar_button.dart';
import 'package:moonswing/app_info.dart';
import 'package:moonswing/desktop/desktop_menu.dart';
import 'package:moonswing/config_reader.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/context_menus.dart' show ModuleMenuScope;
import 'package:moonswing/modules/app_directory.dart';
import 'package:moonswing/modules/dock_launch.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/theme/popup_effect.dart';
import 'package:moonswing/popup_coordinator.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_provider.dart';
import 'package:moonswing/theme/tokens.dart';

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

/// Gap between dock buttons along the bar, and the spacing the buttons are laid
/// out with. The slot arithmetic below assumes every icon is the same length
/// along the bar, which holds because they all render at `icon_size`.
const double kDockSpacing = 4;

/// The offset handed to every dock button that is *not* being dragged.
///
/// Shared, and it never notifies. A slot listens for its translation whether or
/// not a drag is in flight, because a slot whose shape changed when the drag
/// began would take the drag down with it — see [DockState._buildButton].
final ValueListenable<double> kNoDragOffset = ValueNotifier<double>(0);

/// Which slot a button whose leading edge sits at [left] should drop into,
/// given [count] slots each [step] apart. Slot `i` starts at `i * step`.
///
/// One axis, whichever way the bar runs: on a side bar "left" is the top.
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
/// [configIds] can name apps that failed to resolve (an id whose `.desktop` file
/// is gone), which never appear in the dock and so are absent from [newOrder].
/// Those keep their original index; the resolved ids fill the slots around them,
/// so a reorder cannot silently drop or move an entry the user cannot see.
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
  // Dragging is hand-rolled for the desktop grid's reason: Flutter's [Draggable]
  // needs an [Overlay] ancestor and a panel has none. Nothing here reaches
  // [ConfigStore] until the drop — every `set` notifies synchronously and
  // rebuilds every panel on every monitor.

  /// Index into [_apps] of the button being dragged, or null when idle. The
  /// list is reordered live as the pointer crosses slot boundaries, so this
  /// follows the button rather than naming its origin.
  int? _dragIndex;

  /// Where the press started along the bar, in global coordinates, before the
  /// drag threshold is met.
  double? _pressAlong;

  /// Slot pitch (icon length + [kDockSpacing]) and the pointer's grab offset
  /// within the dragged button, both in the apps strip's local space.
  double _slotStep = 0;
  double _grabAlong = 0;

  /// The pointer's current position along the bar, in the apps strip's local
  /// space.
  double _pointerAlong = 0;

  /// Whether the bar runs down a side of the screen, so the strip — and every
  /// coordinate above — runs down it too. Read in [build]; a bar's anchor is
  /// fixed for its window's life, so a gesture never straddles a change.
  bool _vertical = false;

  /// [global]'s component along the bar.
  double _along(Offset global) => _vertical ? global.dy : global.dx;

  /// The dragged button's offset from its slot, in logical pixels, published on
  /// its own notifier rather than through `setState`. A pointer move only ever
  /// moves one button, and a panel has no repaint boundary of its own, so
  /// rebuilding the row per move would re-resolve every icon and re-record the
  /// whole bar. Reordering still goes through `setState`, but that happens once
  /// per slot crossing rather than once per pointer event.
  final ValueNotifier<double> _dragOffset = ValueNotifier<double>(0);

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
      // Any gesture in flight indexes into the list being replaced, and the
      // buttons it was tracking are about to be torn down, so no end or cancel
      // is coming. Drop it here or the dock is left in a drag that can never be
      // released — which would go on eating clicks (see [_onDragEnd]).
      _dragIndex = null;
      _pressAlong = null;
    });
    disposeAppEntries(previous.map((a) => a.entry));
  }

  @override
  void dispose() {
    _dragOffset.dispose();
    disposeAppEntries(_apps.map((a) => a.entry));
    super.dispose();
  }

  /// Opens [app] through the machine's one [DockLaunchStore], which declines
  /// while that application is already starting.
  void _launch(_DockApp app) => DockLaunchStore.instance.launch(app.entry);

  // --- Drag to reorder -------------------------------------------------------

  /// The pointer's position along the bar in the apps strip's local space, or
  /// null before it has laid out.
  double? _localAlong(Offset global) {
    final box = _appsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return _along(box.globalToLocal(global));
  }

  void _onDragStart(Offset global) {
    _pressAlong = _along(global);
  }

  /// Republishes [_dragOffset]. Called for every pointer move, and again after
  /// a reorder — the slot the offset is measured against has moved under the
  /// button, so the two changes have to land together or the icon would jump a
  /// whole slot at each crossing.
  void _publishDragOffset() {
    final index = _dragIndex;
    _dragOffset.value =
        index == null ? 0 : (_pointerAlong - _grabAlong) - index * _slotStep;
  }

  void _onDragUpdate(_DockApp app, Offset global) {
    if (_apps.length < 2) return;

    if (!_dragging) {
      final press = _pressAlong;
      if (press == null) return;
      // A mouse wins the pan arena after a single pixel, so hold the drag back
      // until the pointer has clearly travelled — a jittery click must still
      // count towards the double click that opens the app (see
      // [_DockButton.onDragEnd]).
      if ((_along(global) - press).abs() < 6) return;
      final box = _appsKey.currentContext?.findRenderObject() as RenderBox?;
      final index = _apps.indexOf(app);
      final local = _localAlong(global);
      if (box == null || index < 0 || local == null) return;
      // Every icon is the same length, so the pitch follows from the strip's
      // own length and needs no per-button measurement.
      final n = _apps.length;
      final length = _vertical ? box.size.height : box.size.width;
      final itemLength = (length - kDockSpacing * (n - 1)) / n;
      _slotStep = itemLength + kDockSpacing;
      _grabAlong = local - index * _slotStep;
      _pointerAlong = local;
      setState(() => _dragIndex = index);
      _publishDragOffset();
      return;
    }

    final local = _localAlong(global);
    if (local == null) return;
    _pointerAlong = local;
    final from = _dragIndex!;
    final to = dockDropIndex(local - _grabAlong, _slotStep, _apps.length);
    if (to != from) {
      setState(() {
        _apps = moveDockItem(_apps, from, to);
        _dragIndex = to;
      });
    }
    _publishDragOffset();
  }

  /// Ends the gesture. Returns true when it was a drag (so the caller must not
  /// also treat it as a click).
  bool _onDragEnd() {
    _pressAlong = null;
    if (!_dragging) return false;
    setState(() => _dragIndex = null);
    _publishDragOffset();
    _persistOrder();
    return true;
  }

  void _onDragCancel() {
    _pressAlong = null;
    if (!_dragging) return;
    setState(() => _dragIndex = null);
    _publishDragOffset();
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
    _vertical = BarScope.isVerticalOf(context);

    // Down the bar on a side bar, and the drag with it.
    return BarFlex(
      spacing: kDockSpacing,
      children: [
        BarFlex(
          key: _appsKey,
          spacing: kDockSpacing,
          children: [
            for (var i = 0; i < _apps.length; i++)
              _buildButton(_apps[i], i, size, foreground),
          ],
        ),
        if (showDirectory) ...[
          BarDivider(
            length: size.toDouble(),
            color: ThemeScope.of(context).divider,
          ),
          AppDirectoryButton(iconSize: size),
        ],
      ],
    );
  }

  Widget _buildButton(_DockApp app, int index, int size, Color foreground) {
    final dragging = index == _dragIndex;
    // Two rules, and the drag depends on both.
    //
    // Keyed by identity, because the list is reordered mid-gesture: without a
    // key each button's state (hover, pressed, open tooltip) would stay behind
    // at its old position and reattach to a different app.
    //
    // And the key sits on the *outermost* widget of the slot, whose type never
    // depends on `dragging`. A [Row] matches its children by (runtimeType,
    // key), so wrapping the dragged button in a translation the resting ones do
    // not have makes that slot a different, unkeyed widget the instant the drag
    // begins — Flutter deactivates the button's element and inflates a fresh
    // one, disposing the very pan recognizer driving the drag. Its pointer
    // route is dropped without an end or a cancel, so the gesture dies at its
    // first pixel with the dock still stuck in the dragging state; the next
    // press then resumes that stale drag, and its first reorder swaps the
    // wrapper around again and kills it too. Hence: same shape at rest and in
    // flight, and only [DockSlot.offset] tells them apart.
    return DockSlot(
      key: ObjectKey(app),
      offset: dragging ? _dragOffset : kNoDragOffset,
      axis: _vertical ? Axis.vertical : Axis.horizontal,
      child: _buildButtonContent(app, dragging, size, foreground),
    );
  }

  Widget _buildButtonContent(
    _DockApp app,
    bool dragging,
    int size,
    Color foreground,
  ) {
    return _DockButton(
      appId: app.appId,
      appName: app.entry.name,
      dragging: dragging,
      launching: DockLaunchStore.instance.launchingOf(app.entry.id),
      onOpen: () => _launch(app),
      onDragStart: _onDragStart,
      onDragUpdate: (global) => _onDragUpdate(app, global),
      onDragEnd: _onDragEnd,
      onDragCancel: _onDragCancel,
      child: AppIconImage(
        iconName: app.entry.iconName,
        name: app.entry.name,
        size: size,
        foreground: foreground,
      ),
    );
  }
}

/// One dock button's slot: a fixed-shape wrapper that translates its child by
/// [offset].
///
/// The dragged button follows the pointer by painting outside its slot — nothing
/// here clips, and its siblings have already shifted into the order the drop
/// will persist. Whether a slot is the dragged one is carried entirely by which
/// listenable it is given, never by its shape; [DockState._buildButton] explains
/// why that matters.
///
/// The two repaint boundaries are the pair the shell's repaint discipline calls
/// for around an animating layer: the inner one gives the translation a
/// composited layer to move rather than a picture to re-record, and the outer
/// one keeps the dirtied [Transform] from re-recording the whole panel around
/// it — a panel has no repaint boundary of its own. They earn their keep at rest
/// too, where they contain each button's hover tint.
class DockSlot extends StatelessWidget {
  const DockSlot({
    super.key,
    required this.offset,
    this.axis = Axis.horizontal,
    required this.child,
  });

  /// This slot's translation along [axis]. [kNoDragOffset] for a resting
  /// button.
  final ValueListenable<double> offset;

  /// The way the bar runs, and so the way a dragged button moves.
  final Axis axis;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: offset,
        builder: (context, d, child) => Transform.translate(
          offset: axis == Axis.vertical ? Offset(0, d) : Offset(d, 0),
          child: child,
        ),
        // Handed through unrebuilt: a pointer move re-runs one [Transform] and
        // touches nothing else in the dock.
        child: RepaintBoundary(child: child),
      ),
    );
  }
}

class _DockButton extends StatefulWidget {
  const _DockButton({
    required this.appId,
    required this.appName,
    required this.onOpen,
    required this.dragging,
    required this.launching,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.child,
  });

  final String appId;
  final String appName;

  /// Opens the application. Called on a double click, never a single one.
  final VoidCallback onOpen;

  /// Whether the application is starting; the icon spins while it is.
  final ValueListenable<bool> launching;

  /// True while this button is the one being dragged.
  final bool dragging;

  /// Handed the pointer's global position; the dock takes the component that
  /// runs along the bar.
  final void Function(Offset global) onDragStart;
  final void Function(Offset global) onDragUpdate;

  /// Ends the gesture; true when it resolved as a drag, in which case this
  /// button must not count it as a click.
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

  /// A dock icon opens on a double click. Both of the button's click paths —
  /// a tap, and a pan that never passed the drag threshold — report here.
  final DockDoubleClick _clicks = DockDoubleClick();

  void _onClick() {
    if (_clicks.click()) widget.onOpen();
  }

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
    if (widget.dragging && !oldWidget.dragging) {
      closePopup();
      // A drag is not the first half of a double click: the click that ends
      // it must not open the app.
      _clicks.reset();
    }
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
      // Edge-anchored like every bar popup, but never glued to the bar: a label
      // that comes and goes with the pointer is a floating card, not furniture.
      attach: false,
      // And never animated, whatever `popup_animation` says. The dock is a strip
      // the pointer sweeps along, opening and abandoning a surface at every button
      // on the way past; a card that slid or scaled at each would read as the
      // shell twitching rather than answering.
      effect: PopupEffect.none,
    );
  }

  void _openUnpinMenu(BuildContext context) {
    // Replace any open tooltip with the context menu.
    closePopup();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      openBarPopup(
        context,
        // Loose: the menu sizes to its content (see [DesktopMenuCard]).
        // Tall enough for the dock's own rows under the unpin row.
        preferredConstraints: const BoxConstraints(maxWidth: 320, maxHeight: 420),
        // Its own reopen-guard slot, so a primary click that dismisses the menu
        // does not leave a guard armed under the *tooltip*'s identity and eat
        // the next hover label.
        ownerKey: (this, 'menu'),
        // As the tooltip, and for its reason: neither of the dock's surfaces
        // animates.
        effect: PopupEffect.none,
        child: ThemeProvider(
          child: DesktopMenuCard(
            entries: [
              DesktopMenuEntry(
                label: 'Unpin from dock',
                onTap: () {
                  // Close first: _unpin writes through ConfigStore, which
                  // notifies synchronously and rebuilds the dock without
                  // this button — disposing this State mid-callback.
                  closePopup();
                  _unpin();
                },
              ),
              // The dock's own menu — quick settings, settings links — since
              // this one answers the right-click that would have opened it.
              ...ModuleMenuScope.itemsFor(context, close: closePopup),
            ],
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
        // A double click is two clicks on one icon; leaving it starts over.
        _clicks.reset();
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
          _onClick();
        },
        onTapCancel: () => setState(() => _pressed = false),
        onSecondaryTapDown: (_) => _openUnpinMenu(context),
        // Pan and tap share this detector's arena, so exactly one of them wins:
        // a pan that never passed the drag threshold is a click from onPanEnd,
        // which is the click a 1px mouse wobble would otherwise have eaten —
        // and why the double click is counted by hand rather than by an
        // `onDoubleTap`, which the pan would win against.
        onPanStart: (d) {
          setState(() => _pressed = true);
          widget.onDragStart(d.globalPosition);
        },
        onPanUpdate: (d) => widget.onDragUpdate(d.globalPosition),
        onPanEnd: (_) {
          setState(() => _pressed = false);
          if (!widget.onDragEnd()) _onClick();
        },
        onPanCancel: () {
          setState(() => _pressed = false);
          widget.onDragCancel();
        },
        child: AnimatedContainer(
          duration: ShellDurations.fast,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: BarFill(
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.launching,
              // The icon is handed through unrebuilt: a launch starting or
              // ending dims it and adds or drops the spinner, nothing more.
              child: widget.child,
              builder: (context, launching, icon) =>
                  DockLaunchIndicator(launching: launching, child: icon!),
            ),
          ),
        ),
      ),
    );
  }
}

final Module dockModule = Module.simple(
  configKey: 'dock',
  fromMap: DockConfig.fromMap,
  builder: (context, config) => Dock(config: config),
);
