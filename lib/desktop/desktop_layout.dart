// Pure geometry for the desktop icon grid.
//
// Everything here is a function of its arguments: no BuildContext, no disk, no
// GIO. That is deliberate and it is what `test/desktop_layout_test.dart` points
// at — the interaction code in `desktop_grid.dart` is hard to test, so as much
// of the behaviour as possible is pushed down here where it is not.

import 'dart:math' as math;
import 'dart:ui';

// painting.dart, not widgets.dart: EdgeInsets/Size/Offset/Rect and nothing that
// needs a BuildContext or an engine, so this file stays a pure-logic unit.
import 'package:flutter/painting.dart' show EdgeInsets;

import 'package:graceful_shell/config.dart';

/// A cell address in the grid. A record rather than a class so it has value
/// equality for free, which is what makes `Set<GridCell>` an occupancy test.
typedef GridCell = ({int column, int row});

/// The resolved grid for one surface.
///
/// [columns] and [rows] are *derived*, never configured: the same item list is
/// rendered on every monitor, and a monitor-independent column count would put
/// icons off the edge of the smaller one.
class DesktopGridGeometry {
  const DesktopGridGeometry({
    required this.columns,
    required this.rows,
    required this.cellSize,
    required this.spacing,
    required this.origin,
  });

  final int columns;
  final int rows;
  final Size cellSize;
  final double spacing;

  /// Top-left of cell (0, 0), in surface-local coordinates.
  final Offset origin;

  int get capacity => columns * rows;

  /// The pitch between two adjacent cells' left (or top) edges.
  double get columnPitch => cellSize.width + spacing;
  double get rowPitch => cellSize.height + spacing;

  Rect cellRect(int column, int row) => Rect.fromLTWH(
        origin.dx + column * columnPitch,
        origin.dy + row * rowPitch,
        cellSize.width,
        cellSize.height,
      );

  bool contains(GridCell cell) =>
      cell.column >= 0 &&
      cell.row >= 0 &&
      cell.column < columns &&
      cell.row < rows;

  @override
  bool operator ==(Object other) =>
      other is DesktopGridGeometry &&
      other.columns == columns &&
      other.rows == rows &&
      other.cellSize == cellSize &&
      other.spacing == spacing &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(columns, rows, cellSize, spacing, origin);
}

/// The area of a full-output surface that is not covered by a panel.
///
/// The background surface calls `spanFullOutput` (exclusive zone −1), so it
/// reaches *under* the bars — an icon placed there would simply be hidden. Each
/// panel contributes its thickness plus the theme's [panelMargin] to the edge
/// its anchor names, because per wlr-layer-shell the exclusive zone includes the
/// margin (see `setPanelMargin` in `lib/popup.dart`).
///
/// Two panels anchored to the same edge stack, so their insets add.
EdgeInsets panelInsetsFor(Map<String, PanelConfig> panels, int panelMargin) {
  var top = 0.0;
  var bottom = 0.0;
  var left = 0.0;
  var right = 0.0;
  for (final panel in panels.values) {
    final thickness = (panel.height + panelMargin).toDouble();
    switch (panel.anchor) {
      case 'bottom':
        bottom += thickness;
      case 'left':
        left += thickness;
      case 'right':
        right += thickness;
      default: // 'top'
        top += thickness;
    }
  }
  return EdgeInsets.fromLTRB(left, top, right, bottom);
}

/// Derives the grid for a [surface] of the given size, inset by [insets].
///
/// Always yields at least one column and one row: a grid with no cells has no
/// valid drop target, and every placement helper would return null forever.
DesktopGridGeometry computeGridGeometry(
  Size surface,
  DesktopConfig config, {
  EdgeInsets insets = EdgeInsets.zero,
}) {
  final usableWidth = surface.width - insets.horizontal - 2 * config.padding;
  final usableHeight = surface.height - insets.vertical - 2 * config.padding;

  final columnPitch = config.cellWidth + config.spacing;
  final rowPitch = config.cellHeight + config.spacing;

  // The trailing cell needs no spacing after it, hence the `+ spacing` before
  // the division: N cells occupy N*pitch - spacing.
  final columns =
      math.max(1, ((usableWidth + config.spacing) / columnPitch).floor());
  final rows = math.max(1, ((usableHeight + config.spacing) / rowPitch).floor());

  return DesktopGridGeometry(
    columns: columns,
    rows: rows,
    cellSize: Size(config.cellWidth, config.cellHeight),
    spacing: config.spacing,
    origin: Offset(insets.left + config.padding, insets.top + config.padding),
  );
}

/// The cell containing [point], or null when it is outside the grid or in the
/// gutter between cells. Use [nearestCell] for a drop, which must always land
/// somewhere.
GridCell? cellAt(DesktopGridGeometry g, Offset point) {
  final cell = _unclampedCell(g, point);
  if (!g.contains(cell)) return null;
  return g.cellRect(cell.column, cell.row).contains(point) ? cell : null;
}

/// The cell nearest [point], clamped into range. What a drop resolves to, so it
/// is total: every point on the surface has an answer, including points in a
/// gutter or beyond an edge.
GridCell nearestCell(DesktopGridGeometry g, Offset point) {
  final cell = _unclampedCell(g, point);
  return (
    column: cell.column.clamp(0, g.columns - 1),
    row: cell.row.clamp(0, g.rows - 1),
  );
}

/// The cell [point] falls in if the grid extended infinitely in all directions.
GridCell _unclampedCell(DesktopGridGeometry g, Offset point) {
  final dx = point.dx - g.origin.dx;
  final dy = point.dy - g.origin.dy;
  return (
    column: (dx / g.columnPitch).floor(),
    row: (dy / g.rowPitch).floor(),
  );
}

/// The first unoccupied cell in column-major order, or null when the grid is
/// full. Column-major because icons flow down a column then across, which is
/// what every desktop does.
GridCell? firstFreeCell(DesktopGridGeometry g, Set<GridCell> occupied) {
  for (var column = 0; column < g.columns; column++) {
    for (var row = 0; row < g.rows; row++) {
      final cell = (column: column, row: row);
      if (!occupied.contains(cell)) return cell;
    }
  }
  return null;
}

/// The free cell closest to [preferred], or null when the grid is full.
///
/// Distance is measured in cells, and ties break column-major so the result is
/// deterministic — an "add here" that jumped around between identical calls
/// would be maddening.
GridCell? nearestFreeCell(
  DesktopGridGeometry g,
  Set<GridCell> occupied,
  GridCell preferred,
) {
  if (g.contains(preferred) && !occupied.contains(preferred)) return preferred;

  GridCell? best;
  var bestDistance = double.infinity;
  for (var column = 0; column < g.columns; column++) {
    for (var row = 0; row < g.rows; row++) {
      final cell = (column: column, row: row);
      if (occupied.contains(cell)) continue;
      final dc = (column - preferred.column).toDouble();
      final dr = (row - preferred.row).toDouble();
      final distance = dc * dc + dr * dr;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = cell;
      }
    }
  }
  return best;
}

/// The cells [items] currently occupy.
Set<GridCell> occupiedCells(List<DesktopItem> items, {String? ignoreTarget}) {
  return {
    for (final item in items)
      if (item.target != ignoreTarget) (column: item.column, row: item.row),
  };
}

/// Moves [target] to [cell], **swapping** with whatever is already there.
///
/// Returns the input list unchanged (the identical instance) when there is
/// nothing to do — an unknown target, or a move to the cell it already
/// occupies. Callers use that to skip a config write, so a drag that ends where
/// it started costs nothing.
List<DesktopItem> moveItemTo(
  List<DesktopItem> items,
  String target,
  GridCell cell,
) {
  final index = items.indexWhere((item) => item.target == target);
  if (index < 0) return items;

  final moving = items[index];
  if (moving.column == cell.column && moving.row == cell.row) return items;

  final occupantIndex = items.indexWhere(
    (item) =>
        item.target != target &&
        item.column == cell.column &&
        item.row == cell.row,
  );

  final next = List<DesktopItem>.of(items);
  next[index] = moving.copyWith(column: cell.column, row: cell.row);
  if (occupantIndex >= 0) {
    // The swap: the displaced item takes the mover's old cell, so no item is
    // ever silently stacked on top of another.
    next[occupantIndex] = items[occupantIndex]
        .copyWith(column: moving.column, row: moving.row);
  }
  return next;
}

/// Appends [item] at its own cell if that is free, else at the nearest free
/// cell. Never displaces an existing item; returns the list unchanged when the
/// target is already pinned or the grid is full.
List<DesktopItem> placeItem(
  List<DesktopItem> items,
  DesktopItem item,
  DesktopGridGeometry g,
) {
  if (items.any((existing) => existing.target == item.target)) return items;

  final free = nearestFreeCell(
    g,
    occupiedCells(items),
    (column: item.column, row: item.row),
  );
  if (free == null) return items;

  return [...items, item.copyWith(column: free.column, row: free.row)];
}

/// Re-seats every item into sequential column-major cells, preserving current
/// reading order (column-major by cell, then document order as the tie-break).
///
/// Idempotent: organizing an already-organized grid is a no-op, which is what
/// lets the caller compare and skip the write.
List<DesktopItem> organizeItems(
  List<DesktopItem> items,
  DesktopGridGeometry g,
) {
  final ordered = List<DesktopItem>.of(items);
  // Stable by construction: List.sort is not stable, so the original index is
  // the final tie-break rather than relying on it.
  final indexOf = <String, int>{
    for (var i = 0; i < items.length; i++) items[i].target: i,
  };
  ordered.sort((a, b) {
    final byColumn = a.column.compareTo(b.column);
    if (byColumn != 0) return byColumn;
    final byRow = a.row.compareTo(b.row);
    if (byRow != 0) return byRow;
    return indexOf[a.target]!.compareTo(indexOf[b.target]!);
  });

  final result = <DesktopItem>[];
  for (var i = 0; i < ordered.length; i++) {
    // Items past capacity keep flowing into further rows rather than being
    // dropped — losing a pinned icon to a window resize would be unforgivable.
    final column = g.rows > 0 ? i ~/ g.rows : 0;
    final row = g.rows > 0 ? i % g.rows : 0;
    result.add(ordered[i].copyWith(column: column, row: row));
  }
  return result;
}

/// Pulls items whose authored cell lies outside [g] into free cells, for
/// rendering only.
///
/// A grid arranged on a 4K monitor has cells a 1080p monitor does not, and the
/// same item list is rendered on both. The result is **never persisted**: the
/// authored cell survives in the config, so plugging the big monitor back in
/// restores the layout exactly.
List<DesktopItem> reflowIntoGrid(
  List<DesktopItem> items,
  DesktopGridGeometry g,
) {
  final inRange = <DesktopItem>[];
  final strays = <DesktopItem>[];
  for (final item in items) {
    if (g.contains((column: item.column, row: item.row))) {
      inRange.add(item);
    } else {
      strays.add(item);
    }
  }
  if (strays.isEmpty) return items;

  final occupied = occupiedCells(inRange);
  final result = List<DesktopItem>.of(inRange);
  for (final stray in strays) {
    final free = firstFreeCell(g, occupied);
    // Full grid: leave the stray where it is. It renders clipped rather than
    // vanishing, which is at least visible evidence of what happened.
    if (free == null) {
      result.add(stray);
      continue;
    }
    occupied.add(free);
    result.add(stray.copyWith(column: free.column, row: free.row));
  }
  return result;
}
