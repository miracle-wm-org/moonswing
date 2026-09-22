import 'package:flutter/widgets.dart';

import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_store.dart';

/// Provides the live palette to a widget subtree.
///
/// **This is the only thing in the shell that should construct a [ThemeScope].**
/// The shell renders into many independent FlutterViews and an `InheritedWidget`
/// cannot span them, so each tree has to be given the theme separately. Every
/// module used to do that by reading `ThemeScope.of` in the handler that opened
/// the window and passing the value along — which freezes it, so an open popup
/// never restyled.
///
/// Listening instead of snapshotting fixes it, including inside a popup, where
/// the content widget is built once and stashed in a `WindowEntry` builder: that
/// widget instance is never reconstructed, but the [ListenableBuilder]'s
/// *element* is mounted in the popup's own tree and rebuilds itself.
///
/// The invariant worth preserving: `grep -rn 'ThemeScope(' lib/` should only
/// match `lib/scopes.dart` and this file.
///
/// It is also where the theme's `font_size` is applied, as the `TextScaler` on a
/// [MediaQuery] — the one mechanism that reaches a `fontSize:` a widget spelled
/// out for itself, which nearly every string in the shell does. It goes here
/// rather than in `ShellTextRoot` because a dozen popups still carry the bare
/// `Directionality` preamble that widget is retiring, and every themed tree in
/// the shell is under a [ThemeProvider] by construction.
///
/// The shell boots without a `WidgetsApp`, so there is normally no [MediaQuery]
/// above this at all — hence the fallback below. What it publishes carries the
/// scaler and nothing else: it is deliberately not a metrics source.
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
        // ThemeProviders a popup's tree can end up with are idempotent. At the
        // default font size this is TextScaler.linear(1.0), which compares equal
        // to TextScaler.noScaling — so an unset key leaves every measurement
        // exactly where it was.
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
