import 'package:flutter/foundation.dart';

import 'package:graceful_shell/config_reader.dart';

/// What the shell does when the machine's physical power button is pressed.
///
/// [none] is the only value that hands the key *back*: with it the shell
/// registers no trigger and takes no logind inhibitor, so the button does
/// whatever `logind.conf`'s `HandlePowerKey` says — which is what a user who
/// wants the firmware/systemd behaviour asks for. Every other value means the
/// shell answers the press itself.
enum PowerKeyAction {
  /// Show the power menu — the dialog with Lock / Log Out / Sleep / Restart /
  /// Shut Down. The default: a physical button that powers the machine off
  /// with no confirmation is one nudge away from losing unsaved work.
  menu('menu'),

  /// Power the machine off immediately.
  shutdown('shutdown'),

  /// Restart immediately.
  reboot('reboot'),

  /// Suspend to RAM.
  suspend('suspend'),

  /// Lock the session (`ext-session-lock-v1`).
  lock('lock'),

  /// End the session.
  logout('logout'),

  /// Do nothing — leave the key to logind.
  none('none');

  const PowerKeyAction(this.key);

  /// The spelling used in `config.toml`.
  final String key;

  /// The action [raw] names, or null when the shell does not recognise it.
  /// Callers decide whether that means "fall back to the default" or
  /// "disabled" — `parseShortcut` draws the same line in the same place.
  static PowerKeyAction? fromString(String raw) {
    final trimmed = raw.trim().toLowerCase();
    for (final action in PowerKeyAction.values) {
      if (action.key == trimmed) return action;
    }
    // The spellings a user reaches for that are not the canonical one. `off`
    // and `poweroff` are what the button is called; `restart` and `sleep` are
    // what the menu calls them; `""` is how every other config section spells
    // "disabled".
    return switch (trimmed) {
      'off' || 'poweroff' || 'power_off' => PowerKeyAction.shutdown,
      'restart' => PowerKeyAction.reboot,
      'sleep' || 'suspend_to_ram' => PowerKeyAction.suspend,
      'log_out' || 'logoff' => PowerKeyAction.logout,
      'dialog' || 'power_menu' => PowerKeyAction.menu,
      '' || 'ignore' || 'disabled' => PowerKeyAction.none,
      _ => null,
    };
  }
}

/// `[power]` — what the physical power button does.
///
/// Two settings, and the second one exists because the shell is not the only
/// thing watching that button: systemd-logind opens the ACPI power-button
/// device itself and powers the machine off on a press, whatever the
/// compositor delivers to whom. So intercepting the key is two halves —
/// receiving it (a global trigger, `[shortcuts] power_button`) and stopping
/// logind acting on it first (an inhibitor lock, [inhibitLogind]) — and a
/// build that did only the first would show the power menu on a machine that
/// was already shutting down.
@immutable
class PowerConfig {
  const PowerConfig({
    this.keyAction = PowerKeyAction.menu,
    this.inhibitLogind = true,
  });

  /// What a press does.
  final PowerKeyAction keyAction;

  /// Whether to take logind's `handle-power-key` inhibitor lock while the
  /// shell is handling the key.
  ///
  /// The escape hatch for a machine whose `logind.conf` already says
  /// `HandlePowerKey=ignore`: the lock is then redundant, and a user who would
  /// rather not have the shell holding one can say so. Off means logind's own
  /// handling stands, so unless it is already `ignore` the shell's menu and
  /// logind's shutdown race.
  final bool inhibitLogind;

  /// Whether the shell answers the power key at all.
  bool get handlesKey => keyAction != PowerKeyAction.none;

  /// Whether the logind inhibitor should be held. Never for [PowerKeyAction
  /// .none]: inhibiting the key and then ignoring it is a dead power button,
  /// which is worse than either behaviour on its own.
  bool get inhibitsLogind => handlesKey && inhibitLogind;

  factory PowerConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PowerConfig();
    return PowerConfig(
      keyAction: _readAction(map, 'key_action'),
      inhibitLogind: map.boolOr('inhibit_logind', true),
    );
  }

  /// Reads one action key, falling back to the default on anything unusable —
  /// `TomlReader`'s rule, spelled out here because the value is an enum rather
  /// than one of its scalar types. A typo must not silently disable the power
  /// button: an unreadable value keeps the menu, which is recoverable.
  static PowerKeyAction _readAction(Map<String, dynamic> map, String key) {
    if (!map.containsKey(key)) return PowerKeyAction.menu;
    final raw = map[key];
    if (raw is! String) {
      debugPrint('config: [power].$key is not a string; using the default');
      return PowerKeyAction.menu;
    }
    final action = PowerKeyAction.fromString(raw);
    if (action == null) {
      debugPrint('config: [power].$key ("$raw") is not an action the shell '
          'knows; using the default');
      return PowerKeyAction.menu;
    }
    return action;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PowerConfig &&
          other.keyAction == keyAction &&
          other.inhibitLogind == inhibitLogind;

  @override
  int get hashCode => Object.hash(keyAction, inhibitLogind);
}
