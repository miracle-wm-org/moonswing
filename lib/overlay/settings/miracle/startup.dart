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
          info:
              'Run once the compositor is ready for clients. moonswing '
              'itself is usually one of these.',
          children: [
            MiracleCollection(
              store: store,
              signature: _appsSignature,
              builder: (context, config) {
                final apps = config.startupApps;
                return SettingsList(
                  itemCount: apps.length,
                  // The cards are fields; only the grip drags.
                  handleOnly: true,
                  itemKey: (i) => ValueKey('app:${store.structureRevision}:$i'),
                  emptyText: 'Nothing is launched at startup.',
                  onReorder: (from, to) => store.editStructure(
                    (config) => reorderInPlace(config.startupApps, from, to),
                  ),
                  onRemove: (i) => store.editStructure(
                    (config) => config.startupApps.removeAt(i),
                  ),
                  itemBuilder: (context, i) => _AppCard(
                    app: apps[i],
                    onChanged: (next) => _editApp(i, next),
                  ),
                  adder: SettingsListAddRow(
                    label: 'Add application',
                    onTap: () => store.editStructure(
                      (config) =>
                          config.startupApps.add(const StartupApp(command: '')),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        SliverSettingsSection(
          label: 'Environment variables',
          fillLast: true,
          info:
              'Set for every application miracle launches, and for the '
              'compositor itself.',
          children: [
            MiracleCollection(
              store: store,
              signature: _variablesSignature,
              builder: (context, config) {
                final variables = config.environmentVariables;
                return SettingsList(
                  itemCount: variables.length,
                  handleOnly: true,
                  itemKey: (i) => ValueKey('env:${store.structureRevision}:$i'),
                  emptyText: 'No variables set.',
                  onReorder: (from, to) => store.editStructure(
                    (config) =>
                        reorderInPlace(config.environmentVariables, from, to),
                  ),
                  onRemove: (i) => store.editStructure(
                    (config) => config.environmentVariables.removeAt(i),
                  ),
                  itemBuilder: (context, i) => _VariableCard(
                    variable: variables[i],
                    onChanged: (next) => _editVariable(i, next),
                  ),
                  adder: SettingsListAddRow(
                    label: 'Add variable',
                    onTap: () => store.editStructure(
                      (config) => config.environmentVariables.add(
                        const EnvironmentVariable(key: '', value: ''),
                      ),
                    ),
                  ),
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

  void _editVariable(int index, EnvironmentVariable variable) =>
      store.edit((config) {
        final variables = config.environmentVariables;
        if (index >= variables.length) return;
        variables[index] = variable;
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
  const _AppCard({required this.app, required this.onChanged});

  final StartupApp app;
  final ValueChanged<StartupApp> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
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
    );
  }
}

class _VariableCard extends StatelessWidget {
  const _VariableCard({required this.variable, required this.onChanged});

  final EnvironmentVariable variable;
  final ValueChanged<EnvironmentVariable> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Row(
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
