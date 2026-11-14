// The shell's control interface, as both ends of it read it.
//
// `org.moonswing.Shell` is how something outside the shell's process asks it to
// do what a person would otherwise do with a click or a shortcut: open the
// launcher, switch the theme, start a timer, put a card on the todo board, take
// a picture of a screen. Its first client is `moonswing-mcp` (`lib/mcp/`), the
// Model Context Protocol server an AI agent is pointed at; `gdbus` and `busctl`
// are the second.
//
// Flutter-free on purpose: the service in `shell_control_service.dart` and the
// client in `lib/mcp/shell_client.dart` both import this, and the client is
// compiled as a plain `dart compile exe` binary. So the names here — the bus
// name, the action ids, the overview tabs — are spelt once, and a rename on one
// end is a compile error on the other rather than a `UnknownMethod` at run time.
library;

/// The well-known name the shell owns on the session bus.
const String kShellControlBusName = 'org.moonswing.Shell';

/// The one object the interface is served on.
const String kShellControlObjectPath = '/org/moonswing/Shell';

/// The interface. Versioned in its name, the freedesktop way: an incompatible
/// change is `Shell2` beside this one, never an edit to it.
const String kShellControlInterface = 'org.moonswing.Shell1';

/// What `GetStatus` reports as `api`, so a client can tell an older shell that
/// lacks a method from one that refused it.
const int kShellControlApiVersion = 1;

/// The error names a method answers with. The message is always a sentence a
/// person (or an agent relaying to one) can act on.
abstract final class ShellControlError {
  /// The arguments were the wrong type, or named something that does not exist
  /// — an unknown action, theme, tab, column, application or card id.
  static const String invalidArgs = 'org.moonswing.Shell1.Error.InvalidArgs';

  /// What was asked cannot be done on this machine or right now: the feature is
  /// switched off, the compositor is not miracle, the board did not load.
  static const String unavailable = 'org.moonswing.Shell1.Error.Unavailable';

  /// It was tried and it failed.
  static const String failed = 'org.moonswing.Shell1.Error.Failed';
}

/// One thing `Activate` can do — the same code path its global shortcut runs,
/// so an agent asking is indistinguishable from a person pressing the key.
///
/// The ids are the `[shortcuts]` keys where there is one, so a person reading
/// their config and an agent reading `ListActions` see one vocabulary. Missing
/// on purpose: the window switcher, which is a *held* gesture whose end is a key
/// coming up and so has no meaning as a single call, and the power button, whose
/// action is the power menu below or `[power] key_action`'s choice.
enum ShellAction {
  openLauncher('open_launcher', 'Toggle the application launcher'),
  openSettings('open_settings', 'Toggle the overview on its Settings tab'),
  openEmoji('open_emoji', 'Toggle the emoji picker'),
  openNotifications('open_notifications', 'Toggle the notification panel'),
  openPowerMenu(
    'open_power_menu',
    'Toggle the power menu (shut down, restart, suspend, lock, log out)',
  ),
  screenshotArea(
    'screenshot_area',
    'Start an interactive screenshot: the user drags out the area',
  ),
  recordScreen(
    'record_screen',
    'Start recording the focused screen, or stop the recording in progress',
  ),
  toggleScratchpad(
    'toggle_scratchpad',
    'Show or hide the window manager\'s scratchpad',
    needsMiracle: true,
  ),
  moveToScratchpad(
    'move_to_scratchpad',
    'Move the focused window to the scratchpad',
    needsMiracle: true,
  ),
  lock('lock', 'Lock the session');

  const ShellAction(this.id, this.description, {this.needsMiracle = false});

  /// The wire name.
  final String id;

  /// What it does, for `ListActions` and the MCP tool's description.
  final String description;

  /// Whether this only drives Miracle WM's IPC, and so does nothing on any
  /// other compositor — `ShellShortcut.needsMiracle`'s rule.
  final bool needsMiracle;

  static ShellAction? fromId(String id) {
    for (final action in values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

/// The overview's tabs as `OpenOverview` accepts them — `OverviewTab`'s ids,
/// which `test/shell_control_test.dart` pins this list against.
const List<String> kControlOverviewTabs = [
  'calendar',
  'system',
  'systeminfo',
  'settings',
  'todo',
  'code',
  'shortcuts',
];

/// The settings sidebar's categories as `OpenSettings` accepts them —
/// `SettingsRoute.category`'s documented ids.
const List<String> kControlSettingsCategories = [
  'network',
  'bluetooth',
  'display',
  'audio',
  'keyboard',
  'power',
  'miracle',
  'default_apps',
  'accounts',
  'shell',
];

/// The todo board's columns as the interface spells them — `TodoColumn`'s wire
/// names, pinned by the same test.
const List<String> kControlTodoColumns = [
  'inbox',
  'todo',
  'in_progress',
  'finished',
  'abandoned',
];

/// What `TimerControl` accepts.
const List<String> kControlTimerOperations = [
  'pause',
  'resume',
  'reset',
  'stop',
];
