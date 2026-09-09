// The shell's own `[shortcuts]`, as the cheat sheet reads and writes them.
//
// [KeybindStore] answers "what does the compositor do", and cannot be asked to
// change anything: miracle's bindings are miracle's, and the sheet is a sheet.
// This is the other half — the four shortcuts the shell registers itself, which
// live in the shell's own `config.toml` and are therefore the shell's to edit.
//
// One store for the machine, `ThemeStore`'s shape: every bar on every monitor
// carries the cheat sheet's icon, so the alternative is N listeners on
// [ConfigStore] and N copies of the answer. And it reads the `[shortcuts]`
// table alone rather than `ConfigStore.appConfig`, for `ThemeStore`'s reason:
// building a whole [AppConfig] re-runs `Module.loadAll` as a side effect, which
// is not something a keystroke in this editor should set off.
//
// The one thing it cannot do is make a change take effect. Global shortcuts are
// registered once, at start-up, on the compositor's first answer — so an edit
// here is a change to what the *next* run will register, and [needsRestart] is
// how the sheet says so instead of showing a binding that does nothing.

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/input_trigger/keysym.dart';
import 'package:graceful_shell/keybinds/shell_keybinds.dart';

/// The shell's global shortcuts: what the config file says now, what the
/// running shell actually registered, and the writes that change the first.
class ShellKeybindStore extends ChangeNotifier {
  ShellKeybindStore._();

  static final ShellKeybindStore instance = ShellKeybindStore._();

  /// A detached store, so a widget test can drive the editor against a
  /// [ConfigStore] over a temporary file — or against none at all.
  @visibleForTesting
  factory ShellKeybindStore.forTesting({
    ConfigStore? config,
    ShortcutsConfig registered = const ShortcutsConfig(),
  }) {
    final store = ShellKeybindStore._();
    if (config != null) store.bind(config, registered: registered);
    return store;
  }

  ConfigStore? _config;

  ShortcutsConfig _registered = const ShortcutsConfig();

  /// What the shell registered with the compositor when it started.
  ///
  /// The start-up snapshot, not the live config: it is what the keys on the
  /// user's keyboard actually do right now, and the only thing an edit can
  /// honestly be compared against.
  ShortcutsConfig get registered => _registered;

  ShortcutsConfig _shortcuts = const ShortcutsConfig();

  /// What `[shortcuts]` says now — the edits included.
  ShortcutsConfig get shortcuts => _shortcuts;

  /// Whether there is a config file behind this store at all.
  ///
  /// False in a widget test that pumps the sheet on its own, and the sheet then
  /// draws the shortcuts without offering to change them: an editor whose
  /// writes go nowhere is worse than no editor.
  bool get canEdit => _config != null;

  /// Points the store at the shell's config and records what was registered
  /// from it. Called once from `main()`, beside the other store seeds.
  void bind(ConfigStore config, {required ShortcutsConfig registered}) {
    _config?.removeListener(_reread);
    _config = config;
    _registered = registered;
    _shortcuts = _read(config);
    config.addListener(_reread);
  }

  /// What [shortcut] is bound to now, or null when the user disabled it.
  ShortcutSpec? specFor(ShellShortcut shortcut) => shortcut.specIn(_shortcuts);

  /// Whether [shortcut] is on something other than what the running shell
  /// registered — an edit waiting for a restart.
  bool isPending(ShellShortcut shortcut) =>
      shortcut.specIn(_shortcuts) != shortcut.specIn(_registered);

  /// Whether any of them is. What the sheet says "restart to apply" over.
  bool get needsRestart => _shortcuts != _registered;

  /// Whether [shortcut] is on the value it has with nothing in the config file,
  /// so the sheet knows whether to offer to put it back.
  bool isDefault(ShellShortcut shortcut) =>
      shortcut.specIn(_shortcuts) == shortcut.defaultSpec;

  /// Binds [shortcut] to [spec], writing it as the string a hand-written
  /// `config.toml` would have held.
  ///
  /// [ConfigStore] debounces the write, so a run of edits is one save.
  void setShortcut(ShellShortcut shortcut, ShortcutSpec spec) =>
      _write(shortcut, formatShortcut(spec));

  /// Turns [shortcut] off — an explicit empty string, which is what the config
  /// reader tells apart from an absent key.
  void disable(ShellShortcut shortcut) => _write(shortcut, '');

  /// Drops the key entirely, so [shortcut] falls back to its default.
  void restoreDefault(ShellShortcut shortcut) {
    final config = _config;
    if (config == null) return;
    config.remove(['shortcuts', shortcut.configKey]);
  }

  void _write(ShellShortcut shortcut, String value) {
    final config = _config;
    if (config == null) return;
    config.set(['shortcuts', shortcut.configKey], value);
  }

  /// [ConfigStore] notifies on every keystroke anywhere in the file, so this
  /// compares before it passes the notification on — every bar on every monitor
  /// is a listener, and `[shortcuts]` changes about four times a year.
  void _reread() {
    final config = _config;
    if (config == null) return;
    final next = _read(config);
    if (next == _shortcuts) return;
    _shortcuts = next;
    notifyListeners();
  }

  static ShortcutsConfig _read(ConfigStore config) =>
      ShortcutsConfig.fromMap(config.get<Map<String, dynamic>>(['shortcuts']));

  @override
  void dispose() {
    _config?.removeListener(_reread);
    _config = null;
    super.dispose();
  }
}

/// Points the shared store at the shell's config, with the shortcuts `main()`
/// registered from it.
///
/// Not a `ShellService`, [startKeybindService]'s reason: there is nothing to
/// start, and a shell whose config has no `[shortcuts]` table must not settle a
/// start-up task `failed` over an editor nobody has opened.
void startShellKeybindService(
  ConfigStore config, {
  required ShortcutsConfig registered,
}) => ShellKeybindStore.instance.bind(config, registered: registered);
