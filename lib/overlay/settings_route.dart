import 'package:flutter/foundation.dart';

import 'package:moonswing/request_controller.dart';

/// The Shell category that lists every module, each pushing its own page.
const String kModuleSettingsCategory = 'Modules';

/// The overview's top tab ids, in the order the tab strip draws them.
///
/// The overview — the panel the clock opens — is the one window the calendar,
/// the monitor, the settings, the todo board and the shortcut sheet live in,
/// so a bar button that used to open a surface of its own names one of these
/// instead (see [SettingsController.toggle]).
abstract final class OverviewTab {
  static const String calendar = 'calendar';
  static const String system = 'system';
  static const String systemInfo = 'systeminfo';
  static const String settings = 'settings';
  static const String todo = 'todo';
  static const String shortcuts = 'shortcuts';
}

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
    this.module,
  });

  /// One module's own page inside Shell › Modules, named by its
  /// `[modules.<key>]` config key — `clock`, `screen_recorder`.
  const SettingsRoute.module(String key)
    : this(shellCategory: kModuleSettingsCategory, module: key);

  /// One of the overview's tabs other than Settings, with the settings sidebar
  /// left on its first category — where it would be had nothing named one.
  const SettingsRoute.tab(String tab) : this(tab: tab, category: 'network');

  /// One of the [OverviewTab] ids.
  final String tab;

  /// One of the settings sidebar ids: `network`, `bluetooth`, `display`,
  /// `audio`, `keyboard`, `power`, `miracle`, `default_apps`, `accounts`,
  /// `shell`.
  final String category;

  /// A `_ShellCategory.title` inside the Shell pane, e.g. `Wallpaper`. Null
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

  /// A `[modules.<key>]` config key inside [kModuleSettingsCategory], e.g.
  /// `clock`: that module's page is pushed over the module list. Null lands on
  /// the list itself.
  ///
  /// Keyed on the config key rather than the page's title, because the key is
  /// already in every module row's id — the catalogue derives this field from
  /// it, so a row cannot point at another module's page.
  final String? module;

  /// Where "Change background…" on the desktop goes.
  static const SettingsRoute background =
      SettingsRoute(shellCategory: 'Wallpaper');

  /// Where the desktop grid's own settings live.
  static const SettingsRoute desktop =
      SettingsRoute(shellCategory: 'Desktop Grid');

  /// The list of modules, each of which pushes its own page.
  static const SettingsRoute modules =
      SettingsRoute(shellCategory: kModuleSettingsCategory);

  /// Where the stock market widget's "Manage tickers" goes — the watchlist is
  /// a row on that module's page.
  static const SettingsRoute stocks = SettingsRoute.module('stocks');

  /// Where the keyboard layout popup's "Keyboard settings…" footer goes.
  ///
  /// A top-level category rather than a Shell one: the first six sidebar entries
  /// are the machine's hardware and Shell is this shell's own configuration, and
  /// an input source is the former.
  static const SettingsRoute keyboard = SettingsRoute(category: 'keyboard');

  /// The machine's power mode and the CPU and firmware knobs beneath it.
  ///
  /// A sidebar category of its own rather than a Shell one, for
  /// [keyboard]'s reason: it is the machine's state, not the shell's
  /// configuration. Shell › Power Button is the other "power" page, and that
  /// one *is* the shell's — what the physical key does.
  static const SettingsRoute power = SettingsRoute(category: 'power');

  /// Where anything that needs an account linked goes — the GitHub popup's
  /// "Open Accounts settings", and any module or widget signed out of the
  /// service it reads.
  static const SettingsRoute accounts = SettingsRoute(category: 'accounts');

  /// Where anything offering to configure the *compositor* goes.
  static const SettingsRoute windowManager = SettingsRoute(category: 'miracle');

  /// Where the applications that open each kind of file are chosen — the
  /// default browser, file manager, image viewer.
  static const SettingsRoute defaultApps =
      SettingsRoute(category: 'default_apps');

  @override
  bool operator ==(Object other) =>
      other is SettingsRoute &&
      other.tab == tab &&
      other.category == category &&
      other.shellCategory == shellCategory &&
      other.miracleCategory == miracleCategory &&
      other.module == module;

  @override
  int get hashCode =>
      Object.hash(tab, category, shellCategory, miracleCategory, module);
}

/// The seam between "something deep in a surface wants the overview open at a
/// particular page" and `_MoonswingRootState`, which owns the window.
///
/// Two requests share it, because they share the window: [open] names a page
/// and never closes anything, [toggle] is a bar button's — the clock's, the
/// todo button's, the keyboard icon's — and the root decides from the open
/// overview's tab whether it opens, switches or closes.
///
/// A [SignalController] with a payload. (Why not `InputTriggerStore`: see
/// the base.)
class SettingsController extends SignalController {
  SettingsController._();

  static final SettingsController instance = SettingsController._();

  @visibleForTesting
  factory SettingsController.forTesting() => SettingsController._();

  SettingsRoute? _pending;
  String? _pendingToggle;
  String? _output;

  /// The route the root has not acted on yet, or null.
  SettingsRoute? get pending => _pending;

  /// The [OverviewTab] a bar button toggled that the root has not acted on
  /// yet, or null.
  String? get pendingToggle => _pendingToggle;

  /// The connector name (`DP-1`) of the output the last [toggle] came from, or
  /// null when the caller did not know it yet — the root then lets the
  /// compositor pick the focused output, which is where a click just happened.
  String? get output => _output;

  /// Asks the shell to show the settings overlay at [route].
  ///
  /// Unlike [LauncherController.toggle] this never closes an open overlay: it
  /// is reached from menu items that name a destination, and a "Change
  /// background…" that dismissed the settings would be nonsense.
  void open([SettingsRoute route = const SettingsRoute()]) {
    _pending = route;
    _pendingToggle = null;
    _output = null;
    signal();
  }

  /// A bar button's press: opens the overview at [tab] on [output] if it is
  /// not up, switches it to [tab] if it is showing another, and closes it if
  /// [tab] is the one showing.
  ///
  /// The output is the clicked bar's because the overview is a workspace
  /// asked for by pointing at one particular screen.
  void toggle(String tab, {String? output}) {
    _pending = null;
    _pendingToggle = tab;
    _output = output;
    signal();
  }

  /// Called by the root once it has acted on [pending] or [pendingToggle].
  void consume() {
    _pending = null;
    _pendingToggle = null;
  }
}
