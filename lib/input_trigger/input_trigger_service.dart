import 'package:flutter/foundation.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/emoji/emoji_controller.dart';
import 'package:graceful_shell/input_trigger/input_trigger_protocol.dart';
import 'package:graceful_shell/input_trigger/input_trigger_store.dart';
import 'package:graceful_shell/input_trigger/keysym.dart';
import 'package:graceful_shell/launcher/launcher_controller.dart';
import 'package:graceful_shell/power/power_controller.dart';
import 'package:graceful_shell/power/power_service.dart';
import 'package:wayland/wayland.dart';

/// One global shortcut: a key combination and what it does when the compositor
/// reports it firing.
@immutable
class InputShortcut {
  const InputShortcut({
    required this.name,
    required this.spec,
    required this.onActivate,
    this.onOwnership,
  });

  /// Action name passed to `get_action_control`. Has no semantic weight and may
  /// be duplicated across actions.
  final String name;

  /// The combination to register.
  final ShortcutSpec spec;

  /// Run when the compositor reports the trigger's `begin`.
  final VoidCallback onActivate;

  /// Run with whether the compositor actually gave the shell this combination —
  /// true on the trigger's `done`, false when it was refused, became unavailable,
  /// or the globals were never advertised at all.
  ///
  /// Only the power button has one, and it is what stops the shell inhibiting
  /// logind's power-key handling on a machine where the press will never arrive:
  /// an inhibited key nobody answers is a power button that does nothing.
  /// Everything else fails soft by simply not firing.
  final void Function(bool owned)? onOwnership;

  int get modifiers => spec.modifiers;
  int get keysym => spec.keysym;
}

/// The action name the power-button trigger is registered under. Named
/// because two things care: the registration, and the ownership report that
/// decides whether the shell holds logind's inhibitor.
const String kPowerButtonShortcut = 'graceful-shell.power-button';

/// Turns the user's `[shortcuts]` config into the list the manager registers.
///
/// Disabled shortcuts (a null spec) are dropped, and two shortcuts resolving to
/// the same combination are collapsed to the first — otherwise the second
/// registration would come back `failed` and be logged as "owned by another
/// client", which would be a lie about the shell's own config.
///
/// The power button is registered whatever `[power] key_action` says, `"none"`
/// included: registration latches on the compositor's first answer, so a binding
/// skipped here is one no setting could turn back on without a restart. What
/// `"none"` costs instead is the logind inhibitor and the root's response to the
/// press, both read from the live config at the moment they matter.
List<InputShortcut> inputShortcutsFor(ShortcutsConfig config) {
  final wanted = <(String, ShortcutSpec?, VoidCallback, void Function(bool)?)>[
    (
      'graceful-shell.open-settings',
      config.openSettings,
      InputTriggerStore.instance.triggerSettings,
      null,
    ),
    (
      'graceful-shell.open-launcher',
      config.openLauncher,
      LauncherController.instance.toggle,
      null,
    ),
    (
      'graceful-shell.open-emoji',
      config.openEmoji,
      EmojiPickerController.instance.toggle,
      null,
    ),
    (
      kPowerButtonShortcut,
      config.powerButton,
      PowerController.instance.pressPowerKey,
      PowerKeyService.instance.setKeyOwned,
    ),
  ];

  final shortcuts = <InputShortcut>[];
  final seen = <ShortcutSpec, String>{};
  for (final (name, spec, onActivate, onOwnership) in wanted) {
    if (spec == null) {
      debugPrint('input-trigger: "$name" is disabled by config');
      // A shortcut that is never registered is one the compositor will never
      // confirm, and for the power button that is the difference between the
      // shell holding logind's inhibitor and not. Say so now rather than
      // leaving the service waiting for an answer that cannot come.
      onOwnership?.call(false);
      continue;
    }
    final owner = seen[spec];
    if (owner != null) {
      debugPrint('input-trigger: "$name" is configured to the same combination '
          'as "$owner"; only "$owner" is registered');
      onOwnership?.call(false);
      continue;
    }
    seen[spec] = name;
    shortcuts.add(InputShortcut(
      name: name,
      spec: spec,
      onActivate: onActivate,
      onOwnership: onOwnership,
    ));
  }
  return shortcuts;
}

/// The shell's shortcuts with no user config applied.
List<InputShortcut> defaultInputShortcuts() =>
    inputShortcutsFor(const ShortcutsConfig());

/// Registers the shell's global shortcuts with the compositor through the
/// ext-input-trigger protocols and routes their activations into
/// [InputTriggerStore].
///
/// It binds two globals — the registration manager, to register a trigger and
/// mint an action token, and the action manager, to subscribe to that token —
/// running the handshake once both are present. Everything is best-effort: a
/// compositor advertising neither global gets no shortcuts, and a trigger already
/// owned by another client is logged and skipped.
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

  /// Tells every shortcut that cares that the compositor never offered the
  /// protocols, so nothing of theirs was registered and nothing ever will be.
  /// Called once by [_connectDisplays] after the initial global burst.
  void reportUnregistered() {
    if (_registered) return;
    for (final shortcut in _shortcuts) {
      shortcut.onOwnership?.call(false);
    }
  }

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
    final kind = shortcut.spec.isKeycode ? 'keycode' : 'keysym';
    debugPrint('input-trigger: registering "${shortcut.name}" '
        'modifiers=0x${shortcut.modifiers.toRadixString(16)} '
        '$kind=0x${shortcut.keysym.toRadixString(16)}');
    // The `code:` config form asks for a physical key rather than a character,
    // which is what makes a shortcut survive a layout change.
    final trigger = shortcut.spec.isKeycode
        ? registration.registerKeyboardCodeTrigger(
            shortcut.modifiers, shortcut.keysym)
        : registration.registerKeyboardSymTrigger(
            shortcut.modifiers, shortcut.keysym);

    trigger.onDone = () {
      // We own the combination. Bind it to an action; the control's token then
      // drives the action-side subscription that delivers begin/end.
      debugPrint('input-trigger: "${shortcut.name}" owned; requesting token');
      shortcut.onOwnership?.call(true);
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
          onUnavailable: () {
            debugPrint(
                'input-trigger: "${shortcut.name}" became unavailable');
            shortcut.onOwnership?.call(false);
          },
        );
      };
      control.addInputTriggerEvent(trigger);
    };

    trigger.onFailed = () {
      debugPrint('input-trigger: "${shortcut.name}" is already owned by '
          'another client; skipping');
      shortcut.onOwnership?.call(false);
      trigger.destroy();
    };
  }
}

/// Creates the manager that wires the shell's global shortcuts into the
/// compositor. The caller feeds it globals from the shared Wayland registry
/// callback. Safe on a compositor without the ext-input-trigger globals: the
/// manager just never binds anything.
///
/// [shortcuts] comes from the start-up config snapshot, not the live store:
/// registration latches, so a later edit cannot take effect anyway.
InputTriggerManager startInputTriggerService(
  WaylandClient client, {
  ShortcutsConfig shortcuts = const ShortcutsConfig(),
}) {
  return InputTriggerManager(client, shortcuts: inputShortcutsFor(shortcuts));
}
