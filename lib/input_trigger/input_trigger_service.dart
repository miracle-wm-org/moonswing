import 'package:flutter/foundation.dart';
import 'package:graceful_shell/input_trigger/input_trigger_protocol.dart';
import 'package:graceful_shell/input_trigger/input_trigger_store.dart';
import 'package:wayland/wayland.dart';

/// One built-in global shortcut: a modifier+keysym combination and what it does
/// when the compositor reports it firing.
@immutable
class InputShortcut {
  const InputShortcut({
    required this.name,
    required this.modifiers,
    required this.keysym,
    required this.onActivate,
  });

  /// Action name passed to `get_action_control`. Has no semantic weight and may
  /// be duplicated across actions.
  final String name;

  /// Modifier bitfield ([InputTriggerModifiers]).
  final int modifiers;

  /// `xkbcommon` keysym, the shift-resolved character ([InputTriggerKeysyms]).
  final int keysym;

  /// Run when the compositor reports the trigger's `begin`.
  final VoidCallback onActivate;
}

/// The shell's built-in shortcuts. A list so making it config-driven (a
/// `[shortcuts]` TOML section) later is additive.
List<InputShortcut> defaultInputShortcuts() => [
      InputShortcut(
        name: 'graceful-shell.open-settings',
        modifiers: InputTriggerModifiers.ctrl | InputTriggerModifiers.shift,
        // Shift-resolved keysym: holding Shift turns the `s` key into `S`, and
        // Mir matches on the resolved character (see [InputTriggerKeysyms]).
        keysym: InputTriggerKeysyms.capitalS,
        onActivate: InputTriggerStore.instance.triggerSettings,
      ),
    ];

/// Registers the shell's global shortcuts with the compositor through the
/// ext-input-trigger protocols and routes their activations into
/// [InputTriggerStore].
///
/// It binds two globals: the registration manager (to register a trigger and
/// mint an action token) and the action manager (to subscribe to that token),
/// running the handshake once both are present. Everything is best-effort, the
/// same posture as `startOsdService`: a compositor that advertises neither
/// global (older Mir, or not Mir at all) simply gets no shortcuts, and a trigger
/// already owned by another client is logged and skipped — the shell never fails
/// because of this.
class InputTriggerManager {
  InputTriggerManager(this._client, {List<InputShortcut>? shortcuts})
      : _shortcuts = shortcuts ?? defaultInputShortcuts();

  final WaylandClient _client;
  final List<InputShortcut> _shortcuts;

  ExtInputTriggerRegistrationManagerV1? _registration;
  ExtInputTriggerActionManagerV1? _actionManager;
  bool _registered = false;

  /// True once both managers have been bound and the shortcuts registered.
  bool get isRegistered => _registered;

  /// Feed every global advertised by the shared Wayland registry here. Binds the
  /// two managers we care about (ignoring everything else) and, once both are
  /// up, registers the shortcuts.
  void handleGlobal(
      WaylandRegistry registry, int name, String interface, int version) {
    if (interface == registrationManagerInterface && _registration == null) {
      debugPrint('input-trigger: bound $interface v$version');
      _registration = ExtInputTriggerRegistrationManagerV1(
        _client,
        registry.bind(name, interface, version),
        onCapabilities: (c) =>
            debugPrint('input-trigger: capabilities=0x${c.toRadixString(16)} '
                '(keyboard=${c & 0x01 != 0})'),
      );
      _maybeRegister();
    } else if (interface == actionManagerInterface && _actionManager == null) {
      debugPrint('input-trigger: bound $interface v$version');
      _actionManager = ExtInputTriggerActionManagerV1(
        _client,
        registry.bind(name, interface, version),
      );
      _maybeRegister();
    }
  }

  void _maybeRegister() {
    if (_registered) return;
    final registration = _registration;
    final actionManager = _actionManager;
    if (registration == null || actionManager == null) return;
    _registered = true;
    for (final shortcut in _shortcuts) {
      _registerShortcut(registration, actionManager, shortcut);
    }
  }

  void _registerShortcut(
    ExtInputTriggerRegistrationManagerV1 registration,
    ExtInputTriggerActionManagerV1 actionManager,
    InputShortcut shortcut,
  ) {
    debugPrint('input-trigger: registering "${shortcut.name}" '
        'modifiers=0x${shortcut.modifiers.toRadixString(16)} '
        'keysym=0x${shortcut.keysym.toRadixString(16)}');
    final trigger = registration.registerKeyboardSymTrigger(
        shortcut.modifiers, shortcut.keysym);

    trigger.onDone = () {
      // We own the combination. Bind it to an action; the control's token then
      // drives the action-side subscription that delivers begin/end.
      debugPrint('input-trigger: "${shortcut.name}" owned; requesting token');
      final control = registration.getActionControl(shortcut.name);
      control.onToken = (token) {
        debugPrint('input-trigger: "${shortcut.name}" token received; '
            'subscribing to action');
        actionManager.getInputTriggerAction(
          token,
          onBegin: (_) {
            debugPrint('input-trigger: "${shortcut.name}" activated');
            shortcut.onActivate();
          },
          onUnavailable: () => debugPrint(
              'input-trigger: "${shortcut.name}" became unavailable'),
        );
      };
      control.addInputTriggerEvent(trigger);
    };

    trigger.onFailed = () {
      debugPrint('input-trigger: "${shortcut.name}" is already owned by '
          'another client; skipping');
      trigger.destroy();
    };
  }
}

/// Creates the manager that wires the shell's built-in global shortcuts into the
/// compositor. The caller feeds it globals from the shared Wayland registry
/// callback (see [InputTriggerManager.handleGlobal]). Safe on a compositor
/// without the ext-input-trigger globals: the manager just never binds anything.
InputTriggerManager startInputTriggerService(WaylandClient client) {
  return InputTriggerManager(client);
}
