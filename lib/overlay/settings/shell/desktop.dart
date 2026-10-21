import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/desktop/app_chooser.dart';
import 'package:moonswing/desktop/desktop_actions.dart';
import 'package:moonswing/desktop/desktop_layout.dart';
import 'package:moonswing/desktop/desktop_store.dart';
import 'package:moonswing/launcher/app_index.dart';
import 'package:moonswing/news/news_config.dart';
import 'package:moonswing/news/news_source.dart';
import 'package:moonswing/overlay/file_picker.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The Desktop category: grid geometry plus the list of pinned items.
///
/// Everything here is edited through [DesktopStore] rather than written to
/// [ConfigStore] directly, so the running grid and the file cannot drift.
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
  /// The rows hold `GAppInfo` pointers owned by [AppIndex], whose refresh unrefs
  /// the previous ones, so the index is pinned while the chooser is up.
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
    return SliverMainAxisGroup(
      slivers: [
        _grid(),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
        // Its own section, and outside the grid's builder: the news card's
        // feeds are `[news]`, which [DesktopStore] knows nothing about.
        NewsSettingsSection(store: widget.store),
      ],
    );
  }

  Widget _grid() {
    return ListenableBuilder(
      listenable: _desktop,
      builder: (context, _) {
        final config = _desktop.config;
        final items = _desktop.items;
        // One pass here rather than a `desktopItemExists` — a `File`/`Directory`
        // stat — inside every row's `build`. The rows rebuild whenever this
        // builder does, and a syscall per pinned item per build is a cost that
        // grows with what the user pinned.
        final missing = <String>{
          for (final item in items)
            if (!desktopItemExists(item)) item.target,
        };

        return SliverSettingsSection(
          label: 'Desktop Grid',
          children: [
            // Enabling the grid is what creates the background surface when
            // there is no wallpaper, and that surface is built at startup.
            SettingsRow.field(
              SettingsCatalog.desktopEnabled,
              info:
                  '${SettingsCatalog.desktopEnabled.description} Turning it on '
                  'or off takes effect after a restart when no wallpaper is '
                  'configured.',
              control: SettingsToggle(
                value: config.enabled,
                onChanged: (v) => _setGrid((c) => _copyDesktop(c, enabled: v)),
              ),
            ),
            SettingsRow.field(
              SettingsCatalog.desktopCellWidth,
              info:
                  '${SettingsCatalog.desktopCellWidth.description} The number '
                  'of columns and rows is derived from each monitor, so the '
                  'same icons fit displays of different sizes.',
              control: SettingsNumberField(
                value: config.cellWidth,
                isInt: true,
                onChanged: (v) =>
                    _setGrid((c) => _copyDesktop(c, cellWidth: v.toDouble())),
              ),
            ),
            SettingsRow.field(
              SettingsCatalog.desktopCellHeight,
              control: SettingsNumberField(
                value: config.cellHeight,
                isInt: true,
                onChanged: (v) =>
                    _setGrid((c) => _copyDesktop(c, cellHeight: v.toDouble())),
              ),
            ),
            SettingsRow.field(
              SettingsCatalog.desktopSpacing,
              control: SettingsNumberField(
                value: config.spacing,
                isInt: true,
                onChanged: (v) =>
                    _setGrid((c) => _copyDesktop(c, spacing: v.toDouble())),
              ),
            ),
            SettingsRow.field(
              SettingsCatalog.desktopPadding,
              control: SettingsNumberField(
                value: config.padding,
                isInt: true,
                onChanged: (v) =>
                    _setGrid((c) => _copyDesktop(c, padding: v.toDouble())),
              ),
            ),
            SettingsRow.field(
              SettingsCatalog.desktopIconSize,
              control: SettingsNumberField(
                value: config.iconSize,
                isInt: true,
                onChanged: (v) =>
                    _setGrid((c) => _copyDesktop(c, iconSize: v.toDouble())),
              ),
            ),
            SettingsRow.field(
              SettingsCatalog.desktopShowLabels,
              control: SettingsToggle(
                value: config.showLabels,
                onChanged: (v) =>
                    _setGrid((c) => _copyDesktop(c, showLabels: v)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SettingsSubLabel('Pinned items'),
            ),
            // Unordered: an item's place is its grid cell, which the desktop
            // itself is where to move, so these rows neither drag nor number.
            SettingsList(
              itemCount: items.length,
              emptyText: 'Nothing pinned yet.',
              removeTooltip: 'Unpin',
              onRemove: (i) => _desktop.removeItem(items[i].target),
              itemKey: (i) => ValueKey(items[i].target),
              iconBuilder: (context, i) => _DesktopItemIcon(item: items[i]),
              itemBuilder: (context, i) => _DesktopItemText(
                item: items[i],
                missing: missing.contains(items[i].target),
              ),
              // Two places a pin comes from, side by side as the last row.
              adder: Row(
                children: [
                  Expanded(
                    child: SettingsListAddRow(
                      label: 'Application…',
                      onTap: _addApplication,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SettingsListAddRow(
                      label: 'File or folder…',
                      onTap: _addFiles,
                    ),
                  ),
                ],
              ),
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

/// A pinned item's kind, as the leading icon of its row.
class _DesktopItemIcon extends StatelessWidget {
  const _DesktopItemIcon({required this.item});

  final DesktopItem item;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return FaIcon(
      switch (item.kind) {
        DesktopItemKind.app => FontAwesomeIcons.rocket,
        DesktopItemKind.folder => FontAwesomeIcons.solidFolder,
        DesktopItemKind.file => FontAwesomeIcons.file,
      },
      size: 13,
      color: theme.accentText,
    );
  }
}

/// A pinned item's label over its path.
class _DesktopItemText extends StatelessWidget {
  const _DesktopItemText({required this.item, required this.missing});

  final DesktopItem item;

  /// Whether the target is gone. Passed in rather than stat'd here: this row
  /// is one of however many the user has pinned, and `build` is not the place
  /// for a syscall.
  final bool missing;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
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
            color: missing ? kErrorColor : theme.muted,
          ),
        ),
      ],
    );
  }
}

/// The News widget's `[news]` table: which outlets it reads, and how often.
///
/// Presets are chips; a feed of the user's own is a URL in a list under them.
/// Both are the one `sources` key, so each control rewrites only its own half
/// of it and leaves the other's entries where they were.
class NewsSettingsSection extends StatelessWidget {
  const NewsSettingsSection({super.key, required this.store});

  final ConfigStore store;

  static const List<String> _sourcesPath = ['news', 'sources'];
  static const List<String> _refreshPath = ['news', 'refresh_minutes'];

  /// `sources` as the widget reads it — an absent key is the default pair,
  /// not an empty list — normalized the same way.
  List<String> _sources() =>
      NewsConfig.fromMap(store.get<Map<String, dynamic>>(const ['news'])).sources;

  @override
  Widget build(BuildContext context) {
    return SliverSettingsSection(
      label: 'News widget',
      children: [
        SettingsRow.field(
          SettingsCatalog.newsSources,
          alignTop: true,
          // Selected on a spelling of the list: a fresh `List` per read has no
          // value equality, so a bare selector would report a change on every
          // notify. The join is the signature, as on the Modules page.
          control: StoreSelector<String>(
            listenable: store,
            selector: () => _sources().join('\u0000'),
            builder: (context, _) {
              final sources = _sources();
              return SettingsChipToggles<String>(
                options: [for (final preset in kNewsPresets) preset.id],
                selected: sources.where((s) => newsPreset(s) != null).toSet(),
                labelOf: (id) => newsPreset(id)?.name ?? id,
                onChanged: (selected) => store.set(_sourcesPath, [
                  // Presets in the order Settings offers them, then every
                  // feed of the user's own exactly where it was.
                  for (final preset in kNewsPresets)
                    if (selected.contains(preset.id)) preset.id,
                  for (final s in sources)
                    if (newsPreset(s) == null) s,
                ]),
              );
            },
          ),
        ),
        StoreSelector<String>(
          listenable: store,
          selector: () => _sources().join('\u0000'),
          builder: (context, _) {
            final sources = _sources();
            return SettingsStringListEditor(
              label: 'Other feeds',
              addLabel: 'Add feed',
              addHint: 'https://example.com/rss.xml',
              emptyText: 'No feeds of your own.',
              iconOf: (_) => FaIcon(
                FontAwesomeIcons.rss,
                size: 12,
                color: ThemeScope.of(context).accentText,
              ),
              items: [
                for (final s in sources)
                  if (newsPreset(s) == null) s,
              ],
              onChanged: (custom) => store.set(_sourcesPath, [
                for (final s in sources)
                  if (newsPreset(s) != null) s,
                // A typed address that names no feed is kept out of the file
                // rather than written and silently ignored.
                for (final s in custom)
                  if (parseNewsSource(s) != null) s.trim(),
              ]),
            );
          },
        ),
        SettingsRow.field(
          SettingsCatalog.newsRefreshMinutes,
          control: ConfigValue<num>(
            store: store,
            path: _refreshPath,
            fallback: NewsConfig.defaultRefreshMinutes,
            builder: (context, value) => SettingsNumberField(
              value: value!,
              isInt: true,
              onChanged: (v) => store.set(
                _refreshPath,
                v.toInt().clamp(
                  NewsConfig.minRefreshMinutes,
                  NewsConfig.maxRefreshMinutes,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
