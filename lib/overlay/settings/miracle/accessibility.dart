// Window Manager > Accessibility: the magnifier, the two ways to click without
// pressing a button, the two ways to type without holding one, and the shader
// miracle can run over the whole screen.
//
// Grouped together because that is how somebody looks for them — under
// "accessibility", not under "pointer" and "keyboard" — even though miracle
// spreads them across five unrelated structs.

import 'package:flutter/widgets.dart';

import 'package:miracle/miracle.dart';

import 'package:moonswing/miracle_config/miracle_config_store.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/miracle/miracle_controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/overlay/settings/settings_search.dart';

class MiracleAccessibilitySection extends StatelessWidget {
  const MiracleAccessibilitySection({super.key, required this.store});

  final MiracleConfigStore store;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverSettingsSection(
          label: 'Magnifier',
          children: [
            _toggle(
              SettingsCatalog.miracleMagnifierEnabled,
              select: (config) => config.magnifier.enabled,
              apply: (config, value) => config.magnifier.enabled = value,
            ),
            _decimal(
              SettingsCatalog.miracleMagnifierScale,
              select: (config) => config.magnifier.scale,
              apply: (config, value) => config.magnifier.scale = value,
            ),
            _decimal(
              SettingsCatalog.miracleMagnifierScaleIncrement,
              select: (config) => config.magnifier.scaleIncrement,
              apply: (config, value) =>
                  config.magnifier.scaleIncrement = value,
            ),
            _whole(
              SettingsCatalog.miracleMagnifierWidth,
              select: (config) => config.magnifier.width,
              apply: (config, value) => config.magnifier.width = value,
            ),
            _whole(
              SettingsCatalog.miracleMagnifierHeight,
              select: (config) => config.magnifier.height,
              apply: (config, value) => config.magnifier.height = value,
            ),
            _whole(
              SettingsCatalog.miracleMagnifierSizeIncrement,
              select: (config) => config.magnifier.sizeIncrement,
              apply: (config, value) => config.magnifier.sizeIncrement = value,
            ),
            const SettingsHint(
              'The two increments are what one press of a magnifier binding '
              'changes — see Key Bindings for which keys those are.',
            ),
          ],
        ),
        SliverSettingsSection(
          label: 'Clicking without a button',
          children: [
            _toggle(
              SettingsCatalog.miracleHoverClickEnabled,
              select: (config) => config.hoverClick.enabled,
              apply: (config, value) => config.hoverClick.enabled = value,
            ),
            _milliseconds(
              SettingsCatalog.miracleHoverClickDuration,
              select: (config) => config.hoverClick.hoverDuration,
              apply: (config, value) =>
                  config.hoverClick.hoverDuration = value,
            ),
            _whole(
              SettingsCatalog.miracleHoverClickCancel,
              select: (config) =>
                  config.hoverClick.cancelDisplacementThreshold,
              apply: (config, value) =>
                  config.hoverClick.cancelDisplacementThreshold = value,
            ),
            _whole(
              SettingsCatalog.miracleHoverClickReclick,
              select: (config) =>
                  config.hoverClick.reclickDisplacementThreshold,
              apply: (config, value) =>
                  config.hoverClick.reclickDisplacementThreshold = value,
            ),
            const SettingsHint(
              'Resting the pointer still clicks where it rests. The cancel '
              'distance is how far it may drift before the pending click is '
              'abandoned; the re-click distance is how far it must move before '
              'it will click again.',
            ),
            _toggle(
              SettingsCatalog.miracleSecondaryClickEnabled,
              select: (config) => config.simulatedSecondaryClick.enabled,
              apply: (config, value) =>
                  config.simulatedSecondaryClick.enabled = value,
            ),
            _milliseconds(
              SettingsCatalog.miracleSecondaryClickHold,
              select: (config) => config.simulatedSecondaryClick.holdDuration,
              apply: (config, value) =>
                  config.simulatedSecondaryClick.holdDuration = value,
            ),
            _whole(
              SettingsCatalog.miracleSecondaryClickThreshold,
              select: (config) =>
                  config.simulatedSecondaryClick.displacementThreshold,
              apply: (config, value) =>
                  config.simulatedSecondaryClick.displacementThreshold = value,
            ),
          ],
        ),
        SliverSettingsSection(
          label: 'Typing',
          children: [
            _toggle(
              SettingsCatalog.miracleSlowKeysEnabled,
              select: (config) => config.slowKeys.enabled,
              apply: (config, value) => config.slowKeys.enabled = value,
            ),
            _milliseconds(
              SettingsCatalog.miracleSlowKeysDuration,
              select: (config) => config.slowKeys.holdDuration,
              apply: (config, value) => config.slowKeys.holdDuration = value,
            ),
            _toggle(
              SettingsCatalog.miracleStickyKeysEnabled,
              select: (config) => config.stickyKeys.enabled,
              apply: (config, value) => config.stickyKeys.enabled = value,
            ),
            _toggle(
              SettingsCatalog.miracleStickyKeysDisable,
              select: (config) =>
                  config.stickyKeys.disableIfTwoKeysArePressedTogether,
              apply: (config, value) => config
                  .stickyKeys
                  .disableIfTwoKeysArePressedTogether = value,
            ),
            const SettingsHint(
              'Sticky keys latch a modifier when it is pressed, so Action Key '
              'and Shift can be typed one after the other rather than held '
              'together.',
            ),
          ],
        ),
        SliverSettingsSection(
          label: 'Screen filter',
          children: [
            SettingsRow.field(
              SettingsCatalog.miracleOutputFilterShader,
              control: MiracleValue<String>(
                store: store,
                select: (config) => config.outputFilter.shaderPath ?? '',
                fallback: '',
                builder: (context, value) => SettingsTextField(
                  width: 300,
                  initial: value,
                  hint: 'no filter',
                  onChanged: (text) {
                    final trimmed = text.trim();
                    store.edit(
                      (config) => config.outputFilter.shaderPath = trimmed
                              .isEmpty
                          ? null
                          : trimmed,
                    );
                  },
                ),
              ),
            ),
            const SettingsHint(
              'A path to a shader miracle runs over every output — a '
              'colour-blindness filter, a night tint. A leading ~ resolves to '
              'your home directory. Leave it empty for none.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _toggle(
    SettingsField field, {
    required bool Function(MiracleConfig config) select,
    required void Function(MiracleConfig config, bool value) apply,
  }) => SettingsRow.field(
    field,
    control: MiracleValue<bool>(
      store: store,
      select: select,
      fallback: false,
      builder: (context, value) => SettingsToggle(
        value: value,
        onChanged: (next) => store.edit((config) => apply(config, next)),
      ),
    ),
  );

  Widget _whole(
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

  Widget _decimal(
    SettingsField field, {
    required double Function(MiracleConfig config) select,
    required void Function(MiracleConfig config, double value) apply,
  }) => SettingsRow.field(
    field,
    control: MiracleValue<double>(
      store: store,
      select: select,
      fallback: 0,
      builder: (context, value) => SettingsNumberField(
        value: value,
        isInt: false,
        onChanged: (next) =>
            store.edit((config) => apply(config, next.toDouble())),
      ),
    ),
  );

  /// A [Duration] the user edits in milliseconds.
  ///
  /// The package types these as `Duration` because that is what a duration is;
  /// the configuration file and every one of miracle's own defaults are written
  /// in milliseconds, so that is the unit the field takes and the label says.
  Widget _milliseconds(
    SettingsField field, {
    required Duration Function(MiracleConfig config) select,
    required void Function(MiracleConfig config, Duration value) apply,
  }) => SettingsRow.field(
    field,
    control: MiracleValue<int>(
      store: store,
      select: (config) => select(config).inMilliseconds,
      fallback: 0,
      builder: (context, value) => SettingsNumberField(
        value: value,
        isInt: true,
        onChanged: (next) => store.edit(
          (config) =>
              apply(config, Duration(milliseconds: next.toInt())),
        ),
      ),
    ),
  );
}
