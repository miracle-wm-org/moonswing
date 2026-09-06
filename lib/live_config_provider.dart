import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/scopes.dart';

/// Provides the live [AppConfig] to a window's widget subtree.
///
/// **This is the only thing in the shell that should construct a
/// [LiveConfigScope]** — the `ThemeProvider` rule, installed the same way, once
/// per window, because an `InheritedWidget` cannot span FlutterViews.
///
/// The root owns the notifier and refreshes it from its `ConfigStore` listener,
/// because deriving the typed config has side effects and must not happen during
/// `build`. Everything downstream is ordinary: the value changes, the scope is
/// rebuilt, and only the widgets that depend on it are rebuilt with it.
class LiveConfigProvider extends StatelessWidget {
  const LiveConfigProvider({
    super.key,
    required this.config,
    required this.child,
  });

  final ValueListenable<AppConfig> config;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: config,
        // `child` is passed through rather than rebuilt: descendants that read
        // the config depend on the LiveConfigScope above them, so rebuilding
        // the subtree here would be pure waste — and would put every window
        // back in the path of every keystroke.
        builder: (context, child) =>
            LiveConfigScope(config: config.value, child: child!),
        child: child,
      );
}
