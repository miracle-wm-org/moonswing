// The `[keyboard]` section: the user's ordered list of input sources.
//
// Beside its feature the way `power/power_config.dart` sits beside the power
// menu, and re-exported from `config.dart`.
//
// Deliberately *not* a field of `AppConfig`. Nothing above `runWidget` needs it
// and no `main()` wiring pushes it anywhere, so putting it in would force
// `KeyboardStore` either to read `ConfigStore.appConfig`, which re-runs
// `Module.loadAll` on every keystroke in the settings UI, or to parse the same
// table twice.

import 'package:flutter/foundation.dart';

import 'package:moonswing/config_reader.dart';

/// One xkb layout, optionally narrowed to a variant.
///
/// The identity of a source is the *pair*: `de` and `de+nodeadkeys` are two rows
/// in the user's list, and a variant code is not unique on its own — `nativo`
/// exists under both `pt` and `br`.
@immutable
class InputSource {
  const InputSource(this.layout, {this.variant = ''});

  /// An xkb layout code: `us`, `de`, `latam`, `ara`.
  final String layout;

  /// An xkb variant code, or empty for the layout's default variant.
  final String variant;

  bool get hasVariant => variant.isNotEmpty;

  /// The xkb spelling of the pair — `us`, `br+nativo`. What the settings page
  /// shows as a source's trailing code, and what the free-form adder accepts.
  String get id => hasVariant ? '$layout+$variant' : layout;

  /// Parses [id]'s spelling back. Returns null when there is no layout, which
  /// is the only part with no honest default.
  static InputSource? parseId(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    final plus = trimmed.indexOf('+');
    if (plus < 0) return InputSource(trimmed);
    final layout = trimmed.substring(0, plus).trim();
    if (layout.isEmpty) return null;
    return InputSource(layout, variant: trimmed.substring(plus + 1).trim());
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'layout': layout,
    if (hasVariant) 'variant': variant,
  };

  @override
  bool operator ==(Object other) =>
      other is InputSource && other.layout == layout && other.variant == variant;

  @override
  int get hashCode => Object.hash(layout, variant);

  @override
  String toString() => 'InputSource($id)';
}

/// `[keyboard]` — the ordered input sources and nothing else, for now.
@immutable
class KeyboardConfig {
  const KeyboardConfig({this.sources = const []});

  /// The user's sources, in the order the popup and the settings page show
  /// them. Empty is a legitimate state: the user removed everything.
  final List<InputSource> sources;

  factory KeyboardConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const KeyboardConfig();
    return KeyboardConfig(sources: parseSources(map.tableListOr('sources')));
  }

  /// The `[[keyboard.sources]]` tables, as sources.
  ///
  /// A table with no `layout` is **dropped** rather than defaulted — there is no
  /// honest default for "which keyboard" — and an exact duplicate is collapsed,
  /// the `[[desktop.widgets]]` id-uniquing precedent: two identical sources would
  /// activate together and remove together.
  static List<InputSource> parseSources(List<Map<String, dynamic>> tables) {
    final seen = <InputSource>{};
    final sources = <InputSource>[];
    for (final table in tables) {
      final layout = table.stringOrNull('layout');
      if (layout == null) continue;
      final source = InputSource(
        layout,
        variant: table.stringOr('variant', '').trim(),
      );
      if (!seen.add(source)) continue;
      sources.add(source);
    }
    return sources;
  }

  @override
  bool operator ==(Object other) =>
      other is KeyboardConfig && listEquals(other.sources, sources);

  @override
  int get hashCode => Object.hashAll(sources);
}
