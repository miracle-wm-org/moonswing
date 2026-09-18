// ignore_for_file: library_private_types_in_public_api

// Settings > Window Manager: miracle-wm's own configuration.
//
// The one pane in this shell that edits *another program's* file. Everything
// else under Settings either drives a running service (locale1, BlueZ,
// PulseAudio) or writes graceful-shell's own `config.toml`; this writes
// `~/.config/miracle-wm/config.yaml`, which belongs to the compositor the shell
// is running inside.
//
// Three consequences shape the page, and they are why it does not simply look
// like the Shell pane:
//
//  * **Nothing is written until Save.** The Shell pane debounces every keystroke
//    straight to disk, which is safe because the shell re-reads its own config
//    live. A compositor does not: a half-typed border size written the moment it
//    is typed is what the user's next reload would apply, and a compositor that
//    will not start has no settings page to fix it from. So edits accumulate in
//    native memory and Save is a deliberate act — with Reset to throw the batch
//    away.
//  * **A save is only half the job.** miracle does not watch its configuration
//    file, so the page tells the user how to make it re-read one — read off the
//    configuration rather than hard-coded, because the binding can be rebound.
//  * **miracle-wm may not be installed.** The whole pane is then one sentence
//    and a Retry, rather than an empty form that looks like a compositor with no
//    settings.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:miracle/miracle.dart' show MiracleConfigError;

import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/miracle_config/miracle_config_store.dart';
import 'package:graceful_shell/miracle_config/miracle_key_codes.dart';
import 'package:graceful_shell/miracle_config/miracle_labels.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/overlay/settings/miracle/accessibility.dart';
import 'package:graceful_shell/overlay/settings/miracle/animations.dart';
import 'package:graceful_shell/overlay/settings/miracle/gaps_borders.dart';
import 'package:graceful_shell/overlay/settings/miracle/general.dart';
import 'package:graceful_shell/overlay/settings/miracle/includes.dart';
import 'package:graceful_shell/overlay/settings/miracle/key_bindings.dart';
import 'package:graceful_shell/overlay/settings/miracle/keyboard.dart';
import 'package:graceful_shell/overlay/settings/miracle/pointer.dart';
import 'package:graceful_shell/overlay/settings/miracle/startup.dart';
import 'package:graceful_shell/overlay/settings/miracle/workspaces.dart';
import 'package:graceful_shell/overlay/settings/settings_highlight.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

class MiracleSettingsPage extends StatefulWidget {
  const MiracleSettingsPage({
    super.key,
    this.initialCategory,
    MiracleConfigStore? store,
  }) : _store = store;

  /// A `_MiracleCategory.title` to open directly, e.g. `Gaps & Borders`. Null
  /// lands on the category list.
  final String? initialCategory;

  /// Injected by widget tests, so nothing here dlopens `libmiracle-wm-c`.
  final MiracleConfigStore? _store;

  @override
  _MiracleSettingsPageState createState() => _MiracleSettingsPageState();
}

class _MiracleSettingsPageState extends State<MiracleSettingsPage> {
  late final MiracleConfigStore _store =
      widget._store ?? MiracleConfigStore.instance;

  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  SettingsHighlightController? _highlight;

  @override
  void initState() {
    super.initState();
    // Naturally scoped, like the Keyboard pane's: `_buildCategoryContent` is a
    // switch returning a different widget per sidebar category, so leaving the
    // pane releases the lease. Whether that frees the configuration is the
    // store's call — it holds on to one with unsaved edits in it.
    _store.acquire();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_highlight != null) return;
    // `readOf`, not `maybeOf`, for `shell.dart`'s reason: this pane owns a
    // `Navigator` and must not be rebuilt by a jump landing.
    final highlight = SettingsHighlightScope.readOf(context);
    if (highlight == null) return;
    _highlight = highlight;
    highlight.addListener(_onJumpRequested);
  }

  @override
  void dispose() {
    _highlight?.removeListener(_onJumpRequested);
    _store.release();
    super.dispose();
  }

  /// Takes the pane to the category a search result named.
  void _onJumpRequested() {
    final target = _highlight?.target;
    final category = _miracleCategoryByTitle(
      target?.field.route.miracleCategory,
    );
    if (category == null) return;
    final navigator = _navigator.currentState;
    if (navigator == null) return;
    navigator.popUntil((route) => route.isFirst);
    navigator.push(
      _categoryRoute(_MiracleCategoryView(category: category, store: _store)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The whole pane is one subscription on the *status*, not on the
    // configuration: which of the four screens is showing changes about twice
    // in a session, while the tree under it changes on every keystroke. The
    // rows below subscribe per value; see [MiracleValue].
    return StoreSelector<MiracleConfigStatus>(
      listenable: _store,
      selector: () => _store.status,
      builder: (context, status) => switch (status) {
        MiracleConfigStatus.loaded => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildBody()),
            _MiracleFooter(store: _store),
          ],
        ),
        MiracleConfigStatus.idle => const Center(
          child: LoadingIndicator(size: 22),
        ),
        MiracleConfigStatus.unavailable => _unavailable(),
        MiracleConfigStatus.failed => _failed(),
      },
    );
  }

  Widget _buildBody() {
    // A jump that arrives before this pane exists seeds the initial route;
    // `_onJumpRequested` covers the other order. `shell.dart`'s arrangement.
    final pending = _highlight?.target?.field.route.miracleCategory;
    final initial = _miracleCategoryByTitle(pending ?? widget.initialCategory);
    return Navigator(
      key: _navigator,
      onGenerateInitialRoutes: (navigator, initialRoute) => [
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, _, _) => _MiracleHome(store: _store),
        ),
        if (initial != null)
          _categoryRoute(
            _MiracleCategoryView(category: initial, store: _store),
          ),
      ],
    );
  }

  Widget _unavailable() => _Message(
    icon: FontAwesomeIcons.puzzlePiece,
    title: 'miracle-wm is not installed here',
    message: _store.unavailableReason.isEmpty
        ? 'This page reads and writes the compositor’s configuration '
              'through libmiracle-wm-c, which ships with miracle-wm 0.10 and '
              'newer. Install the miracle-wm package to edit it here.'
        : '${_store.unavailableReason}\n\nThe library ships with miracle-wm '
              '0.10 and newer.',
    onRetry: _store.retry,
  );

  Widget _failed() => _Message(
    icon: FontAwesomeIcons.triangleExclamation,
    title: 'Could not read the configuration',
    message: _store.unavailableReason,
    onRetry: _store.retry,
  );
}

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

/// One selectable category, shown on the landing page and pushed as its own
/// view when tapped.
class _MiracleCategory {
  const _MiracleCategory({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.build,
  });

  final String title;
  final String subtitle;
  final FaIconData icon;

  /// Builds the category's body as a **sliver**, for the [CustomScrollView] in
  /// [_MiracleCategoryView] — the Shell pane's contract, unchanged.
  final Widget Function(MiracleConfigStore store) build;
}

const List<_MiracleCategory> _miracleCategories = [
  _MiracleCategory(
    title: 'General',
    subtitle: 'Action Key, terminal, background',
    icon: FontAwesomeIcons.sliders,
    build: _buildGeneral,
  ),
  _MiracleCategory(
    title: 'Gaps & Borders',
    subtitle: 'Space around windows, and the line around each',
    icon: FontAwesomeIcons.borderAll,
    build: _buildGaps,
  ),
  _MiracleCategory(
    title: 'Animations',
    subtitle: 'What each window and workspace event looks like',
    icon: FontAwesomeIcons.wandMagicSparkles,
    build: _buildAnimations,
  ),
  _MiracleCategory(
    title: 'Key Bindings',
    subtitle: 'Your shortcuts, and rebindings of the built-in ones',
    icon: FontAwesomeIcons.keyboard,
    build: _buildKeyBindings,
  ),
  _MiracleCategory(
    title: 'Mouse',
    subtitle: 'Pointer, cursor and dragging windows',
    icon: FontAwesomeIcons.computerMouse,
    build: _buildMouse,
  ),
  _MiracleCategory(
    title: 'Touchpad',
    subtitle: 'Tapping, scrolling and pointer speed',
    icon: FontAwesomeIcons.hand,
    build: _buildTouchpad,
  ),
  _MiracleCategory(
    title: 'Keyboard',
    subtitle: 'The compositor’s layout and key repeat',
    icon: FontAwesomeIcons.language,
    build: _buildKeyboard,
  ),
  _MiracleCategory(
    title: 'Accessibility',
    subtitle: 'Magnifier, hover click, slow and sticky keys',
    icon: FontAwesomeIcons.universalAccess,
    build: _buildAccessibility,
  ),
  _MiracleCategory(
    title: 'Workspaces',
    subtitle: 'Per-workspace settings',
    icon: FontAwesomeIcons.tableColumns,
    build: _buildWorkspaces,
  ),
  _MiracleCategory(
    title: 'Startup',
    subtitle: 'Applications and environment variables',
    icon: FontAwesomeIcons.play,
    build: _buildStartup,
  ),
  _MiracleCategory(
    title: 'Includes & Plugins',
    subtitle: 'Other configuration files, and loaded plugins',
    icon: FontAwesomeIcons.plug,
    build: _buildIncludes,
  ),
];

Widget _buildGeneral(MiracleConfigStore store) =>
    MiracleGeneralSection(store: store);
Widget _buildGaps(MiracleConfigStore store) => MiracleGapsSection(store: store);
Widget _buildAnimations(MiracleConfigStore store) =>
    MiracleAnimationsSection(store: store);
Widget _buildKeyBindings(MiracleConfigStore store) =>
    MiracleKeyBindingsSection(store: store);
Widget _buildMouse(MiracleConfigStore store) =>
    MiracleMouseSection(store: store);
Widget _buildTouchpad(MiracleConfigStore store) =>
    MiracleTouchpadSection(store: store);
Widget _buildKeyboard(MiracleConfigStore store) =>
    MiracleKeyboardSection(store: store);
Widget _buildAccessibility(MiracleConfigStore store) =>
    MiracleAccessibilitySection(store: store);
Widget _buildWorkspaces(MiracleConfigStore store) =>
    MiracleWorkspacesSection(store: store);
Widget _buildStartup(MiracleConfigStore store) =>
    MiracleStartupSection(store: store);
Widget _buildIncludes(MiracleConfigStore store) =>
    MiracleIncludesSection(store: store);

_MiracleCategory? _miracleCategoryByTitle(String? title) {
  if (title == null) return null;
  for (final category in _miracleCategories) {
    if (category.title == title) return category;
  }
  return null;
}

/// Whether [title] names a Window Manager settings category.
///
/// [isShellCategory]'s counterpart. `test/settings_search_test.dart` asserts
/// every route the catalogue can emit actually lands somewhere.
bool isMiracleCategory(String title) => _miracleCategoryByTitle(title) != null;

/// The category titles, for the tests that pin the catalogue against them.
@visibleForTesting
List<String> get miracleCategoryTitles => [
  for (final category in _miracleCategories) category.title,
];

// ---------------------------------------------------------------------------
// Views
// ---------------------------------------------------------------------------

/// Landing view: the header, whatever miracle objected to in the file, and a
/// tappable row per category.
class _MiracleHome extends StatelessWidget {
  const _MiracleHome({required this.store});

  final MiracleConfigStore store;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Window Manager',
                style: TextStyle(
                  fontSize: ShellFontSizes.title,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                store.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ShellFontSizes.caption,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        Container(height: 1, color: theme.divider),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                sliver: SliverList.list(
                  children: [
                    // What miracle could not understand in the user's file.
                    // Shown once, here, rather than in the persistent footer:
                    // it is about the file as it was *read*, so it is news on
                    // arrival rather than a running state.
                    if (store.errors.isNotEmpty) ...[
                      _LoadProblems(store: store),
                      const SizedBox(height: 12),
                    ],
                    for (final category in _miracleCategories)
                      _CategoryCard(
                        category: category,
                        onTap: () => Navigator.of(context).push(
                          _categoryRoute(
                            _MiracleCategoryView(
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

/// Detail view: a back button and the category's title over its sections.
class _MiracleCategoryView extends StatelessWidget {
  const _MiracleCategoryView({required this.category, required this.store});

  final _MiracleCategory category;
  final MiracleConfigStore store;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final target = SettingsHighlightScope.maybeOf(context)?.target;
    final jumping =
        target != null &&
        target.field.highlights &&
        target.field.route.miracleCategory == category.title;
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
                  fontSize: ShellFontSizes.title,
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
          // No `ListenableBuilder` here, deliberately — the Shell pane's rule,
          // for the same reason: the store notifies on every edit anywhere in
          // the pane, so a builder at this level would rebuild every row of the
          // category for one digit typed into one of them. Each control
          // subscribes to the value it renders; see [MiracleValue].
          child: CustomScrollView(
            scrollCacheExtent: jumping
                ? const ScrollCacheExtent.pixels(1e6)
                : const ScrollCacheExtent.pixels(600),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                // Keyed on the store's revision, which is what makes Reset
                // work. Every text field on these pages seeds its controller
                // once and then ignores its widget's `initial` — so a Reset
                // that replaced the configuration under a live form would
                // leave every field showing the value the user had just
                // discarded. Re-keying discards the form and rebuilds it from
                // the configuration that is actually loaded.
                //
                // Selected rather than listened to: the revision moves on a
                // reset and on a list gaining or losing an element, not on a
                // keystroke, so this does not undo the per-value subscriptions
                // the rows below are built on.
                sliver: StoreSelector<int>(
                  listenable: store,
                  selector: () => store.structureRevision,
                  builder: (context, revision) => KeyedSubtree(
                    key: ValueKey(revision),
                    child: category.build(store),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Instant route, for [_MiracleCategoryView]. `shell.dart`'s reasoning: every
/// route in this nested [Navigator] fills the same box against the same opaque
/// fill, so an animated push reads as a flicker rather than as movement.
PageRoute<T> _categoryRoute<T>(Widget child) => PageRouteBuilder<T>(
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
  pageBuilder: (context, animation, secondaryAnimation) => child,
);

// ---------------------------------------------------------------------------
// The Save/Reset strip
// ---------------------------------------------------------------------------

/// Everything the Save/Reset strip renders, as one comparable value.
typedef _FooterState = ({
  bool dirty,
  MiracleSaveOutcome outcome,
  bool notice,
  String problems,
});

/// Pinned under every category: what state the file is in, and the two buttons
/// that change it.
///
/// Outside the [Navigator] on purpose. Save applies to the whole configuration
/// rather than to the category that happens to be open, and a strip that came
/// and went with the page would be a Save the user has to navigate back to.
class _MiracleFooter extends StatelessWidget {
  const _MiracleFooter({required this.store});

  final MiracleConfigStore store;

  Future<void> _reset(BuildContext context) async {
    if (store.dirty) {
      final confirmed = await showSettingsConfirm(
        context,
        title: 'Discard your changes?',
        message:
            'Everything edited since the last save is thrown away and the '
            'file on disk is read again.',
        confirmLabel: 'Discard',
      );
      if (!confirmed) return;
    }
    store.reset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // Selected rather than a plain `ListenableBuilder`, for the reason the
    // Shell pane's restart banner is: the store notifies on every keystroke in
    // any field on any category, and none of those moves what this strip
    // renders after the first one has flipped `dirty`.
    return StoreSelector<_FooterState>(
      listenable: store,
      selector: () => (
        dirty: store.dirty,
        outcome: store.saveOutcome,
        notice: store.showReloadNotice,
        problems: _errorSummary(store.saveErrors, fallback: ''),
      ),
      builder: (context, state) {
        final dirty = state.dirty;
        return RepaintBoundary(
          child: Container(
            decoration: BoxDecoration(
              color: theme.popupBackground,
              border: Border(top: BorderSide(color: theme.divider)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.outcome == MiracleSaveOutcome.failed) ...[
                  SettingsBanner(
                    title: 'Could not write the configuration',
                    message: state.problems.isEmpty
                        ? 'miracle refused the save and said nothing about why.'
                        : state.problems,
                  ),
                  const SizedBox(height: 10),
                ],
                if (state.notice) ...[
                  SettingsNotice(
                    icon: FontAwesomeIcons.rotate,
                    title: 'Saved — now tell miracle to read it',
                    message: _reloadMessage(),
                    onDismiss: store.dismissReloadNotice,
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        // "Saved to" only where a save actually happened;
                        // otherwise this is simply the file being edited, and
                        // saying it was saved on arrival would be a lie the
                        // user has no way to check.
                        dirty
                            ? 'Unsaved changes'
                            : state.outcome == MiracleSaveOutcome.saved
                            ? 'Saved to ${store.path}'
                            : store.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: ShellFontSizes.secondary,
                          fontFamily: theme.fontFamily,
                          color: dirty
                              ? theme.accentText
                              : theme.popupForeground.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 96,
                      child: SettingsActionButton(
                        label: 'Reset',
                        onTap: () => _reset(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 96,
                      child: SettingsActionButton(
                        label: 'Save',
                        primary: true,
                        enabled: dirty,
                        onTap: store.save,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// How to make miracle re-read the file that was just written.
  ///
  /// The shortcut is read off the configuration, not spelled here: a user who
  /// has rebound `reload_config` would otherwise be told to press a combination
  /// they have taken away. The Action Key is named as well as referred to,
  /// because "Action Key + Shift + R" is not a thing anybody can press until
  /// they know which key it is.
  String _reloadMessage() {
    final config = store.config;
    final shortcut = config == null
        ? kDefaultReloadShortcut
        : reloadShortcutLabel(
            config.builtInKeyCommandOverrides,
            miracleKeyLabel,
          );
    final actionKey = config == null
        ? null
        : modifierLabel(config.primaryModifier);
    final aside = actionKey != null && shortcut.contains('Action Key')
        ? ' Your Action Key is $actionKey.'
        : '';
    return 'miracle-wm does not re-read its configuration on its own. Press '
        '$shortcut to apply what was just written.$aside';
  }
}

/// What miracle objected to when it read the file.
class _LoadProblems extends StatelessWidget {
  const _LoadProblems({required this.store});

  final MiracleConfigStore store;

  @override
  Widget build(BuildContext context) {
    final message = _errorSummary(store.errors, fallback: '');
    if (store.hasErrors) {
      return SettingsBanner(
        title: 'miracle could not understand part of this file',
        message:
            '$message\n\nWhat it did understand is editable below. Saving '
            'rewrites the whole file, so anything it dropped is dropped for '
            'good — take a copy first if that matters.',
      );
    }
    return SettingsNotice(
      title: 'miracle had remarks about this file',
      message: message,
    );
  }
}

/// The first few problems, one per line, with a count for the rest.
String _errorSummary(
  List<MiracleConfigError> errors, {
  required String fallback,
}) {
  if (errors.isEmpty) return fallback;
  const shown = 3;
  final lines = <String>[
    for (final error in errors.take(shown)) _errorLine(error),
  ];
  if (errors.length > shown) {
    lines.add('…and ${errors.length - shown} more.');
  }
  return lines.join('\n');
}

String _errorLine(MiracleConfigError error) =>
    error.line > 0 ? 'Line ${error.line}: ${error.message}' : error.message;

// ---------------------------------------------------------------------------
// Chrome
// ---------------------------------------------------------------------------

/// A full-pane message with a Retry: the shape both failure states take.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final FaIconData icon;
  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              FaIcon(
                icon,
                size: 28,
                color: theme.popupForeground.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: ShellFontSizes.title,
                  fontFamily: theme.fontFamily,
                  fontWeight: FontWeight.w600,
                  color: theme.popupForeground,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  fontFamily: theme.fontFamily,
                  height: 1.5,
                  color: theme.popupForeground.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              SettingsRescanButton(label: 'Retry', onTap: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tappable, hover-aware row on the landing page. The Shell pane's card,
/// spelled again here rather than shared: that one is private to `shell.dart`
/// and lifting it into `controls.dart` is a change to a file every settings
/// page imports, for two callers.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});

  final _MiracleCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: HoverRegion(
        onTap: onTap,
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: hovered ? theme.surfaceHover : theme.controlSurface,
            borderRadius: BorderRadius.circular(ShellRadii.control),
            border: Border.all(color: theme.divider),
          ),
          child: Row(
            children: [
              FaIcon(
                category.icon,
                size: ShellFontSizes.label,
                color: hovered
                    ? theme.accentText
                    : theme.popupForeground.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.title,
                      style: TextStyle(
                        fontSize: ShellFontSizes.body,
                        fontFamily: theme.fontFamily,
                        fontWeight: FontWeight.w600,
                        color: theme.popupForeground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category.subtitle,
                      style: TextStyle(
                        fontSize: ShellFontSizes.caption,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              FaIcon(
                FontAwesomeIcons.chevronRight,
                size: ShellFontSizes.caption,
                color: theme.popupForeground.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
