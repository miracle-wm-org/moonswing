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
    return SettingsSection(
      label: 'Calendar',
      children: [
        SettingsRow(
          label: 'Week starts on',
          control: SettingsSegmented(
            options: const ['sunday', 'monday'],
            value: store.get<String>(['calendar', 'week_start']) ?? 'sunday',
            onChanged: (v) => store.set(['calendar', 'week_start'], v),
          ),
        ),
      ],
    );
  }
}
