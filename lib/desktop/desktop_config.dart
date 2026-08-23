/// The desktop icon grid's persisted model: what is pinned, and where.
///
/// The runtime side — geometry, the store, the surface — lives in the
/// sibling files here; this one is only the `[desktop]` config section, and
/// is re-exported through `package:graceful_shell/config.dart`.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/config_reader.dart';

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
/// [target] is the identity: an absolute path in every case, including for
/// applications. A desktop *id* (what `[modules.dock].apps` stores) is
/// deliberately not used — the item is added through the file picker, which
/// yields a path, and `g_desktop_app_info_new` cannot resolve a `.desktop`
/// living outside `XDG_DATA_DIRS`.
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

/// Geometry and behaviour of the desktop icon grid.
///
/// Column and row counts are *derived* from each monitor's usable area rather
/// than configured, so one item list renders sanely on monitors of different
/// sizes. See `computeGridGeometry` in `lib/desktop/desktop_layout.dart`.
class DesktopConfig {
  /// Whether the grid is drawn at all. Restart-only: it decides whether the
  /// native background surface is created (see `ConfigStore._restartSignature`).
  final bool enabled;

  final double cellWidth;
  final double cellHeight;
  final double spacing;

  /// Inset from the usable area's edges, on top of the panel exclusive zones.
  final double padding;

  final double iconSize;
  final bool showLabels;

  final List<DesktopItem> items;

  const DesktopConfig({
    this.enabled = false,
    this.cellWidth = 96,
    this.cellHeight = 96,
    this.spacing = 12,
    this.padding = 24,
    this.iconSize = 48,
    this.showLabels = true,
    this.items = const [],
  });

  factory DesktopConfig.fromMap(Map<String, dynamic> map) {
    // Document order is preserved; cells, not list position, decide layout.
    final items = map
        .tableListOr('items')
        .map(DesktopItem.fromMap)
        .whereType<DesktopItem>()
        .toList();

    return DesktopConfig(
      enabled: map.boolOr('enabled', false),
      // A cell smaller than its icon would clip; floors keep a hand-edited
      // config from producing an unusable grid rather than rejecting it.
      cellWidth: map.doubleOr('cell_width', 96, min: 32),
      cellHeight: map.doubleOr('cell_height', 96, min: 32),
      spacing: map.doubleOr('spacing', 12, min: 0),
      padding: map.doubleOr('padding', 24, min: 0),
      iconSize: map.doubleOr('icon_size', 48, min: 8),
      showLabels: map.boolOr('show_labels', true),
      items: items,
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
          listEquals(other.items, items);

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
      );
}
