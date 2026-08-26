// Parsing of human-written shortcut strings (`"ctrl+shift+s"`) into the
// modifier bitfield + keysym pair the ext-input-trigger protocol takes.
//
// Deliberately dependency-free — no Flutter, no config — so it can be unit
// tested on its own and so `config.dart` can import it without a cycle.

/// One resolved global shortcut: the modifier bitfield and the key it fires on.
///
/// [keysym] is an `xkbcommon` keysym unless [isKeycode], in which case it is a
/// raw evdev keycode and the trigger must be registered with
/// `register_keyboard_code_trigger` instead.
class ShortcutSpec {
  const ShortcutSpec({
    required this.modifiers,
    required this.keysym,
    this.isKeycode = false,
  });

  /// Bitfield from `ext_input_trigger_registration_manager_v1.modifiers`.
  final int modifiers;

  /// `xkbcommon` keysym, or an evdev keycode when [isKeycode].
  final int keysym;

  /// Whether [keysym] is really a physical keycode (the `code:` form).
  final bool isKeycode;

  @override
  bool operator ==(Object other) =>
      other is ShortcutSpec &&
      other.modifiers == modifiers &&
      other.keysym == keysym &&
      other.isKeycode == isKeycode;

  @override
  int get hashCode => Object.hash(modifiers, keysym, isKeycode);

  @override
  String toString() => 'ShortcutSpec(modifiers: 0x${modifiers.toRadixString(16)}'
      ', ${isKeycode ? 'keycode' : 'keysym'}: 0x${keysym.toRadixString(16)})';
}

/// Modifier bits, keyed by the names accepted in a shortcut string.
///
/// Only the *generic* bits are offered: the protocol fires a trigger when
/// exactly the registered modifier set is held, so registering `ctrl_left`
/// would mean the shortcut stops working on the right-hand Control key.
const Map<String, int> _modifierNames = {
  'ctrl': 0x100,
  'control': 0x100,
  'shift': 0x08,
  'alt': 0x01,
  'meta': 0x800,
  'super': 0x800,
  'win': 0x800,
  'logo': 0x800,
};

/// Named (non-character) keys, from `xkbcommon-keysyms.h`.
const Map<String, int> _namedKeysyms = {
  'space': 0x0020,
  'return': 0xff0d,
  'enter': 0xff0d,
  'tab': 0xff09,
  'escape': 0xff1b,
  'esc': 0xff1b,
  'backspace': 0xff08,
  'delete': 0xffff,
  'del': 0xffff,
  'insert': 0xff63,
  'home': 0xff50,
  'end': 0xff57,
  'pageup': 0xff55,
  'pagedown': 0xff56,
  'left': 0xff51,
  'up': 0xff52,
  'right': 0xff53,
  'down': 0xff54,
  'print': 0xff61,
  'pause': 0xff13,
  'menu': 0xff67,
  // The machine's own power button. It is an ordinary key as far as the
  // compositor is concerned — evdev `KEY_POWER` (116), which every standard
  // xkb layout maps to `XF86PowerOff` — which is what lets the shell bind it
  // like any other shortcut. What is *not* ordinary is that systemd-logind
  // watches the same device directly and powers the machine off on a press,
  // so binding this without also taking logind's `handle-power-key` inhibitor
  // (see `lib/power/`) draws a menu onto a machine that is already going
  // down. `sleep` is the same key's neighbour on the keyboards that have one.
  'poweroff': 0x1008ff2a,
  'power': 0x1008ff2a,
  'sleep': 0x1008ff2f,
};

/// Punctuation keysyms, spelled by name so a shortcut string never has to
/// contain a literal `+` (which is the separator).
const Map<String, int> _punctuationKeysyms = {
  'minus': 0x002d,
  'equal': 0x003d,
  'plus': 0x002b,
  'comma': 0x002c,
  'period': 0x002e,
  'slash': 0x002f,
  'backslash': 0x005c,
  'semicolon': 0x003b,
  'apostrophe': 0x0027,
  'grave': 0x0060,
  'bracketleft': 0x005b,
  'bracketright': 0x005d,
};

/// What the US layout produces when Shift is held with a digit or punctuation
/// key. Mir matches on the *resolved* keysym (see [ShortcutSpec] callers and
/// `input_trigger_protocol.dart`), so `"ctrl+shift+1"` has to register `!`.
///
/// Explicitly US-only: on other layouts Shift+2 is not `@`, and there is no way
/// to know the user's layout from here. `CONFIG.md` documents the `0x…` and
/// `code:` escape hatches for anyone this is wrong for.
const Map<int, int> _usShifted = {
  0x0031: 0x0021, // 1 -> !
  0x0032: 0x0040, // 2 -> @
  0x0033: 0x0023, // 3 -> #
  0x0034: 0x0024, // 4 -> $
  0x0035: 0x0025, // 5 -> %
  0x0036: 0x005e, // 6 -> ^
  0x0037: 0x0026, // 7 -> &
  0x0038: 0x002a, // 8 -> *
  0x0039: 0x0028, // 9 -> (
  0x0030: 0x0029, // 0 -> )
  0x002d: 0x005f, // - -> _
  0x003d: 0x002b, // = -> +
  0x002c: 0x003c, // , -> <
  0x002e: 0x003e, // . -> >
  0x002f: 0x003f, // / -> ?
  0x005c: 0x007c, // \ -> |
  0x003b: 0x003a, // ; -> :
  0x0027: 0x0022, // ' -> "
  0x0060: 0x007e, // ` -> ~
  0x005b: 0x007b, // [ -> {
  0x005d: 0x007d, // ] -> }
};

/// Resolves the key half of a shortcut string to a keysym, ignoring modifiers.
int? _keysymForToken(String token) {
  if (token.length == 1) {
    final code = token.codeUnitAt(0);
    // a-z and 0-9 are their own ASCII keysyms.
    if ((code >= 0x61 && code <= 0x7a) || (code >= 0x30 && code <= 0x39)) {
      return code;
    }
    return _punctuationKeysyms.values.contains(code) ? code : null;
  }
  if (_namedKeysyms.containsKey(token)) return _namedKeysyms[token];
  if (_punctuationKeysyms.containsKey(token)) return _punctuationKeysyms[token];
  // F1 - F24 are contiguous from XKB_KEY_F1.
  final function = RegExp(r'^f([1-9]|1[0-9]|2[0-4])$').firstMatch(token);
  if (function != null) {
    return 0xffbe + int.parse(function.group(1)!) - 1;
  }
  return null;
}

/// Parses a shortcut string such as `"ctrl+shift+s"`, `"ctrl+space"`, or
/// `"super+d"` into the pair the compositor is asked to register.
///
/// Returns null when the shortcut is disabled (`""` or `"none"`) or cannot be
/// understood; callers decide whether that means "fall back to the default" or
/// "register nothing", and the two are deliberately not distinguished here.
///
/// Accepted forms for the key:
///  * a single letter or digit, a named key (`space`, `f5`, `pageup`, …), or a
///    punctuation name (`comma`, `slash`, …);
///  * `0x41` — a raw keysym, for layouts this table does not cover;
///  * `code:57` — a raw evdev keycode, which is layout-independent.
///
/// Shift must be spelled out: `"ctrl+S"` is read as `"ctrl+s"`, not as
/// `"ctrl+shift+s"`. When shift *is* present the keysym is shift-resolved
/// (`s` becomes `S`), because that is what Mir matches on.
ShortcutSpec? parseShortcut(String value) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.isEmpty || trimmed == 'none') return null;

  final parts = trimmed.split('+').map((p) => p.trim()).toList();
  if (parts.any((p) => p.isEmpty)) return null;

  var modifiers = 0;
  for (var i = 0; i < parts.length - 1; i++) {
    final bit = _modifierNames[parts[i]];
    if (bit == null) return null;
    modifiers |= bit;
  }

  final key = parts.last;

  if (key.startsWith('code:')) {
    final code = int.tryParse(key.substring('code:'.length));
    if (code == null) return null;
    return ShortcutSpec(modifiers: modifiers, keysym: code, isKeycode: true);
  }

  if (key.startsWith('0x')) {
    final raw = int.tryParse(key.substring(2), radix: 16);
    if (raw == null) return null;
    return ShortcutSpec(modifiers: modifiers, keysym: raw);
  }

  var keysym = _keysymForToken(key);
  if (keysym == null) return null;

  if (modifiers & _modifierNames['shift']! != 0) {
    if (keysym >= 0x61 && keysym <= 0x7a) {
      keysym -= 0x20; // 's' -> 'S'
    } else {
      keysym = _usShifted[keysym] ?? keysym;
    }
  }

  return ShortcutSpec(modifiers: modifiers, keysym: keysym);
}
