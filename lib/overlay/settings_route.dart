import 'package:flutter/foundation.dart';

import 'package:moonswing/request_controller.dart';

/// Which page of the settings overlay to land on.
///
/// The overlay's own tab and category are private state seeded in `initState`, so
/// a route is a *starting point*, not a live address — reopening the overlay
/// somewhere else builds a new one.
@immutable
class SettingsRoute {
  const SettingsRoute({
    this.tab = 'settings',
    this.category = 'shell',
    this.shellCategory,
    this.miracleCategory,
  });

  /// One of the overlay's top tab ids: `calendar`, `system`, `systeminfo`,
  /// `settings`.
  final String tab;

  /// One of the settings sidebar ids: `network`, `bluetooth`, `display`,
  /// `audio`, `keyboard`, `miracle`, `accounts`, `shell`.
  final String category;

  /// A `_ShellCategory.title` inside the Shell pane, e.g. `Background`. Null
  /// lands on the category list.
  final String? shellCategory;

  /// A `_MiracleCategory.title` inside the Window Manager pane, e.g. `Gaps &
  /// Borders`. Null lands on that pane's category list.
  ///
  /// A second field rather than a rename of [shellCategory] to something
  /// neutral: the two panes are two nested `Navigator`s with two unrelated sets
  /// of category titles, and one field holding either would let a Shell route
  /// name a Window Manager category. `test/settings_search_test.dart` checks
  /// each against its own pane's list, which it can only do while they are
  /// separate.
  final String? miracleCategory;

  /// Where "Change background…" on the desktop goes.
  static const SettingsRoute background =
      SettingsRoute(shellCategory: 'Background');

  /// Where the desktop grid's own settings live.
  static const SettingsRoute desktop = SettingsRoute(shellCategory: 'Desktop');

  /// Where the keyboard layout popup's "Keyboard settings…" footer goes.
  ///
  /// A top-level category rather than a Shell one: the first five sidebar entries
  /// are the machine's hardware and Shell is this shell's own configuration, and
  /// an input source is the former.
  static const SettingsRoute keyboard = SettingsRoute(category: 'keyboard');

  /// Where anything offering to configure the *compositor* goes.
  static const SettingsRoute windowManager = SettingsRoute(category: 'miracle');

  @override
  bool operator ==(Object other) =>
      other is SettingsRoute &&
      other.tab == tab &&
      other.category == category &&
      other.shellCategory == shellCategory &&
      other.miracleCategory == miracleCategory;

  @override
  int get hashCode =>
      Object.hash(tab, category, shellCategory, miracleCategory);
}

/// The seam between "something deep in a surface wants the settings overlay
/// open at a particular page" and `_MoonswingRootState`, which owns the
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
