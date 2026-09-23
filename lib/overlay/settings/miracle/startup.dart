// Window Manager > Startup: the programs miracle launches once the compositor
// is up, and the environment it launches them into.

import 'package:flutter/widgets.dart';

import 'package:miracle/miracle.dart';

import 'package:moonswing/miracle_config/miracle_config_store.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/miracle/miracle_controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

class MiracleStartupSection extends StatelessWidget {
  const MiracleStartupSection({super.key, required this.store});

  final MiracleConfigStore store;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverSettingsSection(
          label: 'Startup applications',
          trailing: SettingsAddButton(
            label: 'Add application',
            onTap: () => store.editStructure(
              (config) => config.startupApps.add(const StartupApp(command: '')),
            ),
          ),
          info:
              'Run once the compositor is ready for clients. moonswing '
              'itself is usually one of these.',
          children: [
            MiracleCollection(
              store: store,
              signature: _appsSignature,
              builder: (context, config) {
                final apps = config.startupApps;
                if (apps.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: SettingsHint('Nothing is launched at startup.'),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    for (var i = 0; i < apps.length; i++)
                      _AppCard(
                        key: ValueKey('app:${store.structureRevision}:$i'),
                        app: apps[i],
                        onChanged: (next) => _editApp(i, next),
                        onMoveUp: i > 0 ? () => _moveApp(i, -1) : null,
                        onMoveDown: i < apps.length - 1
                            ? () => _moveApp(i, 1)
                            : null,
                        onRemove: () => store.editStructure(
                          (config) => config.startupApps.removeAt(i),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
        SliverSettingsSection(
          label: 'Environment variables',
          trailing: SettingsAddButton(
            label: 'Add variable',
            onTap: () => store.editStructure(
              (config) => config.environmentVariables.add(
                const EnvironmentVariable(key: '', value: ''),
              ),
            ),
          ),
          info:
              'Set for every application miracle launches, and for the '
              'compositor itself.',
          children: [
            MiracleCollection(
              store: store,
              signature: _variablesSignature,
              builder: (context, config) {
                final variables = config.environmentVariables;
                if (variables.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: SettingsHint('No variables set.'),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    for (var i = 0; i < variables.length; i++)
                      _VariableCard(
                        key: ValueKey('env:${store.structureRevision}:$i'),
                        variable: variables[i],
                        onChanged: (next) => _editVariable(i, next),
                        onMoveUp: i > 0 ? () => _moveVariable(i, -1) : null,
                        onMoveDown: i < variables.length - 1
                            ? () => _moveVariable(i, 1)
                            : null,
                        onRemove: () => store.editStructure(
                          (config) => config.environmentVariables.removeAt(i),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  void _editApp(int index, StartupApp app) => store.edit((config) {
    final apps = config.startupApps;
    if (index >= apps.length) return;
    apps[index] = app;
  });

  void _moveApp(int index, int delta) => store.editStructure((config) {
    final apps = config.startupApps;
    final target = index + delta;
    if (target < 0 || target >= apps.length) return;
    final moved = apps[index];
    apps[index] = apps[target];
    apps[target] = moved;
  });

  void _editVariable(int index, EnvironmentVariable variable) =>
      store.edit((config) {
        final variables = config.environmentVariables;
        if (index >= variables.length) return;
        variables[index] = variable;
      });

  void _moveVariable(int index, int delta) => store.editStructure((config) {
    final variables = config.environmentVariables;
    final target = index + delta;
    if (target < 0 || target >= variables.length) return;
    final moved = variables[index];
    variables[index] = variables[target];
    variables[target] = moved;
  });
}

/// The four booleans on a startup entry: the label, the reader, the writer.
typedef _AppFlag = (
  String label,
  bool Function(StartupApp app) read,
  StartupApp Function(StartupApp app, bool value) write,
);

const List<_AppFlag> _kAppFlags = [
  ('Restart if it exits', _restartOnDeath, _setRestartOnDeath),
  ('Quit miracle if it exits', _haltOnDeath, _setHaltOnDeath),
  ('No startup id', _noStartupId, _setNoStartupId),
  ('In a systemd scope', _inSystemdScope, _setInSystemdScope),
];

bool _restartOnDeath(StartupApp app) => app.restartOnDeath;
bool _haltOnDeath(StartupApp app) => app.shouldHaltCompositorOnDeath;
bool _noStartupId(StartupApp app) => app.noStartupId;
bool _inSystemdScope(StartupApp app) => app.inSystemdScope;

StartupApp _setRestartOnDeath(StartupApp app, bool value) =>
    app.copyWith(restartOnDeath: value);
StartupApp _setHaltOnDeath(StartupApp app, bool value) =>
    app.copyWith(shouldHaltCompositorOnDeath: value);
StartupApp _setNoStartupId(StartupApp app, bool value) =>
    app.copyWith(noStartupId: value);
StartupApp _setInSystemdScope(StartupApp app, bool value) =>
    app.copyWith(inSystemdScope: value);

class _AppCard extends StatelessWidget {
  const _AppCard({
    super.key,
    required this.app,
    required this.onChanged,
    required this.onRemove,
    this.onMoveUp,
    this.onMoveDown,
  });

  final StartupApp app;
  final ValueChanged<StartupApp> onChanged;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    return SettingsListRow(
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onRemove: onRemove,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsCommitField(
            initial: app.command,
            hint: 'e.g. nm-applet',
            onCommitted: (text) => onChanged(app.copyWith(command: text)),
          ),
          const SizedBox(height: 6),
          // Pills rather than four labelled [SettingsToggle] rows: toggles
          // inside a list row make a card taller than the viewport by the
          // third application. These are the same pills a multiple choice is
          // drawn with everywhere else in this pane.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (label, read, write) in _kAppFlags)
                SettingsOptionButton(
                  label: label,
                  selected: read(app),
                  onTap: () => onChanged(write(app, !read(app))),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VariableCard extends StatelessWidget {
  const _VariableCard({
    super.key,
    required this.variable,
    required this.onChanged,
    required this.onRemove,
    this.onMoveUp,
    this.onMoveDown,
  });

  final EnvironmentVariable variable;
  final ValueChanged<EnvironmentVariable> onChanged;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return SettingsListRow(
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onRemove: onRemove,
      child: Row(
        children: [
          Expanded(
            child: SettingsCommitField(
              initial: variable.key,
              hint: 'NAME',
              onCommitted: (text) => onChanged(variable.copyWith(key: text)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '=',
              style: TextStyle(
                fontSize: ShellFontSizes.body,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(
            child: SettingsCommitField(
              initial: variable.value,
              hint: 'value',
              onCommitted: (text) => onChanged(variable.copyWith(value: text)),
            ),
          ),
        ],
      ),
    );
  }
}

String _appsSignature(MiracleConfig config) => [
  for (final app in config.startupApps)
    '${app.command}|${app.restartOnDeath}|${app.noStartupId}|'
        '${app.shouldHaltCompositorOnDeath}|${app.inSystemdScope}',
].join('\n');

String _variablesSignature(MiracleConfig config) => [
  for (final variable in config.environmentVariables)
    '${variable.key}=${variable.value}',
].join('\n');
