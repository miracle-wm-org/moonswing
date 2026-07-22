// ignore_for_file: library_private_types_in_public_api

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/overlay/calendar/calendar_store.dart';
import 'package:graceful_shell/overlay/file_picker.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';

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
  _ShellCategory(
    title: 'Lock Screen',
    subtitle: 'Wallpaper and unlock',
    icon: FontAwesomeIcons.lock,
    build: _buildLock,
  ),
  _ShellCategory(
    title: 'Calendar',
    subtitle: 'Connected accounts',
    icon: FontAwesomeIcons.calendarDays,
    build: _buildCalendar,
  ),
];

Widget _buildAppearance(ConfigStore store) => _AppearanceSection(store: store);
Widget _buildModules(ConfigStore store) => _ModulesSection(store: store);
Widget _buildPanels(ConfigStore store) => _PanelsSection(store: store);
Widget _buildBackground(ConfigStore store) => _BackgroundSection(store: store);
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
    return SettingsSection(
      label: 'Appearance',
      children: [
        SettingsRow(
          label: 'Font',
          control: SettingsTextField(
            width: 180,
            initial: store.get<String>(['theme', 'font']) ?? 'Ubuntu Sans',
            onChanged: (v) => store.set(['theme', 'font'], v.trim()),
          ),
        ),
        for (final c in _colors)
          SettingsRow(
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
// Calendar
// ---------------------------------------------------------------------------

/// The same OAuth credentials the calendar tab's connect pane asks for, kept
/// reachable here once an account is connected and that pane is gone. Both
/// write the same config keys, so there is one source of truth.
class _CalendarSection extends StatelessWidget {
  const _CalendarSection({required this.store});

  final ConfigStore store;

  @override
  Widget build(BuildContext context) {
    final calendar = CalendarStore.instance;

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
        SettingsRow(
          label: 'Refresh every (minutes)',
          control: SettingsNumberField(
            isInt: true,
            value: store.get<int>(['calendar', 'refresh_minutes']) ?? 15,
            onChanged: (v) =>
                store.set(['calendar', 'refresh_minutes'], v.toInt()),
          ),
        ),
        const SettingsSubLabel('Google'),
        const SettingsHint(
          'Graceful Shell signs in with your own Google OAuth client. Create a '
          '"Desktop app" client in the Google Cloud Console and enable the '
          'Calendar API, then paste its credentials here. Sign-in tokens are '
          'stored separately, outside config.toml.',
        ),
        SettingsRow(
          label: 'Client ID',
          control: SettingsTextField(
            width: 220,
            initial: store.get<String>(['calendar', 'google', 'client_id']) ?? '',
            onChanged: (v) =>
                store.set(['calendar', 'google', 'client_id'], v.trim()),
          ),
        ),
        SettingsRow(
          label: 'Client secret',
          control: SettingsTextField(
            width: 220,
            initial:
                store.get<String>(['calendar', 'google', 'client_secret']) ?? '',
            onChanged: (v) =>
                store.set(['calendar', 'google', 'client_secret'], v.trim()),
          ),
        ),
        ListenableBuilder(
          listenable: calendar,
          builder: (context, _) {
            final account = calendar.google?.account;
            return SettingsRow(
              label: 'Account',
              control: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsHint(account?.email ?? 'Not connected'),
                  if (account != null) ...[
                    const SizedBox(width: 8),
                    SettingsIconButton(
                      icon: FontAwesomeIcons.rightFromBracket,
                      size: 12,
                      onTap: () => calendar.disconnect('google'),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        if (CalendarStore.instance.google?.isConnected != true)
          const SettingsHint('Connect from the Calendar tab.'),
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
              value: store.get<num>(p(['padding_horizontal'])) ?? 40,
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
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final FaIconData? icon;

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
            ],
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
  final _link = LayerLink();
  // The picker floats in the root overlay (not a nearby OverlayPortal target)
  // so a nested Navigator's clipped Overlay can't cut it off. See _open().
  OverlayEntry? _pickerEntry;
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
    _close();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_pickerEntry != null) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    if (_pickerEntry != null) return;
    // Insert into the root overlay so the picker can extend past the settings
    // content pane (whose nested Navigator Overlay would otherwise clip it).
    final entry = OverlayEntry(builder: (context) => _buildPicker());
    _pickerEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  void _close() {
    _pickerEntry?.remove();
    _pickerEntry = null;
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
    final swatch = parseHexColor(_controller.text);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CompositedTransformTarget(
          link: _link,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _toggle,
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
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),
          child: _ColorPickerPopup(
            initial: parseHexColor(_controller.text) ?? const Color(0xFF000000),
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
    final c = parseHexColor(text);
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
