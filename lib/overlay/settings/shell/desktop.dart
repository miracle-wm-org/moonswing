import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/desktop/app_chooser.dart';
import 'package:graceful_shell/desktop/desktop_actions.dart';
import 'package:graceful_shell/desktop/desktop_layout.dart';
import 'package:graceful_shell/desktop/desktop_store.dart';
import 'package:graceful_shell/launcher/app_index.dart';
import 'package:graceful_shell/overlay/file_picker.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';

/// The Desktop category: grid geometry plus the list of pinned items.
///
/// Everything here is edited through [DesktopStore] rather than written to
/// [ConfigStore] directly, so the running grid and the file cannot drift — the
/// store owns both the in-memory list and the write.
class DesktopSection extends StatefulWidget {
  const DesktopSection({super.key, required this.store});

  final ConfigStore store;

  @override
  State<DesktopSection> createState() => _DesktopSectionState();
}

class _DesktopSectionState extends State<DesktopSection> {
  DesktopStore get _desktop => DesktopStore.instance;

  void _setGrid(DesktopConfig Function(DesktopConfig) update) =>
      _desktop.setGrid(update(_desktop.config));

  /// The settings panel is not the desktop, so there is no live geometry to
  /// place against; a nominal grid is enough, because addItem only needs
  /// somewhere free and the desktop reflows anything out of range anyway.
  DesktopGridGeometry get _nominalGeometry =>
      computeGridGeometry(const Size(1920, 1080), _desktop.config);

  /// Picks an application from a searchable list of what is installed, rather
  /// than making the user find a `.desktop` file on disk.
  ///
  /// The rows hold `GAppInfo` pointers owned by [AppIndex], whose refresh
  /// unrefs the previous ones, so the index is pinned while the chooser is up —
  /// the contract `_openLauncher` follows.
  Future<void> _addApplication() async {
    AppIndex.instance.acquire();
    try {
      final app = await showAppChooser(
        context,
        apps: AppIndex.instance.searchable,
      );
      if (app == null || app.filename.isEmpty || !mounted) return;
      _desktop.addItem(
        DesktopItem(kind: DesktopItemKind.app, target: app.filename),
        _nominalGeometry,
      );
    } finally {
      AppIndex.instance.release();
    }
  }

  Future<void> _addFiles() async {
    final paths = await showFilePicker(
      context,
      filters: [FilePickerFilter.all],
      allowMultiple: true,
      allowDirectories: true,
    );
    if (paths == null || paths.isEmpty || !mounted) return;
    for (final path in paths) {
      _desktop.addItem(desktopItemForPath(path), _nominalGeometry);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _desktop,
      builder: (context, _) {
        final config = _desktop.config;
        final items = _desktop.items;

        return SettingsSection(
          label: 'Desktop',
          children: [
            SettingsRow(
              label: 'Show desktop icons',
              control: SettingsToggle(
                value: config.enabled,
                onChanged: (v) =>
                    _setGrid((c) => _copyDesktop(c, enabled: v)),
              ),
            ),
            // Enabling the grid is what creates the background surface when
            // there is no wallpaper, and that surface is built at startup.
            const SettingsHint(
              'Turning desktop icons on or off takes effect after a restart '
              'when no wallpaper is configured.',
            ),
            SettingsRow(
              label: 'Cell width',
              control: SettingsNumberField(
                value: config.cellWidth,
                isInt: true,
                onChanged: (v) => _setGrid(
                    (c) => _copyDesktop(c, cellWidth: v.toDouble())),
              ),
            ),
            SettingsRow(
              label: 'Cell height',
              control: SettingsNumberField(
                value: config.cellHeight,
                isInt: true,
                onChanged: (v) => _setGrid(
                    (c) => _copyDesktop(c, cellHeight: v.toDouble())),
              ),
            ),
            SettingsRow(
              label: 'Spacing',
              control: SettingsNumberField(
                value: config.spacing,
                isInt: true,
                onChanged: (v) =>
                    _setGrid((c) => _copyDesktop(c, spacing: v.toDouble())),
              ),
            ),
            SettingsRow(
              label: 'Edge padding',
              control: SettingsNumberField(
                value: config.padding,
                isInt: true,
                onChanged: (v) =>
                    _setGrid((c) => _copyDesktop(c, padding: v.toDouble())),
              ),
            ),
            SettingsRow(
              label: 'Icon size',
              control: SettingsNumberField(
                value: config.iconSize,
                isInt: true,
                onChanged: (v) =>
                    _setGrid((c) => _copyDesktop(c, iconSize: v.toDouble())),
              ),
            ),
            SettingsRow(
              label: 'Show labels',
              control: SettingsToggle(
                value: config.showLabels,
                onChanged: (v) =>
                    _setGrid((c) => _copyDesktop(c, showLabels: v)),
              ),
            ),
            const SettingsHint(
              'The number of columns and rows is derived from each monitor, so '
              'the same icons fit displays of different sizes.',
            ),
            SettingsSubLabel(
              'Pinned items',
              // Both adders sit on the heading, above the list rather than
              // below it: this list grows with every pin, and the buttons that
              // grow it were walking down the pane with it.
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsAddButton(
                    label: 'Application…',
                    onTap: _addApplication,
                  ),
                  const SizedBox(width: 8),
                  SettingsAddButton(
                    label: 'File or folder…',
                    onTap: _addFiles,
                  ),
                ],
              ),
            ),
            if (items.isEmpty)
              const SettingsHint('Nothing pinned yet.')
            else
              for (final item in items)
                _DesktopItemRow(
                  item: item,
                  onRemove: () => _desktop.removeItem(item.target),
                ),
          ],
        );
      },
    );
  }
}

/// [DesktopConfig] has no `copyWith` — it is a config type, parsed once from
/// TOML, and every other one in `config.dart` is the same. This is local to the
/// one place that edits fields individually.
DesktopConfig _copyDesktop(
  DesktopConfig c, {
  bool? enabled,
  double? cellWidth,
  double? cellHeight,
  double? spacing,
  double? padding,
  double? iconSize,
  bool? showLabels,
}) {
  return DesktopConfig(
    enabled: enabled ?? c.enabled,
    cellWidth: cellWidth ?? c.cellWidth,
    cellHeight: cellHeight ?? c.cellHeight,
    spacing: spacing ?? c.spacing,
    padding: padding ?? c.padding,
    iconSize: iconSize ?? c.iconSize,
    showLabels: showLabels ?? c.showLabels,
    items: c.items,
  );
}

/// One pinned item: its label, its path, and a remove button.
class _DesktopItemRow extends StatelessWidget {
  const _DesktopItemRow({required this.item, required this.onRemove});

  final DesktopItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final missing = !desktopItemExists(item);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: FaIcon(
              switch (item.kind) {
                DesktopItemKind.app => FontAwesomeIcons.rocket,
                DesktopItemKind.folder => FontAwesomeIcons.solidFolder,
                DesktopItemKind.file => FontAwesomeIcons.file,
              },
              size: 12,
              color: theme.accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  labelForItem(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground,
                  ),
                ),
                Text(
                  item.target,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: theme.fontFamily,
                    // A target that has gone missing is called out here rather
                    // than dropped, matching how the desktop dims it.
                    color: missing ? const Color(0xFFE06C75) : theme.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SettingsIconButton(
            icon: FontAwesomeIcons.trash,
            size: 12,
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}
