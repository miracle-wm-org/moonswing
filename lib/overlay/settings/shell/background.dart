import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/overlay/file_picker.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';

/// Visual wallpaper selector: a 3-column preview grid with multi-select, drag
/// reordering of the shown wallpapers, and a single global rotation interval.
///
/// The on-disk `[[background.entries]]` list is kept normalized (shown
/// wallpapers first in presentation order, then hidden ones) and pruned of any
/// entry whose path is empty, non-image, or missing on disk.
class BackgroundSection extends StatefulWidget {
  const BackgroundSection({super.key, required this.store});

  final ConfigStore store;

  @override
  State<BackgroundSection> createState() => _BackgroundSectionState();
}

class _BackgroundSectionState extends State<BackgroundSection> {
  ConfigStore get store => widget.store;

  List<Map> _rawEntries() =>
      (store.get<List>(['background', 'entries']) ?? const [])
          .whereType<Map>()
          .toList();

  /// Drops invalid entries (empty / non-image / missing on disk), strips the
  /// obsolete `time` key, and orders shown wallpapers before hidden ones — the
  /// canonical presentation order the running shell rotates through.
  List<Map<String, dynamic>> _normalize(List<Map> raw) {
    final valid = <Map<String, dynamic>>[];
    for (final e in raw) {
      final path = '${e['path'] ?? ''}'.trim();
      if (path.isEmpty || !isImagePath(path) || !File(path).existsSync()) {
        continue;
      }
      valid.add({'path': path, 'shown': e['shown'] as bool? ?? true});
    }
    final shown = valid.where((e) => e['shown'] == true).toList();
    final hidden = valid.where((e) => e['shown'] != true).toList();
    return [...shown, ...hidden];
  }

  bool _matches(List<Map> raw, List<Map<String, dynamic>> normalized) {
    if (raw.length != normalized.length) return false;
    for (var i = 0; i < raw.length; i++) {
      if ('${raw[i]['path'] ?? ''}'.trim() != normalized[i]['path']) {
        return false;
      }
      if ((raw[i]['shown'] as bool? ?? true) != normalized[i]['shown']) {
        return false;
      }
    }
    return true;
  }

  void _setShown(String path, bool shown) {
    final list = _normalize(_rawEntries());
    final idx = list.indexWhere((e) => e['path'] == path);
    if (idx < 0) return;
    list[idx] = {'path': path, 'shown': shown};
    store.set(['background', 'entries'], _normalize(list));
  }

  void _reorderShown(int oldIndex, int newIndex) {
    final list = _normalize(_rawEntries());
    final shown = list.where((e) => e['shown'] == true).toList();
    final hidden = list.where((e) => e['shown'] != true).toList();
    if (oldIndex < 0 || oldIndex >= shown.length) return;
    final item = shown.removeAt(oldIndex);
    var insertAt = oldIndex < newIndex ? newIndex - 1 : newIndex;
    insertAt = insertAt.clamp(0, shown.length);
    shown.insert(insertAt, item);
    store.set(['background', 'entries'], [...shown, ...hidden]);
  }

  Future<void> _addWallpapers() async {
    final paths = await showFilePicker(
      context,
      filters: [FilePickerFilter.images, FilePickerFilter.all],
      allowMultiple: true,
    );
    if (paths == null || paths.isEmpty) return;
    final list = _normalize(_rawEntries());
    final existing = list.map((e) => e['path']).toSet();
    for (final p in paths) {
      if (isImagePath(p) && existing.add(p)) {
        list.add({'path': p, 'shown': true});
      }
    }
    store.set(['background', 'entries'], _normalize(list));
  }

  @override
  Widget build(BuildContext context) {
    final raw = _rawEntries();
    final entries = _normalize(raw);
    // Persist the auto-prune / normalization once, after this frame, if it
    // changed anything — never mutate the store during build.
    if (!_matches(raw, entries)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) store.set(['background', 'entries'], entries);
      });
    }
    final shown = entries.where((e) => e['shown'] == true).toList();
    final hidden = entries.where((e) => e['shown'] != true).toList();

    return SettingsSection(
      label: 'Background',
      children: [
        SettingsRow(
          label: 'Fit',
          control: SettingsSegmented(
            options: const ['fill', 'contain', 'natural'],
            value: store.get<String>(['background', 'fit']) ?? 'fill',
            onChanged: (v) => store.set(['background', 'fit'], v),
          ),
        ),
        SettingsRow(
          label: 'Rotation interval (minutes)',
          control: SettingsNumberField(
            value: store.get<num>(['background', 'interval_minutes']) ?? 5,
            isInt: true,
            onChanged: (v) => store.set(['background', 'interval_minutes'],
                v.toInt() < 1 ? 1 : v.toInt()),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: SettingsHint(
              'Selected wallpapers rotate on this interval, in order.'),
        ),
        SettingsSubLabel('Shown'),
        if (shown.isEmpty)
          const SettingsHint(
              'No wallpapers selected. Select one from Available below.')
        else
          _WallpaperGrid(
            entries: shown,
            selected: true,
            onToggle: (p) => _setShown(p, false),
            onReorder: _reorderShown,
          ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SettingsAddButton(label: 'Add wallpaper', onTap: _addWallpapers),
        ),
        SettingsSubLabel('Available'),
        if (hidden.isEmpty)
          const SettingsHint('No hidden wallpapers.')
        else
          _WallpaperGrid(
            entries: hidden,
            selected: false,
            onToggle: (p) => _setShown(p, true),
          ),
      ],
    );
  }
}

/// A responsive 3-column grid of [_WallpaperTile]s. When [onReorder] is given
/// (the "shown" group) each tile is draggable and accepts drops to reorder.
class _WallpaperGrid extends StatelessWidget {
  const _WallpaperGrid({
    required this.entries,
    required this.selected,
    required this.onToggle,
    this.onReorder,
  });

  final List<Map<String, dynamic>> entries;
  final bool selected;
  final void Function(String path) onToggle;
  final void Function(int oldIndex, int newIndex)? onReorder;

  @override
  Widget build(BuildContext context) {
    const columns = 3;
    const gap = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileW = (constraints.maxWidth - gap * (columns - 1)) / columns;
        final tileH = tileW * 0.6;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < entries.length; i++)
              SizedBox(
                width: tileW,
                height: tileH,
                child: _cell(context, i, tileW, tileH),
              ),
          ],
        );
      },
    );
  }

  Widget _cell(BuildContext context, int index, double w, double h) {
    final path = entries[index]['path'] as String;
    final tile = _WallpaperTile(
      path: path,
      selected: selected,
      onTap: () => onToggle(path),
    );
    if (onReorder == null) return tile;
    final theme = ThemeScope.of(context);
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onAcceptWithDetails: (d) => onReorder!(d.data, index),
      builder: (context, candidate, rejected) {
        final isTarget = candidate.isNotEmpty;
        return Draggable<int>(
          data: index,
          feedback: SizedBox(
            width: w,
            height: h,
            child: Opacity(
              opacity: 0.9,
              child: _WallpaperTile(
                path: path,
                selected: true,
                onTap: () {},
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: tile),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: isTarget
                  ? Border.all(color: theme.accent, width: 2)
                  : null,
            ),
            child: tile,
          ),
        );
      },
    );
  }
}

/// A single wallpaper preview cell. Renders the image cover-cropped with a
/// selection border + check badge, mirroring [SettingsOptionButton]'s selected
/// styling.
class _WallpaperTile extends StatefulWidget {
  const _WallpaperTile({
    required this.path,
    required this.selected,
    required this.onTap,
  });

  final String path;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_WallpaperTile> createState() => _WallpaperTileState();
}

class _WallpaperTileState extends State<_WallpaperTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(widget.path),
                fit: BoxFit.cover,
                cacheWidth: 320,
                gaplessPlayback: true,
                errorBuilder: (c, e, s) =>
                    ColoredBox(color: theme.controlSurface),
              ),
              if (!widget.selected && !_hovered)
                const ColoredBox(color: Color(0x33000000)),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: widget.selected
                        ? theme.accent
                        : (_hovered ? theme.surfaceHover : theme.divider),
                    width: widget.selected ? 2 : 1,
                  ),
                ),
              ),
              if (widget.selected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: theme.accent,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const FaIcon(
                      FontAwesomeIcons.check,
                      size: 10,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
