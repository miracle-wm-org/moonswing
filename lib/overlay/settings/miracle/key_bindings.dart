// Window Manager > Key Bindings: the shortcuts that run shell commands, and the
// rebindings of miracle's own commands.
//
// Both lists are the same four fields — modifiers, key, when it fires, and what
// it does — so both are built from one card. Only the last field differs: a
// custom binding runs a string, an override picks one of miracle's fifty
// built-in commands.
//
// The key is an xkb keysym, which is why `miracle_key_codes.dart` exists: a
// binding is stored as the number 0x1008ff13 and has to be edited as "Volume
// up" — or found by typing the `XF86AudioRaiseVolume` its config spells.

import 'package:flutter/widgets.dart';

import 'package:miracle/miracle.dart';

import 'package:moonswing/miracle_config/miracle_config_store.dart';
import 'package:moonswing/miracle_config/miracle_key_codes.dart';
import 'package:moonswing/miracle_config/miracle_labels.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/miracle/miracle_controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The key a new binding starts on.
///
/// `A` rather than nothing: every field of a binding has to hold *something* —
/// the C struct has no "unset" — and a key nobody meant is easier to notice and
/// change than a code of 0, which no keyboard produces and which reads as a
/// binding that simply does not work.
const int _kNewBindingKey = 0x61; // XKB_KEY_a

/// The dropdown items for the whole keysym table, built once.
///
/// Seven hundred rows, each carrying its xkb name as the detail so the filter
/// can match either spelling — "volume" or `XF86AudioRaiseVolume`. Lazy, like every other table in this
/// shell: a user who never opens this page builds none of it.
final List<SettingsDropdownItem<int>> _keyItems = [
  for (final key in kMiracleKeys)
    SettingsDropdownItem(value: key.keysym, label: key.label, detail: key.name),
];

/// [_keyItems], plus a row for [keysym] when the table does not carry it.
///
/// A binding authored against a key this table has never heard of would
/// otherwise show "—" in its own picker; with the row it shows what it is and
/// can be put back after a look at the alternatives.
List<SettingsDropdownItem<int>> _keyItemsWith(int keysym) {
  if (miracleKeyForKeysym(keysym) != null) return _keyItems;
  return [
    ..._keyItems,
    SettingsDropdownItem(value: keysym, label: miracleKeyLabel(keysym)),
  ];
}

final List<SettingsDropdownItem<KeyboardAction>> _actionItems = [
  for (final action in KeyboardAction.values)
    SettingsDropdownItem(value: action, label: keyboardActionLabel(action)),
];

final List<SettingsDropdownItem<BuiltInKeyCommand>> _builtInItems = [
  for (final command in BuiltInKeyCommand.values)
    SettingsDropdownItem(
      value: command,
      label: builtInCommandLabel(command),
      detail: command.wireName,
    ),
];

class MiracleKeyBindingsSection extends StatelessWidget {
  const MiracleKeyBindingsSection({super.key, required this.store});

  final MiracleConfigStore store;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverSettingsSection(
          label: 'Custom key bindings',
          info:
              'Each of these runs a shell command. The Action Key stands for '
              'whatever you set it to under General, so a binding written '
              'against it follows that setting.',
          children: [
            MiracleCollection(
              store: store,
              signature: _customSignature,
              builder: (context, config) {
                final commands = config.customKeyCommands;
                return SettingsList(
                  itemCount: commands.length,
                  // The cards are pickers and a field; only the grip drags.
                  handleOnly: true,
                  // Keyed on the store's structure revision as well as the
                  // position: see `MiracleConfigStore.editStructure` for what
                  // the field on a card would otherwise show after the row
                  // above it is deleted.
                  itemKey: (i) =>
                      ValueKey('custom:${store.structureRevision}:$i'),
                  emptyText: 'No custom bindings yet.',
                  onReorder: (from, to) => store.editStructure(
                    (config) =>
                        reorderInPlace(config.customKeyCommands, from, to),
                  ),
                  onRemove: (i) => store.editStructure(
                    (config) => config.customKeyCommands.removeAt(i),
                  ),
                  itemBuilder: (context, i) => _customCard(context, config, i),
                  adder: SettingsListAddRow(
                    label: 'Add binding',
                    onTap: () => store.editStructure(
                      (config) => config.customKeyCommands.add(
                        const CustomKeyCommand(
                          key: _kNewBindingKey,
                          command: '',
                          modifiers: {Modifier.primary},
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        SliverSettingsSection(
          label: 'Built-in command overrides',
          fillLast: true,
          info:
              "Each of these replaces the default binding for one of miracle's "
              'own commands. A command with no override here keeps whatever '
              'miracle ships with.',
          children: [
            MiracleCollection(
              store: store,
              signature: _overrideSignature,
              builder: (context, config) {
                final overrides = config.builtInKeyCommandOverrides;
                return SettingsList(
                  itemCount: overrides.length,
                  handleOnly: true,
                  itemKey: (i) =>
                      ValueKey('override:${store.structureRevision}:$i'),
                  emptyText:
                      'No overrides yet — every built-in command is on its '
                      'default binding.',
                  onReorder: (from, to) => store.editStructure(
                    (config) => reorderInPlace(
                      config.builtInKeyCommandOverrides,
                      from,
                      to,
                    ),
                  ),
                  onRemove: (i) => store.editStructure(
                    (config) => config.builtInKeyCommandOverrides.removeAt(i),
                  ),
                  itemBuilder: (context, i) =>
                      _overrideCard(context, config, i),
                  adder: SettingsListAddRow(
                    label: 'Add override',
                    onTap: () => store.editStructure(
                      (config) => config.builtInKeyCommandOverrides.add(
                        const KeyCommandOverride(
                          key: _kNewBindingKey,
                          command: BuiltInKeyCommand.terminal,
                          modifiers: {Modifier.primary},
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _customCard(BuildContext context, MiracleConfig config, int index) {
    final binding = config.customKeyCommands[index];
    return _BindingCard(
      shortcut: describeShortcut(
        binding.modifiers,
        miracleKeyLabel(binding.key),
      ),
      modifiers: binding.modifiers,
      keysym: binding.key,
      action: binding.action,
      onModifiers: (next) =>
          _editCustom(index, (binding) => binding.copyWith(modifiers: next)),
      onKey: (next) =>
          _editCustom(index, (binding) => binding.copyWith(key: next)),
      onAction: (next) =>
          _editCustom(index, (binding) => binding.copyWith(action: next)),
      target: _LabelledControl(
        label: 'Runs',
        child: SettingsCommitField(
          initial: binding.command,
          hint: 'e.g. firefox',
          onCommitted: (text) =>
              _editCustom(index, (binding) => binding.copyWith(command: text)),
        ),
      ),
    );
  }

  Widget _overrideCard(BuildContext context, MiracleConfig config, int index) {
    final override = config.builtInKeyCommandOverrides[index];
    return _BindingCard(
      shortcut: describeShortcut(
        override.modifiers,
        miracleKeyLabel(override.key),
      ),
      modifiers: override.modifiers,
      keysym: override.key,
      action: override.action,
      onModifiers: (next) => _editOverride(
        index,
        (override) => override.copyWith(modifiers: next),
      ),
      onKey: (next) =>
          _editOverride(index, (override) => override.copyWith(key: next)),
      onAction: (next) =>
          _editOverride(index, (override) => override.copyWith(action: next)),
      target: _LabelledControl(
        label: 'Runs',
        child: SettingsDropdown<BuiltInKeyCommand>(
          items: _builtInItems,
          selected: override.command,
          onSelected: (next) => _editOverride(
            index,
            (override) => override.copyWith(command: next),
          ),
        ),
      ),
    );
  }

  void _editCustom(
    int index,
    CustomKeyCommand Function(CustomKeyCommand binding) update,
  ) => store.edit((config) {
    final commands = config.customKeyCommands;
    if (index >= commands.length) return;
    commands[index] = update(commands[index]);
  });

  void _editOverride(
    int index,
    KeyCommandOverride Function(KeyCommandOverride override) update,
  ) => store.edit((config) {
    final overrides = config.builtInKeyCommandOverrides;
    if (index >= overrides.length) return;
    overrides[index] = update(overrides[index]);
  });
}

/// One binding, whatever it runs.
///
/// The shortcut is spelled out along the top — `Action Key + Shift + R` — which
/// is the one line somebody scanning the list is actually reading. The controls
/// under it are the same four for both lists.
class _BindingCard extends StatelessWidget {
  const _BindingCard({
    required this.shortcut,
    required this.modifiers,
    required this.keysym,
    required this.action,
    required this.target,
    required this.onModifiers,
    required this.onKey,
    required this.onAction,
  });

  final String shortcut;
  final Set<Modifier> modifiers;
  final int keysym;
  final KeyboardAction action;

  /// What the binding does — a command field, or a built-in command picker.
  final Widget target;

  final ValueChanged<Set<Modifier>> onModifiers;
  final ValueChanged<int> onKey;
  final ValueChanged<KeyboardAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          shortcut,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: ShellFontSizes.body,
            fontFamily: theme.fontFamily,
            fontWeight: FontWeight.w600,
            color: theme.popupForeground,
          ),
        ),
        const SizedBox(height: 8),
        // What it does, then which key and when, on one line: the three
        // fields somebody edits together, and a card a line shorter.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: target),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _LabelledControl(
                label: 'Key',
                child: SettingsDropdown<int>(
                  items: _keyItemsWith(keysym),
                  selected: keysym,
                  onSelected: onKey,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _LabelledControl(
                label: 'Fires on',
                child: SettingsDropdown<KeyboardAction>(
                  items: _actionItems,
                  selected: action,
                  onSelected: onAction,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _LabelledControl(
          label: 'Held with',
          child: SettingsChipToggles<Modifier>(
            options: kModifiersInDisplayOrder,
            selected: modifiers,
            labelOf: modifierLabel,
            alignment: WrapAlignment.start,
            onChanged: onModifiers,
          ),
        ),
      ],
    );
  }
}

/// A caption over a control, for the inside of a card where there is no
/// [SettingsRow] to put a label on the left of.
class _LabelledControl extends StatelessWidget {
  const _LabelledControl({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: ShellFontSizes.caption,
            fontFamily: theme.fontFamily,
            color: theme.popupForeground.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

/// Everything the custom-binding editor renders, as one string.
String _customSignature(MiracleConfig config) => [
  for (final binding in config.customKeyCommands)
    '${binding.key}|${binding.action.value}|${binding.command}|'
        '${sortModifiers(binding.modifiers).map((m) => m.wireName).join('+')}',
].join('\n');

String _overrideSignature(MiracleConfig config) => [
  for (final override in config.builtInKeyCommandOverrides)
    '${override.key}|${override.action.value}|${override.command.wireName}|'
        '${sortModifiers(override.modifiers).map((m) => m.wireName).join('+')}',
].join('\n');
