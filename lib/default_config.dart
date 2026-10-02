/// The `config.toml` written on first run, and the shipped-data lookup its
/// wallpaper paths come from.
library;

import 'dart:io';

import 'package:moonswing/theme/theme_config.dart';

/// Resolves [name] against the directories the shell's shipped wallpapers can
/// live in, returning the first that exists.
///
/// The snap's own copy comes first, because it cannot write into the user's data
/// dir; `make install` puts them in the XDG data dir instead. Null when neither
/// has the file — the callers all treat a missing wallpaper as "draw the
/// fallback".
///
/// Under the snap this deliberately resolves through `/snap/<name>/current`
/// rather than `$SNAP`, which is revisioned: the result is baked into the
/// generated `config.toml` and a revisioned path would go dead on the next
/// `snap refresh`.
String? shippedDataFile(String name) {
  final env = Platform.environment;
  final roots = <String>[];

  final snap = env['SNAP'] ?? '';
  if (snap.isNotEmpty) {
    final snapName = env['SNAP_NAME'] ?? '';
    if (snapName.isNotEmpty) {
      roots.add('/snap/$snapName/current/share/moonswing');
    }
    roots.add('$snap/share/moonswing');
  }

  final dataHome = env['XDG_DATA_HOME'] ?? '';
  if (dataHome.isNotEmpty) {
    roots.add('$dataHome/moonswing');
  } else {
    final home = env['HOME'] ?? '';
    if (home.isNotEmpty) roots.add('$home/.local/share/moonswing');
  }

  for (final root in roots) {
    final path = '$root/$name';
    if (File(path).existsSync()) return path;
  }
  return null;
}

/// The default `config.toml` document, written to disk on first run.
///
/// Wallpapers are baked as absolute paths because config.toml is written once and
/// then owned by the user: resolving at every read would silently move their
/// wallpaper if the shell were reinstalled elsewhere. Falls back to the XDG data
/// dir when nothing is installed yet.
///
/// The golden test parses this document and asserts every field it names lands
/// unchanged in the typed config.
String buildDefaultConfig(String homeDir) {
  final wallpaper = shippedDataFile('wallpaper.jpg') ??
      '$homeDir/.local/share/moonswing/wallpaper.jpg';
  final lockWallpaper = shippedDataFile('lock-wallpaper.jpg') ??
      '$homeDir/.local/share/moonswing/lock-wallpaper.jpg';
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
right = ["screenshot", "screen_recorder", "sound_control", "brightness", "system_tray", "battery", "weather", "todo", "scratchpad", "keybinds", "keyboard_layout", "system"]

[panels.bottom]
height = 32
padding_horizontal = 0
anchor = "bottom"
layer = "top"

[panels.bottom.layout]
left = ["github"]
center = ["dock"]
right = ["media_player", "notifications", "launcher"]

[modules.dock]
apps = ["firefox_firefox", "org.gnome.Ptyxis", "org.gnome.Nautilus"]

# Where the weather is read for is optional: with no `location`/`latitude`/
# `longitude` the shell detects it from this machine's IP address. Settings >
# Shell > Modules > Weather searches for a place by name and writes all three.
[modules.weather]
unit = "fahrenheit"
refresh_minutes = 30

[modules.battery]
poll_seconds = 30

[modules.clock]
show_date = true
# What a finished countdown rings, and how loud. `ding`, `ding-dong`, `alarm`,
# `gong`, a path, a name from the system's sound theme, or `none`. It also posts
# a notification either way, which is what is still there if you missed the
# sound.
timer_sound = "ding"
timer_volume = 0.7

# The badge is hidden while there is only one input source to choose between,
# which is GNOME's arrangement and costs a fresh config nothing. Settings >
# Keyboard is where sources are added; the list itself lives in `[keyboard]`.
[modules.keyboard_layout]
hide_when_single = true
uppercase = false

[modules.media_player]
max_text_width = 200.0

[modules.system_tray]
icon_size = 16
collapsed_overlap = 10
expanded_spacing = 6

[modules.system_monitor]
poll_seconds = 1
temp_unit = "celsius"

# What plays when a notification arrives. `chime`, `ping`, `glass`, `bell` and
# `knock` are the shipped sounds, which the shell synthesises rather than
# shipping as files; `none` is silence, and anything else is either a path or a
# name looked for in the system's sound theme.
[modules.notifications]
sound = "chime"
sound_volume = 0.7

# Stills go to ~/Pictures/Screenshots and recordings to ~/Videos/Screencasts
# unless `directory` names somewhere else; a leading `~` is expanded.
[modules.screenshot]
copy_to_clipboard = true
delay_seconds = 0
show_cursor = false

# `fps` is the rate written to the file, not the rate the compositor produces:
# a still screen sends no frames at all, and the recorder repeats the last one
# so the video runs at the speed of the thing it recorded.
[modules.screen_recorder]
fps = 30
container = "mp4"
quality = 23
show_cursor = true

[background]
fit = "fill"
interval_minutes = 5

[[background.entries]]
path = "$wallpaper"
shown = true

# Icons and widgets pinned to the desktop. On by default; turn it off here or
# in Settings > Shell > Desktop. Icons are appended as [[desktop.items]]
# tables, widgets — added from the desktop's right-click menu — as
# [[desktop.widgets]] ones, each naming a type, a cell and a span in cells.
[desktop]
enabled = true
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
open_settings = "super+s"
open_launcher = "super+d"
open_emoji = "ctrl+shift+e"
open_notifications = "super+n"
# The power menu — shut down, restart, suspend, lock or log out.
open_power_menu = "shift+super+e"
# The window switcher. Hold Alt, press Tab to move through the open windows,
# and let Alt go to switch to the one you are on.
switch_windows = "alt+tab"
switch_windows_back = "alt+shift+tab"
# A screenshot of an area you drag out, and a recording of the screen you are
# on. Press the recording shortcut again to stop it.
screenshot_area = "print"
record_screen = "super+print"
# The window manager's scratchpad: show or hide what is on it, and stash the
# window you are in there.
toggle_scratchpad = "super+z"
move_to_scratchpad = "shift+super+z"
# The machine's own power button. Clear it (or set [power] key_action = "none")
# to hand the key back to systemd-logind.
power_button = "poweroff"

# What that button does. "menu" shows the power dialog; "shutdown", "reboot",
# "suspend", "lock" and "logout" act at once; "none" leaves the key to logind.
# While the shell handles it, it holds logind's handle-power-key inhibitor so
# the machine does not power off behind the dialog — turn that off only if
# logind.conf already says HandlePowerKey=ignore.
[power]
key_action = "menu"
inhibit_logind = true

[screenshare]
enabled = true
preview_fps = 10
max_fps = 0
''';
}
