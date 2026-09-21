import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/emoji/emoji_controller.dart';
import 'package:graceful_shell/input_trigger/input_trigger_protocol.dart';
import 'package:graceful_shell/input_trigger/input_trigger_service.dart';
import 'package:graceful_shell/input_trigger/input_trigger_store.dart';
import 'package:graceful_shell/input_trigger/keysym.dart';
import 'package:graceful_shell/launcher/launcher_controller.dart';
import 'package:graceful_shell/notification_panel_controller.dart';
import 'package:graceful_shell/power/power_menu_controller.dart';
import 'package:wayland/wayland.dart';

/// Builds an event payload the way the compositor would, so decoding is tested
/// against the same wire layout it is written with.
WaylandWriteBuffer _payload() => WaylandWriteBuffer();

/// A config with nothing bound but the shortcuts named here.
///
/// Every key is written out rather than left to default: `ShortcutsConfig`'s
/// own defaults are all non-null, so a test naming only the keys it cares
/// about would quietly register the rest and stop testing what it says.
ShortcutsConfig _only({
  ShortcutSpec? openSettings,
  ShortcutSpec? openLauncher,
}) =>
    ShortcutsConfig(
      openSettings: openSettings,
      openLauncher: openLauncher,
      openEmoji: null,
      openNotifications: null,
      openPowerMenu: null,
      screenshotArea: null,
      recordScreen: null,
      powerButton: null,
      switchWindows: null,
      switchWindowsBack: null,
    );

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
    InputShortcut named(List<InputShortcut> shortcuts, String name) =>
        shortcuts.firstWhere((s) => s.name == name);

    test('the default config yields every shortcut, under distinct names', () {
      final shortcuts = inputShortcutsFor(const ShortcutsConfig());

      expect(shortcuts.map((s) => s.name).toSet(), {
        'graceful-shell.open-settings',
        'graceful-shell.open-launcher',
        'graceful-shell.open-emoji',
        'graceful-shell.open-notifications',
        'graceful-shell.open-power-menu',
        'graceful-shell.switch-windows',
        'graceful-shell.switch-windows-back',
        'graceful-shell.screenshot-area',
        'graceful-shell.record-screen',
        kPowerButtonShortcut,
      });
    });

    // Registration latches on the compositor's first answer, so a binding
    // skipped here would be one no setting could turn back on without a
    // restart — which is why `[power] key_action` is not consulted here at
    // all: what "none" costs is the logind inhibitor and the root's response
    // to the press, both of which are read live.
    test('the power button is bound to XF86PowerOff with no modifiers', () {
      final power = named(
          inputShortcutsFor(const ShortcutsConfig()), kPowerButtonShortcut);

      expect(power.modifiers, 0);
      expect(power.keysym, 0x1008ff2a);
      expect(power.spec.isKeycode, isFalse);
    });

    test('only the power button reports its ownership', () {
      final shortcuts = inputShortcutsFor(const ShortcutsConfig());
      for (final shortcut in shortcuts) {
        expect(
          shortcut.onOwnership,
          shortcut.name == kPowerButtonShortcut ? isNotNull : isNull,
          reason: shortcut.name,
        );
      }
    });

    test('the default settings shortcut is Super+S, unresolved', () {
      final settings = named(inputShortcutsFor(const ShortcutsConfig()),
          'graceful-shell.open-settings');

      expect(settings.modifiers, InputTriggerModifiers.meta);
      // Not `S`: shift resolution applies only to a combination that holds
      // Shift, and this one does not.
      expect(settings.keysym, InputTriggerKeysyms.s);
    });

    test('the default launcher shortcut is Super+D', () {
      final launcher = named(inputShortcutsFor(const ShortcutsConfig()),
          'graceful-shell.open-launcher');

      expect(launcher.modifiers, InputTriggerModifiers.meta);
      expect(launcher.keysym, 0x64);
    });

    test('the notification shortcut is Super+E and toggles the panel', () {
      final panel = named(inputShortcutsFor(const ShortcutsConfig()),
          'graceful-shell.open-notifications');

      expect(panel.modifiers, InputTriggerModifiers.meta);
      expect(panel.keysym, 0x65);

      // Super+E and Ctrl+Shift+E sit next to each other in the table and both
      // are a bare `toggle`, so a copy-paste would open the wrong surface.
      final before = NotificationPanelController.instance.signalCount;
      final emojiBefore = EmojiPickerController.instance.signalCount;
      panel.onActivate();
      expect(NotificationPanelController.instance.signalCount, before + 1);
      expect(EmojiPickerController.instance.signalCount, emojiBefore);
    });

    test('the power menu shortcut is Super+Shift+E, shift-resolved', () {
      final menu = named(inputShortcutsFor(const ShortcutsConfig()),
          'graceful-shell.open-power-menu');

      expect(menu.modifiers,
          InputTriggerModifiers.meta | InputTriggerModifiers.shift);
      // Not 0x65: Mir matches the resolved character, so Shift+e is `E`.
      expect(menu.keysym, 0x45);
      // Three shortcuts sit on the E key — this one, the notification panel
      // and the emoji picker — and only the modifiers tell them apart, so the
      // collision guard must not have collapsed any of them together.
      final panel = named(inputShortcutsFor(const ShortcutsConfig()),
          'graceful-shell.open-notifications');
      final emoji = named(inputShortcutsFor(const ShortcutsConfig()),
          'graceful-shell.open-emoji');
      expect(menu.spec == panel.spec, isFalse);
      expect(menu.spec == emoji.spec, isFalse);
    });

    test('the power menu shortcut opens the menu, not the panel', () {
      // Every one of the three is a bare `toggle` on a SignalController, so a
      // copy-paste that wired this to the notification panel would look right
      // and open the wrong surface.
      final before = PowerMenuController.instance.signalCount;
      final panelBefore = NotificationPanelController.instance.signalCount;

      named(inputShortcutsFor(const ShortcutsConfig()),
              'graceful-shell.open-power-menu')
          .onActivate();

      expect(PowerMenuController.instance.signalCount, before + 1);
      expect(NotificationPanelController.instance.signalCount, panelBefore);
    });

    test('the capture shortcuts are Print and Super+Print', () {
      final shortcuts = inputShortcutsFor(const ShortcutsConfig());
      final area = named(shortcuts, 'graceful-shell.screenshot-area');
      final record = named(shortcuts, 'graceful-shell.record-screen');

      expect(area.modifiers, 0);
      expect(area.keysym, 0xff61);
      expect(record.modifiers, InputTriggerModifiers.meta);
      expect(record.keysym, 0xff61);
      // The same key, and only the modifier telling them apart — so the
      // collision guard must not have collapsed one into the other.
      expect(area.spec == record.spec, isFalse);
    });

    test('the default emoji shortcut is Ctrl+Shift+E, shift-resolved', () {
      final emoji = named(inputShortcutsFor(const ShortcutsConfig()),
          'graceful-shell.open-emoji');

      expect(emoji.modifiers,
          InputTriggerModifiers.ctrl | InputTriggerModifiers.shift);
      // Not 0x65: Mir matches the resolved character, so Shift+e is `E`.
      expect(emoji.keysym, 0x45);
    });

    test('the emoji shortcut toggles the picker rather than the launcher', () {
      // The two sit next to each other in the table and both are a bare
      // `toggle` on a SignalController, so a copy-paste that wired this to
      // LauncherController would look right and open the wrong overlay.
      final before = EmojiPickerController.instance.signalCount;
      final launcherBefore = LauncherController.instance.signalCount;

      named(inputShortcutsFor(const ShortcutsConfig()),
              'graceful-shell.open-emoji')
          .onActivate();

      expect(EmojiPickerController.instance.signalCount, before + 1);
      expect(LauncherController.instance.signalCount, launcherBefore);
    });

    test('a disabled shortcut is not registered at all', () {
      final shortcuts = inputShortcutsFor(_only());
      expect(shortcuts, isEmpty);

      final onlyLauncher =
          inputShortcutsFor(_only(openLauncher: kDefaultOpenLauncher));
      expect(onlyLauncher.single.name, 'graceful-shell.open-launcher');
    });

    test('two shortcuts on the same combination collapse to the first', () {
      // Registering the second would come back `failed`, which the service
      // logs as "owned by another client" — a lie about the shell's own config.
      final shortcuts = inputShortcutsFor(_only(
        openSettings: parseShortcut('ctrl+space'),
        openLauncher: parseShortcut('ctrl+space'),
      ));

      expect(shortcuts.single.name, 'graceful-shell.open-settings');
    });

    test('a code: shortcut registers as a keycode', () {
      final shortcuts =
          inputShortcutsFor(_only(openSettings: parseShortcut('ctrl+code:31')));
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
