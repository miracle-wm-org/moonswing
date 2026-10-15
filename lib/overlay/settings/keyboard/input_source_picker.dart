// "Add Input Source" — the last row of the Keyboard page's input-source list.
//
// Beside its page the way `settings/shell/weather_location.dart` sits beside
// `settings/shell.dart`: it carries its own ranking and its own degradation, and
// is not a value editor.

import 'package:flutter/widgets.dart';

import 'package:moonswing/keyboard/keyboard_config.dart';
import 'package:moonswing/keyboard/keyboard_sources.dart';
import 'package:moonswing/keyboard/xkb_catalog.dart';
import 'package:moonswing/overlay/settings/controls.dart';

/// The last row of the Input Sources list: a dropdown of every layout xkb
/// knows, or — with no catalogue to offer — a field to type one into.
class InputSourcePicker extends StatelessWidget {
  const InputSourcePicker({
    super.key,
    required this.catalog,
    required this.existing,
    required this.onSelected,
  });

  final XkbCatalog catalog;

  /// Already-added sources. They stay in the list, dimmed and refused on
  /// select: GNOME shows them, and hiding them makes the list change shape
  /// under the user between one visit and the next.
  final List<InputSource> existing;

  final ValueChanged<InputSource> onSelected;

  static const String _label = 'Add Input Source';

  @override
  Widget build(BuildContext context) {
    // Degrades rather than locks out — `SettingsFontField`'s rule. With no
    // `xkb-data` on the machine the catalogue is empty, and `[keyboard]` must
    // never become a key the UI can no longer set. The trade is that nothing
    // validates what is typed here; see CONFIG.md.
    if (catalog.entries.isEmpty) {
      return SettingsListAddField(
        label: _label,
        hint: 'us or br+nativo',
        onSubmitted: (raw) {
          final source = InputSource.parseId(raw);
          if (source != null) onSelected(source);
        },
      );
    }

    return SettingsListAddDropdown<XkbEntry>(
      label: _label,
      options: catalog.entries,
      emptyText: 'No matching layout',
      // Synchronous: the entries are already in memory, so a debounce would
      // only add latency to a ranking that costs nothing.
      filter: (query) => rankXkbEntries(catalog.entries, query),
      labelOf: (entry) => entry.description,
      detailOf: (entry) => entry.source.id,
      isAdded: (entry) => existing.contains(entry.source),
      onSelected: (entry) => onSelected(entry.source),
    );
  }
}
