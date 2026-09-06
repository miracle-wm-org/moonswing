import 'package:flutter/widgets.dart';

import 'package:graceful_shell/capture/capture_config.dart'
    show
        RecorderConfig,
        ScreenshotConfig,
        kDefaultRecordingDirectory,
        kDefaultScreenshotDirectory,
        kRecorderContainers;
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/modules/battery.dart' show BatteryConfig;
import 'package:graceful_shell/modules/clock.dart' show ClockConfig;
import 'package:graceful_shell/modules/dock.dart' show DockConfig;
import 'package:graceful_shell/modules/media_player.dart'
    show MediaPlayerConfig;
import 'package:graceful_shell/modules/network.dart' show NetworkConfig;
import 'package:graceful_shell/modules/system_tray.dart' show SystemTrayConfig;
import 'package:graceful_shell/modules/weather.dart' show WeatherConfig;
import 'package:graceful_shell/modules/workspaces.dart' show WorkspacesConfig;
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/overlay/settings/settings_catalog.dart';
import 'package:graceful_shell/overlay/settings/settings_search.dart';
import 'package:graceful_shell/overlay/settings/shell/weather_location.dart';
import 'package:graceful_shell/system/system_monitor_config.dart'
    show SystemMonitorConfig;

/// Which control edits a module setting row.
enum _Kind { toggle, number, segmented, text, stringList, weatherLocation }

/// One `[modules.*]` row: its catalogue entry, and which control edits it.
///
/// [defaultValue] is read off the module's own const config object, so the
/// fallback a control shows when `config.toml` has no value is by construction
/// the value the module's `fromMap` would use.
///
/// The same trick ties a row to the settings search: the row's label comes off
/// [field], and its **config path is the field's id split on the dots** — so a
/// key, the row that edits it and the result that finds it are one string in one
/// place. See [SettingsCatalog].
class _ModuleSetting {
  const _ModuleSetting.toggle(this.field, {required bool this.defaultValue})
    : kind = _Kind.toggle,
      isInt = false,
      options = null,
      addHint = null;

  const _ModuleSetting.number(
    this.field, {
    required num this.defaultValue,
    required this.isInt,
  }) : kind = _Kind.number,
       options = null,
       addHint = null;

  const _ModuleSetting.segmented(
    this.field, {
    required List<String> this.options,
    required String this.defaultValue,
  }) : kind = _Kind.segmented,
       isInt = false,
       addHint = null;

  /// A free-typed string — a path, in the only two rows that use it.
  ///
  /// Deliberately not a file picker: these name a *directory to create*, and the
  /// picker browses what already exists. The default is shown as the placeholder
  /// rather than written into the field, so clearing it goes back to the default
  /// instead of to nowhere.
  const _ModuleSetting.text(this.field, {this.addHint})
    : kind = _Kind.text,
      defaultValue = null,
      isInt = false,
      options = null;

  const _ModuleSetting.stringList(this.field, {this.addHint})
    : kind = _Kind.stringList,
      defaultValue = null,
      isInt = false,
      options = null;

  /// The weather location picker.
  ///
  /// The one row whose control is not a value editor: a location is three config
  /// keys written together and only a geocoding lookup produces them, so the
  /// control owns its own path list rather than taking one.
  const _ModuleSetting.weatherLocation(this.field)
    : kind = _Kind.weatherLocation,
      defaultValue = null,
      isInt = false,
      options = null,
      addHint = null;

  /// The catalogue entry: the row's label, and the config path it edits.
  final SettingsField field;

  final _Kind kind;

  /// The `[modules.*]` key this row writes, from the entry's id.
  ///
  /// Unused by [_Kind.weatherLocation], which owns its own three paths — see
  /// `weather_location.dart`.
  List<String> get path => field.id.split('.');

  /// The module's compiled-in default. Null only for [_Kind.stringList], whose
  /// absent-value state is the empty list [ConfigStore.getList] returns.
  final Object? defaultValue;

  /// [SettingsNumberField.isInt] for [_Kind.number] rows.
  final bool isInt;

  /// The choices for a [_Kind.segmented] row.
  final List<String>? options;

  /// Placeholder text: a [_Kind.stringList] row's free-form adder, or the
  /// compiled-in default a [_Kind.text] row falls back to when it is empty.
  final String? addHint;
}

/// A sub-labelled run of rows — one per module.
class _ModuleGroup {
  const _ModuleGroup(this.label, this.settings);

  final String label;
  final List<_ModuleSetting> settings;
}

/// Every row the section renders, in order. Not `const` because reading a
/// field off a const config object is not a constant expression.
final List<_ModuleGroup> _moduleGroups = [
  _ModuleGroup('Workspaces', [
    _ModuleSetting.toggle(
      SettingsCatalog.workspacesShowAppIcons,
      defaultValue: const WorkspacesConfig().showAppIcons,
    ),
    _ModuleSetting.number(
      SettingsCatalog.workspacesIconSize,
      defaultValue: const WorkspacesConfig().iconSize,
      isInt: true,
    ),
    _ModuleSetting.number(
      SettingsCatalog.workspacesMaxIcons,
      defaultValue: const WorkspacesConfig().maxIcons,
      isInt: true,
    ),
    _ModuleSetting.toggle(
      SettingsCatalog.workspacesFlashUrgent,
      defaultValue: const WorkspacesConfig().flashUrgent,
    ),
    _ModuleSetting.number(
      SettingsCatalog.workspacesUrgentFlashSeconds,
      defaultValue: const WorkspacesConfig().urgentFlashSeconds,
      isInt: false,
    ),
  ]),
  _ModuleGroup('Weather', [
    _ModuleSetting.weatherLocation(SettingsCatalog.weatherLocation),
    _ModuleSetting.segmented(
      SettingsCatalog.weatherUnit,
      options: const ['fahrenheit', 'celsius'],
      defaultValue: const WeatherConfig().unit,
    ),
    _ModuleSetting.number(
      SettingsCatalog.weatherRefreshMinutes,
      defaultValue: const WeatherConfig().refreshMinutes,
      isInt: true,
    ),
  ]),
  _ModuleGroup('Battery', [
    _ModuleSetting.number(
      SettingsCatalog.batteryPollSeconds,
      defaultValue: const BatteryConfig().pollSeconds,
      isInt: true,
    ),
  ]),
  _ModuleGroup('Clock', [
    _ModuleSetting.toggle(
      SettingsCatalog.clockShowDate,
      defaultValue: const ClockConfig().showDate,
    ),
  ]),
  _ModuleGroup('Media player', [
    _ModuleSetting.number(
      SettingsCatalog.mediaPlayerMaxTextWidth,
      defaultValue: const MediaPlayerConfig().maxTextWidth,
      isInt: false,
    ),
  ]),
  _ModuleGroup('System tray', [
    _ModuleSetting.number(
      SettingsCatalog.systemTrayIconSize,
      defaultValue: const SystemTrayConfig().iconSize,
      isInt: false,
    ),
    _ModuleSetting.number(
      SettingsCatalog.systemTrayCollapsedOverlap,
      defaultValue: const SystemTrayConfig().collapsedOverlap,
      isInt: false,
    ),
    _ModuleSetting.number(
      SettingsCatalog.systemTrayExpandedSpacing,
      defaultValue: const SystemTrayConfig().expandedSpacing,
      isInt: false,
    ),
    _ModuleSetting.stringList(
      SettingsCatalog.systemTrayHiddenItems,
      addHint: 'SNI id or title',
    ),
  ]),
  _ModuleGroup('Dock', [
    _ModuleSetting.number(
      SettingsCatalog.dockIconSize,
      defaultValue: const DockConfig().iconSize,
      isInt: true,
    ),
    _ModuleSetting.toggle(
      SettingsCatalog.dockShowAppDirectory,
      defaultValue: const DockConfig().showAppDirectory,
    ),
    _ModuleSetting.stringList(SettingsCatalog.dockApps, addHint: 'app id'),
  ]),
  _ModuleGroup('System monitor', [
    _ModuleSetting.number(
      SettingsCatalog.systemMonitorPollSeconds,
      defaultValue: const SystemMonitorConfig().pollSeconds,
      isInt: true,
    ),
    _ModuleSetting.segmented(
      SettingsCatalog.systemMonitorTempUnit,
      options: const ['celsius', 'fahrenheit'],
      defaultValue: const SystemMonitorConfig().tempUnit,
    ),
    _ModuleSetting.number(
      SettingsCatalog.systemMonitorHistorySamples,
      defaultValue: const SystemMonitorConfig().historySamples,
      isInt: true,
    ),
    // "machine" makes the process rows sum to the total CPU gauge; "core" is
    // top-style, where 100% is one saturated core.
    _ModuleSetting.segmented(
      SettingsCatalog.systemMonitorCpuPercentMode,
      options: const ['machine', 'core'],
      defaultValue: const SystemMonitorConfig().cpuPercentMode.name,
    ),
    _ModuleSetting.toggle(
      SettingsCatalog.systemMonitorShowKernelThreads,
      defaultValue: const SystemMonitorConfig().showKernelThreads,
    ),
    _ModuleSetting.toggle(
      SettingsCatalog.systemMonitorConfirmKill,
      defaultValue: const SystemMonitorConfig().confirmKill,
    ),
  ]),
  _ModuleGroup('Network', [
    _ModuleSetting.number(
      SettingsCatalog.networkPollSeconds,
      defaultValue: const NetworkConfig().pollSeconds,
      isInt: true,
    ),
  ]),
  _ModuleGroup('Screenshot', [
    _ModuleSetting.text(
      SettingsCatalog.screenshotDirectory,
      addHint: '~/$kDefaultScreenshotDirectory',
    ),
    _ModuleSetting.toggle(
      SettingsCatalog.screenshotCopyToClipboard,
      defaultValue: const ScreenshotConfig().copyToClipboard,
    ),
    _ModuleSetting.number(
      SettingsCatalog.screenshotDelaySeconds,
      defaultValue: const ScreenshotConfig().delaySeconds,
      isInt: true,
    ),
    _ModuleSetting.toggle(
      SettingsCatalog.screenshotShowCursor,
      defaultValue: const ScreenshotConfig().showCursor,
    ),
  ]),
  _ModuleGroup('Screen recorder', [
    _ModuleSetting.text(
      SettingsCatalog.recorderDirectory,
      addHint: '~/$kDefaultRecordingDirectory',
    ),
    _ModuleSetting.segmented(
      SettingsCatalog.recorderContainer,
      options: kRecorderContainers,
      defaultValue: const RecorderConfig().container,
    ),
    _ModuleSetting.number(
      SettingsCatalog.recorderFps,
      defaultValue: const RecorderConfig().fps,
      isInt: true,
    ),
    // Lower is better and larger. Named as the encoder names it, because it is
    // handed to ffmpeg verbatim and a "quality: 8/10" scale invented here
    // would be a second thing to explain.
    _ModuleSetting.number(
      SettingsCatalog.recorderQuality,
      defaultValue: const RecorderConfig().quality,
      isInt: true,
    ),
    _ModuleSetting.toggle(
      SettingsCatalog.recorderShowCursor,
      defaultValue: const RecorderConfig().showCursor,
    ),
  ]),
];

/// Per-module options: every row is declared in [_moduleGroups] and rendered
/// by one loop.
class ModulesSection extends StatelessWidget {
  const ModulesSection({super.key, required this.store});

  final ConfigStore store;

  @override
  Widget build(BuildContext context) {
    return SliverSettingsSection(
      label: 'Modules',
      children: [
        for (final group in _moduleGroups) ...[
          SettingsSubLabel(group.label),
          for (final setting in group.settings)
            SettingsRow.field(
              setting.field,
              // The list editors are tall; their label sits at the top.
              alignTop: setting.kind == _Kind.stringList,
              control: _control(setting),
            ),
        ],
      ],
    );
  }

  /// The control for one row, subscribed to its own key.
  ///
  /// Every one is inside a [ConfigValue] rather than under a page-level
  /// `ListenableBuilder`: [ConfigStore] notifies on every `set`, so a digit typed
  /// into one number field used to rebuild all thirty-two rows. The controls that
  /// own a `TextEditingController` are wrapped too — the selector's `==` check
  /// means a notify that did not move *this* key does not reach them at all.
  Widget _control(_ModuleSetting setting) {
    final path = setting.path;
    switch (setting.kind) {
      case _Kind.toggle:
        return ConfigValue<bool>(
          store: store,
          path: path,
          fallback: setting.defaultValue as bool,
          builder: (context, value) => SettingsToggle(
            value: value!,
            onChanged: (v) => store.set(path, v),
          ),
        );
      case _Kind.number:
        return ConfigValue<num>(
          store: store,
          path: path,
          fallback: setting.defaultValue as num,
          builder: (context, value) => SettingsNumberField(
            value: value!,
            isInt: setting.isInt,
            onChanged: (v) => store.set(path, v),
          ),
        );
      case _Kind.segmented:
        return ConfigValue<String>(
          store: store,
          path: path,
          fallback: setting.defaultValue as String,
          builder: (context, value) => SettingsSegmented(
            options: setting.options!,
            value: value!,
            onChanged: (v) => store.set(path, v),
          ),
        );
      case _Kind.text:
        return ConfigValue<String>(
          store: store,
          path: path,
          fallback: '',
          builder: (context, value) => SettingsTextField(
            initial: value!,
            hint: setting.addHint,
            width: 220,
            onChanged: (value) => store.set(path, value),
          ),
        );
      case _Kind.stringList:
        // Selected as the list itself: `getList` mints a fresh `List<String>`
        // per call, and `List` has no value equality, so a bare selector would
        // report a change on every notify. The join is the signature, the way
        // `ConfigStore._restartSignature` and `DesktopStore` both do it.
        return StoreSelector<String>(
          listenable: store,
          selector: () => store.getList<String>(path).join('\u0000'),
          builder: (context, _) => SettingsStringListEditor(
            items: store.getList<String>(path),
            onChanged: (list) => store.set(path, list),
            addHint: setting.addHint,
          ),
        );
      case _Kind.weatherLocation:
        // Subscribes itself — it reads three keys and renders one label from
        // them, so the selector is on the label rather than on a key.
        return WeatherLocationField(store: store);
    }
  }
}
