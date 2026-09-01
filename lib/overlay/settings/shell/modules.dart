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
import 'package:graceful_shell/overlay/settings/shell/weather_location.dart';
import 'package:graceful_shell/system/system_monitor_config.dart'
    show SystemMonitorConfig;

/// Which control edits a module setting row.
enum _Kind { toggle, number, segmented, text, stringList, weatherLocation }

/// One `[modules.*]` row: its config path, its label, and which control edits
/// it.
///
/// [defaultValue] is read off the module's own const config object
/// (`const BatteryConfig().pollSeconds` and friends), so the fallback a
/// control shows when `config.toml` has no value is, by construction, the
/// value the module's `fromMap` would use — the two can never drift again.
class _ModuleSetting {
  const _ModuleSetting.toggle(
    this.path,
    this.label, {
    required bool this.defaultValue,
  }) : kind = _Kind.toggle,
       isInt = false,
       options = null,
       addHint = null;

  const _ModuleSetting.number(
    this.path,
    this.label, {
    required num this.defaultValue,
    required this.isInt,
  }) : kind = _Kind.number,
       options = null,
       addHint = null;

  const _ModuleSetting.segmented(
    this.path,
    this.label, {
    required List<String> this.options,
    required String this.defaultValue,
  }) : kind = _Kind.segmented,
       isInt = false,
       addHint = null;

  /// A free-typed string — a path, in the only two rows that use it.
  ///
  /// Deliberately not a file picker: these name a *directory to create*, and
  /// the picker browses what already exists, so the first recording into a
  /// folder that is not there yet could not be configured at all. The default
  /// is shown as the placeholder rather than written into the field, so
  /// clearing it goes back to the default instead of to nowhere.
  const _ModuleSetting.text(this.path, this.label, {this.addHint})
    : kind = _Kind.text,
      defaultValue = null,
      isInt = false,
      options = null;

  const _ModuleSetting.stringList(this.path, this.label, {this.addHint})
    : kind = _Kind.stringList,
      defaultValue = null,
      isInt = false,
      options = null;

  /// The weather location picker.
  ///
  /// The one row here whose control is not a value editor: a location is three
  /// config keys written together and the only thing that produces them is a
  /// geocoding lookup, so the control owns its own path list rather than taking
  /// one — see `weather_location.dart`.
  const _ModuleSetting.weatherLocation(this.label)
    : kind = _Kind.weatherLocation,
      path = const [],
      defaultValue = null,
      isInt = false,
      options = null,
      addHint = null;

  final List<String> path;
  final String label;
  final _Kind kind;

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
      const ['modules', 'workspaces', 'show_app_icons'],
      'Show app icons',
      defaultValue: const WorkspacesConfig().showAppIcons,
    ),
    _ModuleSetting.number(
      const ['modules', 'workspaces', 'icon_size'],
      'Icon size',
      defaultValue: const WorkspacesConfig().iconSize,
      isInt: true,
    ),
    _ModuleSetting.number(
      const ['modules', 'workspaces', 'max_icons'],
      'Max icons per workspace',
      defaultValue: const WorkspacesConfig().maxIcons,
      isInt: true,
    ),
    _ModuleSetting.toggle(
      const ['modules', 'workspaces', 'flash_urgent'],
      'Flash urgent workspaces',
      defaultValue: const WorkspacesConfig().flashUrgent,
    ),
    _ModuleSetting.number(
      const ['modules', 'workspaces', 'urgent_flash_seconds'],
      'Urgent flash period (seconds)',
      defaultValue: const WorkspacesConfig().urgentFlashSeconds,
      isInt: false,
    ),
  ]),
  _ModuleGroup('Weather', [
    const _ModuleSetting.weatherLocation('Location'),
    _ModuleSetting.segmented(
      const ['modules', 'weather', 'unit'],
      'Unit',
      options: const ['fahrenheit', 'celsius'],
      defaultValue: const WeatherConfig().unit,
    ),
    _ModuleSetting.number(
      const ['modules', 'weather', 'refresh_minutes'],
      'Refresh (minutes)',
      defaultValue: const WeatherConfig().refreshMinutes,
      isInt: true,
    ),
  ]),
  _ModuleGroup('Battery', [
    _ModuleSetting.number(
      const ['modules', 'battery', 'poll_seconds'],
      'Poll (seconds)',
      defaultValue: const BatteryConfig().pollSeconds,
      isInt: true,
    ),
  ]),
  _ModuleGroup('Clock', [
    _ModuleSetting.toggle(
      const ['modules', 'clock', 'show_date'],
      'Show date',
      defaultValue: const ClockConfig().showDate,
    ),
  ]),
  _ModuleGroup('Media player', [
    _ModuleSetting.number(
      const ['modules', 'media_player', 'max_text_width'],
      'Max text width',
      defaultValue: const MediaPlayerConfig().maxTextWidth,
      isInt: false,
    ),
  ]),
  _ModuleGroup('System tray', [
    _ModuleSetting.number(
      const ['modules', 'system_tray', 'icon_size'],
      'Icon size',
      defaultValue: const SystemTrayConfig().iconSize,
      isInt: false,
    ),
    _ModuleSetting.number(
      const ['modules', 'system_tray', 'collapsed_overlap'],
      'Collapsed overlap',
      defaultValue: const SystemTrayConfig().collapsedOverlap,
      isInt: false,
    ),
    _ModuleSetting.number(
      const ['modules', 'system_tray', 'expanded_spacing'],
      'Expanded spacing',
      defaultValue: const SystemTrayConfig().expandedSpacing,
      isInt: false,
    ),
    const _ModuleSetting.stringList(
      ['modules', 'system_tray', 'hidden_items'],
      'Hidden items',
      addHint: 'SNI id or title',
    ),
  ]),
  _ModuleGroup('Dock', [
    _ModuleSetting.number(
      const ['modules', 'dock', 'icon_size'],
      'Icon size',
      defaultValue: const DockConfig().iconSize,
      isInt: true,
    ),
    _ModuleSetting.toggle(
      const ['modules', 'dock', 'show_app_directory'],
      'Show app directory',
      defaultValue: const DockConfig().showAppDirectory,
    ),
    const _ModuleSetting.stringList(
      ['modules', 'dock', 'apps'],
      'Apps',
      addHint: 'app id',
    ),
  ]),
  _ModuleGroup('System monitor', [
    _ModuleSetting.number(
      const ['modules', 'system_monitor', 'poll_seconds'],
      'Poll (seconds)',
      defaultValue: const SystemMonitorConfig().pollSeconds,
      isInt: true,
    ),
    _ModuleSetting.segmented(
      const ['modules', 'system_monitor', 'temp_unit'],
      'Temperature unit',
      options: const ['celsius', 'fahrenheit'],
      defaultValue: const SystemMonitorConfig().tempUnit,
    ),
    _ModuleSetting.number(
      const ['modules', 'system_monitor', 'history_samples'],
      'Graph history (samples)',
      defaultValue: const SystemMonitorConfig().historySamples,
      isInt: true,
    ),
    // "machine" makes the process rows sum to the total CPU gauge; "core" is
    // top-style, where 100% is one saturated core.
    _ModuleSetting.segmented(
      const ['modules', 'system_monitor', 'cpu_percent_mode'],
      'CPU percentages',
      options: const ['machine', 'core'],
      defaultValue: const SystemMonitorConfig().cpuPercentMode.name,
    ),
    _ModuleSetting.toggle(
      const ['modules', 'system_monitor', 'show_kernel_threads'],
      'Show kernel threads',
      defaultValue: const SystemMonitorConfig().showKernelThreads,
    ),
    _ModuleSetting.toggle(
      const ['modules', 'system_monitor', 'confirm_kill'],
      'Confirm before quitting a process',
      defaultValue: const SystemMonitorConfig().confirmKill,
    ),
  ]),
  _ModuleGroup('Network', [
    _ModuleSetting.number(
      const ['modules', 'network', 'poll_seconds'],
      'Poll (seconds)',
      defaultValue: const NetworkConfig().pollSeconds,
      isInt: true,
    ),
  ]),
  _ModuleGroup('Screenshot', [
    const _ModuleSetting.text(
      ['modules', 'screenshot', 'directory'],
      'Save to',
      addHint: '~/$kDefaultScreenshotDirectory',
    ),
    _ModuleSetting.toggle(
      const ['modules', 'screenshot', 'copy_to_clipboard'],
      'Copy to clipboard',
      defaultValue: const ScreenshotConfig().copyToClipboard,
    ),
    _ModuleSetting.number(
      const ['modules', 'screenshot', 'delay_seconds'],
      'Delay (seconds)',
      defaultValue: const ScreenshotConfig().delaySeconds,
      isInt: true,
    ),
    _ModuleSetting.toggle(
      const ['modules', 'screenshot', 'show_cursor'],
      'Include the pointer',
      defaultValue: const ScreenshotConfig().showCursor,
    ),
  ]),
  _ModuleGroup('Screen recorder', [
    const _ModuleSetting.text(
      ['modules', 'screen_recorder', 'directory'],
      'Save to',
      addHint: '~/$kDefaultRecordingDirectory',
    ),
    _ModuleSetting.segmented(
      const ['modules', 'screen_recorder', 'container'],
      'Format',
      options: kRecorderContainers,
      defaultValue: const RecorderConfig().container,
    ),
    _ModuleSetting.number(
      const ['modules', 'screen_recorder', 'fps'],
      'Frames per second',
      defaultValue: const RecorderConfig().fps,
      isInt: true,
    ),
    // Lower is better and larger. Named as the encoder names it, because it is
    // handed to ffmpeg verbatim and a "quality: 8/10" scale invented here
    // would be a second thing to explain.
    _ModuleSetting.number(
      const ['modules', 'screen_recorder', 'quality'],
      'Quality (CRF, lower is better)',
      defaultValue: const RecorderConfig().quality,
      isInt: true,
    ),
    _ModuleSetting.toggle(
      const ['modules', 'screen_recorder', 'show_cursor'],
      'Include the pointer',
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
            SettingsRow(
              label: setting.label,
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
  /// Every one of these is inside a [ConfigValue] rather than under a
  /// page-level `ListenableBuilder`: [ConfigStore] notifies on every `set`, so
  /// a digit typed into one number field used to rebuild all thirty-two of
  /// these rows. The controls that own a `TextEditingController` and read their
  /// seed once are wrapped too — the selector's `==` check means a notify that
  /// did not move *this* key does not reach them at all, which is the cheapest
  /// possible answer and the one that cannot go stale.
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
