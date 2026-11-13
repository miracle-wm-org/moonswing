import 'package:flutter/widgets.dart';

import 'package:moonswing/code/code_config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/overlay/settings/settings_search.dart';
import 'package:moonswing/overlay/settings_route.dart';

/// The Code tab's `[code]` table: when its lists call something stale, how far
/// back Shipped reaches, and how often the forges are read.
///
/// Every row is live — the store re-derives staleness on the next build and
/// re-arms its timer — so nothing here asks for a restart. The accounts the tab
/// reads are not here: they are Settings › Accounts', as every linkage is.
class CodeSection extends StatelessWidget {
  const CodeSection({super.key, required this.store});

  final ConfigStore store;

  Widget _days(
    SettingsField field,
    String key,
    int fallback, {
    int min = CodeConfig.minStaleDays,
    int max = CodeConfig.maxStaleDays,
  }) {
    final path = ['code', key];
    return SettingsRow.field(
      field,
      control: ConfigValue<num>(
        store: store,
        path: path,
        fallback: fallback,
        builder: (context, value) => SettingsNumberField(
          value: value!,
          isInt: true,
          onChanged: (v) => store.set(path, v.toInt().clamp(min, max)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SliverSettingsSection(
      label: kCodeSettingsCategory,
      children: [
        _days(
          SettingsCatalog.codeReviewStaleDays,
          'review_stale_days',
          CodeConfig.defaultReviewStaleDays,
        ),
        _days(
          SettingsCatalog.codeStaleDays,
          'stale_days',
          CodeConfig.defaultStaleDays,
        ),
        _days(
          SettingsCatalog.codeIssueStaleDays,
          'issue_stale_days',
          CodeConfig.defaultIssueStaleDays,
        ),
        _days(
          SettingsCatalog.codeShippedDays,
          'shipped_days',
          CodeConfig.defaultShippedDays,
          min: CodeConfig.minShippedDays,
          max: CodeConfig.maxShippedDays,
        ),
        _days(
          SettingsCatalog.codeRefreshMinutes,
          'refresh_minutes',
          CodeConfig.defaultRefreshMinutes,
          min: CodeConfig.minRefreshMinutes,
          max: CodeConfig.maxRefreshMinutes,
        ),
      ],
    );
  }
}
