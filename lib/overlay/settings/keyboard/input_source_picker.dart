// "Add Input Source" — the picker behind the Keyboard page's add button.
//
// Beside its page the way `settings/shell/weather_location.dart` sits beside
// `settings/shell.dart`: it carries its own ranking and its own degradation, and
// is not a value editor.

import 'package:flutter/widgets.dart';

import 'package:graceful_shell/keyboard/keyboard_config.dart';
import 'package:graceful_shell/keyboard/keyboard_sources.dart';
import 'package:graceful_shell/keyboard/xkb_catalog.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/search_list.dart';
import 'package:graceful_shell/theme/tokens.dart';

class InputSourcePicker extends StatefulWidget {
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

  @override
  State<InputSourcePicker> createState() => _InputSourcePickerState();
}

class _InputSourcePickerState extends State<InputSourcePicker> {
  /// Whether the free-form field is showing. Only ever reachable on the
  /// degraded path — with a catalogue there is a dropdown instead.
  bool _composing = false;
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    final source = InputSource.parseId(raw);
    if (source == null) return;
    widget.onSelected(source);
    _controller.clear();
    setState(() => _composing = false);
  }

  @override
  Widget build(BuildContext context) {
    // Degrades rather than locks out — `SettingsFontField`'s rule. With no
    // `xkb-data` on the machine the catalogue is empty, and `[keyboard]` must
    // never become a key the UI can no longer set. The trade is that nothing
    // validates what is typed here; see CONFIG.md.
    if (widget.catalog.entries.isEmpty) return _buildFreeForm(context);

    return AnchoredSearchDropdown<XkbEntry>(
      // Right-aligned rather than trigger-width: the button is a compact
      // action on the section's heading row, and a card sized to it could not
      // hold "Portuguese (Brazil, Nativo for US keyboards)".
      alignRight: true,
      width: 360,
      maxHeight: 320,
      rowHeight: 34,
      emptyText: 'No matching layout',
      // Synchronous: the entries are already in memory, so a debounce would
      // only add latency to a ranking that costs nothing.
      filter: (query) => rankXkbEntries(widget.catalog.entries, query),
      onSelected: (entry) {
        if (widget.existing.contains(entry.source)) return;
        widget.onSelected(entry.source);
      },
      itemBuilder: (context, entry, highlighted) {
        final theme = ThemeScope.of(context);
        final added = widget.existing.contains(entry.source);
        final alpha = added ? 0.4 : 1.0;
        return Row(
          children: [
            Expanded(
              child: Text(
                entry.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground.withValues(alpha: alpha),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              added ? 'added' : entry.source.id,
              style: TextStyle(
                fontSize: ShellFontSizes.caption,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.5),
              ),
            ),
          ],
        );
      },
      triggerBuilder: (context, open, toggle) =>
          SettingsAddButton(label: 'Add Input Source', onTap: toggle),
    );
  }

  Widget _buildFreeForm(BuildContext context) {
    final button = SettingsAddButton(
      label: 'Add Input Source',
      onTap: () {
        setState(() => _composing = !_composing);
        if (_composing) _focus.requestFocus();
      },
    );
    if (!_composing) return button;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsTextField(
          controller: _controller,
          focusNode: _focus,
          width: 160,
          hint: 'us or br+nativo',
          onChanged: (_) {},
          onSubmitted: _submit,
        ),
        const SizedBox(width: 8),
        button,
      ],
    );
  }
}
