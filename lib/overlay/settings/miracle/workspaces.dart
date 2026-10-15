// Window Manager > Workspaces: the per-workspace settings, matched to a
// workspace by its number or by its name.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:miracle/miracle.dart';

import 'package:moonswing/miracle_config/miracle_config_store.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/miracle/miracle_controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

class MiracleWorkspacesSection extends StatelessWidget {
  const MiracleWorkspacesSection({super.key, required this.store});

  final MiracleConfigStore store;

  @override
  Widget build(BuildContext context) {
    return SliverSettingsSection(
      label: 'Workspaces',
      fillLast: true,
      info:
          'Each entry configures one workspace. At least one of the number and '
          'the name has to be filled in, or miracle has nothing to match the '
          'entry to.',
      children: [
        MiracleCollection(
          store: store,
          signature: _signature,
          builder: (context, config) {
            final workspaces = config.workspaceConfigs;
            return SettingsList(
              itemCount: workspaces.length,
              // The cards are fields; only the grip drags.
              handleOnly: true,
              itemKey: (i) =>
                  ValueKey('workspace:${store.structureRevision}:$i'),
              emptyText: 'No workspaces are configured.',
              onReorder: (from, to) => store.editStructure(
                (config) => reorderInPlace(config.workspaceConfigs, from, to),
              ),
              onRemove: (i) => store.editStructure(
                (config) => config.workspaceConfigs.removeAt(i),
              ),
              itemBuilder: (context, i) => _WorkspaceCard(
                workspace: workspaces[i],
                onChanged: (next) => _edit(i, next),
              ),
              adder: SettingsListAddRow(
                label: 'Add workspace',
                onTap: () => store.editStructure((config) {
                  // Numbered from the count rather than left blank: a
                  // configuration with neither a number nor a name matches no
                  // workspace at all, which miracle reports as a warning on
                  // the next load.
                  final next = config.workspaceConfigs.length + 1;
                  config.workspaceConfigs.add(WorkspaceConfig(number: next));
                }),
              ),
            );
          },
        ),
      ],
    );
  }

  void _edit(int index, WorkspaceConfig workspace) => store.edit((config) {
    final workspaces = config.workspaceConfigs;
    if (index >= workspaces.length) return;
    workspaces[index] = workspace;
  });
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({required this.workspace, required this.onChanged});

  final WorkspaceConfig workspace;
  final ValueChanged<WorkspaceConfig> onChanged;

  /// Digits only. The number is a [SettingsCommitField] rather than a
  /// [SettingsNumberField] because both fields here have to be *clearable* —
  /// either one may legitimately be unset — and a number field cannot report an
  /// empty box, only a number.
  static final List<TextInputFormatter> _digits = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Row(
      children: [
        Text(
          'Number',
          style: TextStyle(
            fontSize: ShellFontSizes.caption,
            fontFamily: theme.fontFamily,
            color: theme.popupForeground.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 6),
        SettingsCommitField(
          width: 70,
          initial: workspace.number?.toString() ?? '',
          hint: 'any',
          inputFormatters: _digits,
          onCommitted: (text) {
            final trimmed = text.trim();
            if (trimmed.isEmpty) {
              onChanged(workspace.copyWith(clearNumber: true));
              return;
            }
            final parsed = int.tryParse(trimmed);
            if (parsed != null) onChanged(workspace.copyWith(number: parsed));
          },
        ),
        const SizedBox(width: 12),
        Text(
          'Name',
          style: TextStyle(
            fontSize: ShellFontSizes.caption,
            fontFamily: theme.fontFamily,
            color: theme.popupForeground.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: SettingsCommitField(
            initial: workspace.name ?? '',
            hint: 'unnamed',
            onCommitted: (text) {
              final trimmed = text.trim();
              onChanged(
                trimmed.isEmpty
                    ? workspace.copyWith(clearName: true)
                    : workspace.copyWith(name: trimmed),
              );
            },
          ),
        ),
      ],
    );
  }
}

String _signature(MiracleConfig config) => [
  for (final workspace in config.workspaceConfigs)
    '${workspace.number ?? ''}|${workspace.name ?? ''}',
].join('\n');
