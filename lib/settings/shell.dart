// ignore_for_file: library_private_types_in_public_api

import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/popup.dart';
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
    // A nested Navigator lets the Shell pane drill from the category menu into
    // a single category's settings and back, while the outer Settings bar and
    // sidebar (owned by SettingsOverlay) stay put around this pane.
    return Navigator(
      onGenerateInitialRoutes: (navigator, initialRoute) => [
        PageRouteBuilder(
          pageBuilder: (context, _, __) => _ShellHome(store: store),
        ),
      ],
    );
  }
}

/// One selectable settings category shown on the Shell landing page and pushed
/// as its own view when tapped.
class _ShellCategory {
  const _ShellCategory({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.build,
  });

  final String title;
  final String subtitle;
  final FaIconData icon;
  final Widget Function(ConfigStore store) build;
}

const List<_ShellCategory> _shellCategories = [
  _ShellCategory(
    title: 'Appearance',
    subtitle: 'Colors and font',
    icon: FontAwesomeIcons.palette,
    build: _buildAppearance,
  ),
  _ShellCategory(
    title: 'Module Settings',
    subtitle: 'Per-module options',
    icon: FontAwesomeIcons.puzzlePiece,
    build: _buildModules,
  ),
  _ShellCategory(
    title: 'Panels & Layout',
    subtitle: 'Size, anchor, module slots',
    icon: FontAwesomeIcons.tableColumns,
    build: _buildPanels,
  ),
  _ShellCategory(
    title: 'Background',
    subtitle: 'Wallpaper and fit',
    icon: FontAwesomeIcons.image,
    build: _buildBackground,
  ),
];

Widget _buildAppearance(ConfigStore store) => _AppearanceSection(store: store);
Widget _buildModules(ConfigStore store) => _ModulesSection(store: store);
Widget _buildPanels(ConfigStore store) => _PanelsSection(store: store);
Widget _buildBackground(ConfigStore store) => _BackgroundSection(store: store);

/// Landing view: the "Graceful Shell" header plus a tappable row per category.
class _ShellHome extends StatelessWidget {
  const _ShellHome({required this.store});

  final ConfigStore store;

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
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final category in _shellCategories)
                  _CategoryCard(
                    category: category,
                    onTap: () => Navigator.of(context).push(
                      _slideRoute(_ShellCategoryView(
                        category: category,
                        store: store,
                      )),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Detail view: a back button + category title header over the category's
/// existing settings section.
class _ShellCategoryView extends StatelessWidget {
  const _ShellCategoryView({required this.category, required this.store});

  final _ShellCategory category;
  final ConfigStore store;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
          child: Row(
            children: [
              _IconButton(
                icon: FontAwesomeIcons.arrowLeft,
                size: 14,
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Text(
                category.title,
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(height: 1, color: theme.divider),
        Expanded(
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: category.build(store),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Subtle horizontal-slide + fade transition for pushing a category view.
PageRoute<T> _slideRoute<T>(Widget child) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) => child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Tappable, hover-aware row on the landing page. Styled after the sidebar's
/// [_SidebarItem]: icon + title + subtitle + trailing chevron.
class _CategoryCard extends StatefulWidget {
  const _CategoryCard({required this.category, required this.onTap});

  final _ShellCategory category;
  final VoidCallback onTap;

  @override
  _CategoryCardState createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: _hovered
                  ? theme.surfaceHover
                  : theme.divider.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered ? theme.accent : theme.divider,
              ),
            ),
            child: Row(
              children: [
                FaIcon(
                  widget.category.icon,
                  size: 16,
                  color: _hovered
                      ? theme.accent
                      : theme.popupForeground.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.category.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: theme.fontFamily,
                          color: theme.popupForeground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.category.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: theme.fontFamily,
                          color: theme.popupForeground.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FaIcon(
                  FontAwesomeIcons.chevronRight,
                  size: 12,
                  color: theme.popupForeground.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
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
/// Parses a `#RRGGBB` / `#AARRGGBB` hex string (`#` optional) into a color.
Color? _parseHexColor(String hex) {
  final s = hex.startsWith('#') ? hex.substring(1) : hex;
  if (s.length != 6 && s.length != 8) return null;
  final value = int.tryParse(s.length == 6 ? 'FF$s' : s, radix: 16);
  return value != null ? Color(value) : null;
}

/// Formats a color back to the config's hex form: `#RRGGBB` when fully opaque,
/// otherwise `#AARRGGBB`.
String _formatHexColor(Color c) {
  final argb = c.toARGB32();
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  final a = (argb >> 24) & 0xFF;
  if (a == 0xFF) return '#$rgb';
  return '#${a.toRadixString(16).padLeft(2, '0')}$rgb';
}

/// A color swatch + hex text field. Clicking the swatch opens a visual color
/// picker ([_ColorPickerPopup]) floated over the settings window.
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
  final _portalController = OverlayPortalController();
  final _link = LayerLink();
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

  void _apply(Color color) {
    final hex = _formatHexColor(color);
    _controller.value = TextEditingValue(
      text: hex,
      selection: TextSelection.collapsed(offset: hex.length),
    );
    setState(() {});
    widget.onChanged(hex);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final swatch = _parseHexColor(_controller.text);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CompositedTransformTarget(
          link: _link,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _portalController.toggle,
              child: Container(
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
            ),
          ),
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
          // Read-only on the main page: the value is edited through the color
          // picker popup, not typed here.
          child: EditableText(
            controller: _controller,
            focusNode: _focusNode,
            readOnly: true,
            style: TextStyle(
              fontSize: 13,
              color: theme.popupForeground,
              fontFamily: theme.fontFamily,
            ),
            cursorColor: theme.accent,
            backgroundCursorColor: theme.divider,
          ),
        ),
        OverlayPortal(
          controller: _portalController,
          overlayChildBuilder: (context) => _buildPicker(),
        ),
      ],
    );
  }

  Widget _buildPicker() {
    return Stack(
      children: [
        // Dismiss when tapping outside the popup.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _portalController.hide,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),
          child: _ColorPickerPopup(
            initial: _parseHexColor(_controller.text) ?? const Color(0xFF000000),
            onChanged: _apply,
          ),
        ),
      ],
    );
  }
}

/// Visual HSV color picker: a draggable saturation/value square, hue and alpha
/// sliders, and a manual hex entry. Emits every change through [onChanged].
class _ColorPickerPopup extends StatefulWidget {
  const _ColorPickerPopup({required this.initial, required this.onChanged});

  final Color initial;
  final ValueChanged<Color> onChanged;

  @override
  State<_ColorPickerPopup> createState() => _ColorPickerPopupState();
}

class _ColorPickerPopupState extends State<_ColorPickerPopup> {
  static const double _w = 200;
  static const double _squareH = 150;
  static const double _sliderH = 14;

  late HSVColor _hsv;
  late final TextEditingController _hexController;
  final _hexFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hexController =
        TextEditingController(text: _formatHexColor(widget.initial));
  }

  @override
  void dispose() {
    _hexController.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  /// Applies a new HSV value, optionally syncing the hex field text (skipped
  /// while the user is typing into that field).
  void _set(HSVColor hsv, {bool syncHex = true}) {
    _hsv = hsv;
    final color = hsv.toColor();
    if (syncHex) {
      final hex = _formatHexColor(color);
      if (_hexController.text != hex) {
        _hexController.value = TextEditingValue(
          text: hex,
          selection: TextSelection.collapsed(offset: hex.length),
        );
      }
    }
    setState(() {});
    widget.onChanged(color);
  }

  void _onHex(String text) {
    final c = _parseHexColor(text);
    if (c != null) _set(HSVColor.fromColor(c), syncHex: false);
  }

  /// A fixed-size region that reports the pointer position (down + drag) as
  /// normalized (0..1) coordinates.
  Widget _draggable({
    required double width,
    required double height,
    required ValueChanged<Offset> onChange,
    required Widget child,
  }) {
    void handle(Offset local) {
      onChange(Offset(
        (local.dx / width).clamp(0.0, 1.0),
        (local.dy / height).clamp(0.0, 1.0),
      ));
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => handle(d.localPosition),
      onPanDown: (d) => handle(d.localPosition),
      onPanUpdate: (d) => handle(d.localPosition),
      child: SizedBox(width: width, height: height, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final color = _hsv.toColor();
    return PopupBounceIn(
      child: Container(
        width: _w + 24,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.popupBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.accent, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Saturation / value square.
            _draggable(
              width: _w,
              height: _squareH,
              onChange: (n) =>
                  _set(_hsv.withSaturation(n.dx).withValue(1 - n.dy)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CustomPaint(
                  painter: _SVPainter(_hsv.hue),
                  foregroundPainter: _SVCursorPainter(
                    saturation: _hsv.saturation,
                    value: _hsv.value,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Hue slider.
            _draggable(
              width: _w,
              height: _sliderH,
              onChange: (n) =>
                  _set(_hsv.withHue((n.dx * 360).clamp(0.0, 360.0))),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_sliderH / 2),
                child: CustomPaint(
                  painter: _HuePainter(),
                  foregroundPainter: _ThumbPainter(_hsv.hue / 360),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Alpha slider.
            _draggable(
              width: _w,
              height: _sliderH,
              onChange: (n) => _set(_hsv.withAlpha(n.dx)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_sliderH / 2),
                child: CustomPaint(
                  painter: _AlphaPainter(_hsv.withAlpha(1).toColor()),
                  foregroundPainter: _ThumbPainter(_hsv.alpha),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Manual hex entry.
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: theme.divider),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.workspaceBackground,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: theme.divider),
                    ),
                    child: EditableText(
                      controller: _hexController,
                      focusNode: _hexFocus,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.popupForeground,
                        fontFamily: theme.fontFamily,
                      ),
                      cursorColor: theme.accent,
                      backgroundCursorColor: theme.divider,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[#0-9a-fA-F]')),
                      ],
                      onChanged: _onHex,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the saturation (x) / value (y) gradient field for a given [hue].
class _SVPainter extends CustomPainter {
  _SVPainter(this.hue);

  final double hue;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [const Color(0xFFFFFFFF), hueColor],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SVPainter old) => old.hue != hue;
}

/// Draws the ring cursor over the saturation/value square.
class _SVCursorPainter extends CustomPainter {
  _SVCursorPainter({required this.saturation, required this.value});

  final double saturation;
  final double value;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final c = Offset(saturation * size.width, (1 - value) * size.height);
    canvas.drawCircle(
      c,
      6,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      c,
      7.5,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x88000000),
    );
  }

  @override
  bool shouldRepaint(_SVCursorPainter old) =>
      old.saturation != saturation || old.value != value;
}

/// Paints the full hue spectrum bar.
class _HuePainter extends CustomPainter {
  @override
  void paint(ui.Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => false;
}

/// Paints the alpha slider: a checkerboard behind a transparent→opaque gradient
/// of the current [color].
class _AlphaPainter extends CustomPainter {
  _AlphaPainter(this.color);

  final Color color;

  @override
  void paint(ui.Canvas canvas, Size size) {
    const cell = 5.0;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, ui.Paint()..color = const Color(0xFFCCCCCC));
    final dark = ui.Paint()..color = const Color(0xFF888888);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        if (((x ~/ cell) + (y ~/ cell)) % 2 == 0) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
        }
      }
    }
    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 1)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_AlphaPainter old) => old.color != color;
}

/// Draws the round thumb for the hue/alpha sliders at normalized position [t].
class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.t);

  final double t;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final r = size.height / 2;
    final x = (t.clamp(0.0, 1.0) * size.width).clamp(r, size.width - r);
    final center = Offset(x, size.height / 2);
    canvas.drawCircle(
      center,
      r - 1,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      center,
      r,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x66000000),
    );
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => old.t != t;
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
