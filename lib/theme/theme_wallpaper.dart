/// Where a theme's `wallpaper` key points.
///
/// A theme names its wallpaper the way it names its pictures (`panel_image`),
/// with one more place to look: a bare name that is not beside the theme file
/// is one of the wallpapers the shell installs itself — `wallpaper-forest.jpg`
/// in `$PREFIX/share/moonswing`, or the snap's `share/moonswing`. That is how
/// the shipped themes name theirs, since a built-in theme is an embedded
/// constant and cannot know where the shell was installed.
library;

import 'dart:io';

import 'package:moonswing/decor/material_textures.dart';
import 'package:moonswing/default_config.dart';
import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/theme_store.dart';

/// [theme]'s wallpaper as a file that exists, or null when the theme has none
/// or names one that is not on this machine.
///
/// A stat or three per call, so a caller that runs it from `build` keys the
/// answer on [ThemeConfig.wallpaper] rather than asking every frame — a theme
/// switch hands every surface a new [ThemeConfig] per frame of its blend.
///
/// [themesDirectory] is where a relative name is looked for first; it defaults
/// to the live themes directory. [shipped] finds one of the shell's own
/// installed files; tests replace it.
String? resolveThemeWallpaper(
  ThemeConfig theme, {
  String? themesDirectory,
  String? Function(String name) shipped = shippedDataFile,
}) {
  final value = theme.wallpaper.trim();
  if (value.isEmpty) return null;
  bool exists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  // `~/…` and absolute paths mean exactly that file.
  if (value.startsWith('/') || value.startsWith('~/')) {
    final path = resolvePicturePath(value, null);
    return exists(path) ? path : null;
  }
  // Beside the theme file first, so a theme and its wallpaper can travel as
  // one folder — and so a user's own `wallpaper-forest.jpg` beside a fork of
  // Forest wins over the shipped one.
  final beside = resolvePicturePath(
    value,
    themesDirectory ?? ThemeStore.instance.directory,
  );
  if (exists(beside)) return beside;
  // A bare name only: `../x.jpg` is a path relative to the themes directory,
  // never a reach into the install tree.
  if (value.contains('/')) return null;
  return shipped(value);
}
