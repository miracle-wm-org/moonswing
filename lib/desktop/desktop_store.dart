import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/desktop/desktop_layout.dart';

/// The desktop grid's state: the pinned items, and what the user is doing to
/// them right now.
///
/// The singleton-[ChangeNotifier] shape, and for `ThemeStore`'s reason it reads
/// [ConfigStore] for the `desktop` subtree alone and **never**
/// [ConfigStore.appConfig], whose getter rebuilds the whole typed config and
/// re-applies every module's options.
///
/// The split that matters is persisted vs. ephemeral. [items] and [config] are
/// written back; [selectedTargets], [draggingTarget] and [renamingTarget] never
/// touch the disk. Every `ConfigStore.set` notifies synchronously and rebuilds
/// every panel on every monitor, so a drag persists once **on drop**.
class DesktopStore extends ChangeNotifier {
  DesktopStore._();

  /// The process-wide store, watched by the desktop surface on every monitor.
  static final DesktopStore instance = DesktopStore._();

  /// A detached store. Tests always use this — the singleton binds to the real
  /// `ConfigStore`, and there is exactly one of those per process.
  @visibleForTesting
  factory DesktopStore.forTesting() => DesktopStore._();

  ConfigStore? _config;
  bool _started = false;
  bool _disposed = false;

  /// True while [_commit] is writing, so the config notifications its own
  /// writes provoke do not re-parse a half-written subtree. See [_commit].
  bool _committing = false;

  DesktopConfig _desktop = const DesktopConfig();

  /// Signature of the `desktop` subtree as last parsed, so [_onConfigChanged]
  /// can early-return. That listener fires on **every** keystroke anywhere in
  /// the settings UI, and re-parsing the item list each time would rebuild the
  /// grid on every monitor for an unrelated edit.
  String _signature = '';

  /// The selection, which the rubber band makes a set rather than a single
  /// target. Mutated in place and exposed read-only, so a caller cannot widen
  /// it behind the store's back and skip the notification.
  final Set<String> _selected = <String>{};
  late final Set<String> _selectedView = UnmodifiableSetView(_selected);

  String? _renaming;
  String? _dragging;

  /// The widget under a drag, and the selected one. Separate fields from the
  /// icons' rather than one union, because the two are identified differently —
  /// an icon by its target path, a widget by its instance id — and a single
  /// nullable string would answer "is this thing dragging?" wrongly the day a
  /// widget id happened to equal a path.
  String? _draggingWidget;
  String? _selectedWidget;

  DesktopConfig get config => _desktop;
  List<DesktopItem> get items => List.unmodifiable(_desktop.items);
  List<DesktopWidgetItem> get widgets => List.unmodifiable(_desktop.widgets);
  bool get enabled => _desktop.enabled;

  /// The cells the widgets cover — what every icon placement takes as its
  /// `blocked` set, so no icon is ever put where the user cannot see it.
  Set<GridCell> get blockedCells => widgetCells(_desktop.widgets);

  Set<String> get selectedTargets => _selectedView;
  bool isSelected(String target) => _selected.contains(target);

  String? get renamingTarget => _renaming;
  String? get draggingTarget => _dragging;

  String? get selectedWidget => _selectedWidget;
  String? get draggingWidget => _draggingWidget;

  /// Whether a drag is in flight — what makes the grid lines visible, and the
  /// only reason they ever are. True for an icon drag or a widget one: the
  /// lines mean the same thing in both.
  bool get isDragging => _dragging != null || _draggingWidget != null;

  /// Seeds the store directly, with no [ConfigStore] behind it.
  ///
  /// For widget tests: `ConfigStore.loadFrom` does real async file I/O, and a real
  /// I/O completion never lands inside `testWidgets`' fake-async zone. Mutations
  /// on an unbound store stay in memory, which is all a widget test needs.
  @visibleForTesting
  void seed(DesktopConfig config) {
    _started = true;
    _desktop = config;
    _signature = _signatureOf(config);
    notifyListeners();
  }

  /// Binds to [config] and reads the initial item list. Safe to call twice.
  void start({ConfigStore? config}) {
    if (config != null && _config == null) {
      _config = config;
      config.addListener(_onConfigChanged);
    }
    _started = true;
    // Read unconditionally rather than leaning on the listener: nothing has
    // fired yet, and the field initialiser is an empty disabled grid.
    _reload();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Ephemeral state — notify, never write
  // ---------------------------------------------------------------------------

  /// Replaces the selection with [target] alone, or clears it when null.
  void select(String? target) =>
      selectAll(target == null ? const <String>[] : [target]);

  /// Replaces the selection wholesale. What the rubber band calls on every pan
  /// update, which is why the no-op guard matters: this store is watched by
  /// every monitor's desktop surface, and a notification per pointer move would
  /// rebuild all of them at pointer rate.
  void selectAll(Iterable<String> targets) {
    final next = targets.toSet();
    if (setEquals(_selected, next) && _selectedWidget == null) return;
    _selected
      ..clear()
      ..addAll(next);
    // One selection, not two: an icon selection and a widget selection on
    // screen at once would leave "Remove" ambiguous. Clearing the icons
    // (a click on bare desktop, a band that crossed nothing) clears the
    // widget too, which is what "nothing is selected" has to mean.
    _selectedWidget = null;
    notifyListeners();
  }

  /// Selects a widget, clearing any icon selection, or clears the selection
  /// when null.
  void selectWidget(String? id) {
    if (_selectedWidget == id && (id == null || _selected.isEmpty)) return;
    _selectedWidget = id;
    if (id != null) _selected.clear();
    notifyListeners();
  }

  void beginWidgetDrag(String id) {
    if (_draggingWidget == id) return;
    _draggingWidget = id;
    notifyListeners();
  }

  void endWidgetDrag() {
    if (_draggingWidget == null) return;
    _draggingWidget = null;
    notifyListeners();
  }

  void beginDrag(String target) {
    if (_dragging == target) return;
    _dragging = target;
    notifyListeners();
  }

  void endDrag() {
    if (_dragging == null) return;
    _dragging = null;
    notifyListeners();
  }

  void beginRename(String target) {
    if (_renaming == target) return;
    _renaming = target;
    // Renaming something implies selecting it *alone*, so the chrome agrees
    // with the edit rather than highlighting a different icon — or several.
    _selected
      ..clear()
      ..add(target);
    notifyListeners();
  }

  void cancelRename() {
    if (_renaming == null) return;
    _renaming = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Persisting mutations
  // ---------------------------------------------------------------------------

  /// Commits an in-place rename. An empty label clears the override, so the
  /// item falls back to the desktop entry's name or the path's basename —
  /// which is the only way back to the original once renamed.
  void commitRename(String target, String label) {
    final trimmed = label.trim();
    _renaming = null;
    _updateItem(
      target,
      (item) => item.copyWith(
        label: trimmed.isEmpty ? null : trimmed,
        clearLabel: trimmed.isEmpty,
      ),
    );
  }

  /// Pins [item], placing it at its own cell when free and at the nearest free
  /// cell otherwise. A target that is already pinned is ignored.
  void addItem(DesktopItem item, DesktopGridGeometry geometry) {
    final next =
        placeItem(_desktop.items, item, geometry, blocked: blockedCells);
    if (identical(next, _desktop.items)) return;
    _commit(items: next);
  }

  void removeItem(String target) => removeItems([target]);

  /// Unpins every target in [targets] with a **single** commit.
  ///
  /// `_commit` goes through `ConfigStore.set`, whose notification is synchronous
  /// and rebuilds every panel on every monitor, so removing a five-icon selection
  /// one at a time would do that five times over.
  void removeItems(Iterable<String> targets) {
    final doomed = targets.toSet();
    if (!_desktop.items.any((item) => doomed.contains(item.target))) return;
    _selected.removeAll(doomed);
    if (_renaming != null && doomed.contains(_renaming)) _renaming = null;
    if (_dragging != null && doomed.contains(_dragging)) _dragging = null;
    _commit(
      items: [
        for (final item in _desktop.items)
          if (!doomed.contains(item.target)) item,
      ],
    );
  }

  /// Moves [target] to [cell], swapping with whatever is already there.
  ///
  /// A drop that resolves to the cell the item already occupies writes nothing:
  /// [moveItemTo] returns the identical list and this returns early.
  void moveTo(String target, GridCell cell) {
    final next =
        moveItemTo(_desktop.items, target, cell, blocked: blockedCells);
    if (identical(next, _desktop.items)) return;
    _commit(items: next);
  }

  /// Translates a whole selection, for a drag that started on one of several
  /// selected icons. Writes nothing when the clamped delta is zero — the same
  /// contract [moveTo] has.
  void moveGroupBy(
    Set<String> targets,
    int dColumn,
    int dRow,
    DesktopGridGeometry geometry,
  ) {
    final next = moveItemsBy(
      _desktop.items,
      targets,
      dColumn,
      dRow,
      geometry,
      blocked: blockedCells,
    );
    if (identical(next, _desktop.items)) return;
    _commit(items: next);
  }

  /// Compacts the grid column-major. Idempotent, and writes nothing when the
  /// items are already in order.
  /// Widgets are deliberately untouched: organize compacts *icons*, and it
  /// flows them around whatever cells the widgets hold.
  void organize(DesktopGridGeometry geometry) {
    final next =
        organizeItems(_desktop.items, geometry, blocked: blockedCells);
    if (_sameCells(next, _desktop.items)) return;
    _commit(items: next);
  }

  /// Replaces the grid geometry, leaving the items alone. The settings UI's
  /// writer; it goes through here rather than straight to [ConfigStore] so the
  /// in-memory config and the file cannot drift.
  void setGrid(DesktopConfig grid) {
    final config = _config;
    if (config == null) {
      _desktop = grid;
      notifyListeners();
      return;
    }
    config.set(['desktop', 'enabled'], grid.enabled);
    config.set(['desktop', 'cell_width'], grid.cellWidth);
    config.set(['desktop', 'cell_height'], grid.cellHeight);
    config.set(['desktop', 'spacing'], grid.spacing);
    config.set(['desktop', 'padding'], grid.padding);
    config.set(['desktop', 'icon_size'], grid.iconSize);
    config.set(['desktop', 'show_labels'], grid.showLabels);
  }

  // ---------------------------------------------------------------------------
  // Widgets
  //
  // Every one of these commits **both** lists at once, because a widget landing
  // on an icon displaces it: two `ConfigStore.set` calls would notify twice, and
  // for one frame between them the config would hold a widget and an icon in the
  // same cell.
  // ---------------------------------------------------------------------------

  /// Adds [widget], at its own area when that is free and at the nearest free
  /// one otherwise, displacing any icons underneath.
  ///
  /// Ignored when the id is taken, or when no placement of that size fits.
  void addWidget(DesktopWidgetItem widget, DesktopGridGeometry geometry) {
    final next = placeWidget(_desktop.widgets, widget, geometry);
    if (identical(next, _desktop.widgets)) return;
    _commitWidgets(next, geometry, placed: next.last);
  }

  void removeWidget(String id) {
    if (!_desktop.widgets.any((widget) => widget.id == id)) return;
    if (_selectedWidget == id) _selectedWidget = null;
    if (_draggingWidget == id) _draggingWidget = null;
    _commit(
      widgets: _desktop.widgets.where((widget) => widget.id != id).toList(),
    );
  }

  /// Moves the widget [id] so its top-left lands on [cell]. Refused — no
  /// write — when that would overlap another widget.
  void moveWidget(String id, GridCell cell, DesktopGridGeometry geometry) {
    final next = moveWidgetTo(_desktop.widgets, id, cell, geometry);
    if (identical(next, _desktop.widgets)) return;
    _commitWidgets(
      next,
      geometry,
      placed: next.firstWhere((widget) => widget.id == id),
    );
  }

  /// Resizes the widget [id] to [area], clamped to the type's [minSpan] and
  /// [maxSpan] and into the grid. Refused when it would overlap another widget.
  void resizeWidget(
    String id,
    GridArea area,
    DesktopGridGeometry geometry, {
    required GridSpan minSpan,
    required GridSpan maxSpan,
  }) {
    final next = resizeWidgetTo(
      _desktop.widgets,
      id,
      area,
      geometry,
      minSpan: minSpan,
      maxSpan: maxSpan,
    );
    if (identical(next, _desktop.widgets)) return;
    _commitWidgets(
      next,
      geometry,
      placed: next.firstWhere((widget) => widget.id == id),
    );
  }

  /// Commits a new widget list, moving any icons out from under [placed].
  void _commitWidgets(
    List<DesktopWidgetItem> widgets,
    DesktopGridGeometry geometry, {
    DesktopWidgetItem? placed,
  }) {
    var items = _desktop.items;
    if (placed != null) {
      items = displaceItemsFrom(
        items,
        areaOf(placed),
        geometry,
        // Every cell the widgets will hold *after* this commit, so a displaced
        // icon cannot be pushed under a different widget.
        blocked: widgetCells(widgets, ignoreId: placed.id),
      );
    }
    _commit(
      items: identical(items, _desktop.items) ? null : items,
      widgets: widgets,
    );
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _updateItem(String target, DesktopItem Function(DesktopItem) transform) {
    final index = _desktop.items.indexWhere((item) => item.target == target);
    if (index < 0) {
      notifyListeners();
      return;
    }
    final next = List<DesktopItem>.of(_desktop.items);
    next[index] = transform(next[index]);
    _commit(items: next);
  }

  /// Applies [items] in memory and writes them back.
  ///
  /// The in-memory update is not left to [_onConfigChanged]: the write is
  /// debounced but the *notification* is synchronous, and a listener rebuilding
  /// from a stale item list would show the icon snapping back for a frame.
  void _commit({List<DesktopItem>? items, List<DesktopWidgetItem>? widgets}) {
    if (items == null && widgets == null) return;
    _desktop = _desktop.copyWith(items: items, widgets: widgets);
    _signature = _signatureOf(_desktop);
    // Both writes are one commit as far as this store is concerned. Every
    // `ConfigStore.set` notifies synchronously, so without the guard the
    // `items` write would send [_onConfigChanged] back in here to re-parse a
    // config that still holds the *old* widgets — a state that never existed
    // and that would then be published to every monitor's surface.
    _committing = true;
    try {
      if (items != null) {
        _config?.set(
          ['desktop', 'items'],
          [for (final item in items) item.toMap()],
        );
      }
      if (widgets != null) {
        _config?.set(
          ['desktop', 'widgets'],
          [for (final widget in widgets) widget.toMap()],
        );
      }
    } finally {
      _committing = false;
    }
    notifyListeners();
  }

  void _reload() {
    final raw = _config?.get<Map<String, dynamic>>(['desktop']);
    _desktop = raw != null ? DesktopConfig.fromMap(raw) : const DesktopConfig();
    _signature = _signatureOf(_desktop);
  }

  void _onConfigChanged() {
    if (!_started || _committing) return;
    final raw = _config?.get<Map<String, dynamic>>(['desktop']);
    final next =
        raw != null ? DesktopConfig.fromMap(raw) : const DesktopConfig();
    final signature = _signatureOf(next);
    if (signature == _signature) return;
    _desktop = next;
    _signature = signature;
    // An item that vanished from under a selection (a hand edit, or another
    // surface removing it) must not leave the chrome pointing at nothing.
    _selected.removeWhere((target) => !_hasTarget(target));
    if (_renaming != null && !_hasTarget(_renaming!)) _renaming = null;
    if (_selectedWidget != null && !_hasWidget(_selectedWidget!)) {
      _selectedWidget = null;
    }
    if (_draggingWidget != null && !_hasWidget(_draggingWidget!)) {
      _draggingWidget = null;
    }
    notifyListeners();
  }

  bool _hasTarget(String target) =>
      _desktop.items.any((item) => item.target == target);

  bool _hasWidget(String id) =>
      _desktop.widgets.any((widget) => widget.id == id);

  static bool _sameCells(List<DesktopItem> a, List<DesktopItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].target != b[i].target ||
          a[i].column != b[i].column ||
          a[i].row != b[i].row) {
        return false;
      }
    }
    return true;
  }

  /// A cheap value-identity for the `desktop` subtree. Compared rather than
  /// deep-equality-checked because it runs on every config notification.
  static String _signatureOf(DesktopConfig config) {
    final buffer = StringBuffer()
      ..write(config.enabled)
      ..write('|${config.cellWidth}x${config.cellHeight}')
      ..write('|${config.spacing}/${config.padding}')
      ..write('|${config.iconSize}')
      ..write('|${config.showLabels}');
    for (final item in config.items) {
      buffer.write('|${item.kind.name}:${item.target}:'
          '${item.label ?? ''}:${item.column},${item.row}');
    }
    for (final widget in config.widgets) {
      buffer.write('|w:${widget.id}:${widget.type}:'
          '${widget.column},${widget.row}:'
          '${widget.columnSpan}x${widget.rowSpan}:${widget.options}');
    }
    return buffer.toString();
  }

  @override
  void dispose() {
    _disposed = true;
    _config?.removeListener(_onConfigChanged);
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }
}

/// Binds the desktop grid to the live config. Called from `main()` beside
/// `startThemeService()`, and like it must never touch `ConfigStore.appConfig`.
void startDesktopService(ConfigStore config) =>
    DesktopStore.instance.start(config: config);
