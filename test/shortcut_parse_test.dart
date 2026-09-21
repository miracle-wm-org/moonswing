import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/input_trigger/keysym.dart';

void main() {
  group('parseShortcut', () {
    test('reproduces the built-in defaults', () {
      // If these two ever diverge, every shortcut silently registers the wrong
      // key — the defaults are const and cannot call the parser themselves.
      expect(parseShortcut('super+s'), kDefaultOpenSettings);
      expect(parseShortcut('super+d'), kDefaultOpenLauncher);
      expect(parseShortcut('ctrl+shift+e'), kDefaultOpenEmoji);
      expect(parseShortcut('super+e'), kDefaultOpenNotifications);
      expect(parseShortcut('super+shift+e'), kDefaultOpenPowerMenu);
      expect(parseShortcut('alt+tab'), kDefaultSwitchWindows);
      expect(parseShortcut('alt+shift+tab'), kDefaultSwitchWindowsBack);
      expect(parseShortcut('print'), kDefaultScreenshotArea);
      expect(parseShortcut('super+print'), kDefaultRecordScreen);
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

    // Not a US-layout guess like the digits below: xkb resolves Shift+Tab to
    // ISO_Left_Tab on every layout, and Mir matches the resolved keysym — so a
    // plain `Tab` here is a shortcut that never fires.
    test('shift resolves Tab to ISO_Left_Tab, and back again', () {
      expect(parseShortcut('alt+shift+tab')!.keysym, kIsoLeftTabKeysym);
      expect(parseShortcut('alt+tab')!.keysym, 0xff09);
      expect(formatShortcut(parseShortcut('alt+shift+tab')!),
          'alt+shift+tab');
      // And the cap both halves of the cheat sheet draw it from.
      expect(xkbKeysymName(kIsoLeftTabKeysym), 'ISO_Left_Tab');
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

  group('formatShortcut', () {
    /// The property the editor rests on: a shortcut captured from the keyboard
    /// is stored as text, and what is stored has to parse back to the very same
    /// registration. A round trip that loses the shift resolution binds the
    /// wrong key on the next start-up, and nothing says so until a key is
    /// pressed.
    void roundTrips(String written) {
      final spec = parseShortcut(written);
      expect(spec, isNotNull, reason: '"$written" should parse');
      expect(formatShortcut(spec!), written);
      expect(parseShortcut(formatShortcut(spec)), spec);
    }

    test('writes the defaults exactly as the default config spells them', () {
      expect(formatShortcut(kDefaultOpenSettings), 'super+s');
      expect(formatShortcut(kDefaultOpenLauncher), 'super+d');
      expect(formatShortcut(kDefaultOpenEmoji), 'ctrl+shift+e');
      expect(formatShortcut(kDefaultOpenNotifications), 'super+e');
      // Spelled in the canonical modifier order, which puts Super last; the
      // parser reads `super+shift+e` as the very same combination.
      expect(formatShortcut(kDefaultOpenPowerMenu), 'shift+super+e');
      expect(formatShortcut(kDefaultScreenshotArea), 'print');
      expect(formatShortcut(kDefaultRecordScreen), 'super+print');
      expect(formatShortcut(kDefaultPowerButton), 'poweroff');
    });

    test('round-trips letters, digits, named keys and punctuation', () {
      roundTrips('ctrl+a');
      roundTrips('super+d');
      roundTrips('alt+f5');
      roundTrips('ctrl+alt+shift+f24');
      roundTrips('ctrl+space');
      roundTrips('escape');
      roundTrips('print');
      roundTrips('super+print');
      roundTrips('ctrl+pageup');
      roundTrips('super+period');
      roundTrips('ctrl+bracketleft');
      roundTrips('poweroff');
      roundTrips('sleep');
    });

    test('un-does the shift resolution it was written with', () {
      // `ctrl+shift+s` parses to `S`; writing that back out as `ctrl+shift+S`
      // would not parse, and writing it as `ctrl+s` would drop the shift.
      roundTrips('ctrl+shift+s');
      roundTrips('ctrl+shift+1');
      roundTrips('ctrl+shift+slash');
      roundTrips('shift+minus');
    });

    test('writes the modifiers in the order a shortcut is read', () {
      // Ctrl, Alt, Shift, Super — `miracle_labels.dart`'s order, because both
      // halves of the cheat sheet are read off one page.
      expect(
        formatShortcut(parseShortcut('super+shift+alt+ctrl+a')!),
        'ctrl+alt+shift+super+a',
      );
    });

    test('keeps the two escape hatches', () {
      roundTrips('ctrl+code:57');
      // A keysym with no name of its own comes back as the number it is,
      // rather than as a key that happens to be near it.
      expect(formatShortcut(const ShortcutSpec(modifiers: 0, keysym: 0xfe03)),
          '0xfe03');
      expect(parseShortcut('0xfe03'),
          const ShortcutSpec(modifiers: 0, keysym: 0xfe03));
    });
  });

  group('xkbKeysymName', () {
    /// The bridge that lets the shell's shortcuts be drawn by the key-cap table
    /// written for miracle's: it has to answer in *miracle's* vocabulary, not
    /// in the parser's.
    test('answers with the compositor\'s spelling, not the config file\'s', () {
      expect(xkbKeysymName(0xff1b), 'Escape');
      expect(xkbKeysymName(0xff0d), 'Return');
      expect(xkbKeysymName(0xff08), 'BackSpace');
      expect(xkbKeysymName(0xff55), 'Prior');
      expect(xkbKeysymName(0x1008ff2a), 'XF86PowerOff');
      expect(xkbKeysymName(0x0020), 'space');
      expect(xkbKeysymName(0xffbe), 'F1');
    });

    test('a printable keysym is its own character', () {
      expect(xkbKeysymName(0x53), 'S');
      expect(xkbKeysymName(0x73), 's');
      expect(xkbKeysymName(0x21), '!');
      expect(xkbKeysymName(0x5b), '[');
    });

    test('a keysym it has never heard of has no name', () {
      expect(xkbKeysymName(0xfe03), isNull);
    });
  });

  group('shortcutTokenForCharacter', () {
    /// What a captured key press goes through: the editor knows only what the
    /// key is labelled, and Shift is reported separately — so a label has to
    /// come back as the *un*shifted token or the shift would be spelled twice.
    test('drops the case and undoes the shift', () {
      expect(shortcutTokenForCharacter('S'), 's');
      expect(shortcutTokenForCharacter('s'), 's');
      expect(shortcutTokenForCharacter('!'), '1');
      expect(shortcutTokenForCharacter('?'), 'slash');
      expect(shortcutTokenForCharacter('_'), 'minus');
      expect(shortcutTokenForCharacter('-'), 'minus');
      expect(shortcutTokenForCharacter('7'), '7');
    });

    test('a character with no spelling is refused, not guessed at', () {
      expect(shortcutTokenForCharacter(''), isNull);
      expect(shortcutTokenForCharacter('ab'), isNull);
      expect(shortcutTokenForCharacter('\u00e9'), isNull);
    });
  });
}
