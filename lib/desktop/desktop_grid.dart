import 'package:flutter/widgets.dart';

import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/desktop_actions.dart';
import 'package:graceful_shell/desktop/desktop_icon.dart';
import 'package:graceful_shell/desktop/desktop_layout.dart';
import 'package:graceful_shell/desktop/desktop_store.dart';
import 'package:graceful_shell/scopes.dart';

/// The interactive icon grid drawn over the wallpaper.
///
/// Takes its callbacks as parameters rather than reaching for the popup or
/// keyboard machinery itself, so a widget test can pump it without a
/// `WindowRegistry`, a layer-shell controller, or GIO — the same shape
/// `LauncherOverlay` uses.
class DesktopLayer extends StatefulWidget {
  const DesktopLayer({
    super.key,
    required this.store,
    this.panels = const {},
    this.onItemMenu,
    this.onEmptyMenu,
    this.onOpen,
    this.onGeometry,
    this.onKeyboardRequested,
  });

  final DesktopStore store;

  /// The startup panel set, whose exclusive zones the grid must clear. Panel
  /// geometry is frozen at startup, so this is the startup config, while the
  /// margin it is combined with is read live from the theme.
  final Map<String, PanelConfig> panels;

  /// Right-click on an item, at a surface-local position.
  final void Function(DesktopItem item, Offset position)? onItemMenu;

  /// Right-click on empty space, at a surface-local position, carrying the cell
  /// under the cursor so "add" can drop the new icon where the user clicked.
  final void Function(GridCell cell, Offset position)? onEmptyMenu;

  /// Double-click. Defaults to [openDesktopItem]; injected in tests so nothing
  /// is actually launched.
  final void Function(DesktopItem item)? onOpen;

  /// Reports the resolved grid each layout, so the host can act on the same
  /// geometry the user is looking at (organizing, or placing a new item).
  final void Function(DesktopGridGeometry geometry)? onGeometry;

  /// Asks the host to give this surface keyboard focus, or take it away.
  ///
  /// The background surface is created `keyboardMode: none` — a text field on
  /// it would never see a key event — and only the root owns the controller
  /// that can change that. True exactly while a rename is being edited: a
  /// background-layer surface that held focus permanently would let a stray
  /// desktop click steal it from the focused application.
  final void Function(bool wanted)? onKeyboardRequested;

  @override
  State<DesktopLayer> createState() => DesktopLayerState();
}

class DesktopLayerState extends State<DesktopLayer> {
  /// Resolved desktop entries for `app` items, keyed by target.
  ///
  /// `loadAppByPath` refs what it returns, so these are resolved once per
  /// change of the app-item set and unref'd on the way out — resolving inside
  /// `build` would leak one `GAppInfo` per frame. Same contract as
  /// `DockState._loadApps`.
  Map<String, AppEntry> _resolved = const {};

  /// Themed icon names by target, resolved alongside [_resolved].
  ///
  /// Also GIO, and also not something `build` may do: `iconNameForItem` guesses
  /// the file's content type, which is a syscall-backed lookup, not a field
  /// read.
  Map<String, String> _iconNames = const {};

  /// The targets [_resolved] was built from, so an unrelated notification (a
  /// selection change, a drag) does not re-run the GIO lookups.
  List<String> _resolvedTargets = const [];

  String? _hovered;

  /// Identifies the Stack the icons sit in, so a pointer position can be
  /// converted from global to surface-local coordinates.
  final GlobalKey _surfaceKey = GlobalKey();

  /// Where the dragged icon's centre currently is, surface-local. Held here
  /// rather than in the store because it changes every frame and the store's
  /// mutations are what reach `config.toml`.
  Offset? _dragPosition;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
    _syncResolved();
  }

  @override
  void didUpdateWidget(DesktopLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStoreChanged);
      widget.store.addListener(_onStoreChanged);
    }
    _syncResolved();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    // Hand the keyboard back before going away, or the surface keeps focus
    // with nothing left to type into.
    if (_keyboardRequested) {
      _keyboardRequested = false;
      widget.onKeyboardRequested?.call(false);
    }
    disposeAppEntries(_resolved.values);
    _resolved = const {};
    _iconNames = const {};
    super.dispose();
  }

  /// Whether the host has been asked for keyboard focus, so the request is
  /// sent once per rename rather than on every store notification.
  bool _keyboardRequested = false;

  void _onStoreChanged() {
    if (!mounted) return;
    setState(_syncResolved);
    _syncKeyboard();
  }

  /// Asks for keyboard focus exactly while a rename is in progress.
  ///
  /// Committing the rename, cancelling it, or the item disappearing all end it,
  /// and so does [dispose] — a monitor unplugged mid-rename must not leave its
  /// background surface holding the keyboard.
  void _syncKeyboard() {
    final wanted = widget.store.renamingTarget != null;
    if (wanted == _keyboardRequested) return;
    _keyboardRequested = wanted;
    widget.onKeyboardRequested?.call(wanted);
  }

  /// Re-resolves desktop entries and icon names, but only when the item set
  /// changed — a selection change or a drag must not re-run the GIO lookups.
  ///
  /// Every GIO call here is guarded: `flutter_tester` does not link GLib, and a
  /// throw during a widget test would take the whole grid down. Falling back to
  /// no icon (a font glyph) is the same answer a machine with no icon theme
  /// gets, so the guard is not test-only special-casing.
  void _syncResolved() {
    final items = widget.store.items;
    final targets = [for (final item in items) item.target];
    if (_sameTargets(targets, _resolvedTargets)) return;

    final entries = <String, AppEntry>{};
    final icons = <String, String>{};
    for (final item in items) {
      if (item.kind == DesktopItemKind.app) {
        try {
          final entry = loadAppByPath(item.target);
          if (entry != null) entries[item.target] = entry;
        } catch (_) {
          // No GIO: the tile falls back to its first-letter badge.
        }
      }
      try {
        final name = iconNameForItem(item, resolved: entries[item.target]);
        if (name.isNotEmpty) icons[item.target] = name;
      } catch (_) {
        // As above — an icon we cannot name is drawn as a glyph.
      }
    }

    final previous = _resolved;
    _resolved = entries;
    _iconNames = icons;
    _resolvedTargets = targets;
    // Unref the old pointers only after the new ones are in place, so a rebuild
    // racing this never reads a freed GAppInfo.
    disposeAppEntries(previous.values);
  }

  static bool _sameTargets(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _open(DesktopItem item) {
    final handler = widget.onOpen;
    if (handler != null) {
      handler(item);
      return;
    }
    openDesktopItem(item);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final store = widget.store;
    final config = store.config;

    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = computeGridGeometry(
          constraints.biggest,
          config,
          // The margin comes from the live theme rather than a stored copy, so
          // a theme change that re-floats the bars re-insets the grid on the
          // same frame with no listener of its own.
          insets: panelInsetsFor(widget.panels, theme.panelMargin),
        );
        widget.onGeometry?.call(geometry);

        // Render-only: an item authored on a wider monitor is pulled into
        // range here, and the config keeps its original cell.
        final items = reflowIntoGrid(store.items, geometry);

        return Stack(
          key: _surfaceKey,
          children: [
            // Empty-space handling sits *under* the icons, so an icon's own
            // gestures win without either needing to know about the other.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => store.select(null),
                onSecondaryTapDown: (details) => widget.onEmptyMenu?.call(
                  nearestCell(geometry, details.localPosition),
                  details.localPosition,
                ),
              ),
            ),
            if (store.isDragging)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: DesktopGridLines(
                      geometry: geometry,
                      color: theme.divider,
                    ),
                  ),
                ),
              ),
            for (final item in items)
              _positioned(context, item, geometry, store),
            if (_dragPosition case final position?)
              if (_itemFor(items, store.draggingTarget) case final dragged?)
                _ghost(dragged, position, geometry, store),
          ],
        );
      },
    );
  }

  Widget _positioned(
    BuildContext context,
    DesktopItem item,
    DesktopGridGeometry geometry,
    DesktopStore store,
  ) {
    final rect = geometry.cellRect(item.column, item.row);
    final tile = DesktopIconTile(
      item: item,
      resolved: _resolved[item.target],
      iconName: _iconNames[item.target] ?? '',
      iconSize: store.config.iconSize,
      showLabel: store.config.showLabels,
      selected: store.selectedTarget == item.target,
      hovered: _hovered == item.target,
      missing: !desktopItemExists(item),
    );

    // A tile being renamed is replaced by its editor, not overlaid: the editor
    // must own the pointer, or a click meant for the text field would land on
    // the drag/select gestures behind it.
    if (store.renamingTarget == item.target) {
      return Positioned(
        key: ValueKey('rename:${item.target}'),
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        child: DesktopRenameField(
          item: item,
          resolved: _resolved[item.target],
          iconName: _iconNames[item.target] ?? '',
          iconSize: store.config.iconSize,
          onCommit: (label) => store.commitRename(item.target, label),
          onCancel: store.cancelRename,
        ),
      );
    }

    final dragging = store.draggingTarget == item.target;

    return Positioned(
      key: ValueKey(item.target),
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = item.target),
        onExit: (_) => setState(() {
          if (_hovered == item.target) _hovered = null;
        }),
        // Dragging is done by hand rather than with Draggable, which requires
        // an Overlay ancestor — machinery a layer-shell background surface has
        // no business hosting. The ghost is just another Stack child, and the
        // drop resolves against the same grid geometry the icons are laid out
        // with.
        // Selection is painted from a raw pointer-down, not from a tap.
        // GestureDetector's onTap waits out the double-tap window, and even
        // onTapDown is deferred until the tap recognizer wins the arena
        // against the pan below — either way the highlight would lag the click
        // by a visible fraction of a second. A Listener fires immediately and
        // competes with nothing.
        child: Listener(
          onPointerDown: (_) => store.select(item.target),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => _open(item),
            onSecondaryTapDown: (details) => widget.onItemMenu
                ?.call(item, _toSurface(details.globalPosition)),
            onPanStart: (details) {
              store.beginDrag(item.target);
              setState(
                  () => _dragPosition = _toSurface(details.globalPosition));
            },
            onPanUpdate: (details) => setState(
                () => _dragPosition = _toSurface(details.globalPosition)),
            onPanEnd: (_) => _finishDrag(geometry, store),
            onPanCancel: () {
              setState(() => _dragPosition = null);
              store.endDrag();
            },
            child: Opacity(opacity: dragging ? 0.3 : 1.0, child: tile),
          ),
        ),
      ),
    );
  }

  /// The icon that follows the cursor during a drag, centred under it.
  Widget _ghost(
    DesktopItem item,
    Offset position,
    DesktopGridGeometry geometry,
    DesktopStore store,
  ) {
    final size = geometry.cellSize;
    return Positioned(
      left: position.dx - size.width / 2,
      top: position.dy - size.height / 2,
      width: size.width,
      height: size.height,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.85,
          child: DesktopIconTile(
            item: item,
            resolved: _resolved[item.target],
            iconName: _iconNames[item.target] ?? '',
            iconSize: store.config.iconSize,
            showLabel: store.config.showLabels,
            selected: true,
          ),
        ),
      ),
    );
  }

  DesktopItem? _itemFor(List<DesktopItem> items, String? target) {
    if (target == null) return null;
    for (final item in items) {
      if (item.target == target) return item;
    }
    return null;
  }

  /// Converts a global pointer position into the surface's coordinate space,
  /// which is what the grid math and a popup's anchor rect are both in.
  Offset _toSurface(Offset global) {
    final box = _surfaceKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return global;
    return box.globalToLocal(global);
  }

  void _finishDrag(DesktopGridGeometry geometry, DesktopStore store) {
    final position = _dragPosition;
    final target = store.draggingTarget;
    setState(() => _dragPosition = null);
    store.endDrag();
    if (position == null || target == null) return;
    // The drop lands on whichever cell the ghost's centre is nearest, so what
    // the user sees is what they get; moveTo swaps if that cell is taken.
    store.moveTo(target, nearestCell(geometry, position));
  }
}

/// The cell outlines, painted **only** while a drag is in flight.
///
/// The desktop is a wallpaper the rest of the time; the lines exist to show
/// where an icon will land, and nothing else.
class DesktopGridLines extends CustomPainter {
  const DesktopGridLines({required this.geometry, required this.color});

  final DesktopGridGeometry geometry;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var column = 0; column < geometry.columns; column++) {
      for (var row = 0; row < geometry.rows; row++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            geometry.cellRect(column, row),
            const Radius.circular(6),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(DesktopGridLines oldDelegate) =>
      oldDelegate.geometry != geometry || oldDelegate.color != color;
}
