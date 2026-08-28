import 'package:flutter/widgets.dart';

import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';

/// The Calendar tab's own settings. The tab is a local month grid — there is no
/// account integration — so this is presentation only.
class CalendarSection extends StatelessWidget {
  const CalendarSection({super.key, required this.store});

  final ConfigStore store;

  @override
  Widget build(BuildContext context) {
    return SliverSettingsSection(
      label: 'Calendar',
      children: [
        SettingsRow(
          label: 'Week starts on',
          // Subscribed per key rather than under a page-level
          // `ListenableBuilder`: [ConfigStore] notifies on every keystroke
          // anywhere in the settings UI. See [ConfigValue].
          control: ConfigValue<String>(
            store: store,
            path: const ['calendar', 'week_start'],
            fallback: 'sunday',
            builder: (context, value) => SettingsSegmented(
              options: const ['sunday', 'monday'],
              value: value!,
              onChanged: (v) => store.set(['calendar', 'week_start'], v),
            ),
          ),
        ),
      ],
    );
  }
}
