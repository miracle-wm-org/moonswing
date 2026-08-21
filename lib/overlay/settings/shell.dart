// ignore_for_file: library_private_types_in_public_api

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/overlay/file_picker.dart';
import 'package:graceful_shell/desktop/app_chooser.dart';
import 'package:graceful_shell/desktop/desktop_actions.dart';
import 'package:graceful_shell/desktop/desktop_layout.dart';
import 'package:graceful_shell/desktop/desktop_store.dart';
import 'package:graceful_shell/launcher/app_index.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/theme/font_catalog.dart';
import 'package:graceful_shell/theme/theme_store.dart';

/// Settings page for graceful-shell's own configuration (`config.toml`).
///
/// Reads the config file into a [ConfigStore], renders form controls for the
/// theme, module options, panels/layout, and background, and writes every
/// change straight back to disk. The running shell is not live-reloaded, so a
/// persistent banner reminds the user to restart for changes to take effect.
class ShellSettingsPage extends StatefulWidget {
  const ShellSettingsPage({super.key, this.initialCategory});

  /// A `_ShellCategory` title to open directly, e.g. `Background`. Null lands
  /// on the category list, which is the behaviour every existing caller wants.
  final String? initialCategory;

  @override
  _ShellSettingsPageState createState() => _ShellSettingsPageState();
}

class _ShellSettingsPageState extends State<ShellSettingsPage> {
  // The process-wide store shared with the running shell. Not disposed here —
  // its lifetime is the whole process, and mutating it live-updates the shell.
  final ConfigStore _store = ConfigStore.instance;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildBody()),
        // Only surfaces when a restart-only field actually changed.
        ListenableBuilder(
          listenable: _store,
          builder: (context, _) =>
              _store.needsRestart ? _RestartBanner() : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildBody() {
    final store = _store;
    final initial = _shellCategoryByTitle(widget.initialCategory);
    // A nested Navigator lets the Shell pane drill from the category menu into
    // a single category's settings and back, while the outer Settings bar and
    // sidebar (owned by SettingsOverlay) stay put around this pane.
    return Navigator(
      onGenerateInitialRoutes: (navigator, initialRoute) => [
        PageRouteBuilder(
          pageBuilder: (context, _, __) => _ShellHome(store: store),
        ),
        // A deep link pushes the category *on top of* the landing page rather
        // than replacing it, so Back still goes where the user expects.
        if (initial != null)
          _slideRoute(_ShellCategoryView(category: initial, store: store)),
      ],
    );
  }
}

_ShellCategory? _shellCategoryByTitle(String? title) {
  if (title == null) return null;
  for (final category in _shellCategories) {
    if (category.title == title) return category;
  }
  return null;
}

/// Whether [title] names a Shell settings category.
///
/// The deep-link titles in `SettingsRoute` are plain strings, so this is what
/// keeps them honest: `test/settings_route_test.dart` asserts every route the
/// shell can emit actually lands somewhere.
bool isShellCategory(String title) => _shellCategoryByTitle(title) != null;

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
  _ShellCategory(
    title: 'Desktop',
    subtitle: 'Icon grid and pinned items',
    icon: FontAwesomeIcons.tableCells,
    build: _buildDesktop,
  ),
  _ShellCategory(
    title: 'Lock Screen',
    subtitle: 'Wallpaper and unlock',
    icon: FontAwesomeIcons.lock,
    build: _buildLock,
  ),
  _ShellCategory(
    title: 'Calendar',
    subtitle: 'Month grid',
    icon: FontAwesomeIcons.calendarDays,
    build: _buildCalendar,
  ),
];

Widget _buildAppearance(ConfigStore store) => _AppearanceSection(store: store);
Widget _buildModules(ConfigStore store) => _ModulesSection(store: store);
Widget _buildPanels(ConfigStore store) => _PanelsSection(store: store);
Widget _buildBackground(ConfigStore store) => _BackgroundSection(store: store);
Widget _buildDesktop(ConfigStore store) => _DesktopSection(store: store);
Widget _buildLock(ConfigStore store) => _LockSection(store: store);
Widget _buildCalendar(ConfigStore store) => _CalendarSection(store: store);

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
              SettingsIconButton(
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
              color: _hovered ? theme.surfaceHover : theme.controlSurface,
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

/// Theme picker + editor.
///
/// The palette no longer lives in `config.toml` — `[ThemeStore]` owns a file
/// per theme under `~/.config/graceful-shell/themes/` and `config.toml` only
/// names the active one. So this section talks to [ThemeStore], not [store];
/// the parameter stays because every category builder takes one.
class _AppearanceSection extends StatefulWidget {
  const _AppearanceSection({required this.store});

  final ConfigStore store;

  @override
  State<_AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<_AppearanceSection> {
  final ThemeStore _themes = ThemeStore.instance;
  bool _naming = false;

  /// Started once, here rather than in `build`: this section rebuilds on every
  /// ThemeStore notify, which includes every frame of a colour-picker drag.
  final Future<List<String>> _fonts = FontCatalog.instance.list();

  static const Map<String, String> _colorLabels = {
    'accent': 'Accent',
    'foreground': 'Foreground',
    'surface_hover': 'Surface (hover)',
    'surface_pressed': 'Surface (pressed)',
    'workspace_background': 'Workspace background',
    'popup_background': 'Popup background',
    'popup_foreground': 'Popup foreground',
    'control_surface': 'Control surface',
    'slider_track': 'Slider track',
    'muted': 'Muted text',
    'divider': 'Divider',
    'panel_background': 'Panel background',
    'panel_border': 'Panel border',
    'popup_border': 'Popup border',
    'scrim': 'Overlay scrim',
  };

  void _duplicate() => setState(() => _themes.duplicateActive());

  @override
  Widget build(BuildContext context) {
    // Rebuilt on every ThemeStore change so the picker's tick, the swatches,
    // and the read-only state all follow a switch made from anywhere.
    return ListenableBuilder(
      listenable: _themes,
      builder: (context, _) {
        final active = _themes.activeName;
        final builtIn = _themes.activeIsBuiltIn;
        // Read straight off the resolved theme rather than the file, so a key
        // the file omits shows the value actually in use.
        final current = _themes.theme.toMap();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSection(
              label: 'Theme',
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final summary in _themes.themes)
                      _ThemeCard(
                        summary: summary,
                        selected: summary.slug == active,
                        onTap: () => _themes.select(summary.slug),
                        onDelete: summary.builtIn
                            ? null
                            : () => _themes.delete(summary.slug),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_naming)
                  _NewThemeRow(
                    onCancel: () => setState(() => _naming = false),
                    onSubmit: (name) {
                      final slug = _themes.create(name);
                      if (slug != null) setState(() => _naming = false);
                    },
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SettingsOptionButton(
                      label: 'New theme…',
                      selected: false,
                      onTap: () => setState(() => _naming = true),
                    ),
                  ),
                const SizedBox(height: 6),
                SettingsHint(
                  'Themes are files in ${_themes.directory}. '
                  'Drop one in to add it by hand.',
                ),
              ],
            ),
            const SizedBox(height: 20),
            SettingsSection(
              label: 'Edit ${_themes.themes.firstWhere(
                    (t) => t.slug == active,
                    orElse: () => _themes.themes.first,
                  ).displayName}',
              children: [
                if (builtIn) ...[
                  const SettingsHint(
                    'This theme ships with the shell and is read-only — the '
                    'next update would overwrite your changes. Duplicate it to '
                    'make it yours.',
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SettingsOptionButton(
                      label: 'Duplicate to edit',
                      selected: false,
                      onTap: _duplicate,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SettingsRow(
                  label: 'Font',
                  control: FutureBuilder<List<String>>(
                    future: _fonts,
                    builder: (context, snapshot) {
                      final fonts = snapshot.data;
                      final value =
                          current['font'] as String? ?? 'Ubuntu Sans';
                      if (fonts == null || fonts.isEmpty) {
                        // Still loading, or no fontconfig on this machine. The
                        // key stays editable by hand either way.
                        return SettingsTextField(
                          // Keyed on the theme so switching re-seeds the field —
                          // SettingsTextField reads `initial` only on first
                          // build.
                          key: ValueKey('font-$active'),
                          width: 180,
                          initial: value,
                          onChanged: (v) => _themes.edit('font', v.trim()),
                        );
                      }
                      return SettingsFontField(
                        value: value,
                        // A theme naming a family this machine does not have
                        // still shows, and stays the selected row, rather than
                        // reading as somebody else's font.
                        fonts: fonts.contains(value)
                            ? fonts
                            : <String>[value, ...fonts],
                        locked: builtIn,
                        onLockedTap: _duplicate,
                        onChanged: (v) => _themes.edit('font', v),
                      );
                    },
                  ),
                ),
                SettingsRow(
                  label: 'Panel gradient',
                  control: SettingsToggle(
                    value: current['panel_gradient'] as bool? ?? true,
                    onChanged: builtIn
                        ? (_) => _duplicate()
                        : (v) => _themes.edit('panel_gradient', v),
                  ),
                ),
                const SettingsHint(
                  'Off paints the bar as a flat panel background. On fades it '
                  'from the accent across to that colour, with every stop at '
                  "the panel background's alpha — so the bar has one opacity.",
                ),
                const SizedBox(height: 8),
                SettingsRow(
                  label: 'Panel margin',
                  control: SettingsNumberField(
                    key: ValueKey('panel_margin-$active'),
                    value: current['panel_margin'] as num? ?? 0,
                    isInt: true,
                    onChanged: (v) =>
                        _themes.edit('panel_margin', v.toInt().clamp(0, 256)),
                  ),
                ),
                SettingsRow(
                  label: 'Panel corner radius',
                  control: SettingsNumberField(
                    key: ValueKey('panel_radius-$active'),
                    value: current['panel_radius'] as num? ?? 0,
                    isInt: false,
                    onChanged: (v) => _themes.edit(
                        'panel_radius', v.toDouble().clamp(0.0, 64.0)),
                  ),
                ),
                SettingsRow(
                  label: 'Panel border width',
                  control: SettingsNumberField(
                    key: ValueKey('panel_border_width-$active'),
                    value: current['panel_border_width'] as num? ?? 0,
                    isInt: false,
                    onChanged: (v) => _themes.edit(
                        'panel_border_width', v.toDouble().clamp(0.0, 16.0)),
                  ),
                ),
                const SettingsHint(
                  'A margin floats the bar off the screen edges. The gap is '
                  'real — windows will not tile into it, and clicks that land '
                  'there reach the desktop. A floating bar rounds all four '
                  'corners; one with no margin rounds only the two facing the '
                  "screen, so the display's own corners stay square. The "
                  'border draws only at a width above zero.',
                ),
                const SizedBox(height: 8),
                SettingsRow(
                  label: 'Popup corner radius',
                  control: SettingsNumberField(
                    key: ValueKey('popup_radius-$active'),
                    // The fallbacks are the ThemeConfig defaults, not 0: a
                    // theme file written before these keys existed has neither,
                    // and a field reading 0 while the shell paints 8 would be
                    // an edit the user never made.
                    value: current['popup_radius'] as num? ?? 8,
                    isInt: false,
                    onChanged: (v) => _themes.edit(
                        'popup_radius', v.toDouble().clamp(0.0, 64.0)),
                  ),
                ),
                SettingsRow(
                  label: 'Popup border width',
                  control: SettingsNumberField(
                    key: ValueKey('popup_border_width-$active'),
                    value: current['popup_border_width'] as num? ?? 1,
                    isInt: false,
                    onChanged: (v) => _themes.edit(
                        'popup_border_width', v.toDouble().clamp(0.0, 16.0)),
                  ),
                ),
                const SettingsHint(
                  'Popup, menu, flyout and on-screen-indicator cards. Unlike '
                  'the bar they round all four corners — nothing sits behind '
                  'them to cut a corner out of. The rim is what gives a '
                  'translucent card an edge over a busy wallpaper, and draws '
                  'only at a width above zero.',
                ),
                const SizedBox(height: 8),
                SettingsRow(
                  label: 'Overlay blur',
                  control: SettingsNumberField(
                    key: ValueKey('blur-$active'),
                    value: current['blur'] as num? ?? 24,
                    isInt: false,
                    onChanged: (v) =>
                        _themes.edit('blur', v.toDouble().clamp(0.0, 100.0)),
                  ),
                ),
                const SettingsHint(
                  'Blur softens the wash behind the settings and launcher '
                  'panels. It cannot blur the desktop itself — the compositor '
                  'owns what is under a shell surface — so translucency comes '
                  'from the alpha channel of the colours below.',
                ),
                const SizedBox(height: 8),
                for (final entry in _colorLabels.entries)
                  SettingsRow(
                    label: entry.value,
                    control: SettingsColorField(
                      key: ValueKey('${entry.key}-$active'),
                      initial: current[entry.key] as String? ?? '#000000',
                      locked: builtIn,
                      onLockedTap: _duplicate,
                      onChanged: (v) => _themes.edit(entry.key, v),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// One theme in the picker: a strip of its own colours, its name, and a tick
/// when it is the active one. Drawn in the theme it represents, so the grid
/// previews rather than describes.
class _ThemeCard extends StatefulWidget {
  const _ThemeCard({
    required this.summary,
    required this.selected,
    required this.onTap,
    this.onDelete,
  });

  final ThemeSummary summary;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  State<_ThemeCard> createState() => _ThemeCardState();
}

class _ThemeCardState extends State<_ThemeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final preview = widget.summary.config;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 168,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _hovered ? theme.surfaceHover : theme.controlSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.selected ? theme.accent : theme.divider,
              width: widget.selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The swatches sit on the preview's own background, or a
              // translucent theme would be judged against the wrong surface.
              Container(
                height: 34,
                decoration: BoxDecoration(
                  color: preview.workspaceBackground,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: preview.divider),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    for (final c in [
                      preview.accent,
                      preview.surfacePressed,
                      preview.popupBackground,
                      preview.foreground,
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(color: preview.divider),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.summary.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground,
                        fontWeight:
                            widget.selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (widget.selected)
                    FaIcon(FontAwesomeIcons.check,
                        size: 11, color: theme.accent)
                  else if (_hovered && widget.onDelete != null)
                    SettingsIconButton(
                      icon: FontAwesomeIcons.trash,
                      size: 11,
                      onTap: widget.onDelete!,
                    ),
                ],
              ),
              Text(
                widget.summary.builtIn ? 'Built-in' : widget.summary.slug,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: theme.fontFamily,
                  color: theme.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Name entry for "New theme…". The name is slugified into a filename, so an
/// empty or punctuation-only name is refused rather than written.
class _NewThemeRow extends StatefulWidget {
  const _NewThemeRow({required this.onSubmit, required this.onCancel});

  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  State<_NewThemeRow> createState() => _NewThemeRowState();
}

class _NewThemeRowState extends State<_NewThemeRow> {
  String _name = '';

  bool get _valid => _name.trim().replaceAll(RegExp(r'[^A-Za-z0-9]'), '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SettingsTextField(
          width: 200,
          initial: '',
          onChanged: (v) => setState(() => _name = v),
        ),
        const SizedBox(width: 8),
        SettingsOptionButton(
          label: 'Create',
          selected: _valid,
          onTap: () {
            if (_valid) widget.onSubmit(_name);
          },
        ),
        const SizedBox(width: 6),
        SettingsIconButton(
          icon: FontAwesomeIcons.xmark,
          size: 12,
          onTap: widget.onCancel,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Calendar
// ---------------------------------------------------------------------------

/// The Calendar tab's own settings. The tab is a local month grid — there is no
/// account integration — so this is presentation only.
class _CalendarSection extends StatelessWidget {
  const _CalendarSection({required this.store});

  final ConfigStore store;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      label: 'Calendar',
      children: [
        SettingsRow(
          label: 'Week starts on',
          control: SettingsSegmented(
            options: const ['sunday', 'monday'],
            value: store.get<String>(['calendar', 'week_start']) ?? 'sunday',
            onChanged: (v) => store.set(['calendar', 'week_start'], v),
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
    return SettingsSection(
      label: 'Modules',
      children: [
        SettingsSubLabel('Weather'),
        SettingsRow(
          label: 'Unit',
          control: SettingsSegmented(
            options: const ['fahrenheit', 'celsius'],
            value: store.get<String>(['modules', 'weather', 'unit']) ??
                'fahrenheit',
            onChanged: (v) => store.set(['modules', 'weather', 'unit'], v),
          ),
        ),
        SettingsRow(
          label: 'Refresh (minutes)',
          control: SettingsNumberField(
            value: store.get<num>(['modules', 'weather', 'refresh_minutes']) ??
                10,
            isInt: true,
            onChanged: (v) =>
                store.set(['modules', 'weather', 'refresh_minutes'], v),
          ),
        ),
        SettingsSubLabel('Battery'),
        SettingsRow(
          label: 'Poll (seconds)',
          control: SettingsNumberField(
            value: store.get<num>(['modules', 'battery', 'poll_seconds']) ?? 30,
            isInt: true,
            onChanged: (v) =>
                store.set(['modules', 'battery', 'poll_seconds'], v),
          ),
        ),
        SettingsSubLabel('Clock'),
        SettingsRow(
          label: 'Show date',
          control: SettingsToggle(
            value: store.get<bool>(['modules', 'clock', 'show_date']) ?? true,
            onChanged: (v) => store.set(['modules', 'clock', 'show_date'], v),
          ),
        ),
        SettingsSubLabel('Media player'),
        SettingsRow(
          label: 'Max text width',
          control: SettingsNumberField(
            value:
                store.get<num>(['modules', 'media_player', 'max_text_width']) ??
                    200,
            isInt: false,
            onChanged: (v) =>
                store.set(['modules', 'media_player', 'max_text_width'], v),
          ),
        ),
        SettingsSubLabel('System tray'),
        SettingsRow(
          label: 'Icon size',
          control: SettingsNumberField(
            value: store.get<num>(['modules', 'system_tray', 'icon_size']) ?? 16,
            isInt: false,
            onChanged: (v) =>
                store.set(['modules', 'system_tray', 'icon_size'], v),
          ),
        ),
        SettingsRow(
          label: 'Collapsed overlap',
          control: SettingsNumberField(
            value: store
                    .get<num>(['modules', 'system_tray', 'collapsed_overlap']) ??
                10,
            isInt: false,
            onChanged: (v) =>
                store.set(['modules', 'system_tray', 'collapsed_overlap'], v),
          ),
        ),
        SettingsRow(
          label: 'Expanded spacing',
          control: SettingsNumberField(
            value:
                store.get<num>(['modules', 'system_tray', 'expanded_spacing']) ??
                    6,
            isInt: false,
            onChanged: (v) =>
                store.set(['modules', 'system_tray', 'expanded_spacing'], v),
          ),
        ),
        SettingsRow(
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
        SettingsSubLabel('Dock'),
        SettingsRow(
          label: 'Icon size',
          control: SettingsNumberField(
            value: store.get<num>(['modules', 'dock', 'icon_size']) ?? 24,
            isInt: true,
            onChanged: (v) => store.set(['modules', 'dock', 'icon_size'], v),
          ),
        ),
        SettingsRow(
          label: 'Show app directory',
          control: SettingsToggle(
            value: store.get<bool>(['modules', 'dock', 'show_app_directory']) ??
                true,
            onChanged: (v) =>
                store.set(['modules', 'dock', 'show_app_directory'], v),
          ),
        ),
        SettingsRow(
          label: 'Apps',
          alignTop: true,
          control: _StringListEditor(
            items: store.getList<String>(['modules', 'dock', 'apps']),
            onChanged: (list) => store.set(['modules', 'dock', 'apps'], list),
            addHint: 'app id',
          ),
        ),
        SettingsSubLabel('System monitor'),
        SettingsRow(
          label: 'Poll (seconds)',
          control: SettingsNumberField(
            value: store.get<num>(['modules', 'system_monitor', 'poll_seconds'])
                    ?.toInt() ??
                2,
            isInt: true,
            onChanged: (v) =>
                store.set(['modules', 'system_monitor', 'poll_seconds'], v),
          ),
        ),
        SettingsRow(
          label: 'Temperature unit',
          control: SettingsSegmented(
            options: const ['celsius', 'fahrenheit'],
            value:
                store.get<String>(['modules', 'system_monitor', 'temp_unit']) ??
                    'celsius',
            onChanged: (v) =>
                store.set(['modules', 'system_monitor', 'temp_unit'], v),
          ),
        ),
        SettingsRow(
          label: 'Graph history (samples)',
          control: SettingsNumberField(
            value: store
                    .get<num>(['modules', 'system_monitor', 'history_samples'])
                    ?.toInt() ??
                120,
            isInt: true,
            onChanged: (v) =>
                store.set(['modules', 'system_monitor', 'history_samples'], v),
          ),
        ),
        SettingsRow(
          label: 'CPU percentages',
          control: SettingsSegmented(
            // "machine" makes the process rows sum to the total CPU gauge;
            // "core" is top-style, where 100% is one saturated core.
            options: const ['machine', 'core'],
            value: store.get<String>(
                    ['modules', 'system_monitor', 'cpu_percent_mode']) ??
                'machine',
            onChanged: (v) =>
                store.set(['modules', 'system_monitor', 'cpu_percent_mode'], v),
          ),
        ),
        SettingsRow(
          label: 'Show kernel threads',
          control: SettingsToggle(
            value: store.get<bool>(
                    ['modules', 'system_monitor', 'show_kernel_threads']) ??
                false,
            onChanged: (v) => store
                .set(['modules', 'system_monitor', 'show_kernel_threads'], v),
          ),
        ),
        SettingsRow(
          label: 'Confirm before quitting a process',
          control: SettingsToggle(
            value:
                store.get<bool>(['modules', 'system_monitor', 'confirm_kill']) ??
                    true,
            onChanged: (v) =>
                store.set(['modules', 'system_monitor', 'confirm_kill'], v),
          ),
        ),
        SettingsSubLabel('Network'),
        SettingsRow(
          label: 'Poll (seconds)',
          control: SettingsNumberField(
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

class _PanelsSection extends StatefulWidget {
  const _PanelsSection({required this.store});

  final ConfigStore store;

  @override
  State<_PanelsSection> createState() => _PanelsSectionState();
}

class _PanelsSectionState extends State<_PanelsSection> {
  /// Known anchor names — used only to give a freshly-added panel a sensible
  /// default anchor (a panel named `left` anchors left). Panels are NOT
  /// created for these by default; the user adds each one manually.
  static const _anchors = ['top', 'bottom', 'left', 'right'];

  int _selected = 0;
  bool _adding = false;
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();

  ConfigStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  String _title(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  void _startAdd() {
    setState(() => _adding = true);
    _nameFocus.requestFocus();
  }

  void _cancelAdd() {
    setState(() {
      _adding = false;
      _nameController.clear();
    });
  }

  void _commitAdd(List<String> existing) {
    final name = _nameController.text.trim();
    if (name.isEmpty || existing.contains(name)) {
      _cancelAdd();
      return;
    }
    // Writing the anchor creates the `[panels.<name>]` table (ConfigStore.set
    // builds intermediate tables); a known anchor name seeds its own position.
    store.set(['panels', name, 'anchor'], _anchors.contains(name) ? name : 'top');
    setState(() {
      _adding = false;
      _nameController.clear();
      _selected = existing.length; // new panel is appended at the end
    });
  }

  /// Deletes `[panels.<name>]` outright, behind a confirmation.
  ///
  /// No restart wiring is needed: `ConfigStore._restartSignature` folds every
  /// panel key, so dropping one raises the restart banner on its own.
  Future<void> _removePanel(String name) async {
    final title = _title(name);
    final names = store.panelNames;
    // Read before the await: the count is what the warning is about, and the
    // name is what survives the removal renumbering every index after it.
    final isLast = names.length <= 1;
    final selectedName =
        names.isEmpty ? null : names[_selected.clamp(0, names.length - 1)];
    final confirmed = await showSettingsConfirm(
      context,
      title: 'Remove the $title panel?',
      message: 'The $title panel and everything under it \u2014 its geometry '
          'and its module layout \u2014 are deleted from config.toml. This '
          'cannot be undone.',
      warning: isLast
          // Not hypothetical: AppConfig.fromMap substitutes a single default
          // panel when `[panels]` is empty, so saying nothing here would make
          // the panel look like it came back on its own.
          ? 'This is the last panel. With none configured, the shell falls '
              'back to a single default panel the next time it starts.'
          : null,
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;
    store.remove(['panels', name]);
    setState(() {
      _adding = false;
      final remaining = store.panelNames;
      // Follow the panel the user was editing rather than the index holding
      // it: removing a tab to its left shifts it down one, and clamping alone
      // would silently land the form on a different panel. Removing the
      // selected one falls back to whatever now occupies its slot.
      final kept = selectedName == null || selectedName == name
          ? -1
          : remaining.indexOf(selectedName);
      _selected = kept >= 0
          ? kept
          : (remaining.isEmpty ? 0 : _selected.clamp(0, remaining.length - 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    final names = store.panelNames;
    final selected = names.isEmpty ? -1 : _selected.clamp(0, names.length - 1);
    return SettingsSection(
      label: 'Panels & Layout',
      children: [
        _buildTabs(names, selected),
        if (_adding) _buildAddField(names),
        if (selected < 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SettingsHint(
              _adding ? 'Name the panel, then press Enter.' : 'No panels yet. '
                  'Use “Add panel” to create one.',
            ),
          )
        else
          _buildPanel(names[selected]),
      ],
    );
  }

  Widget _buildTabs(List<String> names, int selected) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.divider)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < names.length; i++)
                _PanelTab(
                  label: _title(names[i]),
                  selected: i == selected && !_adding,
                  onTap: () => setState(() {
                    _selected = i;
                    _adding = false;
                  }),
                  onRemove: () => _removePanel(names[i]),
                ),
              _PanelTab(
                label: 'Add panel',
                icon: FontAwesomeIcons.plus,
                selected: _adding,
                onTap: _startAdd,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddField(List<String> existing) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.popupBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: _nameFocus.hasFocus ? theme.accent : theme.divider),
              ),
              child: Stack(
                children: [
                  if (_nameController.text.isEmpty)
                    Text(
                      'Panel name (e.g. top)',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.popupForeground.withValues(alpha: 0.35),
                        fontFamily: theme.fontFamily,
                      ),
                    ),
                  EditableText(
                    controller: _nameController,
                    focusNode: _nameFocus,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.popupForeground,
                      fontFamily: theme.fontFamily,
                    ),
                    cursorColor: theme.accent,
                    backgroundCursorColor: theme.divider,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _commitAdd(existing),
                  ),
                ],
              ),
            ),
          ),
          SettingsIconButton(
            icon: FontAwesomeIcons.check,
            onTap: () => _commitAdd(existing),
          ),
          SettingsIconButton(
            icon: FontAwesomeIcons.xmark,
            onTap: _cancelAdd,
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(String name) {
    List<String> p(List<String> rest) => ['panels', name, ...rest];
    // A not-yet-defined anchor panel defaults its anchor to its own position.
    final defaultAnchor = _anchors.contains(name) ? name : 'top';
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsRow(
            label: 'Height',
            control: SettingsNumberField(
              value: store.get<num>(p(['height'])) ?? 32,
              isInt: true,
              onChanged: (v) => store.set(p(['height']), v),
            ),
          ),
          SettingsRow(
            label: 'Horizontal padding',
            control: SettingsNumberField(
              value: store.get<num>(p(['padding_horizontal'])) ?? 8,
              isInt: true,
              onChanged: (v) => store.set(p(['padding_horizontal']), v),
            ),
          ),
          SettingsRow(
            label: 'Anchor',
            control: SettingsSegmented(
              options: const ['top', 'bottom', 'left', 'right'],
              value: store.get<String>(p(['anchor'])) ?? defaultAnchor,
              onChanged: (v) => store.set(p(['anchor']), v),
            ),
          ),
          SettingsRow(
            label: 'Layer',
            control: SettingsSegmented(
              options: const ['background', 'bottom', 'top', 'overlay'],
              value: store.get<String>(p(['layer'])) ?? 'top',
              onChanged: (v) => store.set(p(['layer']), v),
            ),
          ),
          for (final slot in const ['left', 'center', 'right'])
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsSubLabel(
                    '${slot[0].toUpperCase()}${slot.substring(1)} modules',
                  ),
                  const SizedBox(height: 4),
                  _StringListEditor(
                    items: store.getList<String>(p(['layout', slot])),
                    onChanged: (list) => store.set(p(['layout', slot]), list),
                    suggestions: Module.registeredKeys.toList(),
                    width: null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A single tab in the Panels & Layout tab strip. Replicates the overlay's own
/// top-tab underline treatment ([_TabButton] in `overlay.dart`) so the two read
/// as the same idiom: an accent underline and accent text when selected.
class _PanelTab extends StatefulWidget {
  const _PanelTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.onRemove,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final FaIconData? icon;

  /// Deletes the panel this tab names. Null on the "Add panel" tab, which is
  /// the one tab with nothing to delete.
  final VoidCallback? onRemove;

  @override
  State<_PanelTab> createState() => _PanelTabState();
}

class _PanelTabState extends State<_PanelTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final Color color;
    if (widget.selected) {
      color = theme.accent;
    } else if (_hovered) {
      color = theme.popupForeground;
    } else {
      color = theme.popupForeground.withValues(alpha: 0.6);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: widget.selected ? theme.accent : const Color(0x00000000),
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                FaIcon(widget.icon, size: 11, color: color),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: theme.fontFamily,
                  color: color,
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (widget.onRemove != null) ...[
                const SizedBox(width: 6),
                // The slot is occupied whether or not the button is in it: a
                // tab that grew on hover would shove every tab to its right
                // along inside the scrolling strip, under the pointer.
                SizedBox.square(
                  dimension: _kPanelTabCloseSize,
                  child: widget.selected || _hovered
                      ? _PanelTabClose(onTap: widget.onRemove!)
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The side of the square reserved for a tab's remove button.
const double _kPanelTabCloseSize = 18;

/// The x on a panel tab.
///
/// Its own recognizer nested inside the tab's: the gesture arena resolves to
/// the deepest competitor, so a click here removes the panel rather than also
/// selecting the tab. Not a [SettingsIconButton] — that control is 26 square,
/// sized for a form row, and would out-measure the tab's own text.
class _PanelTabClose extends StatefulWidget {
  const _PanelTabClose({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_PanelTabClose> createState() => _PanelTabCloseState();
}

class _PanelTabCloseState extends State<_PanelTabClose> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered ? theme.surfaceHover : const Color(0x00000000),
            borderRadius: BorderRadius.circular(4),
          ),
          child: FaIcon(
            FontAwesomeIcons.xmark,
            size: 10,
            color: _hovered
                ? theme.accent
                : theme.popupForeground.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Background
// ---------------------------------------------------------------------------

/// Visual wallpaper selector: a 3-column preview grid with multi-select, drag
/// reordering of the shown wallpapers, and a single global rotation interval.
///
/// The on-disk `[[background.entries]]` list is kept normalized (shown
/// wallpapers first in presentation order, then hidden ones) and pruned of any
/// entry whose path is empty, non-image, or missing on disk.
/// The lock screen's wallpaper and chrome.
///
/// Unlike the desktop background this is a single wallpaper — a lock screen has
/// no reason to rotate through several — but it accepts video as well as
/// stills, rendered by the same `MediaBackground`.
class _LockSection extends StatefulWidget {
  const _LockSection({required this.store});

  final ConfigStore store;

  @override
  State<_LockSection> createState() => _LockSectionState();
}

class _LockSectionState extends State<_LockSection> {
  ConfigStore get store => widget.store;

  Future<void> _chooseWallpaper() async {
    final paths = await showFilePicker(
      context,
      filters: [
        FilePickerFilter.wallpapers,
        FilePickerFilter.images,
        FilePickerFilter.videos,
        FilePickerFilter.all,
      ],
      allowMultiple: false,
    );
    if (paths == null || paths.isEmpty) return;
    store.set(['lock', 'background'], paths.first);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final path = (store.get<String>(['lock', 'background']) ?? '').trim();
    final missing = path.isNotEmpty && !File(path).existsSync();

    return SettingsSection(
      label: 'Lock Screen',
      children: [
        SettingsRow(
          label: 'Wallpaper',
          alignTop: true,
          control: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsOptionButton(
                    label: 'Choose…',
                    selected: false,
                    onTap: _chooseWallpaper,
                  ),
                  if (path.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    SettingsOptionButton(
                      label: 'Reset',
                      selected: false,
                      onTap: () => store.remove(['lock', 'background']),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 240,
                child: Text(
                  path.isEmpty ? 'Default wallpaper' : path.split('/').last,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: theme.fontFamily,
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.normal,
                    color: missing
                        ? const Color(0xFFE06C75)
                        : theme.popupForeground.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (missing)
          const SettingsHint(
            'That file no longer exists — the shipped default will be used '
            'until you choose another.',
          ),
        SettingsRow(
          label: 'Fit',
          control: SettingsSegmented(
            options: const ['fill', 'contain', 'natural'],
            value: store.get<String>(['lock', 'fit']) ?? 'fill',
            onChanged: (v) => store.set(['lock', 'fit'], v),
          ),
        ),
        SettingsRow(
          label: 'Show name',
          control: SettingsToggle(
            value: store.get<bool>(['lock', 'show_username']) ?? true,
            onChanged: (v) => store.set(['lock', 'show_username'], v),
          ),
        ),
        SettingsRow(
          label: 'Blur when unlocking',
          control: SettingsNumberField(
            value: store.get<num>(['lock', 'blur_sigma']) ?? 18,
            isInt: false,
            onChanged: (v) => store.set(
              ['lock', 'blur_sigma'],
              v.toDouble().clamp(0.0, 100.0),
            ),
          ),
        ),
        const SettingsHint(
          'How strongly the wallpaper blurs once the password field appears. '
          'Set to 0 to leave it sharp.',
        ),
      ],
    );
  }
}

class _BackgroundSection extends StatefulWidget {
  const _BackgroundSection({required this.store});

  final ConfigStore store;

  @override
  State<_BackgroundSection> createState() => _BackgroundSectionState();
}

class _BackgroundSectionState extends State<_BackgroundSection> {
  ConfigStore get store => widget.store;

  List<Map> _rawEntries() =>
      (store.get<List>(['background', 'entries']) ?? const [])
          .whereType<Map>()
          .toList();

  /// Drops invalid entries (empty / non-image / missing on disk), strips the
  /// obsolete `time` key, and orders shown wallpapers before hidden ones — the
  /// canonical presentation order the running shell rotates through.
  List<Map<String, dynamic>> _normalize(List<Map> raw) {
    final valid = <Map<String, dynamic>>[];
    for (final e in raw) {
      final path = '${e['path'] ?? ''}'.trim();
      if (path.isEmpty || !isImagePath(path) || !File(path).existsSync()) {
        continue;
      }
      valid.add({'path': path, 'shown': e['shown'] as bool? ?? true});
    }
    final shown = valid.where((e) => e['shown'] == true).toList();
    final hidden = valid.where((e) => e['shown'] != true).toList();
    return [...shown, ...hidden];
  }

  bool _matches(List<Map> raw, List<Map<String, dynamic>> normalized) {
    if (raw.length != normalized.length) return false;
    for (var i = 0; i < raw.length; i++) {
      if ('${raw[i]['path'] ?? ''}'.trim() != normalized[i]['path']) {
        return false;
      }
      if ((raw[i]['shown'] as bool? ?? true) != normalized[i]['shown']) {
        return false;
      }
    }
    return true;
  }

  void _setShown(String path, bool shown) {
    final list = _normalize(_rawEntries());
    final idx = list.indexWhere((e) => e['path'] == path);
    if (idx < 0) return;
    list[idx] = {'path': path, 'shown': shown};
    store.set(['background', 'entries'], _normalize(list));
  }

  void _reorderShown(int oldIndex, int newIndex) {
    final list = _normalize(_rawEntries());
    final shown = list.where((e) => e['shown'] == true).toList();
    final hidden = list.where((e) => e['shown'] != true).toList();
    if (oldIndex < 0 || oldIndex >= shown.length) return;
    final item = shown.removeAt(oldIndex);
    var insertAt = oldIndex < newIndex ? newIndex - 1 : newIndex;
    insertAt = insertAt.clamp(0, shown.length);
    shown.insert(insertAt, item);
    store.set(['background', 'entries'], [...shown, ...hidden]);
  }

  Future<void> _addWallpapers() async {
    final paths = await showFilePicker(
      context,
      filters: [FilePickerFilter.images, FilePickerFilter.all],
      allowMultiple: true,
    );
    if (paths == null || paths.isEmpty) return;
    final list = _normalize(_rawEntries());
    final existing = list.map((e) => e['path']).toSet();
    for (final p in paths) {
      if (isImagePath(p) && existing.add(p)) {
        list.add({'path': p, 'shown': true});
      }
    }
    store.set(['background', 'entries'], _normalize(list));
  }

  @override
  Widget build(BuildContext context) {
    final raw = _rawEntries();
    final entries = _normalize(raw);
    // Persist the auto-prune / normalization once, after this frame, if it
    // changed anything — never mutate the store during build.
    if (!_matches(raw, entries)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) store.set(['background', 'entries'], entries);
      });
    }
    final shown = entries.where((e) => e['shown'] == true).toList();
    final hidden = entries.where((e) => e['shown'] != true).toList();

    return SettingsSection(
      label: 'Background',
      children: [
        SettingsRow(
          label: 'Fit',
          control: SettingsSegmented(
            options: const ['fill', 'contain', 'natural'],
            value: store.get<String>(['background', 'fit']) ?? 'fill',
            onChanged: (v) => store.set(['background', 'fit'], v),
          ),
        ),
        SettingsRow(
          label: 'Rotation interval (minutes)',
          control: SettingsNumberField(
            value: store.get<num>(['background', 'interval_minutes']) ?? 5,
            isInt: true,
            onChanged: (v) => store.set(['background', 'interval_minutes'],
                v.toInt() < 1 ? 1 : v.toInt()),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: SettingsHint('Selected wallpapers rotate on this interval, in order.'),
        ),
        SettingsSubLabel('Shown'),
        if (shown.isEmpty)
          const SettingsHint('No wallpapers selected. Select one from Available below.')
        else
          _WallpaperGrid(
            entries: shown,
            selected: true,
            onToggle: (p) => _setShown(p, false),
            onReorder: _reorderShown,
          ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _AddButton(label: 'Add wallpaper', onTap: _addWallpapers),
        ),
        SettingsSubLabel('Available'),
        if (hidden.isEmpty)
          const SettingsHint('No hidden wallpapers.')
        else
          _WallpaperGrid(
            entries: hidden,
            selected: false,
            onToggle: (p) => _setShown(p, true),
          ),
      ],
    );
  }
}

/// A responsive 3-column grid of [_WallpaperTile]s. When [onReorder] is given
/// (the "shown" group) each tile is draggable and accepts drops to reorder.
class _WallpaperGrid extends StatelessWidget {
  const _WallpaperGrid({
    required this.entries,
    required this.selected,
    required this.onToggle,
    this.onReorder,
  });

  final List<Map<String, dynamic>> entries;
  final bool selected;
  final void Function(String path) onToggle;
  final void Function(int oldIndex, int newIndex)? onReorder;

  @override
  Widget build(BuildContext context) {
    const columns = 3;
    const gap = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileW = (constraints.maxWidth - gap * (columns - 1)) / columns;
        final tileH = tileW * 0.6;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < entries.length; i++)
              SizedBox(
                width: tileW,
                height: tileH,
                child: _cell(context, i, tileW, tileH),
              ),
          ],
        );
      },
    );
  }

  Widget _cell(BuildContext context, int index, double w, double h) {
    final path = entries[index]['path'] as String;
    final tile = _WallpaperTile(
      path: path,
      selected: selected,
      onTap: () => onToggle(path),
    );
    if (onReorder == null) return tile;
    final theme = ThemeScope.of(context);
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onAcceptWithDetails: (d) => onReorder!(d.data, index),
      builder: (context, candidate, rejected) {
        final isTarget = candidate.isNotEmpty;
        return Draggable<int>(
          data: index,
          feedback: SizedBox(
            width: w,
            height: h,
            child: Opacity(
              opacity: 0.9,
              child: _WallpaperTile(
                path: path,
                selected: true,
                onTap: () {},
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: tile),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: isTarget
                  ? Border.all(color: theme.accent, width: 2)
                  : null,
            ),
            child: tile,
          ),
        );
      },
    );
  }
}

/// A single wallpaper preview cell. Renders the image cover-cropped with a
/// selection border + check badge, mirroring [SettingsOptionButton]'s selected styling.
class _WallpaperTile extends StatefulWidget {
  const _WallpaperTile({
    required this.path,
    required this.selected,
    required this.onTap,
  });

  final String path;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_WallpaperTile> createState() => _WallpaperTileState();
}

class _WallpaperTileState extends State<_WallpaperTile> {
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(widget.path),
                fit: BoxFit.cover,
                cacheWidth: 320,
                gaplessPlayback: true,
                errorBuilder: (c, e, s) =>
                    ColoredBox(color: theme.controlSurface),
              ),
              if (!widget.selected && !_hovered)
                const ColoredBox(color: Color(0x33000000)),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: widget.selected
                        ? theme.accent
                        : (_hovered ? theme.surfaceHover : theme.divider),
                    width: widget.selected ? 2 : 1,
                  ),
                ),
              ),
              if (widget.selected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: theme.accent,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const FaIcon(
                      FontAwesomeIcons.check,
                      size: 10,
                      color: Color(0xFFFFFFFF),
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


/// Editable ordered list of strings. When [suggestions] is provided, new items
/// are added from a dropdown of those values; otherwise a free-form text field
/// is shown. Existing items can be reordered and removed.
class _StringListEditor extends StatefulWidget {
  const _StringListEditor({
    required this.items,
    required this.onChanged,
    this.suggestions,
    this.addHint,
    this.width = 260,
  });

  final List<String> items;
  final ValueChanged<List<String>> onChanged;
  final List<String>? suggestions;
  final String? addHint;

  /// Fixed editor width. Pass `null` to stretch to the parent's width (used on
  /// the Panels page, where the list sits full-width under its label).
  final double? width;

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
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.items.length; i++)
          _row(context, i, widget.items[i]),
        const SizedBox(height: 6),
        _buildAdder(context),
      ],
    );
    final width = widget.width;
    return width == null ? column : SizedBox(width: width, child: column);
  }

  Widget _row(BuildContext context, int i, String item) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        decoration: BoxDecoration(
          color: theme.controlSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.divider),
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
            SettingsIconButton(
              icon: FontAwesomeIcons.chevronUp,
              size: 10,
              onTap: () => _move(i, -1),
            ),
            SettingsIconButton(
              icon: FontAwesomeIcons.chevronDown,
              size: 10,
              onTap: () => _move(i, 1),
            ),
            SettingsIconButton(
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
        SettingsIconButton(
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
              color: theme.controlSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.divider),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
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

/// The Desktop category: grid geometry plus the list of pinned items.
///
/// Everything here is edited through [DesktopStore] rather than written to
/// [ConfigStore] directly, so the running grid and the file cannot drift — the
/// store owns both the in-memory list and the write.
class _DesktopSection extends StatefulWidget {
  const _DesktopSection({required this.store});

  final ConfigStore store;

  @override
  State<_DesktopSection> createState() => _DesktopSectionState();
}

class _DesktopSectionState extends State<_DesktopSection> {
  DesktopStore get _desktop => DesktopStore.instance;

  void _setGrid(DesktopConfig Function(DesktopConfig) update) =>
      _desktop.setGrid(update(_desktop.config));

  /// The settings panel is not the desktop, so there is no live geometry to
  /// place against; a nominal grid is enough, because addItem only needs
  /// somewhere free and the desktop reflows anything out of range anyway.
  DesktopGridGeometry get _nominalGeometry =>
      computeGridGeometry(const Size(1920, 1080), _desktop.config);

  /// Picks an application from a searchable list of what is installed, rather
  /// than making the user find a `.desktop` file on disk.
  ///
  /// The rows hold `GAppInfo` pointers owned by [AppIndex], whose refresh
  /// unrefs the previous ones, so the index is pinned while the chooser is up —
  /// the contract `_openLauncher` follows.
  Future<void> _addApplication() async {
    AppIndex.instance.acquire();
    try {
      final app = await showAppChooser(
        context,
        apps: AppIndex.instance.searchable,
      );
      if (app == null || app.filename.isEmpty || !mounted) return;
      _desktop.addItem(
        DesktopItem(kind: DesktopItemKind.app, target: app.filename),
        _nominalGeometry,
      );
    } finally {
      AppIndex.instance.release();
    }
  }

  Future<void> _addFiles() async {
    final paths = await showFilePicker(
      context,
      filters: [FilePickerFilter.all],
      allowMultiple: true,
      allowDirectories: true,
    );
    if (paths == null || paths.isEmpty || !mounted) return;
    for (final path in paths) {
      _desktop.addItem(desktopItemForPath(path), _nominalGeometry);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _desktop,
      builder: (context, _) {
        final config = _desktop.config;
        final items = _desktop.items;

        return SettingsSection(
          label: 'Desktop',
          children: [
            SettingsRow(
              label: 'Show desktop icons',
              control: SettingsToggle(
                value: config.enabled,
                onChanged: (v) =>
                    _setGrid((c) => _copyDesktop(c, enabled: v)),
              ),
            ),
            // Enabling the grid is what creates the background surface when
            // there is no wallpaper, and that surface is built at startup.
            const SettingsHint(
              'Turning desktop icons on or off takes effect after a restart '
              'when no wallpaper is configured.',
            ),
            SettingsRow(
              label: 'Cell width',
              control: SettingsNumberField(
                value: config.cellWidth,
                isInt: true,
                onChanged: (v) => _setGrid(
                    (c) => _copyDesktop(c, cellWidth: v.toDouble())),
              ),
            ),
            SettingsRow(
              label: 'Cell height',
              control: SettingsNumberField(
                value: config.cellHeight,
                isInt: true,
                onChanged: (v) => _setGrid(
                    (c) => _copyDesktop(c, cellHeight: v.toDouble())),
              ),
            ),
            SettingsRow(
              label: 'Spacing',
              control: SettingsNumberField(
                value: config.spacing,
                isInt: true,
                onChanged: (v) =>
                    _setGrid((c) => _copyDesktop(c, spacing: v.toDouble())),
              ),
            ),
            SettingsRow(
              label: 'Edge padding',
              control: SettingsNumberField(
                value: config.padding,
                isInt: true,
                onChanged: (v) =>
                    _setGrid((c) => _copyDesktop(c, padding: v.toDouble())),
              ),
            ),
            SettingsRow(
              label: 'Icon size',
              control: SettingsNumberField(
                value: config.iconSize,
                isInt: true,
                onChanged: (v) =>
                    _setGrid((c) => _copyDesktop(c, iconSize: v.toDouble())),
              ),
            ),
            SettingsRow(
              label: 'Show labels',
              control: SettingsToggle(
                value: config.showLabels,
                onChanged: (v) =>
                    _setGrid((c) => _copyDesktop(c, showLabels: v)),
              ),
            ),
            const SettingsHint(
              'The number of columns and rows is derived from each monitor, so '
              'the same icons fit displays of different sizes.',
            ),
            const SettingsSubLabel('Pinned items'),
            if (items.isEmpty)
              const SettingsHint('Nothing pinned yet.')
            else
              for (final item in items)
                _DesktopItemRow(
                  item: item,
                  onRemove: () => _desktop.removeItem(item.target),
                ),
            const SizedBox(height: 10),
            Row(
              children: [
                _AddButton(
                  label: 'Add application…',
                  onTap: _addApplication,
                ),
                const SizedBox(width: 8),
                _AddButton(
                  label: 'Add file or folder…',
                  onTap: _addFiles,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// [DesktopConfig] has no `copyWith` — it is a config type, parsed once from
/// TOML, and every other one in `config.dart` is the same. This is local to the
/// one place that edits fields individually.
DesktopConfig _copyDesktop(
  DesktopConfig c, {
  bool? enabled,
  double? cellWidth,
  double? cellHeight,
  double? spacing,
  double? padding,
  double? iconSize,
  bool? showLabels,
}) {
  return DesktopConfig(
    enabled: enabled ?? c.enabled,
    cellWidth: cellWidth ?? c.cellWidth,
    cellHeight: cellHeight ?? c.cellHeight,
    spacing: spacing ?? c.spacing,
    padding: padding ?? c.padding,
    iconSize: iconSize ?? c.iconSize,
    showLabels: showLabels ?? c.showLabels,
    items: c.items,
  );
}

/// One pinned item: its label, its path, and a remove button.
class _DesktopItemRow extends StatelessWidget {
  const _DesktopItemRow({required this.item, required this.onRemove});

  final DesktopItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final missing = !desktopItemExists(item);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: FaIcon(
              switch (item.kind) {
                DesktopItemKind.app => FontAwesomeIcons.rocket,
                DesktopItemKind.folder => FontAwesomeIcons.solidFolder,
                DesktopItemKind.file => FontAwesomeIcons.file,
              },
              size: 12,
              color: theme.accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  labelForItem(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground,
                  ),
                ),
                Text(
                  item.target,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: theme.fontFamily,
                    // A target that has gone missing is called out here rather
                    // than dropped, matching how the desktop dims it.
                    color: missing ? const Color(0xFFE06C75) : theme.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SettingsIconButton(
            icon: FontAwesomeIcons.trash,
            size: 12,
            onTap: onRemove,
          ),
        ],
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
            color: _hovered ? theme.surfaceHover : theme.controlSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(FontAwesomeIcons.plus,
                  size: 11,
                  color: _hovered ? theme.popupForeground : theme.accent),
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
