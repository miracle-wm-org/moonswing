import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miracle/miracle.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/input_trigger/keysym.dart';
import 'package:moonswing/keybinds/shell_keybind_store.dart';
import 'package:moonswing/keybinds/shell_keybinds.dart';
import 'package:moonswing/keybinds/shortcut_capture.dart';

Keybind _bind({
  BuiltInKeyCommand? action,
  String? command,
  List<Modifier> modifiers = const [Modifier.meta],
  String key = 'x',
}) => Keybind(
  action: action,
  actionName: action?.wireName,
  command: command,
  keyboardAction: KeyboardAction.down,
  modifiers: KeybindModifiers(
    modifiers: modifiers,
    mask: modifiers.fold(0, (mask, modifier) => mask | modifier.value),
  ),
  configuredModifiers: modifiers,
  xkbKeysym: 0,
  xkbKeysymName: key,
);

KeybindsResult _result(List<Keybind> keybinds) => KeybindsResult(
  primaryModifier: KeybindModifiers(
    modifiers: const [Modifier.meta],
    mask: Modifier.meta.value,
  ),
  keybinds: keybinds,
);

void main() {
  group('the shell\'s own shortcuts', () {
    test('every one of them is on its documented default', () {
      // The list the sheet draws is the list `[shortcuts]` binds — a shortcut
      // registered by the shell but missing here would be one a person can
      // press and never find written down.
      const config = ShortcutsConfig();
      expect(ShellShortcut.values.length, 12);
      expect(
        ShellShortcut.openLauncher.specIn(config),
        parseShortcut('super+d'),
      );
      expect(
        ShellShortcut.openSettings.specIn(config),
        parseShortcut('super+s'),
      );
      expect(
        ShellShortcut.openEmoji.specIn(config),
        parseShortcut('ctrl+shift+e'),
      );
      expect(
        ShellShortcut.openNotifications.specIn(config),
        parseShortcut('super+n'),
      );
      expect(
        ShellShortcut.openPowerMenu.specIn(config),
        parseShortcut('super+shift+e'),
      );
      expect(
        ShellShortcut.switchWindows.specIn(config),
        parseShortcut('alt+tab'),
      );
      expect(
        ShellShortcut.switchWindowsBack.specIn(config),
        parseShortcut('alt+shift+tab'),
      );
      expect(
        ShellShortcut.screenshotArea.specIn(config),
        parseShortcut('print'),
      );
      expect(
        ShellShortcut.recordScreen.specIn(config),
        parseShortcut('super+print'),
      );
      expect(
        ShellShortcut.toggleScratchpad.specIn(config),
        parseShortcut('super+z'),
      );
      expect(
        ShellShortcut.moveToScratchpad.specIn(config),
        parseShortcut('super+shift+z'),
      );
      expect(
        ShellShortcut.powerButton.specIn(config),
        parseShortcut('poweroff'),
      );
      for (final shortcut in ShellShortcut.values) {
        expect(shortcut.specIn(config), shortcut.defaultSpec);
      }
    });

    test('a disabled shortcut is a null spec, not a missing row', () {
      final config = ShortcutsConfig.fromMap(const {'open_emoji': ''});
      expect(ShellShortcut.openEmoji.specIn(config), isNull);
      // The others are untouched: one key, one shortcut.
      expect(ShellShortcut.openLauncher.specIn(config), kDefaultOpenLauncher);
      expect(ShellShortcut.recordScreen.specIn(config), kDefaultRecordScreen);
    });
  });

  group('caps', () {
    test('are the same caps the compositor\'s rows are drawn with', () {
      expect(shortcutLabel(kDefaultOpenLauncher), 'Super + D');
      expect(shortcutLabel(kDefaultOpenSettings), 'Super + S');
      expect(shortcutLabel(kDefaultScreenshotArea), 'Print');
      expect(shortcutLabel(kDefaultRecordScreen), 'Super + Print');
      expect(shortcutLabel(kDefaultToggleScratchpad), 'Super + Z');
      expect(shortcutLabel(kDefaultMoveToScratchpad), 'Shift + Super + Z');
      expect(shortcutLabel(kDefaultOpenEmoji), 'Ctrl + Shift + E');
      expect(shortcutLabel(kDefaultSwitchWindows), 'Alt + Tab');
      // `ISO_Left_Tab` is what Shift+Tab resolves to, and still the Tab key to
      // the person pressing it.
      expect(shortcutLabel(kDefaultSwitchWindowsBack), 'Alt + Shift + Tab');
      // `Modifier.meta` is `Super` on both halves of the sheet, because both
      // go through `miracle_labels.dart` rather than spelling it here.
      expect(shortcutLabel(parseShortcut('super+d')!), 'Super + D');
      expect(shortcutLabel(parseShortcut('alt+enter')!), 'Alt + Enter');
      expect(shortcutLabel(parseShortcut('ctrl+pageup')!), 'Ctrl + Page Up');
    });

    test('the power key reads as the key a keyboard prints', () {
      // `XF86PowerOff` with the vendor prefix dropped and the words split.
      expect(shortcutLabel(kDefaultPowerButton), 'Power Off');
    });

    test('modifiers are written in the conventional order', () {
      final spec = parseShortcut('super+shift+alt+ctrl+a')!;
      expect(shortcutLabel(spec), 'Ctrl + Alt + Shift + Super + A');
    });

    test('a key with no name is shown as it was written, never hidden', () {
      expect(
        shortcutLabel(const ShortcutSpec(modifiers: 0, keysym: 0xfe03)),
        '0xfe03',
      );
      expect(
        shortcutLabel(
          const ShortcutSpec(modifiers: 0, keysym: 116, isKeycode: true),
        ),
        'Code 116',
      );
    });

    test('Enter and the arrows carry their glyph', () {
      expect(capsForSpec(parseShortcut('enter')!).single.glyph, isNotNull);
      expect(capsForSpec(parseShortcut('left')!).single.glyph, isNotNull);
      // The label stays honest behind the picture.
      expect(capsForSpec(parseShortcut('enter')!).single.label, 'Enter');
    });
  });

  group('collisions', () {
    test('another shell shortcut on the same keys is named', () {
      const config = ShortcutsConfig();
      expect(
        shellCollisionFor(
          ShellShortcut.openEmoji,
          kDefaultOpenLauncher,
          config,
        ),
        ShellShortcut.openLauncher,
      );
      // Its own combination is not a collision with itself.
      expect(
        shellCollisionFor(
          ShellShortcut.openLauncher,
          kDefaultOpenLauncher,
          config,
        ),
        isNull,
      );
      expect(
        shellCollisionFor(
          ShellShortcut.openEmoji,
          parseShortcut('super+period')!,
          config,
        ),
        isNull,
      );
    });

    test('a disabled shortcut collides with nothing', () {
      // Both switched off is not both on the same key.
      final config = ShortcutsConfig.fromMap(const {
        'open_emoji': '',
        'open_launcher': '',
      });
      expect(
        shellCollisionFor(ShellShortcut.openEmoji, kDefaultOpenEmoji, config),
        isNull,
      );
    });

    test('a compositor binding on the same caps is named, never guessed', () {
      final result = _result([
        _bind(action: BuiltInKeyCommand.quitActiveWindow, key: 'q'),
        _bind(
          command: 'ptyxis',
          modifiers: const [Modifier.ctrl],
          key: 'space',
        ),
      ]);
      // Ctrl+Space, which is what the fake binds `ptyxis` to — no longer any
      // shell shortcut's default, and it does not need to be: what is being
      // tested is that the same caps on both sides are noticed.
      expect(
        compositorCollisionFor(parseShortcut('ctrl+space')!, result),
        'ptyxis',
      );
      expect(
        compositorCollisionFor(parseShortcut('super+q')!, result),
        'Close the focused window',
      );
      // Same key, different modifiers is not a collision.
      expect(compositorCollisionFor(parseShortcut('alt+q')!, result), isNull);
      // Nothing to compare against is not a collision either.
      expect(compositorCollisionFor(kDefaultOpenLauncher, null), isNull);
      // And the launcher's own default is on nothing the compositor binds.
      expect(compositorCollisionFor(kDefaultOpenLauncher, result), isNull);
    });
  });

  group('capturing a press', () {
    test('a letter with modifiers is the shortcut the parser would build', () {
      expect(
        captureShortcut(
          LogicalKeyboardKey.keyS,
          ctrl: false,
          alt: false,
          shift: false,
          meta: true,
        ),
        kDefaultOpenSettings,
      );
      expect(
        captureShortcut(
          LogicalKeyboardKey.keyD,
          ctrl: false,
          alt: false,
          shift: false,
          meta: true,
        ),
        kDefaultOpenLauncher,
      );
      // A key with a name rather than a character, captured with and without
      // the modifier that tells the two capture shortcuts apart.
      expect(
        captureShortcut(
          LogicalKeyboardKey.printScreen,
          ctrl: false,
          alt: false,
          shift: false,
          meta: false,
        ),
        kDefaultScreenshotArea,
      );
      expect(
        captureShortcut(
          LogicalKeyboardKey.printScreen,
          ctrl: false,
          alt: false,
          shift: false,
          meta: true,
        ),
        kDefaultRecordScreen,
      );
      expect(
        captureShortcut(
          LogicalKeyboardKey.space,
          ctrl: true,
          alt: false,
          shift: false,
          meta: false,
        ),
        parseShortcut('ctrl+space'),
      );
      expect(
        captureShortcut(
          LogicalKeyboardKey.f5,
          ctrl: false,
          alt: true,
          shift: false,
          meta: false,
        ),
        parseShortcut('alt+f5'),
      );
      expect(
        captureShortcut(
          LogicalKeyboardKey.period,
          ctrl: false,
          alt: false,
          shift: false,
          meta: true,
        ),
        parseShortcut('super+period'),
      );
    });

    test('a modifier on its own is not an answer', () {
      for (final key in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shift,
        LogicalKeyboardKey.altRight,
        LogicalKeyboardKey.metaLeft,
        // A lock is a state rather than something held, and the protocol fires
        // on an exact set of held modifiers.
        LogicalKeyboardKey.capsLock,
      ]) {
        expect(
          captureShortcut(
            key,
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
          ),
          isNull,
          reason: '$key is a modifier',
        );
      }
    });

    test('a key with no spelling is refused rather than mis-bound', () {
      expect(
        captureShortcut(
          LogicalKeyboardKey.launchMail,
          ctrl: false,
          alt: false,
          shift: false,
          meta: false,
        ),
        isNull,
      );
    });

    test('the named keys go through the same table the config file uses', () {
      expect(shortcutTokenForKey(LogicalKeyboardKey.escape), 'escape');
      expect(shortcutTokenForKey(LogicalKeyboardKey.numpadEnter), 'enter');
      expect(shortcutTokenForKey(LogicalKeyboardKey.pageDown), 'pagedown');
      expect(shortcutTokenForKey(LogicalKeyboardKey.f24), 'f24');
      expect(shortcutTokenForKey(LogicalKeyboardKey.power), 'poweroff');
      expect(shortcutTokenForKey(LogicalKeyboardKey.keyA), 'a');
      expect(shortcutTokenForKey(LogicalKeyboardKey.digit1), '1');
    });
  });

  group('the store', () {
    late Directory tempDir;
    late String path;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('gs_shell_keybind_test');
      path = '${tempDir.path}/config.toml';
      await File(path).writeAsString('''
theme = "dracula"

[shortcuts]
open_launcher = "super+space"
''');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    /// The store over a real file, with the shortcuts a shell started from it
    /// would have registered — which is what makes "pending" mean anything.
    Future<({ShellKeybindStore store, ConfigStore config})> open({
      ShortcutsConfig? registered,
    }) async {
      final config = await ConfigStore.loadFrom(path);
      addTearDown(config.dispose);
      final store = ShellKeybindStore.forTesting(
        config: config,
        registered:
            registered ??
            ShortcutsConfig.fromMap(
              config.get<Map<String, dynamic>>(['shortcuts']),
            ),
      );
      addTearDown(store.dispose);
      return (store: store, config: config);
    }

    test('reads the file, and an absent key is the default', () async {
      final (:store, :config) = await open();
      expect(store.canEdit, isTrue);
      expect(
        store.specFor(ShellShortcut.openLauncher),
        parseShortcut('super+space'),
      );
      expect(store.specFor(ShellShortcut.openEmoji), kDefaultOpenEmoji);
      expect(store.isDefault(ShellShortcut.openLauncher), isFalse);
      expect(store.isDefault(ShellShortcut.openEmoji), isTrue);
      expect(config.get<String>(['theme']), 'dracula');
    });

    test('a write lands in the file as the text a person would have typed',
        () async {
      final (:store, :config) = await open();
      var notifications = 0;
      store.addListener(() => notifications++);

      store.setShortcut(ShellShortcut.openEmoji, parseShortcut('super+e')!);
      expect(notifications, 1);
      expect(store.specFor(ShellShortcut.openEmoji), parseShortcut('super+e'));

      await config.flush();
      // Stored as a shortcut string, not as a bitfield: the config file has to
      // stay something a person can still read and edit by hand.
      expect(await File(path).readAsString(), contains("open_emoji = 'super+e'"));
    });

    test('an edit is pending until the shell is restarted', () async {
      final (:store, config: _) = await open();
      expect(store.needsRestart, isFalse);
      expect(store.isPending(ShellShortcut.openEmoji), isFalse);

      store.setShortcut(ShellShortcut.openEmoji, parseShortcut('super+e')!);

      // Global shortcuts latch on the compositor's first answer, so what the
      // keyboard does has not changed and the sheet has to say so.
      expect(store.needsRestart, isTrue);
      expect(store.isPending(ShellShortcut.openEmoji), isTrue);
      expect(store.isPending(ShellShortcut.openLauncher), isFalse);

      // Put back what was registered and there is nothing left to restart for.
      store.setShortcut(ShellShortcut.openEmoji, kDefaultOpenEmoji);
      expect(store.needsRestart, isFalse);
    });

    test('disabling writes the empty string the reader tells from absent',
        () async {
      final (:store, :config) = await open();
      store.disable(ShellShortcut.openEmoji);

      expect(store.specFor(ShellShortcut.openEmoji), isNull);
      expect(store.isDefault(ShellShortcut.openEmoji), isFalse);
      await config.flush();
      // The key stays, holding an empty string: an absent key is the default,
      // and only the empty one is "off".
      expect(await File(path).readAsString(), contains("open_emoji = ''"));
    });

    test('restoring the default drops the key rather than writing it out',
        () async {
      final (:store, :config) = await open();
      store.restoreDefault(ShellShortcut.openLauncher);

      expect(store.specFor(ShellShortcut.openLauncher), kDefaultOpenLauncher);
      await config.flush();
      expect(await File(path).readAsString(), isNot(contains('open_launcher')));
    });

    test('a change elsewhere in the file is not a notification', () async {
      final (:store, :config) = await open();
      var notifications = 0;
      store.addListener(() => notifications++);

      // Every bar on every monitor listens to this store; a keystroke in the
      // theme name must not reach any of them.
      config.set(['theme'], 'forest');
      expect(notifications, 0);
    });

    test('an unbound store shows the defaults and offers no editing', () {
      final store = ShellKeybindStore.forTesting();
      addTearDown(store.dispose);
      expect(store.canEdit, isFalse);
      expect(store.specFor(ShellShortcut.openLauncher), kDefaultOpenLauncher);
      expect(store.needsRestart, isFalse);
      // The writes are no-ops rather than a crash: the sheet hides the editor,
      // and nothing below it has to know that it did.
      store.setShortcut(ShellShortcut.openEmoji, kDefaultOpenLauncher);
      expect(store.specFor(ShellShortcut.openEmoji), kDefaultOpenEmoji);
    });
  });
}
