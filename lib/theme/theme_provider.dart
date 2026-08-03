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
      builder: (context, child) => ThemeScope(theme: store.theme, child: child!),
      child: child,
    );
  }
}
