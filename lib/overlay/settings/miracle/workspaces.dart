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
      trailing: SettingsAddButton(
        label: 'Add workspace',
        onTap: () => store.editStructure((config) {
          // Numbered from the count rather than left blank: a configuration
          // with neither a number nor a name matches no workspace at all,
          // which miracle reports as a warning on the next load.
          final next = config.workspaceConfigs.length + 1;
          config.workspaceConfigs.add(WorkspaceConfig(number: next));
        }),
      ),
      children: [
        const SettingsHint(
          'Each entry configures one workspace. At least one of the number and '
          'the name has to be filled in, or miracle has nothing to match the '
          'entry to.',
        ),
        MiracleCollection(
          store: store,
          signature: _signature,
          builder: (context, config) {
            final workspaces = config.workspaceConfigs;
            if (workspaces.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SettingsHint('No workspaces are configured.'),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                for (var i = 0; i < workspaces.length; i++)
                  _WorkspaceCard(
                    key: ValueKey('workspace:${store.structureRevision}:$i'),
                    workspace: workspaces[i],
                    onChanged: (next) => _edit(i, next),
                    onMoveUp: i > 0 ? () => _move(i, -1) : null,
                    onMoveDown: i < workspaces.length - 1
                        ? () => _move(i, 1)
                        : null,
                    onRemove: () => store.editStructure(
                      (config) => config.workspaceConfigs.removeAt(i),
                    ),
                  ),
              ],
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

  void _move(int index, int delta) => store.editStructure((config) {
    final workspaces = config.workspaceConfigs;
    final target = index + delta;
    if (target < 0 || target >= workspaces.length) return;
    final moved = workspaces[index];
    workspaces[index] = workspaces[target];
    workspaces[target] = moved;
  });
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    super.key,
    required this.workspace,
    required this.onChanged,
    required this.onRemove,
    this.onMoveUp,
    this.onMoveDown,
  });

  final WorkspaceConfig workspace;
  final ValueChanged<WorkspaceConfig> onChanged;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// Digits only. The number is a `SettingsTextField` rather than a
  /// [SettingsNumberField] because both fields here have to be *clearable* —
  /// either one may legitimately be unset — and a number field cannot report an
  /// empty box, only the last number that was in it.
  static final List<TextInputFormatter> _digits = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return SettingsListRow(
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onRemove: onRemove,
      child: Row(
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
          SettingsTextField(
            width: 70,
            initial: workspace.number?.toString() ?? '',
            hint: 'any',
            inputFormatters: _digits,
            onChanged: (text) {
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
            child: SettingsTextField(
              initial: workspace.name ?? '',
              hint: 'unnamed',
              onChanged: (text) {
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
      ),
    );
  }
}

String _signature(MiracleConfig config) => [
  for (final workspace in config.workspaceConfigs)
    '${workspace.number ?? ''}|${workspace.name ?? ''}',
].join('\n');
