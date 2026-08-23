import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/wallpaper_catalog.dart';

/// The installed-wallpaper scan, against a temp tree standing in for the
/// distributions' real layouts.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gs_wallpaper_catalog');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// Creates [relative] under the temp root, parents included.
  Future<String> touch(String relative) async {
    final path = '${tempDir.path}/$relative';
    await Directory(path.substring(0, path.lastIndexOf('/')))
        .create(recursive: true);
    await File(path).writeAsBytes(const [0]);
    return path;
  }

  group('scan', () {
    test('finds images across the layouts the distributions actually ship',
        () async {
      // Ubuntu: flat files plus a vendor subdirectory.
      final warty = await touch('backgrounds/warty-final-ubuntu.png');
      final adwaita = await touch('backgrounds/gnome/adwaita-l.jpg');
      // Fedora: one directory per release, day/night variants inside.
      final f41 = await touch('backgrounds/f41/default/f41-01-day.png');
      // KDE: a wallpaper package per theme.
      final kde = await touch('wallpapers/Altai/contents/images/1920x1080.jpg');
      // Not wallpapers.
      await touch('backgrounds/gnome-backgrounds.xml');
      await touch('backgrounds/.hidden.png');

      final found = await SystemWallpaperCatalog(roots: [
        '${tempDir.path}/backgrounds',
        '${tempDir.path}/wallpapers',
      ]).list();

      expect(found, [adwaita, f41, warty, kde]..sort());
    });

    test('keeps one resolution per KDE wallpaper package, the largest',
        () async {
      await touch('wallpapers/Altai/contents/images/1920x1080.jpg');
      final big = await touch('wallpapers/Altai/contents/images/3840x2160.jpg');
      await touch('wallpapers/Altai/contents/images/2560x1600.jpg');
      // A dark variant is its own package directory, so it keeps its own tile.
      final dark =
          await touch('wallpapers/Altai/contents/images_dark/1920x1080.jpg');

      final found = await SystemWallpaperCatalog(
        roots: ['${tempDir.path}/wallpapers'],
      ).list();

      expect(found, [big, dark]..sort());
    });

    test('lists an ordinary directory in full, resolutions or not', () async {
      // The collapse is keyed on the `contents/images` layout, so a plain
      // directory of numbered files is not a wallpaper package.
      final a = await touch('backgrounds/1920x1080.jpg');
      final b = await touch('backgrounds/3840x2160.jpg');

      final found = await SystemWallpaperCatalog(
        roots: ['${tempDir.path}/backgrounds'],
      ).list();

      expect(found, [a, b]..sort());
    });

    test('counts a symlinked wallpaper once, under its listed name', () async {
      final real = await touch('backgrounds/gnome/adwaita-l.jpg');
      await Link('${tempDir.path}/backgrounds/current.jpg').create(real);

      final found = await SystemWallpaperCatalog(
        roots: ['${tempDir.path}/backgrounds'],
      ).list();

      expect(found.length, 1);
      // Either name is the same file; whichever is walked first wins, and the
      // point is that the grid shows one tile rather than two.
      expect(found.single,
          anyOf(real, '${tempDir.path}/backgrounds/current.jpg'));
    });

    test('walks a root only once when two roots resolve to the same place',
        () async {
      final real = await touch('share/backgrounds/warty.png');
      await Link('${tempDir.path}/share/wallpapers')
          .create('${tempDir.path}/share/backgrounds');

      final found = await SystemWallpaperCatalog(roots: [
        '${tempDir.path}/share/backgrounds',
        '${tempDir.path}/share/wallpapers',
      ]).list();

      expect(found, [real]);
    });

    test('stops at the depth cap rather than crawling the disk', () async {
      final deep = List.filled(SystemWallpaperCatalog.maxDepth + 2, 'd')
          .join('/');
      await touch('backgrounds/$deep/too-deep.png');
      final shallow = await touch('backgrounds/a/b/reachable.png');

      final found = await SystemWallpaperCatalog(
        roots: ['${tempDir.path}/backgrounds'],
      ).list();

      expect(found, [shallow]);
    });

    test('caps the number of wallpapers offered', () async {
      for (var i = 0; i < SystemWallpaperCatalog.maxEntries + 10; i++) {
        await touch('backgrounds/${i.toString().padLeft(4, '0')}.png');
      }

      final found = await SystemWallpaperCatalog(
        roots: ['${tempDir.path}/backgrounds'],
      ).list();

      expect(found.length, SystemWallpaperCatalog.maxEntries);
    });

    test('an absent or unreadable root is empty, not an error', () async {
      final found = await SystemWallpaperCatalog(roots: [
        '${tempDir.path}/nothing-here',
        '/proc/self/mem',
      ]).list();

      expect(found, isEmpty);
    });

    test('memoises the future so two callers share one walk', () async {
      await touch('backgrounds/warty.png');
      final catalog =
          SystemWallpaperCatalog(roots: ['${tempDir.path}/backgrounds']);

      final first = catalog.list();
      final second = catalog.list();

      expect(identical(first, second), isTrue);
      expect(await first, await second);
    });
  });

  group('systemWallpaperRoots', () {
    test('derives backgrounds/ and wallpapers/ under every XDG data dir', () {
      final roots = systemWallpaperRoots({
        'HOME': '/home/ada',
        'XDG_DATA_DIRS': '/usr/share:/var/lib/flatpak/exports/share',
      });

      expect(roots, contains('/home/ada/.local/share/backgrounds'));
      expect(roots, contains('/usr/share/backgrounds'));
      expect(roots, contains('/usr/share/wallpapers'));
      expect(roots, contains('/var/lib/flatpak/exports/share/backgrounds'));
      // The shell's own installed wallpapers.
      expect(roots, contains('/usr/share/graceful-shell'));
    });

    test('falls back to the spec default when nothing is exported', () {
      final roots = systemWallpaperRoots(const {});

      expect(roots, contains('/usr/share/backgrounds'));
      expect(roots, contains('/usr/local/share/wallpapers'));
      // The layouts that predate the convention.
      expect(roots, contains('/usr/share/desktop-base'));
      expect(roots, contains('/usr/share/pixmaps/backgrounds'));
    });

    test('honours XDG_DATA_HOME over HOME, and lists it first', () {
      final roots = systemWallpaperRoots({
        'HOME': '/home/ada',
        'XDG_DATA_HOME': '/home/ada/data',
      });

      expect(roots.first, '/home/ada/data/backgrounds');
      expect(roots, isNot(contains('/home/ada/.local/share/backgrounds')));
    });

    test('adds a classic snap\'s own share directory', () {
      final roots = systemWallpaperRoots({'SNAP': '/snap/graceful-shell/42'});

      expect(roots, contains('/snap/graceful-shell/42/share/backgrounds'));
      expect(roots, contains('/snap/graceful-shell/42/share/graceful-shell'));
    });

    test('drops empty and relative entries, and never repeats a directory', () {
      final roots = systemWallpaperRoots({
        // A trailing colon is a real thing in `XDG_DATA_DIRS`, and a relative
        // entry is meaningless per the spec.
        'XDG_DATA_DIRS': '/usr/share:/usr/share/:relative/share::',
      });

      expect(roots.where((r) => r == '/usr/share/backgrounds').length, 1);
      expect(roots.any((r) => !r.startsWith('/')), isFalse);
    });
  });
}
