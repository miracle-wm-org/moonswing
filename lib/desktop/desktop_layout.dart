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

/// A rectangle of cells: where a desktop *widget* sits. Also a record, for
/// [GridCell]'s reason — value equality, and no class to keep in step.
typedef GridArea = ({int column, int row, int columnSpan, int rowSpan});

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

  /// The pixel rect a whole [GridArea] covers.
  ///
  /// The spanned gutters are *inside* the rect: a 2x1 widget is two cells wide
  /// plus the one gap between them, so a widget reads as one surface rather
  /// than as two tiles that happen to touch.
  Rect areaRect(GridArea area) => Rect.fromLTWH(
        origin.dx + area.column * columnPitch,
        origin.dy + area.row * rowPitch,
        area.columnSpan * cellSize.width + (area.columnSpan - 1) * spacing,
        area.rowSpan * cellSize.height + (area.rowSpan - 1) * spacing,
      );

  /// Whether every cell of [area] is inside the grid.
  bool containsArea(GridArea area) =>
      area.column >= 0 &&
      area.row >= 0 &&
      area.columnSpan >= 1 &&
      area.rowSpan >= 1 &&
      area.column + area.columnSpan <= columns &&
      area.row + area.rowSpan <= rows;

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
  GridCell cell, {
  Set<GridCell> blocked = const {},
}) {
  // A drop onto a widget is refused outright rather than redirected to a free
  // cell nearby: the icon snapping back where it came from says "not there",
  // while an icon that reappears two cells away looks like a bug in the drop.
  if (blocked.contains(cell)) return items;

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

/// The targets whose cell overlaps [rect], which is in the same surface-local
/// pixel space as [DesktopGridGeometry.cellRect].
///
/// [items] must be the list the grid is *rendering* — the output of
/// [reflowIntoGrid] — so a selection band picks what the user can see rather
/// than what the config authored.
///
/// Overlap is [Rect.overlaps], which is strict: a band whose edge exactly
/// touches a cell does not select it, and a band that has not moved (a zero-area
/// rect) selects nothing. That last one is what lets a plain click on bare
/// desktop still clear the selection.
Set<String> targetsInRect(
  List<DesktopItem> items,
  DesktopGridGeometry g,
  Rect rect,
) {
  if (rect.isEmpty) return const {};
  return {
    for (final item in items)
      if (g.cellRect(item.column, item.row).overlaps(rect)) item.target,
  };
}

/// Translates every item in [targets] by ([dColumn], [dRow]).
///
/// The delta is clamped so the whole group stays inside [g]: a group dragged
/// past an edge slides along it rather than losing its shape or losing members
/// off the grid.
///
/// Non-selected items standing in the group's destination cells are displaced,
/// preferring the cells the group **vacated** — which is what makes a one-item
/// group behave exactly like [moveItemTo]'s swap — and falling back to
/// [nearestFreeCell] otherwise. A displaced item with nowhere to go is left
/// where it is rather than silently stacked.
///
/// Returns the identical list when there is nothing to do, so a group drag that
/// ends where it started costs no config write. Note this resolves against
/// whatever list it is given while the caller measured the delta against the
/// rendered one; they differ only for items [reflowIntoGrid] pulled in, which is
/// the same split [moveItemTo] already has.
List<DesktopItem> moveItemsBy(
  List<DesktopItem> items,
  Set<String> targets,
  int dColumn,
  int dRow,
  DesktopGridGeometry g, {
  Set<GridCell> blocked = const {},
}) {
  final moving = [
    for (final item in items)
      if (targets.contains(item.target)) item,
  ];
  if (moving.isEmpty) return items;

  var minColumn = moving.first.column;
  var maxColumn = moving.first.column;
  var minRow = moving.first.row;
  var maxRow = moving.first.row;
  for (final item in moving) {
    minColumn = math.min(minColumn, item.column);
    maxColumn = math.max(maxColumn, item.column);
    minRow = math.min(minRow, item.row);
    maxRow = math.max(maxRow, item.row);
  }
  final dc = _clampDelta(dColumn, -minColumn, g.columns - 1 - maxColumn);
  final dr = _clampDelta(dRow, -minRow, g.rows - 1 - maxRow);
  if (dc == 0 && dr == 0) return items;

  final destinations = <String, GridCell>{
    for (final item in moving)
      item.target: (column: item.column + dc, row: item.row + dr),
  };
  // A group landing on a widget is refused whole, [moveItemTo]'s rule: moving
  // the members that fit and leaving the rest behind would silently break the
  // arrangement the user was preserving by dragging them together.
  if (destinations.values.any(blocked.contains)) return items;

  final taken = destinations.values.toSet()..addAll(blocked);
  final vacated = {
    for (final item in moving) (column: item.column, row: item.row),
  }.difference(taken);

  // First pass: move the group, and note which bystanders it landed on. Their
  // cells are left alone for now so the second pass can see what is free.
  final next = List<DesktopItem>.of(items);
  final displaced = <int>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final destination = destinations[item.target];
    if (destination != null) {
      next[i] = item.copyWith(
        column: destination.column,
        row: destination.row,
      );
      continue;
    }
    final cell = (column: item.column, row: item.row);
    if (taken.contains(cell)) {
      displaced.add(i);
      continue;
    }
    taken.add(cell);
  }

  final free = vacated.difference(taken);
  for (final index in displaced) {
    final item = items[index];
    final from = (column: item.column, row: item.row);
    final cell = _nearestOf(free, from) ?? nearestFreeCell(g, taken, from);
    // Nowhere left: leave it where it was. Stacking it under a group member
    // would lose it entirely.
    if (cell == null) continue;
    free.remove(cell);
    taken.add(cell);
    next[index] = item.copyWith(column: cell.column, row: cell.row);
  }
  return next;
}

/// Clamps a group delta, tolerating a range that has inverted — which happens
/// when a member is already outside the grid, and must not throw from
/// [num.clamp].
int _clampDelta(int delta, int lower, int upper) =>
    upper < lower ? 0 : delta.clamp(lower, upper);

/// The member of [candidates] closest to [preferred], ties broken column-major
/// so the result does not depend on set iteration order.
GridCell? _nearestOf(Set<GridCell> candidates, GridCell preferred) {
  GridCell? best;
  var bestDistance = double.infinity;
  for (final cell in candidates) {
    final dc = (cell.column - preferred.column).toDouble();
    final dr = (cell.row - preferred.row).toDouble();
    final distance = dc * dc + dr * dr;
    if (distance > bestDistance) continue;
    if (distance == bestDistance && best != null) {
      if (cell.column > best.column) continue;
      if (cell.column == best.column && cell.row > best.row) continue;
    }
    bestDistance = distance;
    best = cell;
  }
  return best;
}

/// Appends [item] at its own cell if that is free, else at the nearest free
/// cell. Never displaces an existing item; returns the list unchanged when the
/// target is already pinned or the grid is full.
List<DesktopItem> placeItem(
  List<DesktopItem> items,
  DesktopItem item,
  DesktopGridGeometry g, {
  Set<GridCell> blocked = const {},
}) {
  if (items.any((existing) => existing.target == item.target)) return items;

  final free = nearestFreeCell(
    g,
    occupiedCells(items)..addAll(blocked),
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
  DesktopGridGeometry g, {
  Set<GridCell> blocked = const {},
}) {
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

  // The flow steps over cells a widget owns rather than stacking under one:
  // organize is what the user reaches for to *tidy*, and a compaction that
  // buried three icons behind the media player would be the opposite.
  final result = <DesktopItem>[];
  var cursor = 0;
  for (final item in ordered) {
    var column = g.rows > 0 ? cursor ~/ g.rows : 0;
    var row = g.rows > 0 ? cursor % g.rows : 0;
    // Items past capacity keep flowing into further rows rather than being
    // dropped — losing a pinned icon to a window resize would be unforgivable.
    // Past capacity there are no widgets either, so this terminates.
    while (blocked.contains((column: column, row: row))) {
      cursor++;
      column = g.rows > 0 ? cursor ~/ g.rows : 0;
      row = g.rows > 0 ? cursor % g.rows : 0;
    }
    cursor++;
    result.add(item.copyWith(column: column, row: row));
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
  DesktopGridGeometry g, {
  Set<GridCell> blocked = const {},
}) {
  final inRange = <DesktopItem>[];
  final strays = <DesktopItem>[];
  for (final item in items) {
    final cell = (column: item.column, row: item.row);
    // A cell a widget covers is "out of range" for the same reason a cell past
    // the last column is: the icon would be there but the user could neither
    // see nor click it. This is what a widget reflowed onto a smaller monitor
    // does to the icons it lands on, and it is render-only — the config still
    // has the icon where its owner put it.
    if (g.contains(cell) && !blocked.contains(cell)) {
      inRange.add(item);
    } else {
      strays.add(item);
    }
  }
  if (strays.isEmpty) return items;

  final occupied = occupiedCells(inRange)..addAll(blocked);
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

// -----------------------------------------------------------------------------
// Widgets
//
// A widget occupies a rectangle of cells rather than one, is identified by its
// instance id rather than by a path, and — unlike an icon — is never moved by
// [organizeItems]. Everything below is the span-aware twin of the single-cell
// helpers above; the two meet through [widgetCells], which is what an icon
// helper takes as its `blocked` set.
// -----------------------------------------------------------------------------

/// The area [widget] occupies.
GridArea areaOf(DesktopWidgetItem widget) => (
      column: widget.column,
      row: widget.row,
      columnSpan: widget.columnSpan,
      rowSpan: widget.rowSpan,
    );

/// Every cell in [area].
Set<GridCell> cellsOfArea(GridArea area) => {
      for (var c = 0; c < area.columnSpan; c++)
        for (var r = 0; r < area.rowSpan; r++)
          (column: area.column + c, row: area.row + r),
    };

/// The cells [widgets] cover — the `blocked` set every icon helper takes.
///
/// [ignoreId] drops one widget's own cells, which is what makes "may this
/// widget move here?" answerable: a widget always overlaps itself.
Set<GridCell> widgetCells(
  Iterable<DesktopWidgetItem> widgets, {
  String? ignoreId,
}) {
  return {
    for (final widget in widgets)
      if (widget.id != ignoreId) ...cellsOfArea(areaOf(widget)),
  };
}

/// Whether no cell of [area] is in [occupied].
bool areaFree(GridArea area, Set<GridCell> occupied) {
  if (occupied.isEmpty) return true;
  for (final cell in cellsOfArea(area)) {
    if (occupied.contains(cell)) return false;
  }
  return true;
}

/// [area] clamped so it fits inside [g]: the span first (a 3x2 widget cannot
/// fit a 2x2 grid), then the origin.
///
/// Total, like [nearestCell]: every area has an answer, because the alternative
/// on a small monitor is a widget that renders nowhere.
GridArea clampAreaInto(GridArea area, DesktopGridGeometry g) {
  final columnSpan = area.columnSpan.clamp(1, g.columns);
  final rowSpan = area.rowSpan.clamp(1, g.rows);
  return (
    column: area.column.clamp(0, g.columns - columnSpan),
    row: area.row.clamp(0, g.rows - rowSpan),
    columnSpan: columnSpan,
    rowSpan: rowSpan,
  );
}

/// The placement of [area]'s size nearest [area]'s own origin that overlaps
/// nothing in [occupied], or null when the grid has no room for it at all.
///
/// [nearestFreeCell]'s contract, one dimension up: distance is measured in
/// cells between origins and ties break column-major, so "add a widget here"
/// is deterministic.
GridArea? nearestFreeArea(
  GridArea area,
  DesktopGridGeometry g,
  Set<GridCell> occupied,
) {
  final wanted = clampAreaInto(area, g);
  if (areaFree(wanted, occupied)) return wanted;

  GridArea? best;
  var bestDistance = double.infinity;
  for (var column = 0; column <= g.columns - wanted.columnSpan; column++) {
    for (var row = 0; row <= g.rows - wanted.rowSpan; row++) {
      final candidate = (
        column: column,
        row: row,
        columnSpan: wanted.columnSpan,
        rowSpan: wanted.rowSpan,
      );
      if (!areaFree(candidate, occupied)) continue;
      final dc = (column - wanted.column).toDouble();
      final dr = (row - wanted.row).toDouble();
      final distance = dc * dc + dr * dr;
      if (distance >= bestDistance) continue;
      bestDistance = distance;
      best = candidate;
    }
  }
  return best;
}

/// Adds [widget] at its own area when that is free, else at the nearest free
/// one. Returns the list unchanged when the id is taken or nothing fits.
///
/// Only *other widgets* block a placement, never icons: an icon in the way is
/// displaced by the caller ([displaceItemsFrom]), because a desktop with icons
/// in every visible cell would otherwise refuse to take a widget at all.
List<DesktopWidgetItem> placeWidget(
  List<DesktopWidgetItem> widgets,
  DesktopWidgetItem widget,
  DesktopGridGeometry g,
) {
  if (widgets.any((existing) => existing.id == widget.id)) return widgets;
  final area = nearestFreeArea(areaOf(widget), g, widgetCells(widgets));
  if (area == null) return widgets;
  return [
    ...widgets,
    widget.copyWith(
      column: area.column,
      row: area.row,
      columnSpan: area.columnSpan,
      rowSpan: area.rowSpan,
    ),
  ];
}

/// Moves the widget [id] so its top-left lands on [cell], keeping its span.
///
/// The move is clamped into the grid and **refused** when it would overlap
/// another widget — [moveItemTo]'s rule rather than its swap: two widgets are
/// two different sizes, so there is no exchange of places to make.
List<DesktopWidgetItem> moveWidgetTo(
  List<DesktopWidgetItem> widgets,
  String id,
  GridCell cell,
  DesktopGridGeometry g,
) {
  final index = widgets.indexWhere((widget) => widget.id == id);
  if (index < 0) return widgets;
  final widget = widgets[index];

  final area = clampAreaInto(
    (
      column: cell.column,
      row: cell.row,
      columnSpan: widget.columnSpan,
      rowSpan: widget.rowSpan,
    ),
    g,
  );
  if (area.column == widget.column && area.row == widget.row) return widgets;
  if (!areaFree(area, widgetCells(widgets, ignoreId: id))) return widgets;

  final next = List<DesktopWidgetItem>.of(widgets);
  next[index] = widget.copyWith(column: area.column, row: area.row);
  return next;
}

/// Resizes the widget [id] to [area], which carries both the new span and the
/// new origin — dragging the top-left handle moves the corner as well as the
/// size.
///
/// [minSpan] and [maxSpan] are the type's limits from its
/// `DesktopWidgetSpec`; the area is clamped to them, then into the grid, and
/// refused if it overlaps another widget.
List<DesktopWidgetItem> resizeWidgetTo(
  List<DesktopWidgetItem> widgets,
  String id,
  GridArea area,
  DesktopGridGeometry g, {
  required GridSpan minSpan,
  required GridSpan maxSpan,
}) {
  final index = widgets.indexWhere((widget) => widget.id == id);
  if (index < 0) return widgets;
  final widget = widgets[index];

  final clamped = clampAreaInto(
    (
      column: area.column,
      row: area.row,
      columnSpan: area.columnSpan.clamp(minSpan.columns, maxSpan.columns),
      rowSpan: area.rowSpan.clamp(minSpan.rows, maxSpan.rows),
    ),
    g,
  );
  if (clamped == areaOf(widget)) return widgets;
  if (!areaFree(clamped, widgetCells(widgets, ignoreId: id))) return widgets;

  final next = List<DesktopWidgetItem>.of(widgets);
  next[index] = widget.copyWith(
    column: clamped.column,
    row: clamped.row,
    columnSpan: clamped.columnSpan,
    rowSpan: clamped.rowSpan,
  );
  return next;
}

/// A widget's size in cells. Named rather than a bare record pair so a spec's
/// minimum and maximum cannot be passed the wrong way round unnoticed.
typedef GridSpan = ({int columns, int rows});

/// Pulls widgets whose authored area does not fit [g] into one that does, for
/// **rendering only** — [reflowIntoGrid]'s contract, and for its reason: the
/// same config is rendered on every monitor, and the authored area has to
/// survive unplugging the big one.
///
/// A widget that cannot be fitted at all is left where it is and renders
/// clipped, which is at least visible evidence of what happened.
List<DesktopWidgetItem> reflowWidgetsIntoGrid(
  List<DesktopWidgetItem> widgets,
  DesktopGridGeometry g,
) {
  if (widgets.every((widget) => g.containsArea(areaOf(widget)))) return widgets;

  final result = <DesktopWidgetItem>[];
  final occupied = <GridCell>{};
  for (final widget in widgets) {
    final wanted = areaOf(widget);
    final fits = g.containsArea(wanted) && areaFree(wanted, occupied);
    final area = fits ? wanted : nearestFreeArea(wanted, g, occupied);
    if (area == null) {
      result.add(widget);
      continue;
    }
    occupied.addAll(cellsOfArea(area));
    result.add(widget.copyWith(
      column: area.column,
      row: area.row,
      columnSpan: area.columnSpan,
      rowSpan: area.rowSpan,
    ));
  }
  return result;
}

/// Moves every icon standing in [area] out to the nearest free cell.
///
/// What a widget being added, moved or resized does to the icons underneath it.
/// Widgets take precedence over icons deliberately: an icon has somewhere else
/// to go and its identity is its target, so nothing is lost by shuffling it,
/// while refusing the widget move would leave the user unable to place a widget
/// on a busy desktop at all.
///
/// [blocked] is every cell the widgets will occupy *after* the move, so a
/// displaced icon cannot be pushed under a different widget. An icon with
/// nowhere to go is left where it is — [reflowIntoGrid] then renders it out
/// from under the widget, and the config still has its authored cell.
List<DesktopItem> displaceItemsFrom(
  List<DesktopItem> items,
  GridArea area,
  DesktopGridGeometry g, {
  Set<GridCell> blocked = const {},
}) {
  final cells = cellsOfArea(area);
  final covered = items.any(
    (item) => cells.contains((column: item.column, row: item.row)),
  );
  if (!covered) return items;

  final taken = <GridCell>{...blocked, ...cells};
  final moving = <int>[];
  for (var i = 0; i < items.length; i++) {
    final cell = (column: items[i].column, row: items[i].row);
    if (cells.contains(cell)) {
      moving.add(i);
      continue;
    }
    taken.add(cell);
  }

  final next = List<DesktopItem>.of(items);
  for (final index in moving) {
    final item = items[index];
    final free = nearestFreeCell(
      g,
      taken,
      (column: item.column, row: item.row),
    );
    if (free == null) continue;
    taken.add(free);
    next[index] = item.copyWith(column: free.column, row: free.row);
  }
  return next;
}
