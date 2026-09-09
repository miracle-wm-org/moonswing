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

/// The modifier bits, named. Public because a shortcut is also *built* — by the
/// cheat sheet's editor, from a key press — and not only parsed; a bitfield
/// spelled `0x800` at a call site is the kind of literal this file exists to
/// keep in one place.
const int kShortcutModAlt = 0x01;
const int kShortcutModShift = 0x08;
const int kShortcutModCtrl = 0x100;
const int kShortcutModSuper = 0x800;

/// Modifier bits, keyed by the names accepted in a shortcut string.
///
/// Only the *generic* bits are offered: the protocol fires a trigger when exactly
/// the registered modifier set is held, so registering `ctrl_left` would mean the
/// shortcut stops working on the right-hand Control key.
const Map<String, int> _modifierNames = {
  'ctrl': kShortcutModCtrl,
  'control': kShortcutModCtrl,
  'shift': kShortcutModShift,
  'alt': kShortcutModAlt,
  'meta': kShortcutModSuper,
  'super': kShortcutModSuper,
  'win': kShortcutModSuper,
  'logo': kShortcutModSuper,
};

/// The modifier bits in the order a shortcut is *written* — Ctrl, Alt, Shift,
/// Super — each with the spelling [formatShortcut] writes.
///
/// The same order `miracle_labels.dart` sorts the compositor's own modifiers
/// into, because both are read off the same cheat sheet.
const List<(int, String)> kShortcutModifiersInWrittenOrder = [
  (kShortcutModCtrl, 'ctrl'),
  (kShortcutModAlt, 'alt'),
  (kShortcutModShift, 'shift'),
  (kShortcutModSuper, 'super'),
];

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
  // The machine's own power button. To the compositor it is an ordinary key —
  // evdev `KEY_POWER` (116), which every standard xkb layout maps to
  // `XF86PowerOff` — which is what lets the shell bind it like any other
  // shortcut. What is *not* ordinary is that systemd-logind watches the same
  // device and powers the machine off on a press, so binding this without also
  // taking logind's `handle-power-key` inhibitor draws a menu onto a machine
  // that is already going down.
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
/// key. Mir matches on the *resolved* keysym, so `"ctrl+shift+1"` registers `!`.
///
/// Explicitly US-only: on other layouts Shift+2 is not `@`, and there is no way
/// to know the user's layout from here. `CONFIG.md` documents the `0x…` and
/// `code:` escape hatches.
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

/// Parses a shortcut string such as `"ctrl+shift+s"` or `"super+d"` into the pair
/// the compositor is asked to register.
///
/// Returns null when the shortcut is disabled (`""` or `"none"`) or cannot be
/// understood; callers decide whether that means "fall back to the default" or
/// "register nothing".
///
/// Accepted forms for the key:
///  * a single letter or digit, a named key (`space`, `f5`, `pageup`, …), or a
///    punctuation name (`comma`, `slash`, …);
///  * `0x41` — a raw keysym, for layouts this table does not cover;
///  * `code:57` — a raw evdev keycode, which is layout-independent.
///
/// Shift must be spelled out: `"ctrl+S"` reads as `"ctrl+s"`. When shift *is*
/// present the keysym is shift-resolved, because that is what Mir matches on.
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

/// The canonical spellings for one named keysym: the token [formatShortcut]
/// writes into `config.toml`, and the xkb name a key cap is drawn from.
///
/// Both, because the two vocabularies differ and only one table should have to
/// know it: this file's own parser calls the Escape key `escape`, while the
/// compositor — and so `keybind_model.dart`, which draws the caps for *its*
/// bindings — calls it `Escape`. A shell shortcut drawn beside a compositor one
/// has to arrive as the same kind of name, or the two would read as two
/// different keyboards.
///
/// Only keysyms with a name are here. Everything printable is its own
/// character, and everything else falls back to the `0x…` form the parser
/// already accepts.
const Map<int, ({String token, String xkb})> _namedKeysymSpellings = {
  0x0020: (token: 'space', xkb: 'space'),
  0xff0d: (token: 'enter', xkb: 'Return'),
  0xff09: (token: 'tab', xkb: 'Tab'),
  0xff1b: (token: 'escape', xkb: 'Escape'),
  0xff08: (token: 'backspace', xkb: 'BackSpace'),
  0xffff: (token: 'delete', xkb: 'Delete'),
  0xff63: (token: 'insert', xkb: 'Insert'),
  0xff50: (token: 'home', xkb: 'Home'),
  0xff57: (token: 'end', xkb: 'End'),
  0xff55: (token: 'pageup', xkb: 'Prior'),
  0xff56: (token: 'pagedown', xkb: 'Next'),
  0xff51: (token: 'left', xkb: 'Left'),
  0xff52: (token: 'up', xkb: 'Up'),
  0xff53: (token: 'right', xkb: 'Right'),
  0xff54: (token: 'down', xkb: 'Down'),
  0xff61: (token: 'print', xkb: 'Print'),
  0xff13: (token: 'pause', xkb: 'Pause'),
  0xff67: (token: 'menu', xkb: 'Menu'),
  0x1008ff2a: (token: 'poweroff', xkb: 'XF86PowerOff'),
  0x1008ff2f: (token: 'sleep', xkb: 'XF86Sleep'),
};

/// The punctuation names, keyed by the keysym rather than the spelling.
///
/// Derived from [_punctuationKeysyms] rather than written out again: two hand
/// written tables that must agree are two tables that will not.
final Map<int, String> _punctuationNames = {
  for (final entry in _punctuationKeysyms.entries) entry.value: entry.key,
};

/// F1 - F24, which are contiguous from `XKB_KEY_F1`.
const int _firstFunctionKeysym = 0xffbe;
const int _lastFunctionKeysym = _firstFunctionKeysym + 23;

/// [keysym] as the shell would write it in a shortcut string, or null when
/// there is no spelling for it — the caller then falls back to `0x…`.
String? _tokenForKeysym(int keysym) {
  final named = _namedKeysymSpellings[keysym];
  if (named != null) return named.token;
  if (keysym >= _firstFunctionKeysym && keysym <= _lastFunctionKeysym) {
    return 'f${keysym - _firstFunctionKeysym + 1}';
  }
  final punctuation = _punctuationNames[keysym];
  if (punctuation != null) return punctuation;
  // a-z and 0-9 are their own ASCII keysyms, and the parser reads them back as
  // themselves. Anything else printable is a *shifted* character the parser
  // only reaches through [_usShifted], so [formatShortcut] un-shifts first.
  if ((keysym >= 0x61 && keysym <= 0x7a) || (keysym >= 0x30 && keysym <= 0x39)) {
    return String.fromCharCode(keysym);
  }
  return null;
}

/// The xkb keysym *name* for [keysym] — the vocabulary the compositor reports
/// its own bindings in — or null when this file has no name for it.
///
/// The bridge that lets a shell shortcut be drawn by the same key-cap table as
/// a compositor binding: `0xff1b` comes back as `Escape`, which is exactly what
/// miracle would have said.
String? xkbKeysymName(int keysym) {
  final named = _namedKeysymSpellings[keysym];
  if (named != null) return named.xkb;
  if (keysym >= _firstFunctionKeysym && keysym <= _lastFunctionKeysym) {
    return 'F${keysym - _firstFunctionKeysym + 1}';
  }
  // Every other printable ASCII keysym *is* its character, `S` and `!` and `[`
  // alike — which is both the xkb name for the ones that have one and a cap a
  // person can read for the ones that do not.
  if (keysym > 0x20 && keysym < 0x7f) return String.fromCharCode(keysym);
  return null;
}

/// The keysym a shifted [keysym] was written from — `S` back to `s`, `!` back
/// to `1` — or [keysym] itself when Shift did not move it.
///
/// [parseShortcut] resolves the shift as it parses, because that is what Mir
/// matches on; writing a spec back out has to undo exactly that, or every
/// shifted shortcut would come back as an unparseable `ctrl+shift+S`.
int _unshiftKeysym(int keysym) {
  if (keysym >= 0x41 && keysym <= 0x5a) return keysym + 0x20; // 'S' -> 's'
  for (final entry in _usShifted.entries) {
    if (entry.value == keysym) return entry.key;
  }
  return keysym;
}

/// [spec] as a shortcut string [parseShortcut] reads back as [spec].
///
/// The other half of the parser, and the reason an editor can exist at all: a
/// shortcut captured from a key press is stored as the text a hand-written
/// `config.toml` would have held, so the file stays something a person can
/// still read and edit.
///
/// `test/shortcut_parse_test.dart` pins the round trip.
String formatShortcut(ShortcutSpec spec) {
  final parts = <String>[
    for (final (bit, name) in kShortcutModifiersInWrittenOrder)
      if (spec.modifiers & bit != 0) name,
  ];
  if (spec.isKeycode) {
    parts.add('code:${spec.keysym}');
    return parts.join('+');
  }
  final shifted = spec.modifiers & kShortcutModShift != 0;
  final keysym = shifted ? _unshiftKeysym(spec.keysym) : spec.keysym;
  parts.add(_tokenForKeysym(keysym) ?? '0x${keysym.toRadixString(16)}');
  return parts.join('+');
}

/// The token [parseShortcut] accepts for the character [character] produces, or
/// null when there is no way to write it.
///
/// The entry point for a shortcut *captured from a key press* rather than read
/// out of the config file: the editor knows only what the key is labelled, and
/// this is what turns that label back into the vocabulary of a shortcut string.
///
/// Case is dropped and the shift is undone — `S` is the `s` key and `!` is the
/// `1` key — because Shift is a modifier the caller reports separately, and
/// spelling it twice is how a shortcut string stops parsing.
String? shortcutTokenForCharacter(String character) {
  if (character.length != 1) return null;
  var code = character.codeUnitAt(0);
  if (code >= 0x41 && code <= 0x5a) code += 0x20; // 'S' -> 's'
  code = _unshiftKeysym(code);
  return _tokenForKeysym(code);
}
