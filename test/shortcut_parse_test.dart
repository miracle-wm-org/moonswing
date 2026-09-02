import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/input_trigger/keysym.dart';

void main() {
  group('parseShortcut', () {
    test('reproduces the built-in defaults', () {
      // If these two ever diverge, every shortcut silently registers the wrong
      // key — the defaults are const and cannot call the parser themselves.
      expect(parseShortcut('ctrl+shift+s'), kDefaultOpenSettings);
      expect(parseShortcut('ctrl+space'), kDefaultOpenLauncher);
      expect(parseShortcut('ctrl+shift+e'), kDefaultOpenEmoji);
      expect(parseShortcut('poweroff'), kDefaultPowerButton);
    });

    // The machine's own power button is an ordinary key to the compositor:
    // evdev KEY_POWER, which the standard layouts map to XF86PowerOff.
    test('the power key is a named keysym, and bindable by code', () {
      expect(parseShortcut('poweroff')!.keysym, 0x1008ff2a);
      expect(parseShortcut('power'), parseShortcut('poweroff'));
      expect(parseShortcut('poweroff')!.modifiers, 0);
      expect(parseShortcut('sleep')!.keysym, 0x1008ff2f);
      // The layout-independent escape hatch, for a keyboard whose power key
      // does not produce that keysym.
      expect(parseShortcut('code:116')!.isKeycode, isTrue);
      expect(parseShortcut('code:116')!.keysym, 116);
    });

    test('shift resolves a letter to its shifted keysym', () {
      // Mir matches the character the layout produces, so Ctrl+Shift+S must be
      // registered as `S` (0x53), never `s` (0x73).
      expect(parseShortcut('ctrl+shift+s')!.keysym, 0x53);
      expect(parseShortcut('ctrl+s')!.keysym, 0x73);
    });

    test('shift resolves digits and punctuation through the US layout', () {
      expect(parseShortcut('ctrl+shift+1')!.keysym, 0x21); // !
      expect(parseShortcut('ctrl+shift+slash')!.keysym, 0x3f); // ?
    });

    test('a bare capital is not read as an implicit shift', () {
      // "ctrl+S" means Ctrl and the S key, not Ctrl+Shift+S; shift must be
      // spelled out or the modifier set the compositor matches would be wrong.
      expect(parseShortcut('ctrl+S'), parseShortcut('ctrl+s'));
      expect(parseShortcut('ctrl+S')!.modifiers, 0x100);
    });

    test('uses the generic modifier bits, not the left/right variants', () {
      expect(parseShortcut('ctrl+a')!.modifiers, 0x100);
      expect(parseShortcut('shift+a')!.modifiers, 0x08);
      expect(parseShortcut('alt+a')!.modifiers, 0x01);
      expect(parseShortcut('super+d')!.modifiers, 0x800);
      expect(parseShortcut('meta+d'), parseShortcut('super+d'));
      expect(parseShortcut('win+d'), parseShortcut('super+d'));
      expect(parseShortcut('control+a'), parseShortcut('ctrl+a'));
    });

    test('combines modifiers and ignores case and surrounding space', () {
      expect(parseShortcut('  CTRL + Alt + Shift + F5  '),
          parseShortcut('ctrl+alt+shift+f5'));
      expect(parseShortcut('ctrl+alt+shift+f5')!.modifiers, 0x100 | 0x01 | 0x08);
    });

    test('named keys resolve to their xkb keysyms', () {
      expect(parseShortcut('escape')!.keysym, 0xff1b);
      expect(parseShortcut('esc'), parseShortcut('escape'));
      expect(parseShortcut('enter'), parseShortcut('return'));
      expect(parseShortcut('f1')!.keysym, 0xffbe);
      expect(parseShortcut('f24')!.keysym, 0xffbe + 23);
      expect(parseShortcut('pageup')!.keysym, 0xff55);
      expect(parseShortcut('comma')!.keysym, 0x2c);
    });

    test('a raw keysym passes through untouched', () {
      final spec = parseShortcut('ctrl+0x41');
      expect(spec, const ShortcutSpec(modifiers: 0x100, keysym: 0x41));
      expect(spec!.isKeycode, isFalse);
    });

    test('the code: form marks the spec as a physical keycode', () {
      final spec = parseShortcut('alt+code:57');
      expect(spec!.isKeycode, isTrue);
      expect(spec.keysym, 57);
      expect(spec.modifiers, 0x01);
      // A keycode spec is never equal to the same number as a keysym.
      expect(spec, isNot(const ShortcutSpec(modifiers: 0x01, keysym: 57)));
    });

    test('an empty or "none" value means disabled', () {
      expect(parseShortcut(''), isNull);
      expect(parseShortcut('   '), isNull);
      expect(parseShortcut('none'), isNull);
      expect(parseShortcut('None'), isNull);
    });

    test('unusable strings are rejected rather than guessed at', () {
      expect(parseShortcut('ctrl+nosuchkey'), isNull);
      expect(parseShortcut('hyper+a'), isNull); // unknown modifier
      expect(parseShortcut('ctrl+'), isNull);
      expect(parseShortcut('+a'), isNull);
      expect(parseShortcut('ctrl+f25'), isNull);
      expect(parseShortcut('ctrl+0xzz'), isNull);
      expect(parseShortcut('ctrl+code:abc'), isNull);
    });
  });
}
