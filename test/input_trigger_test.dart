import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/input_trigger/input_trigger_protocol.dart';
import 'package:graceful_shell/input_trigger/input_trigger_service.dart';
import 'package:graceful_shell/input_trigger/input_trigger_store.dart';
import 'package:graceful_shell/input_trigger/keysym.dart';
import 'package:wayland/wayland.dart';

/// Builds an event payload the way the compositor would, so decoding is tested
/// against the same wire layout it is written with.
WaylandWriteBuffer _payload() => WaylandWriteBuffer();

void main() {
  group('InputTriggerStore', () {
    test('triggerSettings notifies and counts each fire', () {
      final store = InputTriggerStore.forTesting();
      var fires = 0;
      store.addListener(() => fires++);

      store.triggerSettings();
      store.triggerSettings();

      expect(fires, 2);
      expect(store.settingsShortcutCount, 2);
    });
  });

  group('protocol event decoding', () {
    test('registration manager capabilities event sets keyboard support', () {
      final client = WaylandClient();
      int? reported;
      final manager = ExtInputTriggerRegistrationManagerV1(
        client,
        10,
        onCapabilities: (c) => reported = c,
      );

      final payload = _payload()..writeUint(0x01);
      expect(manager.processEvent(0, payload.data), isTrue);

      expect(reported, 0x01);
      expect(manager.capabilities, 0x01);
      expect(manager.keyboardSupported, isTrue);
    });

    test('trigger done and failed dispatch to the right callback', () {
      final client = WaylandClient();
      var done = false;
      var failed = false;
      final trigger = ExtInputTriggerV1(
        client,
        11,
        onDone: () => done = true,
        onFailed: () => failed = true,
      );

      expect(trigger.processEvent(0, _payload().data), isTrue);
      expect(done, isTrue);
      expect(failed, isFalse);

      expect(trigger.processEvent(1, _payload().data), isTrue);
      expect(failed, isTrue);
    });

    test('action control done delivers the token', () {
      final client = WaylandClient();
      String? token;
      final control = ExtInputTriggerActionControlV1(
        client,
        12,
        onToken: (t) => token = t,
      );

      final payload = _payload()..writeString('token-abc');
      expect(control.processEvent(0, payload.data), isTrue);

      expect(token, 'token-abc');
    });

    test('action begin/end decode time and skip the activation token', () {
      final client = WaylandClient();
      int? beginTime;
      int? endTime;
      var unavailable = false;
      final action = ExtInputTriggerActionV1(
        client,
        13,
        onBegin: (t) => beginTime = t,
        onEnd: (t) => endTime = t,
        onUnavailable: () => unavailable = true,
      );

      final begin = _payload()
        ..writeUint(4242)
        ..writeString('xdg-activation-token');
      expect(action.processEvent(0, begin.data), isTrue);
      expect(beginTime, 4242);

      final end = _payload()
        ..writeUint(9999)
        ..writeString('xdg-activation-token');
      expect(action.processEvent(1, end.data), isTrue);
      expect(endTime, 9999);

      expect(action.processEvent(2, _payload().data), isTrue);
      expect(unavailable, isTrue);
    });

    test('unknown opcodes are reported as unhandled', () {
      final client = WaylandClient();
      final trigger = ExtInputTriggerV1(client, 14);
      expect(trigger.processEvent(7, _payload().data), isFalse);
    });
  });

  group('protocol request construction', () {
    test('constructor requests return correctly-typed child objects', () {
      final client = WaylandClient();
      final registration = ExtInputTriggerRegistrationManagerV1(client, 20);
      final actionManager = ExtInputTriggerActionManagerV1(client, 21);

      final trigger = registration.registerKeyboardSymTrigger(
          InputTriggerModifiers.ctrl | InputTriggerModifiers.shift,
          InputTriggerKeysyms.s);
      expect(trigger, isA<ExtInputTriggerV1>());

      final codeTrigger =
          registration.registerKeyboardCodeTrigger(InputTriggerModifiers.alt, 31);
      expect(codeTrigger, isA<ExtInputTriggerV1>());

      final control = registration.getActionControl('an-action');
      expect(control, isA<ExtInputTriggerActionControlV1>());

      final action = actionManager.getInputTriggerAction('a-token');
      expect(action, isA<ExtInputTriggerActionV1>());

      // Every object gets a distinct, fresh id above the display's reserved 1.
      final ids = {trigger.id, codeTrigger.id, control.id, action.id};
      expect(ids.length, 4);
      expect(ids.every((id) => id > 1), isTrue);
    });
  });

  group('handshake wiring', () {
    test('a full register -> token -> begin chain reaches the activation', () {
      // Mirrors what InputTriggerManager drives, holding references so events
      // can be fed in, which validates that the sequence of wire ops is
      // internally consistent (child types, token flow, begin dispatch).
      final client = WaylandClient();
      final registration = ExtInputTriggerRegistrationManagerV1(client, 30);
      final actionManager = ExtInputTriggerActionManagerV1(client, 31);

      var activated = 0;

      final trigger = registration.registerKeyboardSymTrigger(
          InputTriggerModifiers.ctrl | InputTriggerModifiers.shift,
          InputTriggerKeysyms.s);

      ExtInputTriggerActionControlV1? control;
      ExtInputTriggerActionV1? action;

      trigger.onDone = () {
        control = registration.getActionControl('graceful-shell.open-settings');
        control!.onToken = (token) {
          action = actionManager.getInputTriggerAction(
            token,
            onBegin: (_) => activated++,
          );
        };
        control!.addInputTriggerEvent(trigger);
      };

      // Compositor grants ownership.
      trigger.processEvent(0, _payload().data);
      expect(control, isNotNull);

      // Control reports its token.
      control!.processEvent(0, (_payload()..writeString('tok')).data);
      expect(action, isNotNull);

      // The trigger fires: begin -> activation.
      action!.processEvent(
          0, (_payload()..writeUint(1)..writeString('act')).data);
      expect(activated, 1);
    });
  });

  group('inputShortcutsFor', () {
    test('the default config yields the settings shortcut, shift-resolved', () {
      final shortcuts = inputShortcutsFor(const ShortcutsConfig());

      expect(shortcuts, hasLength(1));
      expect(shortcuts.single.name, 'graceful-shell.open-settings');
      expect(shortcuts.single.modifiers,
          InputTriggerModifiers.ctrl | InputTriggerModifiers.shift);
      // Not 0x73: Mir matches the resolved character, so Shift+s is `S`.
      expect(shortcuts.single.keysym, InputTriggerKeysyms.capitalS);
    });

    test('a disabled shortcut is not registered at all', () {
      final shortcuts =
          inputShortcutsFor(const ShortcutsConfig(openSettings: null));
      expect(shortcuts, isEmpty);
    });

    test('a code: shortcut registers as a keycode', () {
      final shortcuts = inputShortcutsFor(ShortcutsConfig(
          openSettings: parseShortcut('ctrl+code:31')));
      expect(shortcuts.single.spec.isKeycode, isTrue);
      expect(shortcuts.single.keysym, 31);
    });
  });

  group('InputTriggerManager.handleGlobal', () {
    test('registers only once both managers are bound', () {
      final client = WaylandClient();
      final registry = WaylandRegistry(client, 2);
      final manager = InputTriggerManager(
        client,
        shortcuts: [
          InputShortcut(
            name: 'test',
            spec: const ShortcutSpec(
              modifiers: InputTriggerModifiers.ctrl,
              keysym: InputTriggerKeysyms.s,
            ),
            onActivate: () {},
          ),
        ],
      );

      manager.handleGlobal(registry, 3, 'wl_output', 4);
      expect(manager.isRegistered, isFalse);

      manager.handleGlobal(registry, 5, registrationManagerInterface, 1);
      expect(manager.isRegistered, isFalse);

      manager.handleGlobal(registry, 6, actionManagerInterface, 1);
      expect(manager.isRegistered, isTrue);
    });

    test('ignores duplicate globals without re-registering', () {
      final client = WaylandClient();
      final registry = WaylandRegistry(client, 2);
      final manager = InputTriggerManager(client, shortcuts: const []);

      manager.handleGlobal(registry, 5, registrationManagerInterface, 1);
      manager.handleGlobal(registry, 6, actionManagerInterface, 1);
      expect(manager.isRegistered, isTrue);

      // A second advertisement of the same interface must be a no-op.
      manager.handleGlobal(registry, 7, registrationManagerInterface, 1);
      expect(manager.isRegistered, isTrue);
    });
  });
}
