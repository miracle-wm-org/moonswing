// Window Manager › Mouse and Window Manager › Touchpad: the two pointer
// devices, the cursor they share, and dragging windows with either.
//
// One file for two categories because they are the same nine or ten settings
// twice over, and a pair of files would be the place a fix reached one device
// and not the other.

import 'package:flutter/widgets.dart';

import 'package:miracle/miracle.dart';

import 'package:moonswing/miracle_config/miracle_config_store.dart';
import 'package:moonswing/miracle_config/miracle_labels.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/miracle/miracle_controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/overlay/settings/settings_search.dart';

class MiracleMouseSection extends StatelessWidget {
  const MiracleMouseSection({super.key, required this.store});

  final MiracleConfigStore store;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverSettingsSection(
          label: 'Pointer',
          children: [
            SettingsRow.field(
              SettingsCatalog.miracleMouseHandedness,
              control: MiracleValue<Handedness>(
                store: store,
                select: (config) => config.mouse.handedness,
                fallback: Handedness.right,
                builder: (context, value) => miracleEnumDropdown<Handedness>(
                  values: Handedness.values,
                  selected: value,
                  labelOf: handednessLabel,
                  searchFrom: 99,
                  onSelected: (next) =>
                      store.edit((config) => config.mouse.handedness = next),
                ),
              ),
            ),
            SettingsRow.field(
              SettingsCatalog.miracleMouseAcceleration,
              control: MiracleValue<Acceleration>(
                store: store,
                select: (config) => config.mouse.acceleration,
                fallback: Acceleration.none,
                builder: (context, value) => miracleEnumDropdown<Acceleration>(
                  values: Acceleration.values,
                  selected: value,
                  labelOf: accelerationLabel,
                  searchFrom: 99,
                  onSelected: (next) =>
                      store.edit((config) => config.mouse.acceleration = next),
                ),
              ),
            ),
            _signedDecimal(
              SettingsCatalog.miracleMouseAccelerationBias,
              select: (config) => config.mouse.accelerationBias,
              apply: (config, value) => config.mouse.accelerationBias = value,
            ),
            _decimal(
              SettingsCatalog.miracleMouseVscroll,
              select: (config) => config.mouse.vscrollSpeed,
              apply: (config, value) => config.mouse.vscrollSpeed = value,
            ),
            _decimal(
              SettingsCatalog.miracleMouseHscroll,
              select: (config) => config.mouse.hscrollSpeed,
              apply: (config, value) => config.mouse.hscrollSpeed = value,
            ),
            const SettingsHint(
              'The acceleration bias runs from -1 (slowest) through 0 (the '
              'device\'s own speed) to 1. The scroll speeds are multipliers, '
              'where 1 leaves the device alone.',
            ),
          ],
        ),
        SliverSettingsSection(
          label: 'Cursor',
          children: [
            _decimal(
              SettingsCatalog.miracleCursorScale,
              select: (config) => config.cursor.scale,
              apply: (config, value) => config.cursor.scale = value,
            ),
            SettingsRow.field(
              SettingsCatalog.miracleCursorFocusMode,
              control: MiracleValue<CursorFocusMode>(
                store: store,
                select: (config) => config.cursor.focusMode,
                fallback: CursorFocusMode.hover,
                builder: (context, value) =>
                    miracleEnumDropdown<CursorFocusMode>(
                      values: CursorFocusMode.values,
                      selected: value,
                      labelOf: cursorFocusModeLabel,
                      searchFrom: 99,
                      onSelected: (next) => store.edit(
                        (config) => config.cursor.focusMode = next,
                      ),
                    ),
              ),
            ),
          ],
        ),
        SliverSettingsSection(
          label: 'Dragging windows',
          children: [
            SettingsRow.field(
              SettingsCatalog.miracleDragAndDrop,
              control: MiracleValue<bool>(
                store: store,
                select: (config) => config.dragAndDrop.enabled,
                fallback: true,
                builder: (context, value) => SettingsToggle(
                  value: value,
                  onChanged: (next) =>
                      store.edit((config) => config.dragAndDrop.enabled = next),
                ),
              ),
            ),
            SettingsRow.field(
              SettingsCatalog.miracleDragModifiers,
              alignTop: true,
              control: MiracleValue<String>(
                store: store,
                // A `Set` cannot be the selected value — it compares by
                // identity and the getter mints a fresh one per read — so the
                // subscription is keyed on a spelling of the set and the
                // builder re-reads it.
                select: (config) => _modifierSignature(
                  config.dragAndDrop.modifiers,
                ),
                fallback: '',
                builder: (context, _) {
                  final config = store.config;
                  final selected =
                      config?.dragAndDrop.modifiers ?? const <Modifier>{};
                  return SizedBox(
                    width: 360,
                    child: SettingsChipToggles<Modifier>(
                      options: kModifiersInDisplayOrder,
                      selected: selected,
                      labelOf: modifierLabel,
                      onChanged: (next) => store.edit(
                        (config) => config.dragAndDrop.modifiers = next,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SettingsHint(
              'All of the chosen modifiers have to be held at once. With none '
              'chosen, a bare drag on a window moves it.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _decimal(
    SettingsField field, {
    required double Function(MiracleConfig config) select,
    required void Function(MiracleConfig config, double value) apply,
  }) => _number(field, select: select, apply: apply, allowNegative: false);

  Widget _signedDecimal(
    SettingsField field, {
    required double Function(MiracleConfig config) select,
    required void Function(MiracleConfig config, double value) apply,
  }) => _number(field, select: select, apply: apply, allowNegative: true);

  Widget _number(
    SettingsField field, {
    required double Function(MiracleConfig config) select,
    required void Function(MiracleConfig config, double value) apply,
    required bool allowNegative,
  }) => SettingsRow.field(
    field,
    control: MiracleValue<double>(
      store: store,
      select: select,
      fallback: 0,
      builder: (context, value) => SettingsNumberField(
        value: value,
        isInt: false,
        allowNegative: allowNegative,
        onChanged: (next) =>
            store.edit((config) => apply(config, next.toDouble())),
      ),
    ),
  );
}

class MiracleTouchpadSection extends StatelessWidget {
  const MiracleTouchpadSection({super.key, required this.store});

  final MiracleConfigStore store;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverSettingsSection(
          label: 'Clicking',
          children: [
            _toggle(
              SettingsCatalog.miracleTouchpadTapToClick,
              select: (config) => config.touchpad.tapToClick,
              apply: (config, value) => config.touchpad.tapToClick = value,
            ),
            _toggle(
              SettingsCatalog.miracleTouchpadMiddleEmulation,
              select: (config) => config.touchpad.middleMouseButtonEmulation,
              apply: (config, value) =>
                  config.touchpad.middleMouseButtonEmulation = value,
            ),
            SettingsRow.field(
              SettingsCatalog.miracleTouchpadClickMode,
              control: MiracleValue<TouchpadClickMode>(
                store: store,
                select: (config) => config.touchpad.clickMode,
                fallback: TouchpadClickMode.fingerCount,
                builder: (context, value) =>
                    miracleEnumDropdown<TouchpadClickMode>(
                      values: TouchpadClickMode.values,
                      selected: value,
                      labelOf: touchpadClickModeLabel,
                      searchFrom: 99,
                      onSelected: (next) => store.edit(
                        (config) => config.touchpad.clickMode = next,
                      ),
                    ),
              ),
            ),
          ],
        ),
        SliverSettingsSection(
          label: 'Scrolling',
          children: [
            SettingsRow.field(
              SettingsCatalog.miracleTouchpadScrollMode,
              control: MiracleValue<TouchpadScrollMode>(
                store: store,
                select: (config) => config.touchpad.scrollMode,
                fallback: TouchpadScrollMode.twoFingerScroll,
                builder: (context, value) =>
                    miracleEnumDropdown<TouchpadScrollMode>(
                      values: TouchpadScrollMode.values,
                      selected: value,
                      labelOf: touchpadScrollModeLabel,
                      searchFrom: 99,
                      onSelected: (next) => store.edit(
                        (config) => config.touchpad.scrollMode = next,
                      ),
                    ),
              ),
            ),
            _number(
              SettingsCatalog.miracleTouchpadVscroll,
              select: (config) => config.touchpad.vscrollSpeed,
              apply: (config, value) => config.touchpad.vscrollSpeed = value,
              allowNegative: false,
            ),
            _number(
              SettingsCatalog.miracleTouchpadHscroll,
              select: (config) => config.touchpad.hscrollSpeed,
              apply: (config, value) => config.touchpad.hscrollSpeed = value,
              allowNegative: false,
            ),
          ],
        ),
        SliverSettingsSection(
          label: 'Pointer',
          children: [
            _number(
              SettingsCatalog.miracleTouchpadAccelerationBias,
              select: (config) => config.touchpad.accelerationBias,
              apply: (config, value) =>
                  config.touchpad.accelerationBias = value,
              allowNegative: true,
            ),
            _toggle(
              SettingsCatalog.miracleTouchpadDisableTyping,
              select: (config) => config.touchpad.disableWhileTyping,
              apply: (config, value) =>
                  config.touchpad.disableWhileTyping = value,
            ),
            _toggle(
              SettingsCatalog.miracleTouchpadDisableMouse,
              select: (config) => config.touchpad.disableWithExternalMouse,
              apply: (config, value) =>
                  config.touchpad.disableWithExternalMouse = value,
            ),
            const SettingsHint(
              'These apply to every touchpad miracle sees. A machine with no '
              'touchpad keeps the settings and simply has nothing to apply '
              'them to.',
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

  Widget _number(
    SettingsField field, {
    required double Function(MiracleConfig config) select,
    required void Function(MiracleConfig config, double value) apply,
    required bool allowNegative,
  }) => SettingsRow.field(
    field,
    control: MiracleValue<double>(
      store: store,
      select: select,
      fallback: 0,
      builder: (context, value) => SettingsNumberField(
        value: value,
        isInt: false,
        allowNegative: allowNegative,
        onChanged: (next) =>
            store.edit((config) => apply(config, next.toDouble())),
      ),
    ),
  );
}

/// A spelling of a modifier set, for [MiracleValue]'s `==` check.
String _modifierSignature(Set<Modifier> modifiers) =>
    sortModifiers(modifiers).map((modifier) => modifier.wireName).join(',');
