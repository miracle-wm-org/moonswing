// What a keybinding *reads* as: the caps a person presses, and the section of
// the cheat sheet the binding belongs in.
//
// `package:miracle` reports a binding the way the compositor holds it — an xkb
// keysym name, a modifier list, and either a built-in command's wire name or a
// shell command. None of those is what goes on a key cap: `Return` is Enter,
// `bracketleft` is `[`, `meta` is Super, and `move_to_workspace_3` is a sentence.
//
// Deliberately Flutter-free, like `miracle_config/miracle_labels.dart` — which
// this leans on for the modifier and command names — so the grouping, the
// ordering and every cap label are a plain unit test rather than a widget one.
// A glyph is *named* ([KeyCapGlyph]) rather than drawn, which is the whole
// reason the file can stay that way; the overlay picks the icon.
library;

import 'package:miracle/miracle.dart';

import 'package:moonswing/miracle_config/miracle_labels.dart';

/// A picture a key cap can carry instead of its [KeyCap.label].
///
/// Only the keys whose picture is *clearer* than their name are here: an arrow
/// key is an arrow, Enter is the turning arrow every keyboard prints on it, and
/// Backspace is the arrow with the cross. Everything else — Tab, Esc, Super —
/// reads better as the word, so it has no glyph and is drawn as text.
enum KeyCapGlyph { up, down, left, right, enter, backspace }

/// One cap in a shortcut: `Ctrl`, `Shift`, `A`.
///
/// [label] is always the honest text — the fallback when the glyph cannot be
/// drawn, and what a test asserts on.
class KeyCap {
  const KeyCap(this.label, {this.glyph});

  /// What the cap says, e.g. `Super`, `A`, `Enter`.
  final String label;

  /// The picture to draw instead of [label], where one is clearer.
  final KeyCapGlyph? glyph;

  @override
  bool operator ==(Object other) =>
      other is KeyCap && other.label == label && other.glyph == glyph;

  @override
  int get hashCode => Object.hash(label, glyph);

  @override
  String toString() => 'KeyCap($label${glyph == null ? '' : ', $glyph'})';
}

/// The X11 keysym names that are not the character they produce.
///
/// Only the ones a binding realistically names; anything missing falls through
/// to [keyCapForKeysym]'s other rules and, ultimately, to the keysym name
/// itself — a binding is never dropped for being spelled unusually.
const Map<String, KeyCap> _namedCaps = {
  'Return': KeyCap('Enter', glyph: KeyCapGlyph.enter),
  'KP_Enter': KeyCap('Enter', glyph: KeyCapGlyph.enter),
  'space': KeyCap('Space'),
  'Tab': KeyCap('Tab'),
  'ISO_Left_Tab': KeyCap('Tab'),
  'Escape': KeyCap('Esc'),
  'BackSpace': KeyCap('Backspace', glyph: KeyCapGlyph.backspace),
  'Delete': KeyCap('Del'),
  'Insert': KeyCap('Ins'),
  'Home': KeyCap('Home'),
  'End': KeyCap('End'),
  'Prior': KeyCap('Page Up'),
  'Next': KeyCap('Page Down'),
  'Up': KeyCap('Up', glyph: KeyCapGlyph.up),
  'Down': KeyCap('Down', glyph: KeyCapGlyph.down),
  'Left': KeyCap('Left', glyph: KeyCapGlyph.left),
  'Right': KeyCap('Right', glyph: KeyCapGlyph.right),
  'KP_Up': KeyCap('Up', glyph: KeyCapGlyph.up),
  'KP_Down': KeyCap('Down', glyph: KeyCapGlyph.down),
  'KP_Left': KeyCap('Left', glyph: KeyCapGlyph.left),
  'KP_Right': KeyCap('Right', glyph: KeyCapGlyph.right),
  'Print': KeyCap('Print'),
  'Pause': KeyCap('Pause'),
  'Menu': KeyCap('Menu'),
};

/// The X11 name for a character that cannot be spelled as itself.
const Map<String, String> _punctuationCaps = {
  'exclam': '!',
  'quotedbl': '"',
  'numbersign': '#',
  'dollar': r'$',
  'percent': '%',
  'ampersand': '&',
  'apostrophe': "'",
  'parenleft': '(',
  'parenright': ')',
  'asterisk': '*',
  'plus': '+',
  'comma': ',',
  'minus': '-',
  'period': '.',
  'slash': '/',
  'colon': ':',
  'semicolon': ';',
  'less': '<',
  'equal': '=',
  'greater': '>',
  'question': '?',
  'at': '@',
  'bracketleft': '[',
  'backslash': r'\',
  'bracketright': ']',
  'asciicircum': '^',
  'underscore': '_',
  'grave': '`',
  'braceleft': '{',
  'bar': '|',
  'braceright': '}',
  'asciitilde': '~',
};

/// The cap for the key miracle reported as [name], an xkb keysym name.
///
/// Unknown names are shown, never hidden: a key this table has never heard of
/// still has its binding on the sheet, under the compositor's own spelling.
KeyCap keyCapForKeysym(String name) {
  if (name.isEmpty) return const KeyCap('?');
  final named = _namedCaps[name];
  if (named != null) return named;
  final punctuation = _punctuationCaps[name];
  if (punctuation != null) return KeyCap(punctuation);
  // A single character is the character: `x` is the X key, `1` is the 1 key.
  if (name.length == 1) return KeyCap(name.toUpperCase());
  // `XF86AudioRaiseVolume` is a key a keyboard prints a picture on; the vendor
  // prefix is noise and the words after it are the name.
  if (name.startsWith('XF86')) {
    return KeyCap(_splitCamelCase(name.substring(4)));
  }
  if (name.startsWith('KP_')) return KeyCap('Numpad ${name.substring(3)}');
  return KeyCap(name);
}

/// `AudioRaiseVolume` as `Audio Raise Volume`.
String _splitCamelCase(String value) {
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    // A boundary is a capital that follows something that is not one — so
    // `AudioRaiseVolume` splits three ways and `XY` does not split at all.
    final isUpper = char.toUpperCase() == char && char.toLowerCase() != char;
    if (i > 0 && isUpper && value[i - 1] == value[i - 1].toLowerCase()) {
      buffer.write(' ');
    }
    buffer.write(char);
  }
  final split = buffer.toString();
  return split.isEmpty ? value : split;
}

/// The cap for one modifier — [modifierLabel], which already calls `meta`
/// Super and `primary` the Action Key.
KeyCap modifierCap(Modifier modifier) => KeyCap(modifierLabel(modifier));

/// A part of the cheat sheet.
///
/// Sections rather than one flat list because a configuration runs to fifty-odd
/// bindings, and the questions people bring to a cheat sheet are grouped ones:
/// "how do I move a window", "how do I get to workspace 4".
enum KeybindSection {
  windows('Windows'),
  layout('Layout'),
  workspaces('Workspaces'),
  magnifier('Magnifier'),
  session('Session'),
  commands('Applications & commands'),
  other('Other');

  const KeybindSection(this.label);

  /// The heading this section is drawn under.
  final String label;
}

/// Which section [command] belongs in.
KeybindSection sectionForCommand(BuiltInKeyCommand command) =>
    switch (command) {
      BuiltInKeyCommand.terminal => KeybindSection.commands,
      BuiltInKeyCommand.moveUp ||
      BuiltInKeyCommand.moveDown ||
      BuiltInKeyCommand.moveLeft ||
      BuiltInKeyCommand.moveRight ||
      BuiltInKeyCommand.selectUp ||
      BuiltInKeyCommand.selectDown ||
      BuiltInKeyCommand.selectLeft ||
      BuiltInKeyCommand.selectRight ||
      BuiltInKeyCommand.quitActiveWindow ||
      BuiltInKeyCommand.fullscreen ||
      BuiltInKeyCommand.toggleFloating ||
      BuiltInKeyCommand.togglePinnedToWorkspace ||
      BuiltInKeyCommand.toggleResize ||
      BuiltInKeyCommand.resizeUp ||
      BuiltInKeyCommand.resizeDown ||
      BuiltInKeyCommand.resizeLeft ||
      BuiltInKeyCommand.resizeRight => KeybindSection.windows,
      BuiltInKeyCommand.requestVerticalLayout ||
      BuiltInKeyCommand.requestHorizontalLayout ||
      BuiltInKeyCommand.toggleTabbing ||
      BuiltInKeyCommand.toggleStacking => KeybindSection.layout,
      BuiltInKeyCommand.magnifierOn ||
      BuiltInKeyCommand.magnifierOff ||
      BuiltInKeyCommand.magnifierIncreaseSize ||
      BuiltInKeyCommand.magnifierDecreaseSize ||
      BuiltInKeyCommand.magnifierIncreaseScale ||
      BuiltInKeyCommand.magnifierDecreaseScale => KeybindSection.magnifier,
      BuiltInKeyCommand.quitCompositor ||
      BuiltInKeyCommand.reloadConfig => KeybindSection.session,
      // Everything that is left is `select_workspace_*` / `move_to_workspace_*`.
      _ => KeybindSection.workspaces,
    };

/// One line of the cheat sheet: what it does, and what to press.
class KeybindRow {
  const KeybindRow({
    required this.description,
    required this.caps,
    this.detail,
    this.isCommand = false,
  });

  /// What the binding does, in a person's words.
  final String description;

  /// The caps to press, in the order they are written.
  final List<KeyCap> caps;

  /// A qualifier the row would be wrong without — today, a binding that fires
  /// on key *up* or on repeat rather than on the press.
  final String? detail;

  /// Whether [description] is a shell command rather than a sentence, so the
  /// sheet can set it in the monospace it was typed in.
  final bool isCommand;

  /// The shortcut as one string, e.g. `Super + Shift + R`. What a test reads,
  /// and the honest text behind a row of drawn caps.
  String get shortcut => caps.map((cap) => cap.label).join(' + ');
}

/// One section of the cheat sheet, with at least one row.
class KeybindGroup {
  const KeybindGroup({required this.section, required this.rows});

  final KeybindSection section;
  final List<KeybindRow> rows;
}

/// The caps for [keybind], in the order a shortcut is written.
///
/// The **resolved** modifiers, not the configured ones: the sheet answers "what
/// do I press", and `Modifier.primary` is not a key. Which key it resolved to is
/// said once, in the sheet's header, rather than fifty times down its rows.
List<KeyCap> capsFor(Keybind keybind) => [
  for (final modifier in sortModifiers(keybind.modifiers.modifiers))
    modifierCap(modifier),
  keyCapForKeysym(keybind.xkbKeysymName),
];

/// [keybind] as a row, or null when there is nothing to say it does.
///
/// A binding with neither an action nor a command is miracle reporting
/// something this shell has no name for at all, and a row reading
/// "Super + K does nothing" is worse than no row.
KeybindRow? rowFor(Keybind keybind) {
  final action = keybind.action;
  final command = keybind.command;
  final String description;
  var isCommand = false;
  if (action != null) {
    description = builtInCommandLabel(action);
  } else if (command != null && command.trim().isNotEmpty) {
    description = command.trim();
    isCommand = true;
  } else if (keybind.actionName case final name? when name.isNotEmpty) {
    // An action newer than this shell's copy of `package:miracle`. Its wire
    // name humanised is still a better answer than dropping the row.
    description = _humaniseWireName(name);
  } else {
    return null;
  }

  final keyboardAction = keybind.keyboardAction;
  return KeybindRow(
    description: description,
    caps: capsFor(keybind),
    detail: keyboardAction == null || keyboardAction == KeyboardAction.down
        ? null
        : keyboardActionLabel(keyboardAction),
    isCommand: isCommand,
  );
}

/// `move_to_workspace_3` as `Move to workspace 3`.
String _humaniseWireName(String name) {
  final words = name.split('_').where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return name;
  return [
    words.first[0].toUpperCase() + words.first.substring(1),
    ...words.skip(1),
  ].join(' ');
}

/// [result]'s bindings as the sections the cheat sheet draws, in
/// [KeybindSection]'s own order, with empty sections left out.
///
/// Rows are ordered by the built-in command's own value — which is how miracle
/// numbers them, so the workspaces come out 1..10 rather than alphabetically —
/// and shell commands after them, alphabetically. Identical rows collapse: two
/// bindings that do the same thing on the same keys are one line, which is what
/// a configuration naming both `alt` and `alt_left` produces.
List<KeybindGroup> groupKeybinds(KeybindsResult result) {
  final rows = <KeybindSection, List<(int, KeybindRow)>>{};
  for (final keybind in result.keybinds) {
    final row = rowFor(keybind);
    if (row == null) continue;
    final action = keybind.action;
    final section = action != null
        ? sectionForCommand(action)
        : (keybind.command != null
              ? KeybindSection.commands
              : KeybindSection.other);
    // Anything without a built-in command sorts after every one that has one,
    // and among its own kind by description.
    rows.putIfAbsent(section, () => []).add((action?.value ?? 1 << 20, row));
  }

  final groups = <KeybindGroup>[];
  for (final section in KeybindSection.values) {
    final entries = rows[section];
    if (entries == null || entries.isEmpty) continue;
    entries.sort((a, b) {
      final byValue = a.$1.compareTo(b.$1);
      if (byValue != 0) return byValue;
      return a.$2.description.toLowerCase().compareTo(
        b.$2.description.toLowerCase(),
      );
    });
    final seen = <String>{};
    final unique = <KeybindRow>[];
    for (final (_, row) in entries) {
      if (seen.add('${row.description} ${row.shortcut}')) unique.add(row);
    }
    groups.add(KeybindGroup(section: section, rows: unique));
  }
  return groups;
}

/// [groups] dealt into [columns] columns of roughly equal height.
///
/// Here rather than in the sheet's `build` because it is arithmetic, and the
/// arithmetic is the part that is easy to get wrong: a cheat sheet laid out by
/// splitting the list in half puts one nine-row section beside four one-row
/// ones. A section is never split across columns — a heading with two of its
/// rows under it and the rest in the next column reads as two sections.
///
/// Weight is rows plus two, the heading and the gap after it, so a column of
/// small sections is not counted as cheap as its row count suggests. Ties go to
/// the leftmost column, which keeps the first (and usually largest) section at
/// the top left where reading starts.
List<List<KeybindGroup>> balanceGroups(
  List<KeybindGroup> groups, {
  int columns = 2,
}) {
  if (columns <= 1) return [List<KeybindGroup>.of(groups)];
  final buckets = List.generate(columns, (_) => <KeybindGroup>[]);
  final weights = List<int>.filled(columns, 0);
  for (final group in groups) {
    var best = 0;
    for (var i = 1; i < columns; i++) {
      if (weights[i] < weights[best]) best = i;
    }
    buckets[best].add(group);
    weights[best] += group.rows.length + 2;
  }
  return buckets;
}

/// What the Action Key resolves to on this machine, e.g. `Super`.
///
/// Null when miracle reported a modifier this shell cannot name — the header
/// then says nothing rather than guessing, and every row still carries the real
/// caps.
String? primaryModifierLabel(KeybindsResult result) {
  final modifiers = result.primaryModifier.modifiers
      .where((modifier) => modifier != Modifier.primary)
      .toList();
  if (modifiers.isEmpty) return null;
  return sortModifiers(modifiers).map(modifierLabel).join(' + ');
}
