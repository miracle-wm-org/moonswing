import 'package:flutter/widgets.dart';

import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/modules/battery.dart' show BatteryConfig;
import 'package:graceful_shell/modules/clock.dart' show ClockConfig;
import 'package:graceful_shell/modules/dock.dart' show DockConfig;
import 'package:graceful_shell/modules/media_player.dart' show MediaPlayerConfig;
import 'package:graceful_shell/modules/network.dart' show NetworkConfig;
import 'package:graceful_shell/modules/system_tray.dart' show SystemTrayConfig;
import 'package:graceful_shell/modules/weather.dart' show WeatherConfig;
import 'package:graceful_shell/modules/workspaces.dart' show WorkspacesConfig;
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/system/system_monitor_config.dart'
    show SystemMonitorConfig;

/// Which control edits a module setting row.
enum _Kind { toggle, number, segmented, stringList }

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
  })  : kind = _Kind.toggle,
        isInt = false,
        options = null,
        addHint = null;

  const _ModuleSetting.number(
    this.path,
    this.label, {
    required num this.defaultValue,
    required this.isInt,
  })  : kind = _Kind.number,
        options = null,
        addHint = null;

  const _ModuleSetting.segmented(
    this.path,
    this.label, {
    required List<String> this.options,
    required String this.defaultValue,
  })  : kind = _Kind.segmented,
        isInt = false,
        addHint = null;

  const _ModuleSetting.stringList(
    this.path,
    this.label, {
    this.addHint,
  })  : kind = _Kind.stringList,
        defaultValue = null,
        isInt = false,
        options = null;

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

  /// Placeholder for a [_Kind.stringList] row's free-form adder.
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
  ]),
  _ModuleGroup('Weather', [
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
];

/// Per-module options: every row is declared in [_moduleGroups] and rendered
/// by one loop.
class ModulesSection extends StatelessWidget {
  const ModulesSection({super.key, required this.store});

  final ConfigStore store;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
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

  Widget _control(_ModuleSetting setting) {
    final path = setting.path;
    switch (setting.kind) {
      case _Kind.toggle:
        return SettingsToggle(
          value: store.get<bool>(path) ?? setting.defaultValue as bool,
          onChanged: (v) => store.set(path, v),
        );
      case _Kind.number:
        return SettingsNumberField(
          value: store.get<num>(path) ?? setting.defaultValue as num,
          isInt: setting.isInt,
          onChanged: (v) => store.set(path, v),
        );
      case _Kind.segmented:
        return SettingsSegmented(
          options: setting.options!,
          value: store.get<String>(path) ?? setting.defaultValue as String,
          onChanged: (v) => store.set(path, v),
        );
      case _Kind.stringList:
        return SettingsStringListEditor(
          items: store.getList<String>(path),
          onChanged: (list) => store.set(path, list),
          addHint: setting.addHint,
        );
    }
  }
}
