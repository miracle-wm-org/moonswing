import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/miracle_manager.dart';
import 'package:wayland/wayland.dart';

/// The nearest [S], or a [FlutterError] naming the missing scope — the
/// `WindowRegistry.of` pattern, so a widget built outside its provider fails
/// with a diagnosis instead of a bare null-check crash.
S _of<S extends InheritedWidget>(BuildContext context, String provider) {
  final scope = context.dependOnInheritedWidgetOfExactType<S>();
  assert(() {
    if (scope == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('No $S found in context.'),
        ErrorDescription(
          '${context.widget.runtimeType} widgets must be built inside a '
          '$provider, which is what provides the $S.',
        ),
        context.describeOwnershipChain(
            'The ownership chain for the affected widget is'),
      ]);
    }
    return true;
  }());
  return scope!;
}

/// Provides the shell's [MiracleManager] to the widget subtree.
///
/// The manager — not the connection — is scoped, because the connection can
/// come and go at runtime (Miracle may not be up when the shell starts, and a
/// user can retry from any bar). Consumers read `manager.connection` and listen
/// to the manager for changes; the scope itself is stable.
class MiracleScope extends InheritedWidget {
  const MiracleScope({
    super.key,
    required this.manager,
    required super.child,
  });

  final MiracleManager manager;

  static MiracleManager of(BuildContext context) =>
      _of<MiracleScope>(context, 'MiracleScope').manager;

  static MiracleManager? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MiracleScope>()?.manager;

  @override
  bool updateShouldNotify(MiracleScope old) => manager != old.manager;
}

/// Provides bar information — specifically the side the bar is anchored to —
/// to the widget subtree.
class BarScope extends InheritedWidget {
  const BarScope({
    super.key,
    required this.anchor,
    required super.child,
  });

  /// The side of the screen this bar is anchored to.
  /// One of: `'top'`, `'bottom'`, `'left'`, `'right'`.
  final String anchor;

  /// The anchor itself — every caller wants the value, not the widget.
  static String of(BuildContext context) =>
      _of<BarScope>(context, 'BarScope').anchor;

  static String? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BarScope>()?.anchor;

  @override
  bool updateShouldNotify(BarScope old) => anchor != old.anchor;
}

/// Provides [WaylandOutput] for the display this bar is rendered on.
class DisplayScope extends InheritedWidget {
  const DisplayScope({
    super.key,
    required this.output,
    required super.child,
  });

  /// The output this bar is on, or null while the shell is still enumerating
  /// them.
  ///
  /// Nullable because output enumeration is no longer awaited before the first
  /// frame: a bar paints as soon as its geometry is known and learns which
  /// physical display it is on a moment later. Consumers show a loader for that
  /// moment rather than an empty row that then pops full.
  final WaylandOutput? output;

  /// Deliberately `maybeOf`-shaped: null means "not known yet" as much as
  /// "no scope", and every consumer already renders that state.
  static WaylandOutput? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DisplayScope>()?.output;

  @override
  bool updateShouldNotify(DisplayScope old) => output?.name != old.output?.name;
}

/// Provides the live [AppConfig] — the typed view of `config.toml` as the user
/// is editing it — to the widget subtree.
///
/// Never constructed outside `LiveConfigProvider`, the [ThemeScope] rule.
///
/// The value cannot be read from `build` at its source: `ConfigStore.appConfig`
/// rebuilds the whole typed config and re-applies every module's options via
/// `Module.loadAll` as a side effect, so the shell root derives it in a
/// listener and publishes it here. What that buys is the rebuild *boundary* —
/// `ConfigStore` notifies on every keystroke anywhere in the settings UI, and
/// before this the root answered each one by rebuilding every view it owns.
///
/// Window *geometry* is not in here. Anchor, height and layer are frozen at
/// startup because the native layer-shell surface was created from them; the
/// startup snapshot stays on `GracefulShellRoot.appConfig`.
class LiveConfigScope extends InheritedWidget {
  const LiveConfigScope({
    super.key,
    required this.config,
    required super.child,
  });

  final AppConfig config;

  static AppConfig of(BuildContext context) =>
      _of<LiveConfigScope>(context, 'LiveConfigProvider').config;

  static AppConfig? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LiveConfigScope>()?.config;

  /// Value equality, not identity: `ConfigStore.appConfig` mints a fresh
  /// [AppConfig] on every read, so identity would make every keystroke a
  /// change and undo the whole point of the scope.
  @override
  bool updateShouldNotify(LiveConfigScope old) => config != old.config;
}

/// Provides [ThemeConfig] to the widget subtree.
///
/// Never constructed directly outside `ThemeProvider` — see the theming
/// section of CLAUDE.md.
class ThemeScope extends InheritedWidget {
  const ThemeScope({
    super.key,
    required this.theme,
    required super.child,
  });

  final ThemeConfig theme;

  static ThemeConfig of(BuildContext context) =>
      _of<ThemeScope>(context, 'ThemeProvider').theme;

  static ThemeConfig? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()?.theme;

  @override
  bool updateShouldNotify(ThemeScope old) => theme != old.theme;
}
