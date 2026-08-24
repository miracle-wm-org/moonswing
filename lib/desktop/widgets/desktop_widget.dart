// The desktop widget registry: what kinds of widget exist, how big each may be,
// and what each one draws.
//
// This is `lib/module.dart` for the desktop what `Module` is for the bar, and
// deliberately the same shape — a registry keyed by a config string, populated
// from `main()` before any config is read, looked up at render time. The two
// are separate registries because a bar module and a desktop widget answer
// different questions: a module is a strip of a panel sized by its content, a
// widget is a rectangle of grid cells the user resizes.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/desktop_layout.dart';

/// What a widget's [DesktopWidgetSpec.builder] is handed.
///
/// A class rather than three positional parameters so a widget that later needs
/// its stored options, or a way to write them back, gains them here without
/// every existing builder changing shape.
class DesktopWidgetContext {
  const DesktopWidgetContext({
    required this.item,
    required this.size,
    required this.span,
  });

  /// The persisted entry, including its `options` table.
  final DesktopWidgetItem item;

  /// The pixel size the widget is being drawn at. Passed rather than left to a
  /// `LayoutBuilder` inside every widget: most of them want to switch layout on
  /// their *span* and only glance at the pixels.
  final Size size;

  /// The widget's size in cells, already clamped to the spec's limits.
  final GridSpan span;

  /// Whether the widget is at least [columns] wide and [rows] tall — the test a
  /// responsive widget writes instead of comparing pixel widths.
  bool atLeast(int columns, int rows) =>
      span.columns >= columns && span.rows >= rows;
}

/// Everything the desktop grid knows about one kind of widget.
///
/// The size limits are the spec's, not the item's: a widget type decides what
/// it can usefully render in, and a config authored before those limits changed
/// is clamped at render time rather than rewritten (see [spanFor]).
class DesktopWidgetSpec {
  const DesktopWidgetSpec({
    required this.type,
    required this.name,
    required this.icon,
    required this.builder,
    this.description = '',
    this.minSpan = (columns: 1, rows: 1),
    this.maxSpan = (columns: 6, rows: 4),
    GridSpan? defaultSpan,
  }) : _defaultSpan = defaultSpan;

  /// The `[[desktop.widgets]] type` value. Stable forever once shipped — it is
  /// what a user's config names.
  final String type;

  /// What the "Add widget…" menu calls it.
  final String name;

  /// One line under the name in that menu.
  final String description;

  final FaIconData icon;

  /// The smallest and largest span the user may resize this widget to.
  final GridSpan minSpan;
  final GridSpan maxSpan;

  final GridSpan? _defaultSpan;

  /// The span a freshly added widget takes. Its minimum unless the spec says
  /// otherwise — a widget that needs more room than its floor to look right on
  /// first sight says so.
  GridSpan get defaultSpan => _defaultSpan ?? minSpan;

  final Widget Function(BuildContext context, DesktopWidgetContext widget)
      builder;
}

/// The process-wide registry, populated from `main()`.
///
/// [Module]'s registry is a `Map` on the class for exactly this reason: the
/// widget types are compiled in, the config only names them, and a name the
/// build does not know has to degrade rather than throw — see
/// `DesktopWidgetFrame`, which renders an unknown type as a placeholder instead
/// of dropping the entry from the user's config.
abstract final class DesktopWidgetRegistry {
  static final Map<String, DesktopWidgetSpec> _specs = {};

  /// Registers [spec]. Called before `AppConfig.load()`, like `Module.register`.
  static void register(DesktopWidgetSpec spec) => _specs[spec.type] = spec;

  static DesktopWidgetSpec? lookup(String type) => _specs[type];

  /// Every registered spec, in registration order — what the "Add widget…"
  /// menu lists.
  static List<DesktopWidgetSpec> get all => List.unmodifiable(_specs.values);

  /// Empties the registry. Tests only: the registry is global, and a test that
  /// registered a fake would otherwise leak it into the next one.
  @visibleForTesting
  static void clear() => _specs.clear();
}

/// [item]'s span, clamped to what [spec] allows.
///
/// A null [spec] (an unknown type) is left exactly as authored: the placeholder
/// has to occupy the cells the config says it does, or removing it would leave
/// a hole somewhere else.
GridSpan spanFor(DesktopWidgetSpec? spec, DesktopWidgetItem item) {
  if (spec == null) return (columns: item.columnSpan, rows: item.rowSpan);
  return (
    columns: item.columnSpan.clamp(spec.minSpan.columns, spec.maxSpan.columns),
    rows: item.rowSpan.clamp(spec.minSpan.rows, spec.maxSpan.rows),
  );
}

/// The area [item] renders at, with its span clamped to [spec].
GridArea renderAreaFor(DesktopWidgetSpec? spec, DesktopWidgetItem item) {
  final span = spanFor(spec, item);
  return (
    column: item.column,
    row: item.row,
    columnSpan: span.columns,
    rowSpan: span.rows,
  );
}

/// A new instance of [spec] at [cell], with an id not already taken by
/// [existing].
DesktopWidgetItem newWidgetItem(
  DesktopWidgetSpec spec,
  GridCell cell,
  Iterable<DesktopWidgetItem> existing,
) {
  return DesktopWidgetItem(
    id: nextDesktopWidgetId(existing, spec.type),
    type: spec.type,
    column: cell.column,
    row: cell.row,
    columnSpan: spec.defaultSpan.columns,
    rowSpan: spec.defaultSpan.rows,
  );
}
