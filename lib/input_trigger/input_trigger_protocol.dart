import 'dart:typed_data';

import 'package:wayland/wayland.dart';

/// Dart bindings for Mir's `ext-input-trigger-registration-v1` and
/// `ext-input-trigger-action-v1` protocols, written as [WaylandObject]
/// subclasses in the same shape as the interfaces in `package:wayland` (e.g.
/// [WaylandOutput]): a request builds a payload and calls
/// `client.sendRequest(id, opcode, payload)`; a constructor request allocates
/// `client.getNextId()` and returns a new typed object; events dispatch through
/// the `processEvent(code, payload)` switch.
///
/// These live in the app rather than in the vendored `package:wayland` checkout,
/// which is an immutable git dependency.

/// The interface names as advertised by the compositor's registry.
const String registrationManagerInterface =
    'ext_input_trigger_registration_manager_v1';
const String actionManagerInterface = 'ext_input_trigger_action_manager_v1';

/// Bitfield from `ext_input_trigger_registration_manager_v1.modifiers`. A
/// trigger fires when exactly this set of modifiers is held with the key.
class InputTriggerModifiers {
  InputTriggerModifiers._();

  static const int alt = 0x01;
  static const int altLeft = 0x02;
  static const int altRight = 0x04;
  static const int shift = 0x08;
  static const int shiftLeft = 0x10;
  static const int shiftRight = 0x20;
  static const int sym = 0x40;
  static const int function = 0x80;
  static const int ctrl = 0x100;
  static const int ctrlLeft = 0x200;
  static const int ctrlRight = 0x400;
  static const int meta = 0x800;
  static const int metaLeft = 0x1000;
  static const int metaRight = 0x2000;
}

/// The handful of `xkbcommon-keysyms.h` keysyms the shell's built-in shortcuts
/// use. The keysym is the character the layout actually produces *after*
/// modifiers are applied — so a trigger that includes [InputTriggerModifiers.shift]
/// must use the shifted form ([capitalS], not [s]), even though the Shift bit is
/// also set. Mir matches on the resolved keysym: registering `s` for Ctrl+Shift+S
/// never fires because holding Shift turns the key into `S`.
class InputTriggerKeysyms {
  InputTriggerKeysyms._();

  static const int s = 0x0073; // XKB_KEY_s
  static const int capitalS = 0x0053; // XKB_KEY_S (Shift+s)
}

/// Bit in the registration manager's `capabilities` event indicating the
/// compositor can register keyboard triggers.
const int _capabilityKeyboard = 0x01;

/// `ext_input_trigger_registration_manager_v1` — the manager the shell binds to
/// register global input triggers and mint action tokens.
class ExtInputTriggerRegistrationManagerV1 extends WaylandObject {
  @override
  String get interfaceName => registrationManagerInterface;

  /// Latest `capabilities` bitfield reported by the compositor.
  int capabilities = 0;

  /// Fired when the `capabilities` event arrives.
  void Function(int capabilities)? onCapabilities;

  ExtInputTriggerRegistrationManagerV1(super.client, super.id,
      {this.onCapabilities});

  bool get keyboardSupported => capabilities & _capabilityKeyboard != 0;

  /// req 1 `register_keyboard_sym_trigger` — a character-key trigger. The
  /// returned trigger reports ownership through its `done`/`failed` events.
  ExtInputTriggerV1 registerKeyboardSymTrigger(int modifiers, int keysym) {
    final id = client.getNextId();
    final payload = WaylandWriteBuffer();
    payload.writeUint(modifiers);
    payload.writeUint(keysym);
    payload.writeUint(id);
    client.sendRequest(this.id, 1, payload.data);
    return ExtInputTriggerV1(client, id);
  }

  /// req 2 `register_keyboard_code_trigger` — a physical-key trigger keyed on an
  /// evdev keycode (layout-independent).
  ExtInputTriggerV1 registerKeyboardCodeTrigger(int modifiers, int keycode) {
    final id = client.getNextId();
    final payload = WaylandWriteBuffer();
    payload.writeUint(modifiers);
    payload.writeUint(keycode);
    payload.writeUint(id);
    client.sendRequest(this.id, 2, payload.data);
    return ExtInputTriggerV1(client, id);
  }

  /// req 3 `get_action_control` — create an action that a set of triggers
  /// activate. [name] has no semantic weight and may be duplicated. The control
  /// yields the action token through its `done` event.
  ExtInputTriggerActionControlV1 getActionControl(String name) {
    final id = client.getNextId();
    final payload = WaylandWriteBuffer();
    payload.writeString(name);
    payload.writeUint(id);
    client.sendRequest(this.id, 3, payload.data);
    return ExtInputTriggerActionControlV1(client, id);
  }

  /// req 0 `destroy`.
  void destroy() => client.sendRequest(id, 0);

  @override
  bool processEvent(int code, Uint8List payload) {
    switch (code) {
      case 0: // capabilities
        final buffer = WaylandReadBuffer(payload);
        capabilities = buffer.readUint();
        onCapabilities?.call(capabilities);
        return true;
      default:
        return false;
    }
  }
}

/// `ext_input_trigger_v1` — one attempted trigger registration. The compositor
/// sends exactly one of `done` (the shell now owns the trigger) or `failed`
/// (another client owns it; this object is dead and should be destroyed).
class ExtInputTriggerV1 extends WaylandObject {
  @override
  String get interfaceName => 'ext_input_trigger_v1';

  void Function()? onDone;
  void Function()? onFailed;

  ExtInputTriggerV1(super.client, super.id, {this.onDone, this.onFailed});

  /// req 0 `destroy`.
  void destroy() => client.sendRequest(id, 0);

  @override
  bool processEvent(int code, Uint8List payload) {
    switch (code) {
      case 0: // done
        onDone?.call();
        return true;
      case 1: // failed
        onFailed?.call();
        return true;
      default:
        return false;
    }
  }
}

/// `ext_input_trigger_action_control_v1` — binds triggers to an action and
/// yields the token that the action side subscribes to. The `done` token is
/// only briefly valid, so consume it immediately.
class ExtInputTriggerActionControlV1 extends WaylandObject {
  @override
  String get interfaceName => 'ext_input_trigger_action_control_v1';

  void Function(String token)? onToken;

  ExtInputTriggerActionControlV1(super.client, super.id, {this.onToken});

  /// req 0 `add_input_trigger_event` — add [trigger] to those that activate the
  /// action.
  void addInputTriggerEvent(ExtInputTriggerV1 trigger) {
    final payload = WaylandWriteBuffer();
    payload.writeObject(trigger);
    client.sendRequest(id, 0, payload.data);
  }

  /// req 1 `drop_input_trigger_event`.
  void dropInputTriggerEvent(ExtInputTriggerV1 trigger) {
    final payload = WaylandWriteBuffer();
    payload.writeObject(trigger);
    client.sendRequest(id, 1, payload.data);
  }

  /// req 2 `cancel` — any action created from this token becomes unavailable.
  void cancel() => client.sendRequest(id, 2);

  /// req 3 `destroy`.
  void destroy() => client.sendRequest(id, 3);

  @override
  bool processEvent(int code, Uint8List payload) {
    switch (code) {
      case 0: // done
        final buffer = WaylandReadBuffer(payload);
        onToken?.call(buffer.readString());
        return true;
      default:
        return false;
    }
  }
}

/// `ext_input_trigger_action_manager_v1` — the manager the shell binds to
/// subscribe to an action token and receive its activation events.
class ExtInputTriggerActionManagerV1 extends WaylandObject {
  @override
  String get interfaceName => actionManagerInterface;

  ExtInputTriggerActionManagerV1(super.client, super.id);

  /// req 1 `get_input_trigger_action` — subscribe to [token]. The returned
  /// action reports activations through its `begin`/`end` events.
  ExtInputTriggerActionV1 getInputTriggerAction(String token,
      {void Function(int time)? onBegin,
      void Function(int time)? onEnd,
      void Function()? onUnavailable}) {
    final id = client.getNextId();
    final payload = WaylandWriteBuffer();
    payload.writeString(token);
    payload.writeUint(id);
    client.sendRequest(this.id, 1, payload.data);
    return ExtInputTriggerActionV1(client, id,
        onBegin: onBegin, onEnd: onEnd, onUnavailable: onUnavailable);
  }

  /// req 0 `destroy`.
  void destroy() => client.sendRequest(id, 0);
}

/// `ext_input_trigger_action_v1` — a live subscription to one action token.
/// `begin`/`end` always arrive in pairs, begin first. The activation token is an
/// `xdg_activation` token the shell doesn't need to open its own overlay, so it
/// is read off the wire and discarded.
class ExtInputTriggerActionV1 extends WaylandObject {
  @override
  String get interfaceName => 'ext_input_trigger_action_v1';

  void Function(int time)? onBegin;
  void Function(int time)? onEnd;
  void Function()? onUnavailable;

  ExtInputTriggerActionV1(super.client, super.id,
      {this.onBegin, this.onEnd, this.onUnavailable});

  /// req 0 `destroy`.
  void destroy() => client.sendRequest(id, 0);

  @override
  bool processEvent(int code, Uint8List payload) {
    switch (code) {
      case 0: // begin
        final buffer = WaylandReadBuffer(payload);
        final time = buffer.readUint();
        buffer.readString(); // activation_token, unused
        onBegin?.call(time);
        return true;
      case 1: // end
        final buffer = WaylandReadBuffer(payload);
        final time = buffer.readUint();
        buffer.readString(); // activation_token, unused
        onEnd?.call(time);
        return true;
      case 2: // unavailable
        onUnavailable?.call();
        return true;
      default:
        return false;
    }
  }
}
