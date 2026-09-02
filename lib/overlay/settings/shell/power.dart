import 'package:flutter/widgets.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/overlay/settings/settings_catalog.dart';

/// What the machine's physical power button does.
///
/// Both settings are live: the key *binding* (`[shortcuts] power_button`)
/// latches at start-up and is not editable here, but which verb a press runs
/// and whether logind's lock is held are re-read on every change, so nothing
/// on this page asks for a restart.
class PowerSection extends StatelessWidget {
  const PowerSection({super.key, required this.store});

  final ConfigStore store;

  /// The width the picker is given.
  ///
  /// A [SettingsRow] sizes its control to itself, so without this the trigger
  /// is as wide as whichever verb happens to be selected — and it would
  /// resize, along with the card `matchTriggerWidth` sizes to it, every time
  /// the user picked a different one.
  static const double _pickerWidth = 260;

  /// What each verb does is said in the hint under the row rather than in a
  /// [SettingsDropdownItem.detail]: that slot is a marker beside the label
  /// ("preferred", on the display page's mode list), and a sentence in it is
  /// wider than the card the row it sits in can be.
  static const List<SettingsDropdownItem<String>> _actions = [
    SettingsDropdownItem(value: 'menu', label: 'Show the power menu'),
    SettingsDropdownItem(value: 'shutdown', label: 'Shut down'),
    SettingsDropdownItem(value: 'reboot', label: 'Restart'),
    SettingsDropdownItem(value: 'suspend', label: 'Sleep'),
    SettingsDropdownItem(value: 'lock', label: 'Lock the session'),
    SettingsDropdownItem(value: 'logout', label: 'Log out'),
    SettingsDropdownItem(
      value: 'none',
      label: 'Nothing (leave it to the system)',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SliverSettingsSection(
      label: 'Power Button',
      children: [
        // One subscription spanning the picker *and* the two hints under it:
        // the second hint's text reads the action, so it has to be inside the
        // same [ConfigValue] rather than beside it. Subscribed per key rather
        // than under a page-level `ListenableBuilder`, because [ConfigStore]
        // notifies on every keystroke anywhere in the settings UI.
        ConfigValue<String>(
          store: store,
          path: const ['power', 'key_action'],
          builder: (context, raw) {
            // Resolved through [PowerKeyAction.fromString] rather than shown
            // raw, so a hand-edited spelling the parser accepts ("off",
            // "restart") selects the action it resolves to instead of leaving
            // the picker on an em dash.
            final action =
                (raw == null ? null : PowerKeyAction.fromString(raw)) ??
                PowerKeyAction.menu;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsRow.field(
                  SettingsCatalog.powerKeyAction,
                  control: SizedBox(
                    width: _pickerWidth,
                    child: SettingsDropdown<String>(
                      items: _actions,
                      selected: action.key,
                      onSelected: (value) =>
                          store.set(['power', 'key_action'], value),
                    ),
                  ),
                ),
                const SettingsHint(
                  'The power menu offers Lock, Log Out, Sleep, Restart and '
                  'Shut Down over the desktop; any of those five can be run by '
                  'the button directly instead. The shell can only answer the '
                  'button on a compositor that reports it — everything '
                  'Mir-based does. Everywhere else the key keeps doing '
                  'whatever the system does with it.',
                ),
                SettingsRow.field(
                  SettingsCatalog.powerInhibitLogind,
                  control: ConfigValue<bool>(
                    store: store,
                    path: const ['power', 'inhibit_logind'],
                    fallback: true,
                    builder: (context, inhibit) => SettingsToggle(
                      value: inhibit!,
                      onChanged: (v) =>
                          store.set(['power', 'inhibit_logind'], v),
                    ),
                  ),
                ),
                SettingsHint(
                  action != PowerKeyAction.none
                      ? 'systemd-logind watches the power button too, and '
                            'powers the machine off on a press. The shell '
                            'holds its handle-power-key lock so that cannot '
                            'happen behind the power menu — turn it off only '
                            'if logind.conf already says '
                            'HandlePowerKey=ignore.'
                      : 'Nothing is held while the button is left to the '
                            'system.',
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
