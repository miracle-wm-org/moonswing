// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/hover_region.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/overlay/settings/shell/appearance.dart';
import 'package:moonswing/overlay/settings/shell/background.dart';
import 'package:moonswing/overlay/settings/shell/calendar.dart';
import 'package:moonswing/overlay/settings/shell/desktop.dart';
import 'package:moonswing/overlay/settings/shell/lock.dart';
import 'package:moonswing/overlay/settings/shell/modules.dart';
import 'package:moonswing/overlay/settings/shell/panels.dart';
import 'package:moonswing/overlay/settings/shell/power.dart';
import 'package:moonswing/overlay/settings/shell/volume_sound.dart';

import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_highlight.dart';
import 'package:moonswing/theme/theme_store.dart';

/// Settings page for moonswing's own configuration (`config.toml`).
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

  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  SettingsHighlightController? _highlight;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_highlight != null) return;
    // `readOf`, not `maybeOf`: this pane is a `Navigator`'s owner and must not
    // be rebuilt by a jump landing — what it does about one is push a route,
    // which is not a build. Null outside the settings overlay, which is what a
    // page pumped alone in a widget test is.
    final highlight = SettingsHighlightScope.readOf(context);
    if (highlight == null) return;
    _highlight = highlight;
    highlight.addListener(_onJumpRequested);
  }

  /// Takes the Shell pane to the category a search result named.
  ///
  /// Always pops to the landing page and pushes again, even when the category is
  /// the one already showing: the row that claims the jump does so from its own
  /// first build, so re-entering the category is what guarantees there is one.
  /// Both routes are instant, so this is one frame with nothing to see.
  void _onJumpRequested() {
    final target = _highlight?.target;
    final category = _shellCategoryByTitle(target?.field.route.shellCategory);
    if (category == null) return;
    final navigator = _navigator.currentState;
    if (navigator == null) return;
    navigator.popUntil((route) => route.isFirst);
    navigator.push(
      _categoryRoute(_ShellCategoryView(category: category, store: _store)),
    );
  }

  @override
  void dispose() {
    _highlight?.removeListener(_onJumpRequested);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildBody()),
        // Only surfaces when a restart-only field actually changed.
        // Selected rather than built on every notify: `needsRestart` walks
        // `[panels]` and allocates a string per key, and this listener fired on
        // every keystroke anywhere in the settings UI.
        StoreSelector<bool>(
          listenable: _store,
          selector: () => _store.needsRestart,
          builder: (context, needsRestart) =>
              needsRestart ? _RestartBanner() : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildBody() {
    final store = _store;
    // A jump that arrives *before* this pane exists — the user was on the
    // Audio page and searched for a theme colour — has nothing to push onto,
    // so the pending target seeds the initial route instead. `_onJumpRequested`
    // covers the other order, where the pane is already built.
    final pending = _highlight?.target?.field.route.shellCategory;
    final initial = _shellCategoryByTitle(pending ?? widget.initialCategory);
    // A nested Navigator lets the Shell pane drill from the category menu into
    // a single category's settings and back, while the outer Settings bar and
    // sidebar (owned by SettingsOverlay) stay put around this pane.
    return Navigator(
      key: _navigator,
      onGenerateInitialRoutes: (navigator, initialRoute) => [
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, _, _) => _ShellHome(store: store),
        ),
        // A deep link pushes the category *on top of* the landing page rather
        // than replacing it, so Back still goes where the user expects.
        if (initial != null)
          _categoryRoute(_ShellCategoryView(category: initial, store: store)),
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

  /// Builds the category's body as a **sliver**, for the [CustomScrollView] in
  /// [_ShellCategoryView] — [SliverSettingsSection] in the ordinary case. The
  /// signature is unchanged from when these returned boxes; only the contract
  /// is, because a sliver is a widget like any other.
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
    title: 'Power Button',
    subtitle: 'What the machine\'s power key does',
    icon: FontAwesomeIcons.powerOff,
    build: _buildPower,
  ),
  _ShellCategory(
    title: 'Volume Sound',
    subtitle: 'What a volume change sounds like',
    icon: FontAwesomeIcons.volumeHigh,
    build: _buildVolumeSound,
  ),
  _ShellCategory(
    title: 'Calendar',
    subtitle: 'Month grid and Google calendars',
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
Widget _buildPower(ConfigStore store) => PowerSection(store: store);
Widget _buildVolumeSound(ConfigStore store) =>
    VolumeSoundSection(store: store);
Widget _buildCalendar(ConfigStore store) => CalendarSection(store: store);

/// Landing view: the "Moonswing" header plus a tappable row per category.
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
            'Moonswing',
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
          // Eight cards do not need laziness, but `SliverList` gives each one
          // its own repaint boundary for free, which is what a hover on one of
          // them needs — see [SettingsRow].
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                sliver: SliverList.list(
                  children: [
                    for (final category in _shellCategories)
                      _CategoryCard(
                        category: category,
                        onTap: () => Navigator.of(context).push(
                          _categoryRoute(
                            _ShellCategoryView(
                              category: category,
                              store: store,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
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
    // Depends on the scope deliberately, unlike the rows and the pane above:
    // this widget's whole reaction to a jump *is* a rebuild, and it is two of
    // them — one when the target lands and one when the row clears it.
    final target = SettingsHighlightScope.maybeOf(context)?.target;
    // A result with no row to land on — the "Theme", "Wallpapers" and "Pinned
    // items" entries name a collection rather than a field — navigates here
    // and nothing more. Holding the page mounted for one of those would be
    // paying the whole cost of the mechanism for a jump that has nothing to
    // scroll to, and paying it until the target expires.
    final jumping =
        target != null &&
        target.field.highlights &&
        target.field.route.shellCategory == category.title;
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
          // No `ListenableBuilder` here, deliberately. [ConfigStore] notifies on
          // every `set` — once per keystroke in any field on any pane — so a
          // builder at this level rebuilt every row of the category for one digit
          // typed into one of them. Each section subscribes to the values it
          // renders instead; see `ConfigValue` and `StoreSelector`.
          //
          // The rule that leaves behind: every `store.get`/`getList` under
          // `settings/shell/` is either inside one of those builders or inside an
          // event handler. A read left in a bare `build` does not throw — it
          // silently stops updating, which reads as "I typed and nothing
          // happened".
          //
          // Every category builder returns a **sliver**. A
          // `SingleChildScrollView` laid the whole category out at once and,
          // with no repaint boundary on its child, re-recorded the entire page's
          // display list on every scroll frame.
          //
          // `cacheExtent` is raised well past the default 250: a `SliverList`
          // unmounts a child that far past the edge, and these controls own their
          // state — a [SettingsTextField]'s controller reads its seed once, so a
          // remount mid-word would reset the selection.
          child: CustomScrollView(
            // Ordinarily 600. While a search jump for *this* category is pending
            // it is effectively unbounded, which is the whole mechanism behind
            // "take me to that field": a `SliverList` never builds a child far
            // past the viewport edge, so a row forty settings down has no element
            // for `Scrollable.ensureVisible` to scroll to. Holding the page
            // mounted for the one frame the jump lands in is what gives it one,
            // and the row clears the target as soon as it has scrolled.
            scrollCacheExtent: jumping
                ? const ScrollCacheExtent.pixels(1e6)
                : const ScrollCacheExtent.pixels(600),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                sliver: category.build(store),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Instant route for pushing a category view.
///
/// Deliberately no transition. Every route in this nested [Navigator] fills the
/// same box against the same opaque panel fill, so an animated push spends its
/// whole duration showing the outgoing page *through* the incoming one — which
/// reads as the pane flickering rather than as movement. `transitionsBuilder` is
/// left at its default, which returns the child unwrapped.
PageRoute<T> _categoryRoute<T>(Widget child) {
  return PageRouteBuilder<T>(
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) => child,
  );
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
    // Everything but the leading glyph and the card's own fill is
    // hover-invariant, so it is built once here and handed to the builder as a
    // captured child. An identical widget is one the framework skips outright,
    // which is what keeps the rebuild the RepaintBoundary contains down to a
    // decoration — see [SettingsRow].
    final label = Expanded(
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
    );
    final chevron = FaIcon(
      FontAwesomeIcons.chevronRight,
      size: ShellFontSizes.secondary,
      color: theme.popupForeground.withValues(alpha: 0.4),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      // Not inside a [SettingsRow], so it carries its own — see that class for
      // the rule.
      child: RepaintBoundary(
        child: HoverRegion(
          onTap: onTap,
          builder: (context, hovered) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: hovered ? theme.surfaceHover : theme.controlSurface,
              borderRadius: BorderRadius.circular(ShellRadii.card),
              border: Border.all(color: hovered ? theme.accent : theme.divider),
            ),
            child: Row(
              children: [
                FaIcon(
                  category.icon,
                  size: ShellFontSizes.title,
                  color: hovered
                      ? theme.accentText
                      : theme.popupForeground.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 14),
                label,
                const SizedBox(width: 10),
                chevron,
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
/// The palette no longer lives in `config.toml` — [ThemeStore] owns a file per
/// theme and `config.toml` only names the active one. So this section talks to
/// [ThemeStore], not [store]; the parameter stays because every category builder
/// takes one.

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
          FaIcon(
            FontAwesomeIcons.arrowsRotate,
            size: 12,
            color: theme.accentText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Changes are saved automatically. Restart Moonswing for '
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
