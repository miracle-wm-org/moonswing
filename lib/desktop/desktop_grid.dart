import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/widgets.dart';

import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/desktop_actions.dart';
import 'package:graceful_shell/desktop/desktop_icon.dart';
import 'package:graceful_shell/desktop/desktop_layout.dart';
import 'package:graceful_shell/desktop/desktop_store.dart';
import 'package:graceful_shell/desktop/widgets/desktop_widget.dart';
import 'package:graceful_shell/desktop/widgets/desktop_widget_frame.dart';
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
    this.onWidgetMenu,
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

  /// Right-click on a widget, at a surface-local position.
  final void Function(DesktopWidgetItem widget, Offset position)?
      onWidgetMenu;

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

  /// Everything moving with the drag: the pressed icon, plus the rest of the
  /// selection when it was pressed as a member of one. Local for [_dragPosition]'s
  /// reason — it is derived from the selection at press time and never persisted.
  Set<String> _dragGroup = const {};

  /// The id of the widget the pointer is over, so its rim and its resize grips
  /// are drawn for it alone.
  String? _hoveredWidget;

  /// How far the widget under a drag has been pulled from its laid-out
  /// position. Per-frame and never persisted, [_dragPosition]'s rule.
  Offset? _widgetDragDelta;

  /// The resize in flight: which widget, which corner, and the area the widget
  /// started at. The preview area is [_resizeArea]; the commit happens once, on
  /// release.
  ({String id, DesktopWidgetCorner corner, GridArea start})? _resize;
  GridArea? _resizeArea;

  /// Where the rubber band was anchored — the position the button went down
  /// at — while one is being drawn. Local, and never persisted.
  Offset? _bandAnchor;

  /// The band's current rect, surface-local, or null when none is being drawn.
  ///
  /// **A notifier rather than a `setState` field, and that is the whole reason
  /// the band is smooth.** A pointer move arrives every frame at least, and a
  /// `setState` here rebuilt the entire desktop: two grid reflows, every icon
  /// tile, and every widget card — a weather sky and a Moon among them — to
  /// move one translucent rect. It is now a `ValueListenableBuilder` over this,
  /// under its own `RepaintBoundary`, so a band move relayouts and repaints
  /// the band alone and nothing else on the surface hears about it. The
  /// selection it drives still goes through the store, which no-ops when the
  /// set is unchanged, so a full rebuild happens only when the band actually
  /// crosses an icon.
  final ValueNotifier<Rect?> _band = ValueNotifier<Rect?>(null);

  /// Targets whose file or folder is gone, so the tile can say so.
  ///
  /// Cached rather than re-checked in `build`: `desktopItemExists` is an
  /// `existsSync`, so asking per icon per build meant a stat syscall per icon
  /// per *frame* for as long as any gesture was in flight. Refreshed when the
  /// item set changes and on any store notification between gestures — which
  /// is no less often than an idle desktop rebuilt before, since an idle
  /// desktop does not rebuild at all.
  Set<String> _missing = const {};

  /// True while a pointer gesture is driving per-frame rebuilds, which is when
  /// the shell must not be doing filesystem work.
  bool get _gestureInFlight =>
      _band.value != null ||
      _dragPosition != null ||
      _widgetDragDelta != null ||
      _resize != null;

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
    _band.dispose();
    super.dispose();
  }

  /// Whether the host has been asked for keyboard focus, so the request is
  /// sent once per rename rather than on every store notification.
  bool _keyboardRequested = false;

  void _onStoreChanged() {
    if (!mounted) return;
    setState(() {
      _syncResolved();
      // Only between gestures: a drag notifies this store on every crossing
      // and re-stat'ing every icon on the way past is exactly the work the
      // cache exists to avoid.
      if (!_gestureInFlight) _refreshMissing();
    });
    _syncKeyboard();
  }

  /// Re-checks which targets are gone. See [_missing].
  void _refreshMissing() {
    final next = <String>{};
    for (final item in widget.store.items) {
      try {
        if (!desktopItemExists(item)) next.add(item.target);
      } catch (_) {
        // An unreadable path is not a missing one; leave the tile alone.
      }
    }
    // Compared rather than assigned outright so an unchanged answer keeps the
    // same set, which is one fewer thing for a rebuild to look at.
    if (next.length == _missing.length && next.every(_missing.contains)) return;
    _missing = next;
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
    _refreshMissing();
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
        // range here, and the config keeps its original cell. Widgets reflow
        // first, because where they end up is what the icons have to avoid.
        final widgets = reflowWidgetsIntoGrid(store.widgets, geometry);
        final items = reflowIntoGrid(
          store.items,
          geometry,
          blocked: widgetCells(widgets),
        );

        return Stack(
          key: _surfaceKey,
          children: [
            // Empty-space handling sits *under* the icons, so an icon's own
            // gestures win without either needing to know about the other.
            // `RenderStack` stops at the first child that accepts and the tiles
            // are `HitTestBehavior.opaque`, so a drag that begins on an icon
            // never reaches this detector — which is what lets the rubber band
            // share it with the icon drag and need no coordination between them.
            //
            // This detector fills the Stack, so `localPosition` is already the
            // surface-local space the grid math works in.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // The band is anchored where the button went down, not where
                // the pan slop was crossed: with the default `.start` the
                // pending slop delta is folded into the reported start
                // position, so the corner would jump away from the press.
                dragStartBehavior: DragStartBehavior.down,
                onTap: () => store.select(null),
                onSecondaryTapDown: (details) => widget.onEmptyMenu?.call(
                  nearestCell(geometry, details.localPosition),
                  details.localPosition,
                ),
                // The band replaces the selection rather than extending it, and
                // there is no threshold to tune: the pan recognizer withholds
                // `onPanStart` until the touch slop is exceeded, so a plain
                // click still resolves as `onTap` and still clears. It is also
                // primary-button only by default, so the empty-space menu above
                // is untouched.
                onPanStart: (details) {
                  _bandAnchor = details.localPosition;
                  // fromPoints normalizes, so a band drawn up and to the left
                  // is the same rect as one drawn down and to the right.
                  _band.value = Rect.fromPoints(
                    details.localPosition,
                    details.localPosition,
                  );
                  store.selectAll(const <String>[]);
                },
                onPanUpdate: (details) {
                  final anchor = _bandAnchor;
                  if (anchor == null) return;
                  final band = Rect.fromPoints(anchor, details.localPosition);
                  _band.value = band;
                  // Against the reflowed list, so the band selects what is on
                  // screen. `selectAll` no-ops when the set is unchanged, so a
                  // move that crosses no new icon notifies nothing.
                  store.selectAll(targetsInRect(items, geometry, band));
                },
                onPanEnd: (_) => _endBand(),
                onPanCancel: _endBand,
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
            // Under the icons: the two never share a cell, so this only
            // decides what wins if a hand-edited config puts them on top of
            // each other — and an icon that has vanished behind a widget is
            // less recoverable than the other way round.
            for (final widget in widgets)
              _positionedWidget(context, widget, geometry, store),
            for (final item in items)
              _positioned(context, item, geometry, store),
            if (_dragPosition case final position?)
              ..._ghosts(items, position, geometry, store),
            // Where a dragged widget will land. The card itself follows the
            // pointer freely, so without this the drop point is a guess.
            if (_widgetDropArea(widgets, geometry, store) case final area?)
              DesktopWidgetPreview(
                rect: geometry.areaRect(area),
                color: theme.accent,
              ),
            // Over the icons, so the band is never hidden behind the thing it
            // is selecting — and in its own repaint-bounded subtree, so a band
            // move costs one relayout of one rect rather than a rebuild of
            // everything under it. See [_band].
            Positioned.fill(
              child: RepaintBoundary(
                child: ValueListenableBuilder<Rect?>(
                  valueListenable: _band,
                  builder: (context, band, _) => band == null
                      // Not `IgnorePointer` over the whole surface: a bare
                      // SizedBox accepts no hit of its own, so the detector
                      // underneath still sees every press.
                      ? const SizedBox.expand()
                      : Stack(
                          children: [
                            DesktopSelectionBand(
                              rect: band,
                              color: theme.accent,
                            ),
                          ],
                        ),
                ),
              ),
            ),
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
      selected: store.isSelected(item.target),
      hovered: _hovered == item.target,
      missing: _missing.contains(item.target),
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

    final dragging = _dragGroup.contains(item.target);

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
        //
        // Pressing an icon that is *already* selected leaves the selection
        // alone, so pressing a member of a band selection to drag the group
        // does not discard the group first. Narrowing back to one happens on
        // the completed tap below, which only pays the double-tap delay in the
        // multi-selection case.
        child: Listener(
          onPointerDown: (_) {
            if (!store.isSelected(item.target)) store.select(item.target);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (store.selectedTargets.length > 1) store.select(item.target);
            },
            onDoubleTap: () => _open(item),
            onSecondaryTapDown: (details) => widget.onItemMenu
                ?.call(item, _toSurface(details.globalPosition)),
            onPanStart: (details) {
              store.beginDrag(item.target);
              setState(() {
                // The group is frozen at press time: the whole selection when
                // this icon is one of several selected, else just this icon.
                _dragGroup = store.isSelected(item.target)
                    ? Set<String>.of(store.selectedTargets)
                    : {item.target};
                _dragPosition = _toSurface(details.globalPosition);
              });
            },
            onPanUpdate: (details) => setState(
                () => _dragPosition = _toSurface(details.globalPosition)),
            onPanEnd: (_) => _finishDrag(item, geometry, store),
            onPanCancel: () {
              setState(() {
                _dragPosition = null;
                _dragGroup = const {};
              });
              store.endDrag();
            },
            child: Opacity(opacity: dragging ? 0.3 : 1.0, child: tile),
          ),
        ),
      ),
    );
  }


  // ---------------------------------------------------------------------------
  // Widgets
  // ---------------------------------------------------------------------------

  /// One widget: its card, the chrome saying it is under the pointer, the drag
  /// that moves it, and the four grips that resize it.
  ///
  /// The card is dragged *itself* rather than by a ghost, unlike an icon: an
  /// icon's ghost exists because a group of them moves together and each needs
  /// one, while a widget moves alone and a translucent copy of a media player
  /// beside the real one would just be two media players.
  Widget _positionedWidget(
    BuildContext context,
    DesktopWidgetItem item,
    DesktopGridGeometry geometry,
    DesktopStore store,
  ) {
    final theme = ThemeScope.of(context);
    final spec = DesktopWidgetRegistry.lookup(item.type);
    final laidOut = renderAreaFor(spec, item);

    final resizing = _resize?.id == item.id;
    final dragging = store.draggingWidget == item.id;
    // While resizing, the card *is* the preview: it snaps cell by cell, so
    // there is nothing an outline could say that the card does not.
    final area = resizing ? (_resizeArea ?? laidOut) : laidOut;
    var rect = geometry.areaRect(area);
    if (dragging && _widgetDragDelta != null) {
      rect = rect.shift(_widgetDragDelta!);
    }

    final hovered = _hoveredWidget == item.id;
    final selected = store.selectedWidget == item.id;
    final showGrips = hovered || selected || resizing || dragging;

    return Positioned.fromRect(
      key: ValueKey('widget:${item.id}'),
      rect: rect,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredWidget = item.id),
        onExit: (_) => setState(() {
          if (_hoveredWidget == item.id) _hoveredWidget = null;
        }),
        child: Stack(
          // The grips sit on the card's corners and lap over its rim.
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              // A Listener rather than a tap, for the reason the icons'
              // documents: a tap recognizer here would have to win an arena
              // against the pan below it before the rim could light up.
              child: Listener(
                onPointerDown: (_) => store.selectWidget(item.id),
                child: GestureDetector(
                  // Opaque so a drag can start anywhere on the card — the
                  // widget's own buttons are deeper in the tree and are hit
                  // first, and a quick press on one resolves as their tap
                  // rather than as this pan.
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onSecondaryTapDown: (details) => widget.onWidgetMenu
                      ?.call(item, _toSurface(details.globalPosition)),
                  onPanStart: (_) {
                    store.beginWidgetDrag(item.id);
                    setState(() => _widgetDragDelta = Offset.zero);
                  },
                  onPanUpdate: (details) => setState(() =>
                      _widgetDragDelta =
                          (_widgetDragDelta ?? Offset.zero) + details.delta),
                  onPanEnd: (_) => _finishWidgetDrag(item, geometry, store),
                  onPanCancel: () => _cancelWidgetDrag(store),
                  child: DesktopWidgetFrame(
                    item: item,
                    spec: spec,
                    span: (columns: area.columnSpan, rows: area.rowSpan),
                    size: rect.size,
                    selected: selected,
                    hovered: hovered,
                  ),
                ),
              ),
            ),
            if (showGrips)
              for (final corner in DesktopWidgetCorner.values)
                Positioned(
                  left: corner.movesLeftEdge ? -2 : null,
                  right: corner.movesLeftEdge ? null : -2,
                  top: corner.movesTopEdge ? -2 : null,
                  bottom: corner.movesTopEdge ? null : -2,
                  child: DesktopWidgetResizeGrip(
                    corner: corner,
                    color: theme.accent,
                    onPanStart: (_) => _beginResize(item, laidOut, corner),
                    onPanUpdate: (details) => _updateResize(
                      details.globalPosition,
                      geometry,
                      spec,
                    ),
                    onPanEnd: () => _endResize(geometry, spec, store),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// Where a dragged widget would land if it were dropped now, or null when
  /// nothing is being dragged.
  ///
  /// The card follows the pointer freely, so this is the only thing that says
  /// which cells the drop resolves to. Measured from the card's own top-left
  /// plus half a cell, so the widget lands on the cell its corner is *in*
  /// rather than the one it is nearest by a hair.
  GridArea? _widgetDropArea(
    List<DesktopWidgetItem> rendered,
    DesktopGridGeometry geometry,
    DesktopStore store,
  ) {
    final id = store.draggingWidget;
    if (id == null) return null;
    for (final item in rendered) {
      if (item.id == id) return _widgetDropAreaFor(item, geometry);
    }
    return null;
  }

  /// The same answer for one already-resolved widget.
  ///
  /// [rendered] must be the item as the grid **laid it out** — the output of
  /// `reflowWidgetsIntoGrid` — because that is the rect the delta was measured
  /// against. Resolving from the authored item instead would drop a reflowed
  /// widget somewhere the user was not pointing. This is the same
  /// rendered-versus-authored split the icon drop has.
  GridArea? _widgetDropAreaFor(
    DesktopWidgetItem rendered,
    DesktopGridGeometry geometry,
  ) {
    final delta = _widgetDragDelta;
    if (delta == null) return null;
    final area = renderAreaFor(
      DesktopWidgetRegistry.lookup(rendered.type),
      rendered,
    );
    final origin = geometry.areaRect(area).topLeft + delta;
    final half = Offset(
      geometry.cellSize.width / 2,
      geometry.cellSize.height / 2,
    );
    final cell = nearestCell(geometry, origin + half);
    return clampAreaInto(
      (
        column: cell.column,
        row: cell.row,
        columnSpan: area.columnSpan,
        rowSpan: area.rowSpan,
      ),
      geometry,
    );
  }

  void _finishWidgetDrag(
    DesktopWidgetItem item,
    DesktopGridGeometry geometry,
    DesktopStore store,
  ) {
    final area = _widgetDropAreaFor(item, geometry);
    _cancelWidgetDrag(store);
    if (area == null) return;
    // Refused (another widget is there) means no write and no move: the card
    // is already back where it started, because the delta is gone.
    store.moveWidget(
      item.id,
      (column: area.column, row: area.row),
      geometry,
    );
  }

  void _cancelWidgetDrag(DesktopStore store) {
    setState(() => _widgetDragDelta = null);
    store.endWidgetDrag();
  }

  void _beginResize(
    DesktopWidgetItem item,
    GridArea area,
    DesktopWidgetCorner corner,
  ) {
    widget.store.selectWidget(item.id);
    setState(() {
      _resize = (id: item.id, corner: corner, start: area);
      _resizeArea = area;
    });
  }

  /// Resolves the pointer to a cell and moves the dragged corner to it, leaving
  /// the opposite corner exactly where it was.
  void _updateResize(
    Offset globalPosition,
    DesktopGridGeometry geometry,
    DesktopWidgetSpec? spec,
  ) {
    final resize = _resize;
    if (resize == null) return;

    final cell = nearestCell(geometry, _toSurface(globalPosition));
    final start = resize.start;
    var left = start.column;
    var top = start.row;
    var right = start.column + start.columnSpan - 1;
    var bottom = start.row + start.rowSpan - 1;

    // Each edge is clamped against its opposite, so dragging a corner past the
    // far side of the widget stops at one cell instead of inverting it.
    if (resize.corner.movesLeftEdge) {
      left = math.min(cell.column, right);
    } else {
      right = math.max(cell.column, left);
    }
    if (resize.corner.movesTopEdge) {
      top = math.min(cell.row, bottom);
    } else {
      bottom = math.max(cell.row, top);
    }

    final area = _applySpanLimits(
      (
        column: left,
        row: top,
        columnSpan: right - left + 1,
        rowSpan: bottom - top + 1,
      ),
      resize.corner,
      spec,
    );
    setState(() => _resizeArea = clampAreaInto(area, geometry));
  }

  /// Applies the type's minimum and maximum span, keeping the corner the user
  /// is *not* dragging pinned — clamping the span alone would slide the whole
  /// widget out from under the pointer at the limit.
  GridArea _applySpanLimits(
    GridArea area,
    DesktopWidgetCorner corner,
    DesktopWidgetSpec? spec,
  ) {
    if (spec == null) return area;
    final columnSpan =
        area.columnSpan.clamp(spec.minSpan.columns, spec.maxSpan.columns);
    final rowSpan = area.rowSpan.clamp(spec.minSpan.rows, spec.maxSpan.rows);
    return (
      column: corner.movesLeftEdge
          ? area.column + area.columnSpan - columnSpan
          : area.column,
      row: corner.movesTopEdge ? area.row + area.rowSpan - rowSpan : area.row,
      columnSpan: columnSpan,
      rowSpan: rowSpan,
    );
  }

  void _endResize(
    DesktopGridGeometry geometry,
    DesktopWidgetSpec? spec,
    DesktopStore store,
  ) {
    final resize = _resize;
    final area = _resizeArea;
    setState(() {
      _resize = null;
      _resizeArea = null;
    });
    if (resize == null || area == null) return;
    store.resizeWidget(
      resize.id,
      area,
      geometry,
      // No spec (an unknown type) means no limits to enforce beyond the grid's
      // own; the placeholder is resizable so it can be got out of the way.
      minSpan: spec?.minSpan ?? (columns: 1, rows: 1),
      maxSpan: spec?.maxSpan ??
          (columns: geometry.columns, rows: geometry.rows),
    );
  }

  /// The icons that follow the cursor during a drag: the pressed one centred
  /// under it, and the rest of its group holding their relative cells, so a
  /// group keeps its shape and the drop is predictable.
  Iterable<Widget> _ghosts(
    List<DesktopItem> items,
    Offset position,
    DesktopGridGeometry geometry,
    DesktopStore store,
  ) {
    final anchor = _itemFor(items, store.draggingTarget);
    if (anchor == null) return const [];
    return [
      for (final item in items)
        if (_dragGroup.contains(item.target))
          _ghost(
            item,
            position +
                Offset(
                  (item.column - anchor.column) * geometry.columnPitch,
                  (item.row - anchor.row) * geometry.rowPitch,
                ),
            geometry,
            store,
          ),
    ];
  }

  /// One dragged icon, centred on [position].
  Widget _ghost(
    DesktopItem item,
    Offset position,
    DesktopGridGeometry geometry,
    DesktopStore store,
  ) {
    final size = geometry.cellSize;
    return Positioned(
      key: ValueKey('ghost:${item.target}'),
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

  void _endBand() {
    _bandAnchor = null;
    // No setState: the notifier rebuilds the band's own subtree, and the
    // selection the band left behind was published by the store as it went.
    _band.value = null;
  }

  /// Resolves a drop. [anchor] is the *rendered* item that was dragged, so the
  /// delta a group moves by is measured against the cell the user was actually
  /// looking at rather than the one the config authored.
  void _finishDrag(
    DesktopItem anchor,
    DesktopGridGeometry geometry,
    DesktopStore store,
  ) {
    final position = _dragPosition;
    final group = _dragGroup;
    setState(() {
      _dragPosition = null;
      _dragGroup = const {};
    });
    store.endDrag();
    if (position == null) return;

    // The drop lands on whichever cell the anchor ghost's centre is nearest, so
    // what the user sees is what they get.
    final cell = nearestCell(geometry, position);
    if (group.length <= 1) {
      // moveTo swaps if that cell is taken.
      store.moveTo(anchor.target, cell);
      return;
    }

    // A group moves by the delta the anchor travelled, which is what keeps its
    // shape; moveItemsBy clamps that delta to the grid and displaces bystanders.
    store.moveGroupBy(
      group,
      cell.column - anchor.column,
      cell.row - anchor.row,
      geometry,
    );
  }
}

/// The rubber-band selection box: a translucent wash of the shell's accent
/// colour under a heavier outline of the same, so it reads as one transient
/// object over any wallpaper.
///
/// A [DecoratedBox] rather than a [CustomPainter] — it is one rounded rect, and
/// the grid's only painter is [DesktopGridLines], which `desktop_grid_test.dart`
/// asserts is the *only* thing on the CustomPaint path. Colours arrive as
/// parameters, the `time_series_chart.dart` convention.
class DesktopSelectionBand extends StatelessWidget {
  const DesktopSelectionBand({
    super.key,
    required this.rect,
    required this.color,
  });

  final Rect rect;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: rect,
      // The band is painted over the icons and must not eat the pointer that is
      // still drawing it.
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
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
