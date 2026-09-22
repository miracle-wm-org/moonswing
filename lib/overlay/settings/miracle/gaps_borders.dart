// Window Manager › Gaps & Borders: the space miracle leaves around tiled
// windows, and the line it draws around each one.

import 'package:flutter/widgets.dart';

import 'package:miracle/miracle.dart';

import 'package:moonswing/miracle_config/miracle_color.dart';
import 'package:moonswing/miracle_config/miracle_config_store.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/miracle/miracle_controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/overlay/settings/settings_search.dart';

class MiracleGapsSection extends StatelessWidget {
  const MiracleGapsSection({super.key, required this.store});

  final MiracleConfigStore store;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverSettingsSection(
          label: 'Gaps',
          children: [
            _pixels(
              SettingsCatalog.miracleInnerGapsX,
              select: (config) => config.innerGapsX,
              apply: (config, value) => config.innerGapsX = value,
            ),
            _pixels(
              SettingsCatalog.miracleInnerGapsY,
              select: (config) => config.innerGapsY,
              apply: (config, value) => config.innerGapsY = value,
            ),
            _pixels(
              SettingsCatalog.miracleOuterGapsX,
              select: (config) => config.outerGapsX,
              apply: (config, value) => config.outerGapsX = value,
            ),
            _pixels(
              SettingsCatalog.miracleOuterGapsY,
              select: (config) => config.outerGapsY,
              apply: (config, value) => config.outerGapsY = value,
            ),
            const SettingsHint(
              'Inner gaps sit between two windows; outer gaps sit between the '
              'windows and the screen edge. Both are in pixels, and both are '
              'measured before the panels reserve their own space.',
            ),
          ],
        ),
        SliverSettingsSection(
          label: 'Borders',
          children: [
            _pixels(
              SettingsCatalog.miracleBorderSize,
              select: (config) => config.border.size,
              apply: (config, value) => config.border.size = value,
            ),
            SettingsRow.field(
              SettingsCatalog.miracleBorderRadius,
              control: MiracleValue<double>(
                store: store,
                select: (config) => config.border.radius,
                fallback: 0,
                builder: (context, value) => SettingsNumberField(
                  value: value,
                  isInt: false,
                  onChanged: (next) => store.edit(
                    (config) => config.border.radius = next.toDouble(),
                  ),
                ),
              ),
            ),
            _colour(
              SettingsCatalog.miracleBorderFocusColor,
              select: (config) => config.border.focusColor,
              apply: (config, colour) => config.border.focusColor = colour,
            ),
            _colour(
              SettingsCatalog.miracleBorderColor,
              select: (config) => config.border.color,
              apply: (config, colour) => config.border.color = colour,
            ),
            const SettingsHint(
              'A thickness of 0 draws no border at all, which is what the '
              'colours above then have nothing to paint.',
            ),
          ],
        ),
      ],
    );
  }

  /// A whole-pixel row. Four of the gaps and the border thickness are the same
  /// control over the same kind of value, and spelling it five times is five
  /// chances to wire one of them to the wrong setter.
  Widget _pixels(
    SettingsField field, {
    required int Function(MiracleConfig config) select,
    required void Function(MiracleConfig config, int value) apply,
  }) => SettingsRow.field(
    field,
    control: MiracleValue<int>(
      store: store,
      select: select,
      fallback: 0,
      builder: (context, value) => SettingsNumberField(
        value: value,
        isInt: true,
        onChanged: (next) =>
            store.edit((config) => apply(config, next.toInt())),
      ),
    ),
  );

  Widget _colour(
    SettingsField field, {
    required RgbaColor Function(MiracleConfig config) select,
    required void Function(MiracleConfig config, RgbaColor colour) apply,
  }) => SettingsRow.field(
    field,
    control: MiracleValue<String>(
      store: store,
      select: (config) => rgbaToHex(select(config)),
      fallback: '#FF000000',
      builder: (context, value) => SettingsColorField(
        initial: value,
        onChanged: (hex) {
          final colour = rgbaFromHex(hex);
          if (colour == null) return;
          store.edit((config) => apply(config, colour));
        },
      ),
    ),
  );
}
