// Turning a key press into a shortcut the compositor can be asked to register.
//
// The editor in the cheat sheet listens for a press and has to answer, from a
// [LogicalKeyboardKey] and the modifiers held with it, what the user would have
// written in `config.toml`. So that is exactly what this produces: a token plus
// its modifiers, handed to [parseShortcut] — the *same* parser the config file
// goes through — rather than a [ShortcutSpec] built here. A shortcut captured
// from the keyboard and one typed into the file therefore cannot disagree, and
// the shifted-keysym resolution has one implementation rather than two.
//
// No widgets, only `flutter/services` for the key constants, so the whole
// mapping is a plain test.
library;

import 'package:flutter/services.dart';

import 'package:graceful_shell/input_trigger/keysym.dart';

/// The keys that are only ever part of a shortcut, never the whole of one.
///
/// A press of one of these is not an answer — it is the user still on their way
/// to one — so the editor keeps listening rather than binding `Ctrl` to
/// anything. The lock keys are here for a different reason: the protocol fires
/// on an exact modifier set, and Caps Lock is a state rather than something
/// held, so a shortcut naming it would be one that only works half the time.
final Set<LogicalKeyboardKey> kShortcutModifierKeys = {
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.numLock,
  LogicalKeyboardKey.scrollLock,
  LogicalKeyboardKey.fn,
  LogicalKeyboardKey.fnLock,
};

/// Whether [key] is a modifier rather than a key a shortcut can end on.
bool isShortcutModifierKey(LogicalKeyboardKey key) =>
    kShortcutModifierKeys.contains(key);

/// The keys whose token is not the character they produce.
///
/// The named half of `keysym.dart`'s table, addressed by what Flutter calls the
/// key rather than by what xkb does. Anything absent falls through to the
/// key's own label, which is what covers every letter, digit and punctuation
/// key without listing one of them.
final Map<LogicalKeyboardKey, String> _namedTokens = {
  LogicalKeyboardKey.space: 'space',
  LogicalKeyboardKey.enter: 'enter',
  LogicalKeyboardKey.numpadEnter: 'enter',
  LogicalKeyboardKey.tab: 'tab',
  LogicalKeyboardKey.escape: 'escape',
  LogicalKeyboardKey.backspace: 'backspace',
  LogicalKeyboardKey.delete: 'delete',
  LogicalKeyboardKey.insert: 'insert',
  LogicalKeyboardKey.home: 'home',
  LogicalKeyboardKey.end: 'end',
  LogicalKeyboardKey.pageUp: 'pageup',
  LogicalKeyboardKey.pageDown: 'pagedown',
  LogicalKeyboardKey.arrowLeft: 'left',
  LogicalKeyboardKey.arrowRight: 'right',
  LogicalKeyboardKey.arrowUp: 'up',
  LogicalKeyboardKey.arrowDown: 'down',
  LogicalKeyboardKey.printScreen: 'print',
  LogicalKeyboardKey.pause: 'pause',
  LogicalKeyboardKey.contextMenu: 'menu',
  LogicalKeyboardKey.power: 'poweroff',
  LogicalKeyboardKey.sleep: 'sleep',
  // F1 - F24, written out rather than walked from `f1.keyId`: the function keys
  // are contiguous in Flutter's logical plane today, and a table that quietly
  // depends on that would fail as a null-assert at import time if they ever
  // stopped being.
  LogicalKeyboardKey.f1: 'f1',
  LogicalKeyboardKey.f2: 'f2',
  LogicalKeyboardKey.f3: 'f3',
  LogicalKeyboardKey.f4: 'f4',
  LogicalKeyboardKey.f5: 'f5',
  LogicalKeyboardKey.f6: 'f6',
  LogicalKeyboardKey.f7: 'f7',
  LogicalKeyboardKey.f8: 'f8',
  LogicalKeyboardKey.f9: 'f9',
  LogicalKeyboardKey.f10: 'f10',
  LogicalKeyboardKey.f11: 'f11',
  LogicalKeyboardKey.f12: 'f12',
  LogicalKeyboardKey.f13: 'f13',
  LogicalKeyboardKey.f14: 'f14',
  LogicalKeyboardKey.f15: 'f15',
  LogicalKeyboardKey.f16: 'f16',
  LogicalKeyboardKey.f17: 'f17',
  LogicalKeyboardKey.f18: 'f18',
  LogicalKeyboardKey.f19: 'f19',
  LogicalKeyboardKey.f20: 'f20',
  LogicalKeyboardKey.f21: 'f21',
  LogicalKeyboardKey.f22: 'f22',
  LogicalKeyboardKey.f23: 'f23',
  LogicalKeyboardKey.f24: 'f24',
};

/// What [key] is called in a shortcut string, or null when the shell has no
/// spelling for it.
///
/// A key with no spelling is one a shortcut cannot name, and the editor says so
/// rather than binding something the compositor would never fire — the `0x…`
/// and `code:` escape hatches in `config.toml` are for exactly that key, and
/// they stay a thing the user writes by hand deliberately.
String? shortcutTokenForKey(LogicalKeyboardKey key) {
  final named = _namedTokens[key];
  if (named != null) return named;
  return shortcutTokenForCharacter(key.keyLabel);
}

/// The shortcut a press of [key] with the given modifiers describes, or null
/// when the press cannot be one — a modifier on its own, or a key with no
/// spelling.
///
/// Goes out through [parseShortcut] so that what is captured is what a hand
/// written config line would have produced, shift resolution included.
ShortcutSpec? captureShortcut(
  LogicalKeyboardKey key, {
  required bool ctrl,
  required bool alt,
  required bool shift,
  required bool meta,
}) {
  if (isShortcutModifierKey(key)) return null;
  final token = shortcutTokenForKey(key);
  if (token == null) return null;
  return parseShortcut(
    [
      if (ctrl) 'ctrl',
      if (alt) 'alt',
      if (shift) 'shift',
      if (meta) 'super',
      token,
    ].join('+'),
  );
}

/// The same, read off the keyboard's live modifier state.
///
/// [HardwareKeyboard] rather than the event's own `isControlPressed`, because
/// what a shortcut is registered with is the set of modifiers *held at the
/// moment the key went down*, which is what this reports.
ShortcutSpec? captureShortcutFromKeyboard(
  LogicalKeyboardKey key,
  HardwareKeyboard keyboard,
) => captureShortcut(
  key,
  ctrl: keyboard.isControlPressed,
  alt: keyboard.isAltPressed,
  shift: keyboard.isShiftPressed,
  meta: keyboard.isMetaPressed,
);
