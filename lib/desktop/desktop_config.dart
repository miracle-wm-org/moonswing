/// The desktop icon grid's persisted model: what is pinned, and where.
///
/// The runtime side — geometry, the store, the surface — lives in the
/// sibling files here; this one is only the `[desktop]` config section, and
/// is re-exported through `package:moonswing/config.dart`.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:moonswing/config_reader.dart';

/// What a desktop grid item points at, which decides how it opens.
///
/// The distinction between [file] and [folder] is not cosmetic: it picks the
/// icon and decides whether "Open with…" is offered, and a folder cannot be
/// content-sniffed from its name alone (see `iconNameForPath`).
enum DesktopItemKind {
  app,
  file,
  folder;

  static DesktopItemKind fromString(String s) {
    switch (s) {
      case 'app':
        return DesktopItemKind.app;
      case 'folder':
        return DesktopItemKind.folder;
      default:
        return DesktopItemKind.file;
    }
  }
}

/// Infers an item's kind from its target, used when the stored `kind` is
/// missing or has gone stale (a path that was a file and is now a directory).
///
/// A `.desktop` file is an application even though it is also a file on disk —
/// that is the whole point of pinning one.
DesktopItemKind inferDesktopItemKind(String target) {
  if (target.toLowerCase().endsWith('.desktop')) return DesktopItemKind.app;
  if (Directory(target).existsSync()) return DesktopItemKind.folder;
  return DesktopItemKind.file;
}

/// One icon pinned to the desktop grid.
///
/// [target] is the identity: an absolute path in every case, applications
/// included. A desktop *id* (what `[modules.dock].apps` stores) is deliberately
/// not used — the item is added through the file picker, which yields a path, and
/// `g_desktop_app_info_new` cannot resolve a `.desktop` outside `XDG_DATA_DIRS`.
class DesktopItem {
  final DesktopItemKind kind;
  final String target;

  /// The user's rename, or null to derive the label from the desktop entry's
  /// name (for [DesktopItemKind.app]) or the path's basename.
  final String? label;

  final int column;
  final int row;

  const DesktopItem({
    required this.kind,
    required this.target,
    this.label,
    this.column = 0,
    this.row = 0,
  });

  DesktopItem copyWith({
    DesktopItemKind? kind,
    String? label,
    bool clearLabel = false,
    int? column,
    int? row,
  }) {
    return DesktopItem(
      kind: kind ?? this.kind,
      target: target,
      label: clearLabel ? null : (label ?? this.label),
      column: column ?? this.column,
      row: row ?? this.row,
    );
  }

  /// Parses one `[[desktop.items]]` table, or null when it names no target.
  static DesktopItem? fromMap(Map<String, dynamic> map) {
    // The target is deliberately stored verbatim, not trimmed: a path with
    // surrounding whitespace is legal on Linux, and rewriting it would point
    // the item at a different file.
    final target = map['target'];
    if (target is! String || target.trim().isEmpty) return null;

    final rawKind = map.stringOrNull('kind');
    // A stored kind is trusted only when it still matches reality; `app` is the
    // exception, since a `.desktop` file is legitimately both.
    var kind = rawKind != null
        ? DesktopItemKind.fromString(rawKind)
        : inferDesktopItemKind(target);
    if (kind != DesktopItemKind.app) kind = inferDesktopItemKind(target);

    return DesktopItem(
      kind: kind,
      target: target,
      label: map.stringOrNull('label'),
      column: map.intOr('column', 0, min: 0),
      row: map.intOr('row', 0, min: 0),
    );
  }

  /// The TOML table for this item. `label` is omitted when the user has not
  /// renamed it, so a config that was never edited stays minimal.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'kind': kind.name,
        'target': target,
        if (label != null) 'label': label,
        'column': column,
        'row': row,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopItem &&
          other.kind == kind &&
          other.target == target &&
          other.label == label &&
          other.column == column &&
          other.row == row;

  @override
  int get hashCode => Object.hash(kind, target, label, column, row);
}

/// One widget pinned to the desktop grid.
///
/// A widget is *not* a [DesktopItem] with a bigger cell, and the two lists are
/// deliberately separate. An icon is identified by the thing it points at, is
/// exactly one cell, and is what "Organize" compacts; a widget is identified by
/// an instance [id] (two clocks are two widgets), spans a rectangle, and
/// **organize must leave it exactly where it is**.
///
/// [type] names an entry in `DesktopWidgetRegistry`, which owns everything about
/// how a widget renders and how far it may be resized. This class is only what
/// survives a restart.
class DesktopWidgetItem {
  const DesktopWidgetItem({
    required this.id,
    required this.type,
    this.column = 0,
    this.row = 0,
    this.columnSpan = 1,
    this.rowSpan = 1,
    this.options = const <String, dynamic>{},
  });

  /// This instance's identity, unique within the config. Plays the role
  /// [DesktopItem.target] plays for icons: the key a drag, a resize or a
  /// removal names. Generated by [nextDesktopWidgetId] when the user adds one.
  final String id;

  /// The registry key deciding what is drawn — `media_player`, and whatever
  /// comes next.
  final String type;

  /// Top-left cell of the widget's span.
  final int column;
  final int row;

  /// The widget's size **in cells**, always at least one of each.
  ///
  /// Clamped against the registry spec at render time rather than here: a config
  /// authored while a widget allowed 4x2 must not be silently rewritten when a
  /// later version lowers the maximum, and the spec is not reachable from this
  /// layer anyway.
  final int columnSpan;
  final int rowSpan;

  /// Per-instance settings, owned by the widget type. Nothing reads this yet;
  /// it exists so the first widget that needs an option — a clock's format, a
  /// note's text — does not have to migrate every user's config to get one.
  final Map<String, dynamic> options;

  DesktopWidgetItem copyWith({
    int? column,
    int? row,
    int? columnSpan,
    int? rowSpan,
    Map<String, dynamic>? options,
  }) {
    return DesktopWidgetItem(
      id: id,
      type: type,
      column: column ?? this.column,
      row: row ?? this.row,
      columnSpan: columnSpan ?? this.columnSpan,
      rowSpan: rowSpan ?? this.rowSpan,
      options: options ?? this.options,
    );
  }

  /// Parses one `[[desktop.widgets]]` table, or null when it names no type.
  ///
  /// An entry with no `id` is given one derived from its type rather than being
  /// dropped: a hand-written config is a legitimate way to place a widget.
  /// Duplicate ids are resolved by [DesktopConfig.fromMap], the only place that
  /// can see the whole list.
  static DesktopWidgetItem? fromMap(Map<String, dynamic> map) {
    final type = map.stringOrNull('type');
    if (type == null || type.trim().isEmpty) return null;

    final options = map['options'];
    return DesktopWidgetItem(
      id: map.stringOrNull('id')?.trim().isNotEmpty == true
          ? map.stringOrNull('id')!.trim()
          : type.trim(),
      type: type.trim(),
      column: map.intOr('column', 0, min: 0),
      row: map.intOr('row', 0, min: 0),
      // A zero or negative span is a hand-edit or a corrupted write, and a
      // widget occupying no cells is invisible and unclickable — there would be
      // nothing left to fix it with.
      columnSpan: map.intOr('column_span', 1, min: 1),
      rowSpan: map.intOr('row_span', 1, min: 1),
      options: options is Map
          ? Map<String, dynamic>.unmodifiable(options.cast<String, dynamic>())
          : const <String, dynamic>{},
    );
  }

  /// The TOML table for this widget. `options` is omitted while empty, so a
  /// config nobody has customised stays minimal.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'type': type,
        'column': column,
        'row': row,
        'column_span': columnSpan,
        'row_span': rowSpan,
        if (options.isNotEmpty) 'options': options,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopWidgetItem &&
          other.id == id &&
          other.type == type &&
          other.column == column &&
          other.row == row &&
          other.columnSpan == columnSpan &&
          other.rowSpan == rowSpan &&
          mapEquals(other.options, options);

  @override
  int get hashCode => Object.hash(
        id,
        type,
        column,
        row,
        columnSpan,
        rowSpan,
        options.length,
      );
}

/// The first `<type>`, `<type>-2`, `<type>-3`… not already taken by [existing].
///
/// Deterministic rather than random: a test can assert what a second media
/// player is called, and a config diff after adding a widget is one readable
/// line rather than a UUID.
String nextDesktopWidgetId(
  Iterable<DesktopWidgetItem> existing,
  String type,
) {
  final taken = {for (final widget in existing) widget.id};
  if (!taken.contains(type)) return type;
  for (var n = 2;; n++) {
    final candidate = '$type-$n';
    if (!taken.contains(candidate)) return candidate;
  }
}

/// Geometry and behaviour of the desktop icon grid.
///
/// Column and row counts are *derived* from each monitor's usable area rather
/// than configured, so one item list renders sanely on monitors of different
/// sizes. See `computeGridGeometry` in `lib/desktop/desktop_layout.dart`.
class DesktopConfig {
  /// Whether the grid is drawn at all. On by default. Restart-only: it decides
  /// whether the native background surface is created (see
  /// `ConfigStore._restartSignature`).
  final bool enabled;

  final double cellWidth;
  final double cellHeight;
  final double spacing;

  /// Inset from the usable area's edges, on top of the panel exclusive zones.
  final double padding;

  final double iconSize;
  final bool showLabels;

  final List<DesktopItem> items;

  /// The pinned widgets, in document order. A second list rather than a kind
  /// of [DesktopItem] — see [DesktopWidgetItem] for why the two cannot be one.
  final List<DesktopWidgetItem> widgets;

  const DesktopConfig({
    this.enabled = true,
    this.cellWidth = 96,
    this.cellHeight = 96,
    this.spacing = 12,
    this.padding = 24,
    this.iconSize = 48,
    this.showLabels = true,
    this.items = const [],
    this.widgets = const [],
  });

  /// A copy with the persisted lists replaced. What `DesktopStore._commit`
  /// writes through, so the store cannot forget to carry a field across when a
  /// new one is added here.
  DesktopConfig copyWith({
    List<DesktopItem>? items,
    List<DesktopWidgetItem>? widgets,
  }) {
    return DesktopConfig(
      enabled: enabled,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
      spacing: spacing,
      padding: padding,
      iconSize: iconSize,
      showLabels: showLabels,
      items: items ?? this.items,
      widgets: widgets ?? this.widgets,
    );
  }

  factory DesktopConfig.fromMap(Map<String, dynamic> map) {
    // Document order is preserved; cells, not list position, decide layout.
    final items = map
        .tableListOr('items')
        .map(DesktopItem.fromMap)
        .whereType<DesktopItem>()
        .toList();

    // Ids are the identity a drag, a resize and a removal all name, so a
    // duplicate is not survivable: two widgets answering to one id would move
    // together and remove together. A repeat is renamed rather than dropped —
    // the user still gets the widget they hand-wrote.
    final widgets = <DesktopWidgetItem>[];
    for (final raw in map.tableListOr('widgets')) {
      final widget = DesktopWidgetItem.fromMap(raw);
      if (widget == null) continue;
      // Renamed off the *type*, not off the colliding id, so a second
      // hand-written `media_player-2` becomes `media_player-3` rather than
      // `media_player-2-2`.
      final id = widgets.any((existing) => existing.id == widget.id)
          ? nextDesktopWidgetId(widgets, widget.type)
          : widget.id;
      widgets.add(
        id == widget.id
            ? widget
            : DesktopWidgetItem(
                id: id,
                type: widget.type,
                column: widget.column,
                row: widget.row,
                columnSpan: widget.columnSpan,
                rowSpan: widget.rowSpan,
                options: widget.options,
              ),
      );
    }

    return DesktopConfig(
      enabled: map.boolOr('enabled', true),
      // A cell smaller than its icon would clip; floors keep a hand-edited
      // config from producing an unusable grid rather than rejecting it.
      cellWidth: map.doubleOr('cell_width', 96, min: 32),
      cellHeight: map.doubleOr('cell_height', 96, min: 32),
      spacing: map.doubleOr('spacing', 12, min: 0),
      padding: map.doubleOr('padding', 24, min: 0),
      iconSize: map.doubleOr('icon_size', 48, min: 8),
      showLabels: map.boolOr('show_labels', true),
      items: items,
      widgets: widgets,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopConfig &&
          other.enabled == enabled &&
          other.cellWidth == cellWidth &&
          other.cellHeight == cellHeight &&
          other.spacing == spacing &&
          other.padding == padding &&
          other.iconSize == iconSize &&
          other.showLabels == showLabels &&
          listEquals(other.items, items) &&
          listEquals(other.widgets, widgets);

  @override
  int get hashCode => Object.hash(
        enabled,
        cellWidth,
        cellHeight,
        spacing,
        padding,
        iconSize,
        showLabels,
        Object.hashAll(items),
        Object.hashAll(widgets),
      );
}
