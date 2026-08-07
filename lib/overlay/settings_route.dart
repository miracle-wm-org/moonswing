import 'package:flutter/foundation.dart';

/// Which page of the settings overlay to land on.
///
/// The overlay's own tab and category are private state seeded in `initState`,
/// so a route is a *starting point*, not a live address — reopening the overlay
/// somewhere else builds a new one.
@immutable
class SettingsRoute {
  const SettingsRoute({
    this.tab = 'settings',
    this.category = 'shell',
    this.shellCategory,
  });

  /// One of the overlay's top tab ids: `calendar`, `system`, `systeminfo`,
  /// `settings`.
  final String tab;

  /// One of the settings sidebar ids: `network`, `bluetooth`, `display`,
  /// `audio`, `shell`.
  final String category;

  /// A `_ShellCategory.title` inside the Shell pane, e.g. `Background`. Null
  /// lands on the category list.
  final String? shellCategory;

  /// Where "Change background…" on the desktop goes.
  static const SettingsRoute background =
      SettingsRoute(shellCategory: 'Background');

  /// Where the desktop grid's own settings live.
  static const SettingsRoute desktop = SettingsRoute(shellCategory: 'Desktop');

  @override
  bool operator ==(Object other) =>
      other is SettingsRoute &&
      other.tab == tab &&
      other.category == category &&
      other.shellCategory == shellCategory;

  @override
  int get hashCode => Object.hash(tab, category, shellCategory);
}

/// The seam between "something deep in a surface wants the settings overlay
/// open at a particular page" and `_GracefulShellRootState`, which owns the
/// window.
///
/// Same shape as [LauncherController], with a payload. Deliberately not
/// `InputTriggerStore`: that store reports *compositor* triggers and its
/// listener toggles on any notification, so a second signal there would toggle
/// the overlay shut rather than retarget it.
class SettingsController extends ChangeNotifier {
  SettingsController._();

  static final SettingsController instance = SettingsController._();

  @visibleForTesting
  factory SettingsController.forTesting() => SettingsController._();

  SettingsRoute? _pending;
  int _openCount = 0;

  /// The route the root has not acted on yet, or null.
  SettingsRoute? get pending => _pending;

  /// Monotonic count of open requests. Exposed for tests; the root reacts to
  /// [notifyListeners], not to this value.
  int get openCount => _openCount;

  /// Asks the shell to show the settings overlay at [route].
  ///
  /// Unlike [LauncherController.toggle] this never closes an open overlay: it
  /// is reached from menu items that name a destination, and a "Change
  /// background…" that dismissed the settings would be nonsense.
  void open([SettingsRoute route = const SettingsRoute()]) {
    _pending = route;
    _openCount++;
    notifyListeners();
  }

  /// Called by the root once it has acted on [pending].
  void consume() => _pending = null;
}
