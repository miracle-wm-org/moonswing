import 'dart:io';

import 'package:moonswing/media_paths.dart';

/// The wallpapers this machine already ships — Ubuntu's `/usr/share/backgrounds`,
/// Fedora's day/night sets, KDE's `/usr/share/wallpapers` themes — discovered at
/// runtime and offered in the background settings page alongside the user's own
/// picks.
///
/// Deliberately *not* written into `[[background.entries]]`. A config entry is
/// something the user chose and can therefore drop again; a system wallpaper is a
/// permanent fixture of the machine, so the page reads it from here on every
/// visit. Three things follow:
///
/// - **The list cannot be deleted**, because there is nothing on disk backing it
///   to delete. A catalogue tile has no remove button, and hiding one drops the
///   entry the selection created rather than the wallpaper.
/// - **It follows the distribution.** A release upgrade that replaces
///   `f41-01-day.png` is picked up on the next scan, where a seeded config would
///   keep a dead path until the auto-prune noticed.
/// - **It costs an absent user nothing**: a machine with no wallpapers installed
///   yields an empty list.
///
/// Follows the [FontCatalog] shape: roots are injectable so tests never touch the
/// real `/usr`, the *future* is memoised so racing callers share one walk, and
/// every failure resolves to an empty list.
class SystemWallpaperCatalog {
  SystemWallpaperCatalog({
    List<String>? roots,
    Map<String, String>? environment,
  })  : roots =
            roots ?? systemWallpaperRoots(environment ?? Platform.environment);

  static final SystemWallpaperCatalog instance = SystemWallpaperCatalog();

  /// The directories walked, in the order they are presented.
  final List<String> roots;

  /// How deep below a root the walk goes. Four is what the deepest real layout
  /// needs — KDE's `<root>/<Theme>/contents/images/<file>` — and the cap is
  /// what stops a symlink into `/` (or a user's photo library under
  /// `~/.local/share/backgrounds`) from turning a settings visit into a full
  /// disk crawl.
  static const int maxDepth = 4;

  /// How many wallpapers are offered at most. A distribution ships tens; this
  /// only binds when a root turns out to be somebody's picture collection, and
  /// it binds because every tile in the grid decodes an image.
  static const int maxEntries = 120;

  Future<List<String>>? _cached;

  /// Every image found under [roots], deduplicated and sorted. Never throws.
  Future<List<String>> list() => _cached ??= _scan();

  Future<List<String>> _scan() async {
    // Keyed on the resolved target so a distribution's "current wallpaper"
    // symlink does not show up as a second copy of the file it points at; the
    // value is the path as *listed*, which is the one with the readable name.
    final found = <String, String>{};
    final visited = <String>{};
    for (final root in roots) {
      if (found.length >= maxEntries) break;
      await _walk(Directory(root), 0, visited, found);
    }
    final paths = found.values.toList()..sort();
    return paths;
  }

  Future<void> _walk(
    Directory dir,
    int depth,
    Set<String> visited,
    Map<String, String> found,
  ) async {
    if (depth > maxDepth || found.length >= maxEntries) return;
    String real;
    try {
      real = await dir.resolveSymbolicLinks();
    } catch (_) {
      return; // Absent, or not a directory on this machine.
    }
    // Guards both the symlink loop and the overlap between roots — several
    // distributions symlink `/usr/share/wallpapers` at
    // `/usr/share/backgrounds`.
    if (!visited.add(real)) return;

    final files = <String>[];
    final subdirs = <Directory>[];
    try {
      await for (final entity in dir.list()) {
        final name = entity.path.split('/').last;
        if (name.startsWith('.')) continue;
        if (entity is Directory) {
          subdirs.add(entity);
        } else if (entity is File && isImagePath(entity.path)) {
          files.add(entity.path);
        }
      }
    } catch (_) {
      return; // Unreadable (permissions, a dead mount).
    }

    files.sort();
    for (final path in _presentable(real, files)) {
      if (found.length >= maxEntries) return;
      String key;
      try {
        key = await File(path).resolveSymbolicLinks();
      } catch (_) {
        continue; // A dangling link; nothing to render.
      }
      found.putIfAbsent(key, () => path);
    }

    subdirs.sort((a, b) => a.path.compareTo(b.path));
    for (final sub in subdirs) {
      await _walk(sub, depth + 1, visited, found);
    }
  }

  /// The files of one directory that are worth a tile.
  ///
  /// Everything is, except a KDE wallpaper package: `<Theme>/contents/images/`
  /// holds the same picture at every resolution the theme ships, so listing them
  /// all would fill the grid with a dozen identical previews per theme. One is
  /// kept — the largest, which is also the best-looking preview.
  static List<String> _presentable(String dir, List<String> files) {
    if (files.length < 2) return files;
    if (!dir.contains('/contents/images')) return files;
    var best = files.first;
    var bestPixels = _resolutionPixels(best);
    for (final path in files.skip(1)) {
      final pixels = _resolutionPixels(path);
      if (pixels > bestPixels) {
        best = path;
        bestPixels = pixels;
      }
    }
    return [best];
  }

  /// The pixel count encoded in a `1920x1080.png`-style file name, or 0 when
  /// the name does not carry one (in which case the sort order decides).
  static int _resolutionPixels(String path) {
    var name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot >= 0) name = name.substring(0, dot);
    final match = RegExp(r'^(\d{2,5})x(\d{2,5})$').firstMatch(name);
    if (match == null) return 0;
    return int.parse(match.group(1)!) * int.parse(match.group(2)!);
  }
}

/// The directories a distribution keeps its wallpapers in, for [environment].
///
/// Most of the list is derived rather than enumerated: `backgrounds/` and
/// `wallpapers/` under every XDG data directory covers Ubuntu, Fedora, Debian,
/// Arch, Mint, Pop, elementary, openSUSE and every KDE spin at once, because that
/// is the pair of names the desktops have agreed on. `$XDG_DATA_DIRS` is honoured
/// rather than hardcoding `/usr/share`, which makes the shell's own
/// `make install PREFIX=…` tree and a snap's `$SNAP/share` fall out for free.
///
/// The handful appended after that are the layouts that predate the convention
/// and are still shipped: Debian's `desktop-base` theme, and the `pixmaps`
/// directory a few older spins use.
List<String> systemWallpaperRoots(Map<String, String> environment) {
  final dataDirs = <String>[];

  void addDir(String? dir) {
    if (dir == null) return;
    final trimmed = dir.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('/')) return;
    final normalized = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    if (!dataDirs.contains(normalized)) dataDirs.add(normalized);
  }

  final home = environment['HOME'];
  addDir(environment['XDG_DATA_HOME'] ??
      (home != null && home.isNotEmpty ? '$home/.local/share' : null));
  final dirs = environment['XDG_DATA_DIRS'];
  if (dirs != null && dirs.trim().isNotEmpty) {
    dirs.split(':').forEach(addDir);
  }
  // The spec's own fallback, and what a session that never exported the
  // variable actually has.
  addDir('/usr/local/share');
  addDir('/usr/share');
  // A classic snap runs in the host namespace, so `$SNAP/share` is not on
  // `XDG_DATA_DIRS` — the shell's own shipped wallpaper lives there.
  final snap = environment['SNAP'];
  if (snap != null && snap.isNotEmpty) addDir('$snap/share');

  final roots = <String>[];
  for (final dir in dataDirs) {
    roots.add('$dir/backgrounds');
    roots.add('$dir/wallpapers');
    roots.add('$dir/moonswing');
  }
  roots.add('/usr/share/desktop-base');
  roots.add('/usr/share/pixmaps/backgrounds');
  return roots;
}
