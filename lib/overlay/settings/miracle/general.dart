// Window Manager › General: the Action Key every binding hangs off, what the
// terminal binding launches, and the two or three settings that belong to no
// larger group.

import 'package:flutter/widgets.dart';

import 'package:miracle/miracle.dart';

import 'package:graceful_shell/miracle_config/miracle_color.dart';
import 'package:graceful_shell/miracle_config/miracle_config_store.dart';
import 'package:graceful_shell/miracle_config/miracle_labels.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/overlay/settings/miracle/miracle_controls.dart';
import 'package:graceful_shell/overlay/settings/settings_catalog.dart';

class MiracleGeneralSection extends StatelessWidget {
  const MiracleGeneralSection({super.key, required this.store});

  final MiracleConfigStore store;

  /// The Action Key is what [Modifier.primary] *stands for*, so offering it as
  /// a value for the Action Key itself would be circular — miracle would
  /// resolve it to itself. Every other modifier is offered; a binding is free
  /// to name the sentinel, and the Move modifier below does.
  static final List<Modifier> _primaryModifiers = [
    for (final modifier in kModifiersInDisplayOrder)
      if (modifier != Modifier.primary) modifier,
  ];

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverSettingsSection(
          label: 'Keys',
          children: [
            SettingsRow.field(
              SettingsCatalog.miracleActionKey,
              control: MiracleValue<Modifier>(
                store: store,
                select: (config) => config.primaryModifier,
                fallback: Modifier.meta,
                builder: (context, value) => miracleEnumDropdown<Modifier>(
                  values: _primaryModifiers,
                  selected: value,
                  labelOf: modifierLabel,
                  searchFrom: 99,
                  onSelected: (next) =>
                      store.edit((config) => config.primaryModifier = next),
                ),
              ),
            ),
            const SettingsHint(
              'miracle calls this the Action Key. Every built-in binding is '
              'written against it, so changing it here moves all of them at '
              'once — the workspace switches, the window moves, the terminal.',
            ),
            SettingsRow.field(
              SettingsCatalog.miracleMoveModifier,
              control: MiracleValue<Modifier>(
                store: store,
                select: (config) => config.moveModifier,
                fallback: Modifier.primary,
                builder: (context, value) => miracleEnumDropdown<Modifier>(
                  values: kModifiersInDisplayOrder,
                  selected: value,
                  labelOf: modifierLabel,
                  searchFrom: 99,
                  onSelected: (next) =>
                      store.edit((config) => config.moveModifier = next),
                ),
              ),
            ),
            SettingsRow.field(
              SettingsCatalog.miraclePrimaryButton,
              control: MiracleValue<MouseButton>(
                store: store,
                select: (config) => config.primaryButton,
                fallback: MouseButton.primary,
                builder: (context, value) => miracleEnumDropdown<MouseButton>(
                  values: MouseButton.values,
                  selected: value,
                  labelOf: mouseButtonLabel,
                  searchFrom: 99,
                  onSelected: (next) =>
                      store.edit((config) => config.primaryButton = next),
                ),
              ),
            ),
            // Said plainly rather than by disabling the row: the setting is
            // real and a plugin may want it, but miracle has neither a reader
            // nor a writer for it in the configuration file, so a change here
            // lasts as long as this page does. A control that silently forgets
            // is worse than one that says it will.
            const SettingsHint(
              'miracle sets the primary button from plugins rather than from '
              'the configuration file, so this is not written when you save.',
            ),
          ],
        ),
        SliverSettingsSection(
          label: 'Behaviour',
          children: [
            SettingsRow.field(
              SettingsCatalog.miracleTerminal,
              control: MiracleValue<String>(
                store: store,
                select: (config) => config.terminal ?? '',
                fallback: '',
                builder: (context, value) => SettingsTextField(
                  width: kMiracleControlWidth,
                  initial: value,
                  hint: 'miracle picks one',
                  onChanged: (text) {
                    final trimmed = text.trim();
                    store.edit(
                      (config) =>
                          config.terminal = trimmed.isEmpty ? null : trimmed,
                    );
                  },
                ),
              ),
            ),
            // Worth stating because it makes a saved-and-reloaded terminal
            // appear to have been ignored: miracle checks the program exists
            // when it *loads* a configuration, and falls back to its own
            // default when the check fails.
            const SettingsHint(
              'miracle checks the program exists when it loads the '
              'configuration and quietly falls back to its own default if it '
              'does not — so a typo here reads as "nothing happened".',
            ),
            SettingsRow.field(
              SettingsCatalog.miracleResizeJump,
              control: MiracleValue<int>(
                store: store,
                select: (config) => config.resizeJump,
                fallback: 50,
                builder: (context, value) => SettingsNumberField(
                  value: value,
                  isInt: true,
                  onChanged: (next) =>
                      store.edit((config) => config.resizeJump = next.toInt()),
                ),
              ),
            ),
            SettingsRow.field(
              SettingsCatalog.miracleBackAndForth,
              control: MiracleValue<bool>(
                store: store,
                select: (config) => config.workspaceBackAndForth,
                fallback: false,
                builder: (context, value) => SettingsToggle(
                  value: value,
                  onChanged: (next) => store.edit(
                    (config) => config.workspaceBackAndForth = next,
                  ),
                ),
              ),
            ),
            SettingsRow.field(
              SettingsCatalog.miracleBackgroundColor,
              control: MiracleValue<String>(
                store: store,
                // Written without an alpha component: the compositor's
                // background is three floats, so an alpha offered here would be
                // one the user could edit and miracle would discard.
                select: (config) =>
                    rgbaToHex(config.backgroundColor, includeAlpha: false),
                fallback: '#000000',
                builder: (context, value) => SettingsColorField(
                  initial: value,
                  onChanged: (hex) {
                    final colour = rgbaFromHex(hex);
                    if (colour == null) return;
                    store.edit((config) => config.backgroundColor = colour);
                  },
                ),
              ),
            ),
            const SettingsHint(
              'What the compositor clears each output to. You will only see it '
              'where nothing else is painted — the shell draws its own '
              'wallpaper over the whole screen.',
            ),
          ],
        ),
      ],
    );
  }
}
