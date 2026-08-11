import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/desktop/desktop_layout.dart';

/// The desktop grid's state: the pinned items, and what the user is doing to
/// them right now.
///
/// Same singleton-[ChangeNotifier] shape as `ThemeStore`/`OsdStore`, and for
/// `ThemeStore`'s reason: it reads [ConfigStore] for the `desktop` subtree
/// alone and **never** [ConfigStore.appConfig], whose getter rebuilds the whole
/// typed config and re-applies every module's options via `Module.loadAll`.
///
/// The split that matters is persisted vs. ephemeral. [items] and [config] are
/// written back through [ConfigStore]; [selectedTargets], [draggingTarget] and
/// [renamingTarget] are not, and never touch the disk. Every `ConfigStore.set`
/// notifies synchronously and rebuilds every panel on every monitor, so a drag
/// persists once **on drop** rather than per-frame — routing pointer positions
/// through the config would rebuild the shell dozens of times per gesture.
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

  DesktopConfig get config => _desktop;
  List<DesktopItem> get items => List.unmodifiable(_desktop.items);
  bool get enabled => _desktop.enabled;

  Set<String> get selectedTargets => _selectedView;
  bool isSelected(String target) => _selected.contains(target);

  String? get renamingTarget => _renaming;
  String? get draggingTarget => _dragging;

  /// Whether a drag is in flight — what makes the grid lines visible, and the
  /// only reason they ever are.
  bool get isDragging => _dragging != null;

  /// Seeds the store directly, with no [ConfigStore] behind it.
  ///
  /// For widget tests: `ConfigStore.loadFrom` does real async file I/O, and a
  /// real I/O completion never lands inside `testWidgets`' fake-async zone — the
  /// same trap `test/system_tab_test.dart` documents for `DiskReader`. Mutations
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
    if (setEquals(_selected, next)) return;
    _selected
      ..clear()
      ..addAll(next);
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
    final next = placeItem(_desktop.items, item, geometry);
    if (identical(next, _desktop.items)) return;
    _commit(next);
  }

  void removeItem(String target) => removeItems([target]);

  /// Unpins every target in [targets] with a **single** commit.
  ///
  /// One write rather than one per item: `_commit` goes through
  /// `ConfigStore.set`, whose notification is synchronous and rebuilds every
  /// panel on every monitor, so removing a five-icon selection one at a time
  /// would do that five times over.
  void removeItems(Iterable<String> targets) {
    final doomed = targets.toSet();
    if (!_desktop.items.any((item) => doomed.contains(item.target))) return;
    _selected.removeAll(doomed);
    if (_renaming != null && doomed.contains(_renaming)) _renaming = null;
    if (_dragging != null && doomed.contains(_dragging)) _dragging = null;
    _commit(
      _desktop.items.where((item) => !doomed.contains(item.target)).toList(),
    );
  }

  /// Moves [target] to [cell], swapping with whatever is already there.
  ///
  /// A drop that resolves to the cell the item already occupies writes nothing:
  /// [moveItemTo] returns the identical list and this returns early.
  void moveTo(String target, GridCell cell) {
    final next = moveItemTo(_desktop.items, target, cell);
    if (identical(next, _desktop.items)) return;
    _commit(next);
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
    final next = moveItemsBy(_desktop.items, targets, dColumn, dRow, geometry);
    if (identical(next, _desktop.items)) return;
    _commit(next);
  }

  /// Compacts the grid column-major. Idempotent, and writes nothing when the
  /// items are already in order.
  void organize(DesktopGridGeometry geometry) {
    final next = organizeItems(_desktop.items, geometry);
    if (_sameCells(next, _desktop.items)) return;
    _commit(next);
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
    _commit(next);
  }

  /// Applies [items] in memory and writes them back.
  ///
  /// The in-memory update is not left to [_onConfigChanged] to apply: the write
  /// is debounced but the *notification* is synchronous, and a listener that
  /// rebuilt from a stale item list would show the icon snapping back to its
  /// old cell for a frame.
  void _commit(List<DesktopItem> items) {
    _desktop = _copyWithItems(_desktop, items);
    _signature = _signatureOf(_desktop);
    _config?.set(
      ['desktop', 'items'],
      [for (final item in items) item.toMap()],
    );
    notifyListeners();
  }

  void _reload() {
    final raw = _config?.get<Map<String, dynamic>>(['desktop']);
    _desktop = raw != null ? DesktopConfig.fromMap(raw) : const DesktopConfig();
    _signature = _signatureOf(_desktop);
  }

  void _onConfigChanged() {
    if (!_started) return;
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
    notifyListeners();
  }

  bool _hasTarget(String target) =>
      _desktop.items.any((item) => item.target == target);

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
    return buffer.toString();
  }

  static DesktopConfig _copyWithItems(
    DesktopConfig config,
    List<DesktopItem> items,
  ) {
    return DesktopConfig(
      enabled: config.enabled,
      cellWidth: config.cellWidth,
      cellHeight: config.cellHeight,
      spacing: config.spacing,
      padding: config.padding,
      iconSize: config.iconSize,
      showLabels: config.showLabels,
      items: items,
    );
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
