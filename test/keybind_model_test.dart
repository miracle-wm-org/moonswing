import 'package:flutter_test/flutter_test.dart';
import 'package:miracle/miracle.dart';

import 'package:graceful_shell/keybinds/keybind_model.dart';

Keybind _bind({
  BuiltInKeyCommand? action,
  String? actionName,
  String? command,
  List<Modifier> modifiers = const [Modifier.meta],
  String key = 'x',
  KeyboardAction? keyboardAction = KeyboardAction.down,
}) => Keybind(
  action: action,
  actionName: actionName ?? action?.wireName,
  command: command,
  keyboardAction: keyboardAction,
  modifiers: KeybindModifiers(
    modifiers: modifiers,
    mask: modifiers.fold(0, (mask, modifier) => mask | modifier.value),
  ),
  configuredModifiers: modifiers,
  xkbKeysym: 0,
  xkbKeysymName: key,
);

KeybindsResult _result(
  List<Keybind> keybinds, {
  List<Modifier> primary = const [Modifier.meta],
}) => KeybindsResult(
  primaryModifier: KeybindModifiers(
    modifiers: primary,
    mask: primary.fold(0, (mask, modifier) => mask | modifier.value),
  ),
  keybinds: keybinds,
);

void main() {
  group('key caps', () {
    test('a single character is that character, upper-cased', () {
      expect(keyCapForKeysym('x'), const KeyCap('X'));
      expect(keyCapForKeysym('1'), const KeyCap('1'));
    });

    test('a named key is what a keyboard prints on it', () {
      expect(keyCapForKeysym('Return').label, 'Enter');
      expect(keyCapForKeysym('Return').glyph, KeyCapGlyph.enter);
      expect(keyCapForKeysym('Escape').label, 'Esc');
      expect(keyCapForKeysym('Prior').label, 'Page Up');
      // The arrows are the one place a picture beats the word.
      expect(keyCapForKeysym('Up').glyph, KeyCapGlyph.up);
      expect(keyCapForKeysym('KP_Left').glyph, KeyCapGlyph.left);
    });

    test('a punctuation keysym is the character it produces', () {
      expect(keyCapForKeysym('bracketleft'), const KeyCap('['));
      expect(keyCapForKeysym('minus'), const KeyCap('-'));
      expect(keyCapForKeysym('slash'), const KeyCap('/'));
    });

    test('a vendor key drops its prefix and splits its words', () {
      expect(keyCapForKeysym('XF86AudioRaiseVolume').label, 'Audio Raise Volume');
    });

    /// The rule the whole table exists to make safe: a keysym nobody has
    /// tabulated still reaches the sheet, under the compositor's own spelling.
    test('an unknown keysym is shown, not dropped', () {
      expect(keyCapForKeysym('Hyper_R'), const KeyCap('Hyper_R'));
      expect(keyCapForKeysym(''), const KeyCap('?'));
    });

    test('a modifier is what the settings UI calls it', () {
      expect(modifierCap(Modifier.meta).label, 'Super');
      expect(modifierCap(Modifier.primary).label, 'Action Key');
    });
  });

  group('rows', () {
    test('a built-in action reads as a sentence, on the keys it resolved to', () {
      final row = rowFor(
        _bind(
          action: BuiltInKeyCommand.quitActiveWindow,
          modifiers: const [Modifier.meta, Modifier.shift],
          key: 'q',
        ),
      )!;
      expect(row.description, 'Close the focused window');
      // Shift before Super, the order a shortcut is conventionally written.
      expect(row.shortcut, 'Shift + Super + Q');
      expect(row.isCommand, isFalse);
      expect(row.detail, isNull);
    });

    test('a shell command is the command, marked as one', () {
      final row = rowFor(_bind(command: '  ptyxis  ', key: 'Return'))!;
      expect(row.description, 'ptyxis');
      expect(row.isCommand, isTrue);
      expect(row.shortcut, 'Super + Enter');
    });

    /// The reason `action` is nullable *and* `actionName` is kept: a miracle
    /// newer than this shell's `package:miracle` must not empty the sheet.
    test('an action this shell has no name for is humanised, not dropped', () {
      final row = rowFor(_bind(actionName: 'summon_the_kraken', key: 'k'))!;
      expect(row.description, 'Summon the kraken');
    });

    test('a binding that does nothing at all has no row', () {
      expect(rowFor(_bind()), isNull);
    });

    test('a binding on key up says so', () {
      final row = rowFor(
        _bind(
          action: BuiltInKeyCommand.fullscreen,
          keyboardAction: KeyboardAction.up,
        ),
      )!;
      expect(row.detail, 'Key up');
    });
  });

  group('grouping', () {
    test('sections come out in order, and empty ones are left out', () {
      final groups = groupKeybinds(
        _result([
          _bind(action: BuiltInKeyCommand.selectWorkspace2, key: '2'),
          _bind(action: BuiltInKeyCommand.quitActiveWindow, key: 'q'),
          _bind(command: 'ptyxis', key: 'Return'),
        ]),
      );
      expect(
        groups.map((group) => group.section),
        [
          KeybindSection.windows,
          KeybindSection.workspaces,
          KeybindSection.commands,
        ],
      );
    });

    /// Sorted by miracle's own numbering, which is what puts the workspaces in
    /// the order they are on the screen rather than 1, 10, 2, 3.
    test('workspaces are numbered, not alphabetical', () {
      final groups = groupKeybinds(
        _result([
          _bind(action: BuiltInKeyCommand.selectWorkspace0, key: '0'),
          _bind(action: BuiltInKeyCommand.selectWorkspace2, key: '2'),
          _bind(action: BuiltInKeyCommand.selectWorkspace1, key: '1'),
        ]),
      );
      expect(
        groups.single.rows.map((row) => row.description),
        ['Go to workspace 1', 'Go to workspace 2', 'Go to workspace 10'],
      );
    });

    /// What a configuration naming both `alt` and `alt_left` produces, and what
    /// a sheet must not print twice.
    test('two bindings that read alike collapse to one row', () {
      final groups = groupKeybinds(
        _result([
          _bind(action: BuiltInKeyCommand.fullscreen, key: 'f'),
          _bind(action: BuiltInKeyCommand.fullscreen, key: 'f'),
        ]),
      );
      expect(groups.single.rows, hasLength(1));
    });

    test('the terminal is a command, not a window action', () {
      expect(
        sectionForCommand(BuiltInKeyCommand.terminal),
        KeybindSection.commands,
      );
      expect(
        sectionForCommand(BuiltInKeyCommand.moveToWorkspace7),
        KeybindSection.workspaces,
      );
      expect(
        sectionForCommand(BuiltInKeyCommand.magnifierOn),
        KeybindSection.magnifier,
      );
    });
  });

  group('the Action Key', () {
    test('resolves to the key it stands in for', () {
      expect(primaryModifierLabel(_result(const [])), 'Super');
    });

    /// Rows carry the *resolved* modifiers, so the sheet answers "what do I
    /// press"; the sentinel is named once in the header instead.
    test('is never a cap on a row', () {
      final row = rowFor(
        _bind(
          action: BuiltInKeyCommand.fullscreen,
          modifiers: const [Modifier.meta],
          key: 'f',
        ),
      )!;
      expect(row.shortcut, 'Super + F');
    });

    test('says nothing when miracle names a modifier this shell cannot', () {
      expect(primaryModifierLabel(_result(const [], primary: const [])), isNull);
    });
  });

  group('column balancing', () {
    test('keeps a section whole and evens the columns out', () {
      final groups = [
        KeybindGroup(
          section: KeybindSection.windows,
          rows: List.generate(
            8,
            (i) => KeybindRow(description: 'w$i', caps: const [KeyCap('A')]),
          ),
        ),
        KeybindGroup(
          section: KeybindSection.layout,
          rows: List.generate(
            4,
            (i) => KeybindRow(description: 'l$i', caps: const [KeyCap('A')]),
          ),
        ),
        KeybindGroup(
          section: KeybindSection.session,
          rows: List.generate(
            3,
            (i) => KeybindRow(description: 's$i', caps: const [KeyCap('A')]),
          ),
        ),
      ];
      final columns = balanceGroups(groups);
      expect(columns, hasLength(2));
      // The tallest section heads the left column, where reading starts, and
      // the two shorter ones balance it on the right.
      expect(columns.first.map((group) => group.section), [
        KeybindSection.windows,
      ]);
      expect(columns.last.map((group) => group.section), [
        KeybindSection.layout,
        KeybindSection.session,
      ]);
    });

    test('one column is the list itself', () {
      final groups = [
        const KeybindGroup(section: KeybindSection.windows, rows: []),
      ];
      expect(balanceGroups(groups, columns: 1).single, hasLength(1));
    });
  });

  /// The wire shape, decoded by `package:miracle` and read by this file: the
  /// one place the two meet, and the one that a miracle release can move.
  test('decodes a GET_KEYBINDS reply end to end', () {
    final result = KeybindsResult.fromJson({
      'primary_modifier': {
        'modifiers': ['meta'],
        'modifier_mask': 4096,
      },
      'keybinds': [
        {
          'action': 'quit_active_window',
          'command': null,
          'keyboard_action': 'down',
          'modifiers': ['meta', 'shift'],
          'modifier_mask': 4112,
          'configured_modifiers': ['primary', 'shift'],
          'xkb_keysym': 113,
          'xkb_keysym_name': 'q',
        },
      ],
    });
    final groups = groupKeybinds(result);
    expect(primaryModifierLabel(result), 'Super');
    expect(groups.single.section, KeybindSection.windows);
    expect(groups.single.rows.single.description, 'Close the focused window');
    expect(groups.single.rows.single.shortcut, 'Shift + Super + Q');
  });
}
