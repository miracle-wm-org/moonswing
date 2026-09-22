// The shell's *own* global shortcuts as the cheat sheet reads them: which ones
// there are, what each is called, and the caps a person presses for it.
//
// The compositor's half of the sheet comes from `keybind_model.dart`, which is
// handed a `KeybindsResult` and turns it into rows. This is the other half, and
// it starts somewhere else entirely — `[shortcuts]` in the shell's own
// `config.toml`, parsed into a [ShortcutSpec] pair of a modifier bitfield and a
// keysym — so the work here is getting those two vocabularies to meet: a
// keysym goes back through [xkbKeysymName] to the spelling miracle would have
// used, and the caps are then drawn by the very same table.
//
// Flutter-free, `keybind_model.dart`'s rule, so the list, the labels, the caps
// and both collision rules are a plain unit test.
library;

import 'package:miracle/miracle.dart' show KeybindsResult, Modifier;

import 'package:moonswing/config.dart';
import 'package:moonswing/input_trigger/keysym.dart';
import 'package:moonswing/keybinds/keybind_model.dart';

/// One shortcut the *shell* registers with the compositor — every key of
/// `[shortcuts]`, in the order the sheet lists them.
///
/// An enum rather than a list of records because it is an identity: the editor
/// names the row it is changing, the store names the key it writes, and a
/// collision names the shortcut it collided with.
enum ShellShortcut {
  openLauncher(
    label: 'Open the application launcher',
    configKey: 'open_launcher',
    defaultSpec: kDefaultOpenLauncher,
  ),
  openSettings(
    label: 'Open settings',
    configKey: 'open_settings',
    defaultSpec: kDefaultOpenSettings,
  ),
  openEmoji(
    label: 'Open the emoji picker',
    configKey: 'open_emoji',
    defaultSpec: kDefaultOpenEmoji,
  ),
  openNotifications(
    label: 'Open the notification panel',
    configKey: 'open_notifications',
    defaultSpec: kDefaultOpenNotifications,
  ),
  openPowerMenu(
    label: 'Open the power menu',
    // Distinct from the power-button row further down, which is only where
    // the machine's own key is picked up: this one always means the menu.
    detail: 'Shut down, restart, suspend, lock or log out',
    configKey: 'open_power_menu',
    defaultSpec: kDefaultOpenPowerMenu,
  ),
  switchWindows(
    label: 'Switch windows',
    // The gesture, not just the key: this is the one shell shortcut that is
    // held rather than pressed, and a row reading "Alt + Tab" alone would not
    // say that the Tab is repeatable or that letting go is the choice.
    detail: 'Hold Alt and press Tab to move through the open windows; '
        'let Alt go to switch',
    configKey: 'switch_windows',
    defaultSpec: kDefaultSwitchWindows,
  ),
  switchWindowsBack(
    label: 'Switch windows, backwards',
    configKey: 'switch_windows_back',
    defaultSpec: kDefaultSwitchWindowsBack,
  ),
  screenshotArea(
    label: 'Screenshot an area',
    configKey: 'screenshot_area',
    defaultSpec: kDefaultScreenshotArea,
  ),
  recordScreen(
    label: 'Record the current screen',
    // The one shortcut here that is also how the thing it starts is ended,
    // which a row showing only what it opens would not say.
    detail: 'Press it again to stop recording',
    configKey: 'record_screen',
    defaultSpec: kDefaultRecordScreen,
  ),
  powerButton(
    label: 'The power button',
    // Not "power off": what the press *does* is `[power] key_action`, which is
    // live and set elsewhere. This row is only where the key is picked up.
    detail: 'What a press does is set under Settings › Shell › Power Button',
    configKey: 'power_button',
    defaultSpec: kDefaultPowerButton,
  );

  const ShellShortcut({
    required this.label,
    required this.configKey,
    required this.defaultSpec,
    this.detail,
  });

  /// What the shortcut does, in a person's words — the row's description.
  final String label;

  /// A qualifier under the row, where the label alone would mislead.
  final String? detail;

  /// The key under `[shortcuts]` this is stored as.
  final String configKey;

  /// What it is bound to with nothing in the config file.
  final ShortcutSpec defaultSpec;

  /// What [config] binds this to, or null when the user has disabled it.
  ShortcutSpec? specIn(ShortcutsConfig config) => switch (this) {
    ShellShortcut.openLauncher => config.openLauncher,
    ShellShortcut.openSettings => config.openSettings,
    ShellShortcut.openEmoji => config.openEmoji,
    ShellShortcut.openNotifications => config.openNotifications,
    ShellShortcut.openPowerMenu => config.openPowerMenu,
    ShellShortcut.switchWindows => config.switchWindows,
    ShellShortcut.switchWindowsBack => config.switchWindowsBack,
    ShellShortcut.screenshotArea => config.screenshotArea,
    ShellShortcut.recordScreen => config.recordScreen,
    ShellShortcut.powerButton => config.powerButton,
  };
}

/// The section the shell's shortcuts are drawn under.
///
/// Deliberately not a [KeybindSection]: those are the compositor's own
/// grouping, produced by [groupKeybinds] and read off a `KeybindsResult`, and a
/// value none of that machinery can ever emit would be a value every `switch`
/// over it has to carry.
const String kShellSectionLabel = 'Shell';

/// What a row says when the user has disabled a shortcut.
///
/// A disabled shortcut keeps its row: it is still one of the shell's own, and
/// the row is where it is turned back on.
const String kShellShortcutDisabled = 'Disabled';

/// The caps for [spec], in the order a shortcut is written.
///
/// The compositor's rows and the shell's are drawn by one table, so `Escape`
/// reads as `Esc` on both and neither can drift from the other. A key with no
/// name — a raw `0x…` keysym, or the `code:` form that binds a physical key —
/// is shown as what the config file says rather than hidden, [keyCapForKeysym]'s
/// rule.
List<KeyCap> capsForSpec(ShortcutSpec spec) => [
  for (final modifier in _modifiersFor(spec)) modifierCap(modifier),
  _keyCapFor(spec),
];

/// [spec]'s modifier bits as the compositor's own modifiers, so both halves of
/// the sheet spell `Super` the one way.
List<Modifier> _modifiersFor(ShortcutSpec spec) => [
  if (spec.modifiers & kShortcutModCtrl != 0) Modifier.ctrl,
  if (spec.modifiers & kShortcutModAlt != 0) Modifier.alt,
  if (spec.modifiers & kShortcutModShift != 0) Modifier.shift,
  if (spec.modifiers & kShortcutModSuper != 0) Modifier.meta,
];

KeyCap _keyCapFor(ShortcutSpec spec) {
  // A physical key, bound by number because no layout has to agree about what
  // it produces. There is nothing truer to draw than the number itself.
  if (spec.isKeycode) return KeyCap('Code ${spec.keysym}');
  final name = xkbKeysymName(spec.keysym);
  if (name == null) return KeyCap('0x${spec.keysym.toRadixString(16)}');
  return keyCapForKeysym(name);
}

/// [spec] as one string, e.g. `Ctrl + Space`. What a test reads, and the honest
/// text behind a row of drawn caps.
String shortcutLabel(ShortcutSpec spec) =>
    capsForSpec(spec).map((cap) => cap.label).join(' + ');

/// The other shell shortcut [spec] would collide with, or null.
///
/// Worth refusing rather than warning about: `inputShortcutsFor` collapses two
/// shortcuts on one combination to the first, so the second would silently
/// stop working — and the user would have no way of telling that from a
/// compositor that simply refused the registration.
ShellShortcut? shellCollisionFor(
  ShellShortcut editing,
  ShortcutSpec spec,
  ShortcutsConfig config,
) {
  for (final other in ShellShortcut.values) {
    if (other == editing) continue;
    if (other.specIn(config) == spec) return other;
  }
  return null;
}

/// What the compositor already does with [spec], or null when it does nothing.
///
/// A warning, never a refusal: the two are registered through different
/// mechanisms — the shell's through `ext-input-trigger`, miracle's through its
/// own configuration — and which of them wins is the compositor's business, not
/// this sheet's. What the sheet *can* do is say so before the user finds out by
/// pressing it.
///
/// The comparison is on the drawn caps rather than on keysyms: miracle reports
/// a binding as an xkb name and a modifier set, the shell holds a bitfield and
/// a keysym, and the caps are the one form both have already been resolved to —
/// including `Modifier.primary`, which is not a key at all until miracle says
/// which one it is.
String? compositorCollisionFor(ShortcutSpec spec, KeybindsResult? result) {
  if (result == null) return null;
  final wanted = capsForSpec(spec).map((cap) => cap.label).toList();
  for (final keybind in result.keybinds) {
    final caps = capsFor(keybind).map((cap) => cap.label).toList();
    if (caps.length != wanted.length) continue;
    var same = true;
    for (var i = 0; i < caps.length; i++) {
      if (caps[i] != wanted[i]) {
        same = false;
        break;
      }
    }
    if (!same) continue;
    final row = rowFor(keybind);
    if (row != null) return row.description;
  }
  return null;
}
