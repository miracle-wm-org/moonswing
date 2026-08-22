/// The `config.toml` written on first run, and the shipped-data lookup its
/// wallpaper paths come from.
library;

import 'dart:io';

import 'package:graceful_shell/theme/theme_config.dart';

/// Resolves [name] against the directories the shell's shipped data files
/// (the wallpapers) can live in, returning the first that exists.
///
/// The snap's own copy comes first, because it cannot write into the user's
/// data dir; `make install` puts them in the XDG data dir instead. Returns null
/// when neither has the file — the callers all treat a missing wallpaper as
/// "draw the fallback", never as an error.
///
/// Under the snap this deliberately resolves through `/snap/<name>/current`
/// rather than `$SNAP`, which is `/snap/<name>/<revision>`: the result is baked
/// into the generated `config.toml` and a revisioned path would go dead on the
/// next `snap refresh`.
String? shippedDataFile(String name) {
  final env = Platform.environment;
  final roots = <String>[];

  final snap = env['SNAP'] ?? '';
  if (snap.isNotEmpty) {
    final snapName = env['SNAP_NAME'] ?? '';
    if (snapName.isNotEmpty) {
      roots.add('/snap/$snapName/current/share/graceful-shell');
    }
    roots.add('$snap/share/graceful-shell');
  }

  final dataHome = env['XDG_DATA_HOME'] ?? '';
  if (dataHome.isNotEmpty) {
    roots.add('$dataHome/graceful-shell');
  } else {
    final home = env['HOME'] ?? '';
    if (home.isNotEmpty) roots.add('$home/.local/share/graceful-shell');
  }

  for (final root in roots) {
    final path = '$root/$name';
    if (File(path).existsSync()) return path;
  }
  return null;
}

/// The default `config.toml` document, written to disk on first run.
///
/// Wallpapers are baked as absolute paths because config.toml is written once
/// and then owned by the user: resolving at every read would silently move
/// their wallpaper if the shell were later reinstalled somewhere else. Falls
/// back to the XDG data dir when nothing is installed yet, which is where
/// `make install` will put it.
///
/// The golden test parses this document and asserts every field it names lands
/// unchanged in the typed config.
String buildDefaultConfig(String homeDir) {
  final wallpaper = shippedDataFile('wallpaper.jpg') ??
      '$homeDir/.local/share/graceful-shell/wallpaper.jpg';
  final lockWallpaper = shippedDataFile('lock-wallpaper.jpg') ??
      '$homeDir/.local/share/graceful-shell/lock-wallpaper.jpg';
  return '''
theme = "$kDefaultThemeName"

[panels.top]
height = 32
padding_horizontal = 8
anchor = "top"
layer = "top"

[panels.top.layout]
left = ["workspaces"]
center = ["clock"]
right = ["sound_control", "system_tray", "battery", "weather", "system"]

[panels.bottom]
height = 32
padding_horizontal = 0
anchor = "bottom"
layer = "top"

[panels.bottom.layout]
center = ["dock"]
right = ["media_player", "launcher"]

[modules.dock]
apps = ["firefox_firefox", "org.gnome.Ptyxis", "org.gnome.Nautilus"]

[modules.weather]
unit = "fahrenheit"
refresh_minutes = 10

[modules.battery]
poll_seconds = 30

[modules.clock]
show_date = true

[modules.media_player]
max_text_width = 200.0

[modules.system_tray]
icon_size = 16
collapsed_overlap = 10
expanded_spacing = 6

[modules.system_monitor]
poll_seconds = 2
temp_unit = "celsius"

[background]
fit = "fill"
interval_minutes = 5

[[background.entries]]
path = "$wallpaper"
shown = true

# Icons pinned to the desktop. Off by default; turn it on here or in
# Settings > Shell > Desktop. Items are appended as [[desktop.items]] tables.
[desktop]
enabled = false
cell_width = 96
cell_height = 96
spacing = 12
padding = 24
icon_size = 48
show_labels = true

[lock]
background = "$lockWallpaper"
fit = "fill"
show_username = true
blur_sigma = 18.0

[shortcuts]
open_settings = "ctrl+shift+s"
open_launcher = "ctrl+space"

[screenshare]
enabled = true
preview_fps = 10
max_fps = 0
''';
}
