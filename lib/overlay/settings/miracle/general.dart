// Window Manager › General: the Action Key every binding hangs off, what the
// terminal binding launches, and the two or three settings that belong to no
// larger group.

import 'package:flutter/widgets.dart';

import 'package:miracle/miracle.dart';

import 'package:moonswing/miracle_config/miracle_color.dart';
import 'package:moonswing/miracle_config/miracle_config_store.dart';
import 'package:moonswing/miracle_config/miracle_labels.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/miracle/miracle_controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';

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
              info:
                  '${SettingsCatalog.miracleActionKey.description} Every '
                  'built-in binding is written against it, so changing it '
                  'moves all of them at once.',
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
            // Said rather than disabled: the setting is real and a plugin may
            // want it, but miracle has neither a reader nor a writer for it in
            // the configuration file, so a change here lasts as long as this
            // page does. The catalogue description, behind the row's info
            // icon, says so — and a control that silently forgets is worse than
            // one that says it will.
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
          ],
        ),
        SliverSettingsSection(
          label: 'Behaviour',
          children: [
            // The load-time check is worth stating because it makes a
            // saved-and-reloaded terminal appear to have been ignored.
            SettingsRow.field(
              SettingsCatalog.miracleTerminal,
              info:
                  '${SettingsCatalog.miracleTerminal.description} miracle '
                  'checks the program exists when it loads the configuration '
                  'and silently falls back to its default if not.',
              control: MiracleValue<String>(
                store: store,
                select: (config) => config.terminal ?? '',
                fallback: '',
                builder: (context, value) => SettingsCommitField(
                  width: kMiracleControlWidth,
                  initial: value,
                  hint: 'miracle picks one',
                  onCommitted: (text) {
                    final trimmed = text.trim();
                    store.edit(
                      (config) =>
                          config.terminal = trimmed.isEmpty ? null : trimmed,
                    );
                  },
                ),
              ),
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
              info:
                  '${SettingsCatalog.miracleBackgroundColor.description} Only '
                  'visible where nothing else paints — the shell draws its own '
                  'wallpaper over the whole screen.',
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
          ],
        ),
      ],
    );
  }
}
