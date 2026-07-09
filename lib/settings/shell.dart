// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/settings/config_store.dart';

/// Settings page for graceful-shell's own configuration (`config.toml`).
///
/// Reads the config file into a [ConfigStore], renders form controls for the
/// theme, module options, panels/layout, and background, and writes every
/// change straight back to disk. The running shell is not live-reloaded, so a
/// persistent banner reminds the user to restart for changes to take effect.
class ShellSettingsPage extends StatefulWidget {
  const ShellSettingsPage({super.key});

  @override
  _ShellSettingsPageState createState() => _ShellSettingsPageState();
}

class _ShellSettingsPageState extends State<ShellSettingsPage> {
  ConfigStore? _store;

  @override
  void initState() {
    super.initState();
    ConfigStore.load().then((store) {
      if (!mounted) {
        store.dispose();
        return;
      }
      setState(() => _store = store);
    });
  }

  @override
  void dispose() {
    _store?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
          child: Text(
            'Graceful Shell',
            style: TextStyle(
              fontSize: 16,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(height: 1, color: theme.divider),
        Expanded(child: _buildBody(theme)),
        _RestartBanner(),
      ],
    );
  }

  Widget _buildBody(ThemeConfig theme) {
    final store = _store;
    if (store == null) {
      return Center(child: _LoadingIndicator(color: theme.accent));
    }
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AppearanceSection(store: store),
              const SizedBox(height: 24),
              _ModulesSection(store: store),
              const SizedBox(height: 24),
              _PanelsSection(store: store),
              const SizedBox(height: 24),
              _BackgroundSection(store: store),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Appearance (theme)
// ---------------------------------------------------------------------------

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.store});

  final ConfigStore store;

  // key, label, default hex (matching ThemeConfig defaults in config.dart).
  static const List<(String, String, String)> _colors = [
    ('accent', 'Accent', '#853953'),
    ('foreground', 'Foreground', '#F3F4F4'),
    ('surface_hover', 'Surface (hover)', '#853953'),
    ('surface_pressed', 'Surface (pressed)', '#612D53'),
    ('workspace_background', 'Workspace background', '#2C2C2C'),
    ('popup_background', 'Popup background', '#2C2C2C'),
    ('popup_foreground', 'Popup foreground', '#F3F4F4'),
    ('slider_track', 'Slider track', '#612D53'),
    ('muted', 'Muted', '#853953'),
    ('divider', 'Divider', '#33F3F4F4'),
  ];

  @override
  Widget build(BuildContext context) {
    return _Section(
      label: 'Appearance',
      children: [
        _SettingRow(
          label: 'Font',
          control: _TextField(
            width: 180,
            initial: store.get<String>(['theme', 'font']) ?? 'Ubuntu Sans',
            onChanged: (v) => store.set(['theme', 'font'], v.trim()),
          ),
        ),
        for (final c in _colors)
          _SettingRow(
            label: c.$2,
            control: _ColorField(
              initial: store.get<String>(['theme', c.$1]) ?? c.$3,
              onChanged: (v) => store.set(['theme', c.$1], v),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Modules
// ---------------------------------------------------------------------------

class _ModulesSection extends StatelessWidget {
  const _ModulesSection({required this.store});

  final ConfigStore store;

  @override
  Widget build(BuildContext context) {
    return _Section(
      label: 'Modules',
      children: [
        _SubLabel('Weather'),
        _SettingRow(
          label: 'Unit',
          control: _Segmented(
            options: const ['fahrenheit', 'celsius'],
            value: store.get<String>(['modules', 'weather', 'unit']) ??
                'fahrenheit',
            onChanged: (v) => store.set(['modules', 'weather', 'unit'], v),
          ),
        ),
        _SettingRow(
          label: 'Refresh (minutes)',
          control: _NumberField(
            value: store.get<num>(['modules', 'weather', 'refresh_minutes']) ??
                10,
            isInt: true,
            onChanged: (v) =>
                store.set(['modules', 'weather', 'refresh_minutes'], v),
          ),
        ),
        _SubLabel('Battery'),
        _SettingRow(
          label: 'Poll (seconds)',
          control: _NumberField(
            value: store.get<num>(['modules', 'battery', 'poll_seconds']) ?? 30,
            isInt: true,
            onChanged: (v) =>
                store.set(['modules', 'battery', 'poll_seconds'], v),
          ),
        ),
        _SubLabel('Clock'),
        _SettingRow(
          label: 'Show date',
          control: _Toggle(
            value: store.get<bool>(['modules', 'clock', 'show_date']) ?? true,
            onChanged: (v) => store.set(['modules', 'clock', 'show_date'], v),
          ),
        ),
        _SubLabel('Media player'),
        _SettingRow(
          label: 'Max text width',
          control: _NumberField(
            value:
                store.get<num>(['modules', 'media_player', 'max_text_width']) ??
                    200,
            isInt: false,
            onChanged: (v) =>
                store.set(['modules', 'media_player', 'max_text_width'], v),
          ),
        ),
        _SubLabel('System tray'),
        _SettingRow(
          label: 'Icon size',
          control: _NumberField(
            value: store.get<num>(['modules', 'system_tray', 'icon_size']) ?? 16,
            isInt: false,
            onChanged: (v) =>
                store.set(['modules', 'system_tray', 'icon_size'], v),
          ),
        ),
        _SettingRow(
          label: 'Collapsed overlap',
          control: _NumberField(
            value: store
                    .get<num>(['modules', 'system_tray', 'collapsed_overlap']) ??
                10,
            isInt: false,
            onChanged: (v) =>
                store.set(['modules', 'system_tray', 'collapsed_overlap'], v),
          ),
        ),
        _SettingRow(
          label: 'Expanded spacing',
          control: _NumberField(
            value:
                store.get<num>(['modules', 'system_tray', 'expanded_spacing']) ??
                    6,
            isInt: false,
            onChanged: (v) =>
                store.set(['modules', 'system_tray', 'expanded_spacing'], v),
          ),
        ),
        _SettingRow(
          label: 'Hidden items',
          alignTop: true,
          control: _StringListEditor(
            items: store.getList<String>(['modules', 'system_tray',
                'hidden_items']),
            onChanged: (list) =>
                store.set(['modules', 'system_tray', 'hidden_items'], list),
            addHint: 'SNI id or title',
          ),
        ),
        _SubLabel('Dock'),
        _SettingRow(
          label: 'Icon size',
          control: _NumberField(
            value: store.get<num>(['modules', 'dock', 'icon_size']) ?? 24,
            isInt: true,
            onChanged: (v) => store.set(['modules', 'dock', 'icon_size'], v),
          ),
        ),
        _SettingRow(
          label: 'Apps',
          alignTop: true,
          control: _StringListEditor(
            items: store.getList<String>(['modules', 'dock', 'apps']),
            onChanged: (list) => store.set(['modules', 'dock', 'apps'], list),
            addHint: 'app id',
          ),
        ),
        _SubLabel('System monitor'),
        _SettingRow(
          label: 'Poll (seconds)',
          control: _NumberField(
            value: store.get<num>(['modules', 'system_monitor', 'poll_seconds'])
                    ?.toInt() ??
                2,
            isInt: true,
            onChanged: (v) =>
                store.set(['modules', 'system_monitor', 'poll_seconds'], v),
          ),
        ),
        _SettingRow(
          label: 'Temperature unit',
          control: _Segmented(
            options: const ['celsius', 'fahrenheit'],
            value:
                store.get<String>(['modules', 'system_monitor', 'temp_unit']) ??
                    'celsius',
            onChanged: (v) =>
                store.set(['modules', 'system_monitor', 'temp_unit'], v),
          ),
        ),
        _SubLabel('Network'),
        _SettingRow(
          label: 'Poll (seconds)',
          control: _NumberField(
            value: store.get<num>(['modules', 'network', 'poll_seconds']) ?? 10,
            isInt: true,
            onChanged: (v) =>
                store.set(['modules', 'network', 'poll_seconds'], v),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Panels & layout
// ---------------------------------------------------------------------------

class _PanelsSection extends StatelessWidget {
  const _PanelsSection({required this.store});

  final ConfigStore store;

  @override
  Widget build(BuildContext context) {
    final names = store.panelNames;
    return _Section(
      label: 'Panels & Layout',
      children: [
        if (names.isEmpty)
          _Hint('No panels defined in config.toml.')
        else
          for (final name in names) _buildPanel(name),
      ],
    );
  }

  Widget _buildPanel(String name) {
    List<String> p(List<String> rest) => ['panels', name, ...rest];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SubLabel(name),
          _SettingRow(
            label: 'Height',
            control: _NumberField(
              value: store.get<num>(p(['height'])) ?? 32,
              isInt: true,
              onChanged: (v) => store.set(p(['height']), v),
            ),
          ),
          _SettingRow(
            label: 'Horizontal padding',
            control: _NumberField(
              value: store.get<num>(p(['padding_horizontal'])) ?? 40,
              isInt: true,
              onChanged: (v) => store.set(p(['padding_horizontal']), v),
            ),
          ),
          _SettingRow(
            label: 'Anchor',
            control: _Segmented(
              options: const ['top', 'bottom', 'left', 'right'],
              value: store.get<String>(p(['anchor'])) ?? 'top',
              onChanged: (v) => store.set(p(['anchor']), v),
            ),
          ),
          _SettingRow(
            label: 'Layer',
            control: _Segmented(
              options: const ['background', 'bottom', 'top', 'overlay'],
              value: store.get<String>(p(['layer'])) ?? 'top',
              onChanged: (v) => store.set(p(['layer']), v),
            ),
          ),
          for (final slot in const ['left', 'center', 'right'])
            _SettingRow(
              label: '${slot[0].toUpperCase()}${slot.substring(1)} modules',
              alignTop: true,
              control: _StringListEditor(
                items: store.getList<String>(p(['layout', slot])),
                onChanged: (list) => store.set(p(['layout', slot]), list),
                suggestions: Module.registeredKeys.toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Background
// ---------------------------------------------------------------------------

class _BackgroundSection extends StatelessWidget {
  const _BackgroundSection({required this.store});

  final ConfigStore store;

  @override
  Widget build(BuildContext context) {
    final rawEntries = store.get<List>(['background', 'entries']) ?? const [];
    final entries = rawEntries.whereType<Map>().toList();
    return _Section(
      label: 'Background',
      children: [
        _SettingRow(
          label: 'Fit',
          control: _Segmented(
            options: const ['fill', 'contain', 'natural'],
            value: store.get<String>(['background', 'fit']) ?? 'fill',
            onChanged: (v) => store.set(['background', 'fit'], v),
          ),
        ),
        _SubLabel('Wallpapers'),
        for (var i = 0; i < entries.length; i++)
          _buildEntry(i, entries[i]),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _AddButton(
            label: 'Add wallpaper',
            onTap: () {
              final list = _entriesCopy(entries);
              list.add({'path': '', 'time': '00:00'});
              store.set(['background', 'entries'], list);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEntry(int index, Map entry) {
    void update(String key, String value) {
      final list = _entriesCopy(_currentEntries());
      if (index < list.length) {
        list[index][key] = value;
        store.set(['background', 'entries'], list);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _TextField(
              initial: '${entry['path'] ?? ''}',
              onChanged: (v) => update('path', v.trim()),
            ),
          ),
          const SizedBox(width: 8),
          _TextField(
            width: 76,
            initial: '${entry['time'] ?? '00:00'}',
            onChanged: (v) => update('time', v.trim()),
          ),
          const SizedBox(width: 8),
          _IconButton(
            icon: FontAwesomeIcons.xmark,
            onTap: () {
              final list = _entriesCopy(_currentEntries());
              if (index < list.length) {
                list.removeAt(index);
                store.set(['background', 'entries'], list);
              }
            },
          ),
        ],
      ),
    );
  }

  List<Map> _currentEntries() =>
      (store.get<List>(['background', 'entries']) ?? const [])
          .whereType<Map>()
          .toList();

  List<Map<String, dynamic>> _entriesCopy(List<Map> src) => src
      .map((e) => e.map((k, v) => MapEntry('$k', v)))
      .toList();
}

// ---------------------------------------------------------------------------
// Layout helpers
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontFamily: theme.fontFamily,
        color: theme.popupForeground.withValues(alpha: 0.5),
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontFamily: theme.fontFamily,
          color: theme.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontFamily: theme.fontFamily,
        color: theme.popupForeground.withValues(alpha: 0.5),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.control,
    this.alignTop = false,
  });

  final String label;
  final Widget control;
  final bool alignTop;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment:
            alignTop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: alignTop ? 10 : 0),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

class _Toggle extends StatefulWidget {
  const _Toggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  _ToggleState createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final color = widget.value ? theme.accent : theme.divider;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onChanged(!widget.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 24,
          decoration: BoxDecoration(
            color: _hovered ? color.withValues(alpha: 0.8) : color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeInOut,
                left: widget.value ? 22 : 2,
                top: 2,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        for (final o in options)
          _OptionButton(
            label: '${o[0].toUpperCase()}${o.substring(1)}',
            selected: o == value,
            onTap: () => onChanged(o),
          ),
      ],
    );
  }
}

class _OptionButton extends StatefulWidget {
  const _OptionButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  _OptionButtonState createState() => _OptionButtonState();
}

class _OptionButtonState extends State<_OptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final Color bg;
    if (widget.selected) {
      bg = theme.accent;
    } else if (_hovered) {
      bg = theme.surfaceHover;
    } else {
      bg = theme.divider.withValues(alpha: 0.5);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: widget.selected ? theme.accent : theme.divider),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontFamily: theme.fontFamily,
              color: widget.selected
                  ? const Color(0xFFFFFFFF)
                  : theme.popupForeground,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bordered single-line text input backed by [EditableText] (the codebase does
/// not use Material). Seeds its controller once from [initial]; subsequent
/// parent rebuilds do not clobber in-progress edits.
class _TextField extends StatefulWidget {
  const _TextField({
    required this.initial,
    required this.onChanged,
    this.width,
    this.inputFormatters,
  });

  final String initial;
  final ValueChanged<String> onChanged;
  final double? width;
  final List<TextInputFormatter>? inputFormatters;

  @override
  _TextFieldState createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _focusNode.addListener(
        () => setState(() => _focused = _focusNode.hasFocus));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      width: widget.width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.popupBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _focused ? theme.accent : theme.divider,
          width: 1,
        ),
      ),
      child: EditableText(
        controller: _controller,
        focusNode: _focusNode,
        style: TextStyle(
          fontSize: 13,
          color: theme.popupForeground,
          fontFamily: theme.fontFamily,
        ),
        cursorColor: theme.accent,
        backgroundCursorColor: theme.divider,
        inputFormatters: widget.inputFormatters,
        onChanged: (v) => widget.onChanged(v),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.value,
    required this.onChanged,
    required this.isInt,
  });

  final num value;
  final bool isInt;
  final ValueChanged<num> onChanged;

  @override
  Widget build(BuildContext context) {
    return _TextField(
      width: 90,
      initial: isInt ? '${value.toInt()}' : _trimDouble(value.toDouble()),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
            isInt ? RegExp(r'[0-9]') : RegExp(r'[0-9.]')),
      ],
      onChanged: (text) {
        if (text.isEmpty) return;
        if (isInt) {
          final v = int.tryParse(text);
          if (v != null) onChanged(v);
        } else {
          final v = double.tryParse(text);
          if (v != null) onChanged(v);
        }
      },
    );
  }

  static String _trimDouble(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(1);
    return '$v';
  }
}

/// Colour swatch + hex text field. Accepts `#RGB`-style 6- or 8-digit hex
/// (matching [ThemeConfig] parsing) and previews the parsed colour live.
class _ColorField extends StatefulWidget {
  const _ColorField({required this.initial, required this.onChanged});

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  _ColorFieldState createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _focusNode.addListener(
        () => setState(() => _focused = _focusNode.hasFocus));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  static Color? _parse(String hex) {
    final s = hex.startsWith('#') ? hex.substring(1) : hex;
    if (s.length != 6 && s.length != 8) return null;
    final value = int.tryParse(s.length == 6 ? 'FF$s' : s, radix: 16);
    return value != null ? Color(value) : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final swatch = _parse(_controller.text);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: swatch ?? const Color(0x00000000),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.divider),
          ),
          child: swatch == null
              ? FaIcon(FontAwesomeIcons.question,
                  size: 10,
                  color: theme.popupForeground.withValues(alpha: 0.4))
              : null,
        ),
        const SizedBox(width: 8),
        Container(
          width: 110,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: theme.popupBackground,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _focused ? theme.accent : theme.divider,
              width: 1,
            ),
          ),
          child: EditableText(
            controller: _controller,
            focusNode: _focusNode,
            style: TextStyle(
              fontSize: 13,
              color: theme.popupForeground,
              fontFamily: theme.fontFamily,
            ),
            cursorColor: theme.accent,
            backgroundCursorColor: theme.divider,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
            ],
            onChanged: (v) {
              setState(() {});
              if (_parse(v) != null) widget.onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

/// Editable ordered list of strings. When [suggestions] is provided, new items
/// are added from a dropdown of those values; otherwise a free-form text field
/// is shown. Existing items can be reordered and removed.
class _StringListEditor extends StatefulWidget {
  const _StringListEditor({
    required this.items,
    required this.onChanged,
    this.suggestions,
    this.addHint,
  });

  final List<String> items;
  final ValueChanged<List<String>> onChanged;
  final List<String>? suggestions;
  final String? addHint;

  @override
  _StringListEditorState createState() => _StringListEditorState();
}

class _StringListEditorState extends State<_StringListEditor> {
  final _addController = TextEditingController();
  final _addFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _addFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _addController.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  void _emit(List<String> list) => widget.onChanged(list);

  void _add(String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    _emit([...widget.items, v]);
  }

  void _removeAt(int i) {
    final list = [...widget.items]..removeAt(i);
    _emit(list);
  }

  void _move(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= widget.items.length) return;
    final list = [...widget.items];
    final tmp = list[i];
    list[i] = list[j];
    list[j] = tmp;
    _emit(list);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.items.length; i++)
            _row(context, i, widget.items[i]),
          const SizedBox(height: 6),
          _buildAdder(context),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int i, String item) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        decoration: BoxDecoration(
          color: theme.divider.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground,
                ),
              ),
            ),
            _IconButton(
              icon: FontAwesomeIcons.chevronUp,
              size: 10,
              onTap: () => _move(i, -1),
            ),
            _IconButton(
              icon: FontAwesomeIcons.chevronDown,
              size: 10,
              onTap: () => _move(i, 1),
            ),
            _IconButton(
              icon: FontAwesomeIcons.xmark,
              size: 12,
              onTap: () => _removeAt(i),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdder(BuildContext context) {
    final suggestions = widget.suggestions;
    if (suggestions != null) {
      return _AddDropdown(
        options: suggestions,
        onSelected: _add,
      );
    }
    final theme = ThemeScope.of(context);
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.popupBackground,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: _addFocus.hasFocus ? theme.accent : theme.divider),
            ),
            child: Stack(
              children: [
                if (_addController.text.isEmpty)
                  Text(
                    widget.addHint ?? 'add…',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.popupForeground.withValues(alpha: 0.35),
                      fontFamily: theme.fontFamily,
                    ),
                  ),
                EditableText(
                  controller: _addController,
                  focusNode: _addFocus,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.popupForeground,
                    fontFamily: theme.fontFamily,
                  ),
                  cursorColor: theme.accent,
                  backgroundCursorColor: theme.divider,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (v) {
                    _add(v);
                    _addController.clear();
                    setState(() {});
                    _addFocus.requestFocus();
                  },
                ),
              ],
            ),
          ),
        ),
        _IconButton(
          icon: FontAwesomeIcons.plus,
          onTap: () {
            _add(_addController.text);
            _addController.clear();
            setState(() {});
          },
        ),
      ],
    );
  }
}

/// A dropdown that expands to a list of [options] and reports the chosen value.
class _AddDropdown extends StatefulWidget {
  const _AddDropdown({required this.options, required this.onSelected});

  final List<String> options;
  final ValueChanged<String> onSelected;

  @override
  _AddDropdownState createState() => _AddDropdownState();
}

class _AddDropdownState extends State<_AddDropdown> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AddButton(
          label: _open ? 'Close' : 'Add module',
          onTap: () => setState(() => _open = !_open),
        ),
        if (_open)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: theme.popupBackground,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.divider),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final o in widget.options)
                    _DropdownItem(
                      label: o,
                      onTap: () {
                        widget.onSelected(o);
                        setState(() => _open = false);
                      },
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DropdownItem extends StatefulWidget {
  const _DropdownItem({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  _DropdownItemState createState() => _DropdownItemState();
}

class _DropdownItemState extends State<_DropdownItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: _hovered ? theme.surfaceHover : const Color(0x00000000),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground,
            ),
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatefulWidget {
  const _AddButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  _AddButtonState createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? theme.surfaceHover
                : theme.divider.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(FontAwesomeIcons.plus,
                  size: 11, color: theme.popupForeground),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatefulWidget {
  const _IconButton({required this.icon, required this.onTap, this.size = 12});

  final FaIconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  _IconButtonState createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          child: FaIcon(
            widget.icon,
            size: widget.size,
            color: _hovered
                ? theme.accent
                : theme.popupForeground.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _RestartBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.12),
        border: Border(top: BorderSide(color: theme.divider)),
      ),
      child: Row(
        children: [
          FaIcon(FontAwesomeIcons.arrowsRotate, size: 12, color: theme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Changes are saved automatically. Restart Graceful Shell for '
              'them to take effect.',
              style: TextStyle(
                fontSize: 12,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.75),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingIndicator extends StatefulWidget {
  const _LoadingIndicator({required this.color});

  final Color color;

  @override
  _LoadingIndicatorState createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<_LoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.rotate(
        angle: _controller.value * 2 * 3.1415926,
        child: child,
      ),
      child:
          FaIcon(FontAwesomeIcons.circleNotch, size: 20, color: widget.color),
    );
  }
}
