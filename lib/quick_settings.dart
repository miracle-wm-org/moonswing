// What a right-click menu offers to change in place: the handful of a module's
// or desktop widget's options worth flipping without opening the settings
// overlay.
//
// Plain data, so `module.dart` and the desktop widget registry can declare them
// without importing a widget, and so the rows the menus build from them
// (`context_menus.dart`) are the one place they are drawn.

import 'package:flutter/foundation.dart';

import 'package:moonswing/icons/shell_glyph.dart';

/// One row (or, for a [QuickChoice], one small group of rows) of a context
/// menu's quick settings.
sealed class QuickSetting {
  const QuickSetting({required this.label});

  /// What the row says, the settings page's own label for the key.
  final String label;
}

/// A boolean config key, flipped by a tap on its row. The menu stays open so
/// several can be flipped in one visit.
class QuickToggle extends QuickSetting {
  const QuickToggle({
    required super.label,
    required this.path,
    required this.defaultValue,
  });

  /// The config path the row writes, `['modules', 'clock', 'show_date']`.
  final List<String> path;

  /// What the module reads when `config.toml` has no value — the settings
  /// page's own fallback, so the menu and the page cannot disagree.
  final bool defaultValue;
}

/// A config key with a short fixed set of values, drawn as a heading over one
/// checkable row per option. The menu stays open.
class QuickChoice extends QuickSetting {
  const QuickChoice({
    required super.label,
    required this.path,
    required this.options,
    required this.defaultValue,
    this.labelOf,
  });

  final List<String> path;
  final List<String> options;
  final String defaultValue;

  /// An option's name as a person reads it; null capitalises the config
  /// spelling.
  final String Function(String option)? labelOf;

  String optionLabel(String option) {
    final named = labelOf?.call(option);
    if (named != null) return named;
    if (option.isEmpty) return option;
    return '${option[0].toUpperCase()}${option.substring(1)}';
  }
}

/// Something that is not a config key — the notification bell's silence, a
/// news outlet in a list — answered by the code that owns it.
///
/// With [checked] it is a switch: drawn on or off, flipped by [onTap], and the
/// menu stays open and follows [listenable]. Without it, it is an action, and
/// the menu closes once [onTap] has run.
class QuickAction extends QuickSetting {
  const QuickAction({
    required super.label,
    required this.onTap,
    this.icon,
    this.checked,
    this.listenable,
  });

  final VoidCallback onTap;
  final ShellGlyph? icon;

  /// Whether the switch is on, read every time the row builds. Null makes the
  /// row an action rather than a switch.
  final bool Function()? checked;

  /// What says [checked] may have moved. Null for a switch whose state only
  /// this row's own tap can change.
  final Listenable? listenable;

  bool get isSwitch => checked != null;
}
