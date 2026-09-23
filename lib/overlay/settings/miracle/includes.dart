// Window Manager > Includes & Plugins: the other configuration files merged
// into this one, and the shared objects miracle loads at startup.
//
// Two ordered lists of paths, which is exactly what `SettingsStringListEditor`
// is — so this file is mostly the conversion between a `Plugin` and its path.

import 'package:flutter/widgets.dart';

import 'package:miracle/miracle.dart';

import 'package:moonswing/miracle_config/miracle_config_store.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/miracle/miracle_controls.dart';

class MiracleIncludesSection extends StatelessWidget {
  const MiracleIncludesSection({super.key, required this.store});

  final MiracleConfigStore store;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverSettingsSection(
          label: 'Included files',
          info:
              'Other configuration files merged into this one, in order. A '
              'later file wins where two of them set the same thing.',
          children: [
            MiracleCollection(
              store: store,
              signature: (config) => config.includes.join('\n'),
              builder: (context, config) => SettingsStringListEditor(
                items: List<String>.from(config.includes),
                addLabel: 'Add file',
                addHint: '~/.config/miracle-wm/bindings.yaml',
                width: null,
                onChanged: (next) => store.editStructure((config) {
                  final includes = config.includes;
                  includes.clear();
                  includes.addAll(next);
                }),
              ),
            ),
          ],
        ),
        SliverSettingsSection(
          label: 'Plugins',
          info:
              'Shared objects miracle loads at startup. Each is a path to a '
              '.so, or to a directory of them.',
          children: [
            MiracleCollection(
              store: store,
              signature: (config) =>
                  config.plugins.map((plugin) => plugin.path).join('\n'),
              builder: (context, config) => SettingsStringListEditor(
                items: [for (final plugin in config.plugins) plugin.path],
                addLabel: 'Add plugin',
                addHint: '/usr/lib/miracle-wm/plugins/example.so',
                width: null,
                onChanged: (next) => store.editStructure((config) {
                  final plugins = config.plugins;
                  plugins.clear();
                  plugins.addAll([
                    for (final path in next) Plugin(path: path),
                  ]);
                }),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
