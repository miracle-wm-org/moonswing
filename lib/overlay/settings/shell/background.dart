import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/overlay/file_picker.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/wallpaper_catalog.dart';

/// Visual wallpaper selector: a 3-column preview grid with multi-select, drag
/// reordering of the shown wallpapers, and a single global rotation interval.
///
/// The list has two sources, and which one a wallpaper came from is the only
/// thing that distinguishes two tiles:
///
/// - The on-disk `[[background.entries]]` list — what the user picked. It is
///   kept normalized (shown wallpapers first in presentation order, then
///   hidden ones) and pruned of any entry whose path is empty, non-image, or
///   missing on disk.
/// - [SystemWallpaperCatalog] — what the distribution installed. These are
///   discovered on every visit and **never written to the config**, which is
///   what makes them permanent: the tile carries no remove button, and hiding
///   one drops the entry the selection created rather than leaving a hidden
///   entry behind, so the wallpaper simply returns to Available. See the
///   catalogue's own doc comment for why the alternative — seeding the paths
///   into `[[background.entries]]` at first run — is worse.
///
/// Removal therefore exists for user-added wallpapers only. It has to exist:
/// with the machine's own wallpapers in the list, "hidden" is no longer a
/// synonym for "gone", and a mistaken pick from the file picker would otherwise
/// sit in Available forever.
class BackgroundSection extends StatefulWidget {
  const BackgroundSection({super.key, required this.store, this.catalog});

  final ConfigStore store;

  /// The installed-wallpaper source. Injectable so widget tests point it at a
  /// temp directory instead of walking the machine's real `/usr/share`.
  final SystemWallpaperCatalog? catalog;

  @override
  State<BackgroundSection> createState() => _BackgroundSectionState();
}

class _BackgroundSectionState extends State<BackgroundSection> {
  ConfigStore get store => widget.store;

  /// Paths from [SystemWallpaperCatalog], in presentation order, and the same
  /// set for membership tests. Empty until the walk lands (and on a machine
  /// that ships no wallpapers at all), which renders as the page did before
  /// this existed.
  List<String> _system = const [];
  Set<String> _systemPaths = const {};
  bool _loadingSystem = true;

  @override
  void initState() {
    super.initState();
    // The future is memoised by the catalogue, so re-entering this page does
    // not re-walk the disk. `list()` never throws.
    (widget.catalog ?? SystemWallpaperCatalog.instance).list().then((paths) {
      if (!mounted) return;
      setState(() {
        _system = paths;
        _systemPaths = paths.toSet();
        _loadingSystem = false;
      });
    });
  }

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

  /// Puts [path] into the rotation, adding the entry when the wallpaper came
  /// from the catalogue and so had none.
  void _show(String path) {
    final list = _normalize(_rawEntries());
    final idx = list.indexWhere((e) => e['path'] == path);
    if (idx < 0) {
      list.add({'path': path, 'shown': true});
    } else {
      list[idx] = {'path': path, 'shown': true};
    }
    store.set(['background', 'entries'], _normalize(list));
  }

  /// Takes [path] out of the rotation.
  ///
  /// A catalogue wallpaper's entry is dropped rather than flipped to
  /// `shown = false`: it is listed in Available either way, and keeping a
  /// hidden entry would show it twice and write a path into the config that
  /// the user cannot delete.
  void _hide(String path) {
    final list = _normalize(_rawEntries());
    final idx = list.indexWhere((e) => e['path'] == path);
    if (idx < 0) return;
    if (_systemPaths.contains(path)) {
      list.removeAt(idx);
    } else {
      list[idx] = {'path': path, 'shown': false};
    }
    store.set(['background', 'entries'], _normalize(list));
  }

  /// Drops a user-added wallpaper from the list entirely. Never offered for a
  /// catalogue wallpaper — there is no entry behind it to delete, and it would
  /// reappear on the next build.
  void _remove(String path) {
    final list = _normalize(_rawEntries())
      ..removeWhere((e) => e['path'] == path);
    store.set(['background', 'entries'], list);
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
    final configured = entries.map((e) => e['path'] as String).toSet();
    final shown = [
      for (final e in entries.where((e) => e['shown'] == true))
        _WallpaperRef(e['path'] as String, _systemPaths),
    ];
    // Hidden picks first — they are what the user last had in the rotation —
    // then everything the machine ships that is not already in the config.
    final available = [
      for (final e in entries.where((e) => e['shown'] != true))
        _WallpaperRef(e['path'] as String, _systemPaths),
      for (final p in _system)
        if (!configured.contains(p)) _WallpaperRef(p, _systemPaths),
    ];

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
        SettingsSubLabel(
          'Shown',
          // On the heading rather than under the grid: the grid is the tallest
          // thing on this page, and a button below it is a button the user has
          // to scroll past every tile to reach.
          trailing:
              SettingsAddButton(label: 'Add wallpaper', onTap: _addWallpapers),
        ),
        if (shown.isEmpty)
          const SettingsHint(
              'No wallpapers selected. Select one from Available below.')
        else
          _WallpaperGrid(
            entries: shown,
            selected: true,
            onToggle: _hide,
            onRemove: _remove,
            onReorder: _reorderShown,
          ),
        SettingsSubLabel('Available'),
        const SettingsHint(
            'Wallpapers installed on this system are always listed here. Only '
            'the ones you added yourself can be removed.'),
        if (available.isEmpty)
          _loadingSystem
              ? const _LookingForWallpapers()
              : const SettingsHint('No other wallpapers found.')
        else
          _WallpaperGrid(
            entries: available,
            selected: false,
            onToggle: _show,
            onRemove: _remove,
          ),
        if (available.isNotEmpty && _loadingSystem)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: _LookingForWallpapers(),
          ),
      ],
    );
  }
}

/// One tile's worth of wallpaper: where it is, and whether the user is allowed
/// to drop it from the list.
///
/// A wallpaper the distribution installed is never removable, however it got
/// into the config — picking one through the file picker does not make it the
/// user's to delete, because it would come straight back from the catalogue.
class _WallpaperRef {
  _WallpaperRef(this.path, Set<String> systemPaths)
      : removable = !systemPaths.contains(path);

  final String path;
  final bool removable;
}

/// The "still walking `/usr/share`" line under the Available grid.
class _LookingForWallpapers extends StatelessWidget {
  const _LookingForWallpapers();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        LoadingIndicator(size: 12),
        SizedBox(width: 8),
        Flexible(child: SettingsHint('Looking for installed wallpapers…')),
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
    required this.onRemove,
    this.onReorder,
  });

  final List<_WallpaperRef> entries;
  final bool selected;
  final void Function(String path) onToggle;
  final void Function(String path) onRemove;
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
                // Keyed on the path so a reorder moves the tile's element
                // rather than repainting every tile after it — and so a test
                // can find one wallpaper among identical previews.
                key: ValueKey(entries[i].path),
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
    final entry = entries[index];
    final path = entry.path;
    final tile = _WallpaperTile(
      path: path,
      selected: selected,
      onTap: () => onToggle(path),
      onRemove: entry.removable ? () => onRemove(path) : null,
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
              border:
                  isTarget ? Border.all(color: theme.accent, width: 2) : null,
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
///
/// [onRemove] is null for a wallpaper the machine ships, which is the whole of
/// "system wallpapers cannot be deleted" as far as this widget is concerned:
/// no button is drawn, so there is nothing to click.
class _WallpaperTile extends StatelessWidget {
  const _WallpaperTile({
    required this.path,
    required this.selected,
    required this.onTap,
    this.onRemove,
  });

  final String path;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(path),
              fit: BoxFit.cover,
              cacheWidth: 320,
              gaplessPlayback: true,
              errorBuilder: (c, e, s) =>
                  ColoredBox(color: theme.controlSurface),
            ),
            if (!selected && !hovered)
              const ColoredBox(color: Color(0x33000000)),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? theme.accent
                      : (hovered ? theme.surfaceHover : theme.divider),
                  width: selected ? 2 : 1,
                ),
              ),
            ),
            if (selected)
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
            // Bottom-left, so it never lands under the selection badge, and
            // only while the pointer is on the tile — a grid of delete
            // buttons reads as a grid of delete buttons.
            if (onRemove != null && hovered)
              Positioned(
                left: 6,
                bottom: 6,
                child: _RemoveBadge(onTap: onRemove!),
              ),
          ],
        ),
      ),
    );
  }
}


/// The hover-revealed "drop this wallpaper from the list" button.
class _RemoveBadge extends StatefulWidget {
  const _RemoveBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_RemoveBadge> createState() => _RemoveBadgeState();
}

class _RemoveBadgeState extends State<_RemoveBadge> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        // The tile's own onTap would otherwise toggle the wallpaper as well.
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: _hovered ? kErrorColor : const Color(0xCC000000),
            shape: BoxShape.circle,
            border: Border.all(color: theme.divider.withValues(alpha: 0.6)),
          ),
          alignment: Alignment.center,
          child: const FaIcon(
            FontAwesomeIcons.xmark,
            size: 10,
            color: Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
  }
}
