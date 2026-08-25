// ignore_for_file: library_private_types_in_public_api


import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/overlay/settings/shell/appearance.dart';
import 'package:graceful_shell/overlay/settings/shell/background.dart';
import 'package:graceful_shell/overlay/settings/shell/calendar.dart';
import 'package:graceful_shell/overlay/settings/shell/desktop.dart';
import 'package:graceful_shell/overlay/settings/shell/lock.dart';
import 'package:graceful_shell/overlay/settings/shell/modules.dart';
import 'package:graceful_shell/overlay/settings/shell/panels.dart';

import 'package:graceful_shell/overlay/settings/controls.dart';
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

Widget _buildAppearance(ConfigStore store) => AppearanceSection(store: store);
Widget _buildModules(ConfigStore store) => ModulesSection(store: store);
Widget _buildPanels(ConfigStore store) => PanelsSection(store: store);
Widget _buildBackground(ConfigStore store) => BackgroundSection(store: store);
Widget _buildDesktop(ConfigStore store) => DesktopSection(store: store);
Widget _buildLock(ConfigStore store) => LockSection(store: store);
Widget _buildCalendar(ConfigStore store) => CalendarSection(store: store);

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
    // The curve and the tween are built once, by [_SlideFadeTransition], and
    // not here: `transitionsBuilder` is called from a ListenableBuilder on the
    // route's own animations, so it runs on *every frame* of the transition.
    // Spelling the CurvedAnimation inline therefore minted one per frame —
    // each of which registers a status listener on the parent and is never
    // disposed — and handed FadeTransition/SlideTransition a different
    // Listenable every frame, so both re-subscribed on each tick instead of
    // simply being ticked.
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        _SlideFadeTransition(animation: animation, child: child),
  );
}

/// The [_slideRoute] transition, owning its [CurvedAnimation] for the life of
/// the route rather than for one frame.
class _SlideFadeTransition extends StatefulWidget {
  const _SlideFadeTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_SlideFadeTransition> createState() => _SlideFadeTransitionState();
}

class _SlideFadeTransitionState extends State<_SlideFadeTransition> {
  late CurvedAnimation _curved;
  late Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(_SlideFadeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A route keeps one animation for its whole life, so this is defensive
    // rather than expected — but a CurvedAnimation left listening to an
    // animation nobody drives any more is a leak either way.
    if (!identical(oldWidget.animation, widget.animation)) {
      _curved.dispose();
      _bind();
    }
  }

  void _bind() {
    _curved = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _offset = Tween<Offset>(
      begin: const Offset(0.06, 0),
      end: Offset.zero,
    ).animate(_curved);
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curved,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

/// Tappable, hover-aware row on the landing page. Styled after the sidebar's
/// [_SidebarItem]: icon + title + subtitle + trailing chevron.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});

  final _ShellCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: HoverRegion(
        onTap: onTap,
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: hovered ? theme.surfaceHover : theme.controlSurface,
            borderRadius: BorderRadius.circular(ShellRadii.card),
            border: Border.all(
              color: hovered ? theme.accent : theme.divider,
            ),
          ),
          child: Row(
            children: [
              FaIcon(
                category.icon,
                size: ShellFontSizes.title,
                color: hovered
                    ? theme.accent
                    : theme.popupForeground.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.title,
                      style: TextStyle(
                        fontSize: ShellFontSizes.label,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category.subtitle,
                      style: TextStyle(
                        fontSize: ShellFontSizes.secondary,
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
                size: ShellFontSizes.secondary,
                color: theme.popupForeground.withValues(alpha: 0.4),
              ),
            ],
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
