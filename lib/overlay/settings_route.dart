import 'package:flutter/foundation.dart';

import 'package:graceful_shell/request_controller.dart';

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

  /// Where the astrology widget's birthday is set. The one setting a desktop
  /// widget cannot work without, so the card that needs it links here rather
  /// than spelling out a path.
  static const SettingsRoute astrology =
      SettingsRoute(shellCategory: 'Astrology');

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
/// A [SignalController] with a payload. (Why not `InputTriggerStore`: see
/// the base.)
class SettingsController extends SignalController {
  SettingsController._();

  static final SettingsController instance = SettingsController._();

  @visibleForTesting
  factory SettingsController.forTesting() => SettingsController._();

  SettingsRoute? _pending;

  /// The route the root has not acted on yet, or null.
  SettingsRoute? get pending => _pending;

  /// Asks the shell to show the settings overlay at [route].
  ///
  /// Unlike [LauncherController.toggle] this never closes an open overlay: it
  /// is reached from menu items that name a destination, and a "Change
  /// background…" that dismissed the settings would be nonsense.
  void open([SettingsRoute route = const SettingsRoute()]) {
    _pending = route;
    signal();
  }

  /// Called by the root once it has acted on [pending].
  void consume() => _pending = null;
}
