// Window Manager > Keyboard: the layout miracle applies to every device, and
// how fast a held key repeats.
//
// Not to be confused with Settings > Keyboard, which is the *machine's* layout
// through logind's locale1 — that one writes `/etc/default/keyboard` for every
// account and the console. This one is one compositor's own setting and needs
// no authentication.

import 'package:flutter/widgets.dart';

import 'package:moonswing/miracle_config/miracle_config_store.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/miracle/miracle_controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';

class MiracleKeyboardSection extends StatelessWidget {
  const MiracleKeyboardSection({super.key, required this.store});

  final MiracleConfigStore store;

  /// What a keymap is switched *on* to.
  ///
  /// A keymap has to have a layout — the C library builds the struct from
  /// scratch when one was not already set — so turning the row on has to name
  /// one, and `us` is the layout miracle itself falls back to.
  static const String _defaultLanguage = 'us';

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverSettingsSection(
          label: 'Layout',
          children: [
            SettingsRow.field(
              SettingsCatalog.miracleKeymapEnabled,
              control: MiracleValue<bool>(
                store: store,
                select: (config) => config.keymap.isSet,
                fallback: false,
                builder: (context, isSet) => SettingsToggle(
                  value: isSet,
                  onChanged: (next) => store.edit((config) {
                    if (next) {
                      config.keymap.set(language: _defaultLanguage);
                    } else {
                      config.keymap.clear();
                    }
                  }),
                ),
              ),
            ),
            // The layout, variant and options rows exist only while a keymap
            // does. This is not tidiness: the C library dereferences the keymap
            // without checking there is one, so reaching into the options of an
            // unset keymap aborts the process rather than throwing.
            MiracleValue<bool>(
              store: store,
              select: (config) => config.keymap.isSet,
              fallback: false,
              builder: (context, isSet) => isSet
                  ? _layoutRows(context)
                  : const SettingsHint(
                      'miracle is leaving the keyboard layout to the system. '
                      'Turn this on to have the compositor apply one of its '
                      'own to every keyboard.',
                    ),
            ),
          ],
        ),
        SliverSettingsSection(
          label: 'Key repeat',
          children: [
            SettingsRow.field(
              SettingsCatalog.miracleKeyRepeatDelay,
              control: MiracleValue<int>(
                store: store,
                select: (config) => config.keyRepeatDelay,
                fallback: 500,
                builder: (context, value) => SettingsNumberField(
                  value: value,
                  isInt: true,
                  onChanged: (next) => store.edit(
                    (config) => config.keyRepeatDelay = next.toInt(),
                  ),
                ),
              ),
            ),
            SettingsRow.field(
              SettingsCatalog.miracleKeyRepeatRate,
              control: MiracleValue<int>(
                store: store,
                select: (config) => config.keyRepeatRate,
                fallback: 25,
                builder: (context, value) => SettingsNumberField(
                  value: value,
                  isInt: true,
                  onChanged: (next) => store.edit(
                    (config) => config.keyRepeatRate = next.toInt(),
                  ),
                ),
              ),
            ),
            // A real trap, and invisible without saying so: miracle writes its
            // keyboard block only when a keymap is configured, so a repeat rate
            // set with the layout switched off is silently dropped by the save.
            MiracleValue<bool>(
              store: store,
              select: (config) => config.keymap.isSet,
              fallback: false,
              builder: (context, isSet) => SettingsHint(
                isSet
                    ? 'The delay is in milliseconds; the rate is in characters '
                          'a second.'
                    : 'miracle writes its keyboard settings only alongside a '
                          'layout, so these two are dropped when you save '
                          'unless the layout above is switched on.',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _layoutRows(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRow.field(
          SettingsCatalog.miracleKeymapLanguage,
          control: MiracleValue<String>(
            store: store,
            select: (config) => config.keymap.language,
            fallback: '',
            builder: (context, value) => SettingsTextField(
              width: kMiracleControlWidth,
              initial: value,
              hint: _defaultLanguage,
              // The property setter, never `keymap.set()`: setting the whole
              // keymap rebuilds it from scratch and drops every XKB option the
              // user has configured.
              onChanged: (text) =>
                  store.edit((config) => config.keymap.language = text.trim()),
            ),
          ),
        ),
        SettingsRow.field(
          SettingsCatalog.miracleKeymapVariant,
          control: MiracleValue<String>(
            store: store,
            select: (config) => config.keymap.variant ?? '',
            fallback: '',
            builder: (context, value) => SettingsTextField(
              width: kMiracleControlWidth,
              initial: value,
              hint: 'none',
              onChanged: (text) {
                final trimmed = text.trim();
                store.edit(
                  (config) =>
                      config.keymap.variant = trimmed.isEmpty ? null : trimmed,
                );
              },
            ),
          ),
        ),
        MiracleCollection(
          store: store,
          signature: (config) =>
              config.keymap.isSet ? config.keymap.options.join(' ') : '',
          builder: (context, config) => SettingsRow.field(
            SettingsCatalog.miracleKeymapOptions,
            alignTop: true,
            control: SettingsStringListEditor(
              items: config.keymap.isSet
                  ? List<String>.from(config.keymap.options)
                  : const <String>[],
              addLabel: 'Add option',
              addHint: 'caps:swapescape',
              width: 300,
              onChanged: (next) => store.edit((config) {
                if (!config.keymap.isSet) return;
                final options = config.keymap.options;
                options.clear();
                options.addAll(next);
              }),
            ),
          ),
        ),
        const SettingsHint(
          'The layout is an XKB code — us, de, fr — and the variant is one of '
          "that layout's, such as dvorak or intl. Options are the same strings "
          'setxkbmap takes, e.g. caps:swapescape.',
        ),
      ],
    );
  }
}
