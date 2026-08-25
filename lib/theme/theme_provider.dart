import 'package:flutter/widgets.dart';

import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/theme_store.dart';

/// Provides the live palette to a widget subtree.
///
/// **This is the only thing in the shell that should construct a [ThemeScope].**
/// The shell renders into many independent FlutterViews — one per panel per
/// monitor, plus a window for every popup, overlay, OSD card and lock surface —
/// and an `InheritedWidget` cannot span them, so each tree has to be given the
/// theme separately. The obvious way to do that is to read `ThemeScope.of` in
/// the handler that opens the window and pass the value along, and that is what
/// every module used to do; the catch is that the value is then frozen, so an
/// open popup never restyles.
///
/// Listening instead of snapshotting fixes it, including inside a popup, where
/// the content widget is built once and stashed in a `WindowEntry` builder
/// (`lib/popup.dart`). That widget instance is never reconstructed — but the
/// [ListenableBuilder]'s *element* is mounted in the popup's own tree and
/// rebuilds itself when [ThemeStore] notifies.
///
/// The invariant worth preserving: `grep -rn 'ThemeScope(' lib/` should only
/// ever match `lib/scopes.dart` and this file.
///
/// It is also where the theme's `font_size` is applied, as the `TextScaler` on
/// a [MediaQuery]. That is the one mechanism that reaches a `fontSize:` a
/// widget spelled out for itself, and nearly every string in the shell spells
/// one — a scale applied through [DefaultTextStyle] instead would move only the
/// handful that name no size, which is a setting that appears to do nothing.
/// It goes *here* rather than in `ShellTextRoot` because a dozen popups still
/// carry the bare `Directionality` preamble that widget is retiring, and a font
/// size that reached the panels but not the menus they open would be worse than
/// none; every themed tree in the shell, popups included, is under a
/// [ThemeProvider] by construction.
///
/// The shell boots without a `WidgetsApp`, so there is normally no [MediaQuery]
/// above this at all — hence the fallback below. The data it publishes carries
/// the scaler and nothing else worth reading: it is deliberately *not* a
/// metrics source (it neither measures the view nor updates when the view
/// resizes), and nothing in the shell reads one.
class ThemeProvider extends StatelessWidget {
  const ThemeProvider({super.key, required this.child, ThemeStore? store})
      : _store = store;

  final Widget child;

  /// Overridable for tests; the shell always uses the singleton.
  final ThemeStore? _store;

  @override
  Widget build(BuildContext context) {
    final store = _store ?? ThemeStore.instance;
    return ListenableBuilder(
      listenable: store,
      // `child` is passed through rather than rebuilt: descendants that read
      // the theme update because they depend on the ThemeScope above them, so
      // rebuilding the subtree here would be pure waste.
      builder: (context, child) {
        final theme = store.theme;
        // Absolute, never multiplied onto what an ancestor set, so the nested
        // ThemeProviders a popup's own tree can end up with are idempotent.
        // At the default font size this is TextScaler.linear(1.0), which
        // compares equal to TextScaler.noScaling — so an unset key leaves
        // every measurement in the shell exactly where it was.
        final scaled = (MediaQuery.maybeOf(context) ?? const MediaQueryData())
            .copyWith(textScaler: TextScaler.linear(theme.textScale));
        return ThemeScope(
          theme: theme,
          // MediaQuery inside the scope, so `ThemeScope.of` and
          // `MediaQuery.textScalerOf` answer for the same theme; both pass
          // `child` through untouched.
          child: MediaQuery(data: scaled, child: child!),
        );
      },
      child: child,
    );
  }
}
