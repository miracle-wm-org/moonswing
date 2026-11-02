import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/file_picker.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_wallpaper.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/wallpaper_catalog.dart';

/// The grid key of the "Theme default" tile, standing in for the path every
/// other tile is keyed on. Not a path — every real one is absolute — so the two
/// cannot collide.
@visibleForTesting
const String kThemeWallpaperKey = 'theme-default';

/// Visual wallpaper selector: a 3-column preview grid with multi-select, drag
/// reordering of the shown wallpapers, and a single global rotation interval.
///
/// The list has two sources, and which one a wallpaper came from is the only
/// thing distinguishing two tiles:
///
/// - The on-disk `[[background.entries]]` list — what the user picked. Kept
///   normalized (shown first, then hidden) and pruned of any entry whose path is
///   empty, non-image, or missing on disk.
/// - [SystemWallpaperCatalog] — what the distribution installed. Discovered on
///   every visit and **never written to the config**, which is what makes them
///   permanent: the tile carries no remove button, and hiding one drops the entry
///   the selection created rather than leaving a hidden one behind.
///
/// Removal therefore exists for user-added wallpapers only, and has to: with the
/// machine's own wallpapers in the list "hidden" is no longer a synonym for
/// "gone", and a mistaken pick would otherwise sit in Available forever.
///
/// One tile is neither: **Theme default**, always the first one offered. It is
/// a `theme = true` entry rather than a path, drawn as whatever the *active*
/// theme's `wallpaper` is — empty when the theme has none — so with it shown,
/// switching theme switches the wallpaper. Like a catalogue tile it cannot be
/// removed, and deselecting it drops its entry; selecting it puts it at the
/// front of the rotation.
class BackgroundSection extends StatefulWidget {
  const BackgroundSection({
    super.key,
    required this.store,
    this.catalog,
    this.themeWallpaperOf = resolveThemeWallpaper,
  });

  final ConfigStore store;

  /// The installed-wallpaper source. Injectable so widget tests point it at a
  /// temp directory instead of walking the machine's real `/usr/share`.
  final SystemWallpaperCatalog? catalog;

  /// Turns the active theme into its wallpaper's file, for the Theme default
  /// tile's preview. Injectable so tests need no installed wallpapers.
  final String? Function(ThemeConfig theme) themeWallpaperOf;

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

  /// Paths this section has already stat'd, and what `existsSync` answered.
  ///
  /// `_normalize` runs from `build` and a stat is a syscall — for as long as this
  /// pane sat under a page-level `ListenableBuilder`, every wallpaper was stat'd
  /// on every keystroke anywhere in the settings UI. The [StoreSelector] narrows
  /// *when* the build runs; this makes a run over an unchanged path list free.
  /// Cleared whenever the entry list moves.
  final Map<String, bool> _exists = {};

  bool _pathExists(String path) =>
      _exists.putIfAbsent(path, () => File(path).existsSync());

  List<Map> _rawEntries() =>
      (store.get<List>(['background', 'entries']) ?? const [])
          .whereType<Map>()
          .toList();

  /// Whether raw entry [e] is the Theme default (`theme = true`).
  static bool _isTheme(Map e) => e['theme'] == true;

  /// What [e] is keyed on in the grids: its path, or [kThemeWallpaperKey].
  static String _keyOf(Map e) =>
      _isTheme(e) ? kThemeWallpaperKey : '${e['path'] ?? ''}'.trim();

  /// The identity of the entry list, for [StoreSelector]. Keys and shown
  /// flags only: nothing else in `[background]` changes what the grids render.
  String _entriesSignature() {
    final parts = <String>[];
    for (final e in _rawEntries()) {
      parts.add('${_keyOf(e)}:${e['shown'] ?? true}');
    }
    return parts.join('\u0000');
  }

  /// Drops invalid entries (empty / non-image / missing on disk) and any second
  /// Theme default, strips the obsolete `time` key, and orders shown wallpapers
  /// before hidden ones — the canonical presentation order the running shell
  /// rotates through.
  List<Map<String, dynamic>> _normalize(List<Map> raw) {
    final valid = <Map<String, dynamic>>[];
    var hasTheme = false;
    for (final e in raw) {
      final shown = e['shown'] as bool? ?? true;
      if (_isTheme(e)) {
        if (hasTheme) continue;
        hasTheme = true;
        valid.add({'theme': true, 'shown': shown});
        continue;
      }
      final path = '${e['path'] ?? ''}'.trim();
      if (path.isEmpty || !isImagePath(path) || !_pathExists(path)) {
        continue;
      }
      valid.add({'path': path, 'shown': shown});
    }
    final shown = valid.where((e) => e['shown'] == true).toList();
    final hidden = valid.where((e) => e['shown'] != true).toList();
    return [...shown, ...hidden];
  }

  bool _matches(List<Map> raw, List<Map<String, dynamic>> normalized) {
    if (raw.length != normalized.length) return false;
    for (var i = 0; i < raw.length; i++) {
      if (_keyOf(raw[i]) != _keyOf(normalized[i])) return false;
      // A theme entry carrying a stray `path` is rewritten without it.
      if (_isTheme(raw[i]) && raw[i].containsKey('path')) return false;
      if ((raw[i]['shown'] as bool? ?? true) != normalized[i]['shown']) {
        return false;
      }
    }
    return true;
  }

  /// The entry [key] stands for, shown or not.
  static Map<String, dynamic> _entryFor(String key, {required bool shown}) =>
      key == kThemeWallpaperKey
      ? {'theme': true, 'shown': shown}
      : {'path': key, 'shown': shown};

  /// Puts [key] into the rotation, adding the entry when the wallpaper came
  /// from the catalogue (or is the Theme default) and so had none.
  ///
  /// The Theme default goes to the front: it is the first tile offered, and the
  /// wallpaper the desktop opens on is the first one shown.
  void _show(String key) {
    final list = _normalize(_rawEntries());
    final idx = list.indexWhere((e) => _keyOf(e) == key);
    final entry = _entryFor(key, shown: true);
    if (key == kThemeWallpaperKey) {
      if (idx >= 0) list.removeAt(idx);
      list.insert(0, entry);
    } else if (idx < 0) {
      list.add(entry);
    } else {
      list[idx] = entry;
    }
    store.set(['background', 'entries'], _normalize(list));
  }

  /// Takes [key] out of the rotation.
  ///
  /// A catalogue wallpaper's entry — and the Theme default's — is dropped
  /// rather than flipped to `shown = false`: it is listed in Available either
  /// way, and a hidden entry would show it twice and write an entry the user
  /// cannot delete.
  void _hide(String key) {
    final list = _normalize(_rawEntries());
    final idx = list.indexWhere((e) => _keyOf(e) == key);
    if (idx < 0) return;
    if (key == kThemeWallpaperKey || _systemPaths.contains(key)) {
      list.removeAt(idx);
    } else {
      list[idx] = _entryFor(key, shown: false);
    }
    store.set(['background', 'entries'], _normalize(list));
  }

  /// Drops a user-added wallpaper from the list entirely. Never offered for a
  /// catalogue wallpaper or the Theme default — there is no file of the user's
  /// behind either to delete, and it would reappear on the next build.
  void _remove(String key) {
    final list = _normalize(_rawEntries())
      ..removeWhere((e) => _keyOf(e) == key);
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
    // Selected on the entry list's own signature rather than left under a
    // page-level `ListenableBuilder`: [ConfigStore] notifies on every `set`,
    // and this build stats every configured wallpaper and rebuilds both grids.
    // The two scalar rows below subscribe to their own keys. See [ConfigValue].
    return StoreSelector<String>(
      listenable: store,
      selector: _entriesSignature,
      builder: (context, _) {
        // A path list that moved is a stat cache that may be stale.
        _exists.clear();
        return _buildSection(context);
      },
    );
  }

  Widget _buildSection(BuildContext context) {
    final raw = _rawEntries();
    final entries = _normalize(raw);
    // Persist the auto-prune / normalization once, after this frame, if it
    // changed anything — never mutate the store during build.
    if (!_matches(raw, entries)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) store.set(['background', 'entries'], entries);
      });
    }
    final configured = entries.map(_keyOf).toSet();
    final themeShown = entries.any((e) => _isTheme(e) && e['shown'] == true);
    final shown = [
      for (final e in entries.where((e) => e['shown'] == true))
        _WallpaperRef(_keyOf(e), _systemPaths),
    ];
    // The Theme default first, always, when it is not in the rotation; then
    // hidden picks — they are what the user last had in the rotation — then
    // everything the machine ships that is not already in the config.
    final available = [
      if (!themeShown) _WallpaperRef(kThemeWallpaperKey, _systemPaths),
      for (final e in entries.where((e) => e['shown'] != true && !_isTheme(e)))
        _WallpaperRef(_keyOf(e), _systemPaths),
      for (final p in _system)
        if (!configured.contains(p)) _WallpaperRef(p, _systemPaths),
    ];

    return SliverMainAxisGroup(
      slivers: [
        // The two rows on a section card like every other page's; the grids
        // below stay off it, being collections rather than rows.
        SliverSettingsSection(
          label: 'Wallpaper',
          children: [
            SettingsRow.field(
              SettingsCatalog.backgroundFit,
              control: ConfigValue<String>(
                store: store,
                path: const ['background', 'fit'],
                fallback: 'fill',
                builder: (context, value) => SettingsChoice<String>(
                  options: const ['fill', 'contain', 'natural'],
                  value: value!,
                  onChanged: (v) => store.set(['background', 'fit'], v),
                ),
              ),
            ),
            SettingsRow.field(
              SettingsCatalog.backgroundIntervalMinutes,
              info:
                  '${SettingsCatalog.backgroundIntervalMinutes.description} '
                  'Selected wallpapers rotate on this interval, in order.',
              control: ConfigValue<num>(
                store: store,
                path: const ['background', 'interval_minutes'],
                fallback: 5,
                builder: (context, value) => SettingsNumberField(
                  value: value!,
                  isInt: true,
                  onChanged: (v) => store.set([
                    'background',
                    'interval_minutes',
                  ], v.toInt() < 1 ? 1 : v.toInt()),
                ),
              ),
            ),
          ],
        ),
        SliverList.list(
          children: [
            const SizedBox(height: 8),
            SettingsSubLabel(
              'Shown',
              // On the heading rather than under the grid: the grid is the tallest
              // thing on this page, and a button below it is a button the user has
              // to scroll past every tile to reach.
              trailing: SettingsAddButton(
                label: 'Add wallpaper',
                onTap: _addWallpapers,
              ),
            ),
            if (shown.isEmpty)
              const SettingsHint(
                'No wallpapers selected. Select one from Available below.',
              ),
          ],
        ),
        if (shown.isNotEmpty)
          _WallpaperGrid(
            entries: shown,
            selected: true,
            onToggle: _hide,
            onRemove: _remove,
            onReorder: _reorderShown,
            themeWallpaperOf: widget.themeWallpaperOf,
          ),
        SliverList.list(
          children: [
            const SettingsSubLabel(
              'Available',
              info:
                  'Theme default is the wallpaper the current theme comes '
                  'with; while it is selected, changing theme changes the '
                  'wallpaper too. Wallpapers installed on this system are '
                  'always listed here. Only the ones you added yourself can '
                  'be removed.',
            ),
            if (available.isEmpty)
              _loadingSystem
                  ? const _LookingForWallpapers()
                  : const SettingsHint('No other wallpapers found.'),
          ],
        ),
        // The Available grid is the reason this page is a `CustomScrollView`
        // at all: `SystemWallpaperCatalog.maxEntries` is 120, every tile is an
        // `Image.file`, and `Image` resolves its provider on *mount* — so as a
        // `Wrap` inside a `Column` all of them decoded, below the fold or not.
        if (available.isNotEmpty)
          _WallpaperGrid(
            entries: available,
            selected: false,
            onToggle: _show,
            onRemove: _remove,
            themeWallpaperOf: widget.themeWallpaperOf,
          ),
        if (available.isNotEmpty && _loadingSystem)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 8),
              child: _LookingForWallpapers(),
            ),
          ),
      ],
    );
  }
}

/// One tile's worth of wallpaper: where it is, and whether the user may drop it
/// from the list.
///
/// A wallpaper the distribution installed is never removable, however it got into
/// the config — picking one through the file picker does not make it the user's
/// to delete, because it would come straight back from the catalogue. Nor is the
/// Theme default, which is no file at all.
class _WallpaperRef {
  _WallpaperRef(this.path, Set<String> systemPaths)
    : removable = path != kThemeWallpaperKey && !systemPaths.contains(path);

  /// The wallpaper's file, or [kThemeWallpaperKey].
  final String path;
  final bool removable;

  bool get isTheme => path == kThemeWallpaperKey;
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

/// A responsive 3-column grid of [_WallpaperTile]s, as a **sliver**. When
/// [onReorder] is given (the "shown" group) each tile is draggable and accepts
/// drops to reorder.
///
/// A `LayoutBuilder` + `Wrap` before this, which measured and so mounted every
/// tile. `SystemWallpaperCatalog.maxEntries` is 120 and every tile is an
/// `Image.file`, which resolves its provider on *mount* rather than on first
/// paint, so the whole catalogue decoded on a visit to this page.
///
/// The trap on the way back to a box: `GridView.builder(shrinkWrap: true)` inside
/// a scroll view is **not** a fix — `shrinkWrap` makes the sliver lay out all of
/// its children to report its own extent, which is the same eager layout plus a
/// nested viewport. The same goes for `NeverScrollableScrollPhysics`.
///
/// Drag-reorder survives: `Draggable`/`DragTarget` register per built child, and
/// a target scrolled out of the viewport was never a drop candidate anyway.
class _WallpaperGrid extends StatelessWidget {
  const _WallpaperGrid({
    required this.entries,
    required this.selected,
    required this.onToggle,
    required this.onRemove,
    required this.themeWallpaperOf,
    this.onReorder,
  });

  final List<_WallpaperRef> entries;
  final bool selected;
  final void Function(String path) onToggle;
  final void Function(String path) onRemove;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final String? Function(ThemeConfig theme) themeWallpaperOf;

  static const int _columns = 3;
  static const double _gap = 8.0;

  /// The `Wrap`'s `tileH = tileW * 0.6`, as the grid delegate wants it.
  static const double _aspect = 1 / 0.6;

  @override
  Widget build(BuildContext context) {
    // A *sliver* layout builder, and one for the whole grid rather than one per
    // cell: the only thing that needs a measurement is the drag ghost, which is
    // rendered into the root Overlay and so cannot read the cell's constraints
    // itself.
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final tileW =
            (constraints.crossAxisExtent - _gap * (_columns - 1)) / _columns;
        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _columns,
            mainAxisSpacing: _gap,
            crossAxisSpacing: _gap,
            childAspectRatio: _aspect,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => KeyedSubtree(
              // Keyed on the path so a reorder moves the tile's element rather
              // than rebuilding every tile after it — and so a test can find
              // one wallpaper among identical previews.
              key: ValueKey(entries[index].path),
              child: _cell(context, index, tileW, tileW / _aspect),
            ),
            childCount: entries.length,
            // Without this the delegate matches on index alone, so a reorder
            // reads as "every index changed" and the keys buy nothing.
            findChildIndexCallback: (key) {
              final path = (key as ValueKey<String>).value;
              final index = entries.indexWhere((e) => e.path == path);
              return index < 0 ? null : index;
            },
          ),
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
      themeWallpaperOf: themeWallpaperOf,
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
                themeWallpaperOf: themeWallpaperOf,
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
/// selection border and check badge, mirroring [SettingsOptionButton].
///
/// [onRemove] is null for a wallpaper the machine ships, which is the whole of
/// "system wallpapers cannot be deleted" as far as this widget is concerned.
///
/// [path] [kThemeWallpaperKey] is the Theme default: the active theme's
/// wallpaper under a caption saying so, or the caption alone over an empty
/// square when the theme has none.
class _WallpaperTile extends StatelessWidget {
  const _WallpaperTile({
    required this.path,
    required this.selected,
    required this.onTap,
    required this.themeWallpaperOf,
    this.onRemove,
  });

  final String path;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final String? Function(ThemeConfig theme) themeWallpaperOf;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final isTheme = path == kThemeWallpaperKey;
    // Built once here rather than inside the builder: the preview does not
    // depend on `hovered`, and minting a fresh `File` and `FileImage` on every
    // hover flip churns the element for a picture that never changed. See
    // [SettingsRow] for the discipline this belongs to.
    final preview = isTheme
        ? _ThemeWallpaperPreview(resolve: themeWallpaperOf)
        : _WallpaperPreview(path: path);
    // Not inside a [SettingsRow], so it carries its own — see that class for
    // the rule. This grid is the densest thing in the settings UI, so it is
    // also where the containment is worth the most.
    return RepaintBoundary(
      child: HoverRegion(
        onTap: onTap,
        builder: (context, hovered) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              preview,
              if (!selected && !hovered)
                const ColoredBox(color: Color(0x33000000)),
              if (isTheme) const _ThemeDefaultCaption(),
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
                    child: const ShellIcon(
                      ShellGlyph.check,
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
            border: Border.all(color: theme.divider.atMostAlpha(0.6)),
          ),
          alignment: Alignment.center,
          child: const ShellIcon(
            ShellGlyph.close,
            size: 10,
            color: Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
  }
}

/// A wallpaper file, cover-cropped and decoded at tile size.
class _WallpaperPreview extends StatelessWidget {
  const _WallpaperPreview({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: 320,
      gaplessPlayback: true,
      errorBuilder: (c, e, s) => ColoredBox(color: theme.controlSurface),
    );
  }
}

/// The Theme default tile's picture: the active theme's wallpaper, or an empty
/// square when it has none.
///
/// Resolved here, keyed on the theme's `wallpaper` value, rather than by the
/// section: the tile already follows the theme for its colours, and a theme
/// switch hands it a new [ThemeConfig] on every frame of the blend while the
/// value changes once — so the stat behind a resolve happens once too.
class _ThemeWallpaperPreview extends StatefulWidget {
  const _ThemeWallpaperPreview({required this.resolve});

  final String? Function(ThemeConfig theme) resolve;

  @override
  State<_ThemeWallpaperPreview> createState() => _ThemeWallpaperPreviewState();
}

class _ThemeWallpaperPreviewState extends State<_ThemeWallpaperPreview> {
  String? _value;
  String? _path;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = ThemeScope.of(context);
    if (_value != null && _value == theme.wallpaper) return;
    _value = theme.wallpaper;
    _path = widget.resolve(theme);
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    if (path == null) {
      return ColoredBox(color: ThemeScope.of(context).controlSurface);
    }
    // Keyed on the file so a theme switch swaps the picture rather than
    // holding the old one (`gaplessPlayback`) until the new one decodes.
    return _WallpaperPreview(key: ValueKey(path), path: path);
  }
}

/// "Theme default", along the bottom of its tile — which is otherwise an
/// ordinary preview, and is the only one whose picture can change under it.
class _ThemeDefaultCaption extends StatelessWidget {
  const _ThemeDefaultCaption();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: const Color(0x99000000),
        child: Text(
          'Theme default',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xFFFFFFFF),
            fontSize: ShellFontSizes.caption,
          ),
        ),
      ),
    );
  }
}
