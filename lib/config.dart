/// The startup snapshot of `config.toml` — [AppConfig] and the per-section config
/// classes that still live here.
///
/// The sections that belong to a subsystem live beside it and are re-exported
/// below, so `import 'package:moonswing/config.dart'` keeps providing every
/// name it always has: the theme palette, the desktop grid model, the generated
/// default config, the media-extension predicates and the power-button policy.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:toml/toml.dart';

import 'package:moonswing/config_reader.dart';
import 'package:moonswing/default_config.dart';
import 'package:moonswing/desktop/desktop_config.dart';
import 'package:moonswing/caldav/caldav_config.dart';
import 'package:moonswing/google/google_config.dart';
import 'package:moonswing/input_trigger/keysym.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/osd/volume_sound.dart';
import 'package:moonswing/polkit/polkit_config.dart';
import 'package:moonswing/power/power_config.dart';
import 'package:moonswing/theme/theme_config.dart';

export 'package:moonswing/default_config.dart';
export 'package:moonswing/desktop/desktop_config.dart';
export 'package:moonswing/keyboard/keyboard_config.dart';
export 'package:moonswing/media_paths.dart'
    show imageExtensions, videoExtensions, isImagePath;
export 'package:moonswing/polkit/polkit_config.dart';
export 'package:moonswing/power/power_config.dart';
export 'package:moonswing/theme/theme_config.dart';

enum BackgroundFit {
  fill,
  contain,
  natural;

  static BackgroundFit fromString(String s) {
    switch (s) {
      case 'contain':
        return BackgroundFit.contain;
      case 'natural':
        return BackgroundFit.natural;
      default:
        return BackgroundFit.fill;
    }
  }
}

class BackgroundEntry {
  final String path;
  final bool shown;

  const BackgroundEntry({required this.path, this.shown = true});

  factory BackgroundEntry.fromMap(Map<String, dynamic> map) {
    return BackgroundEntry(
      path: map.stringOr('path', ''),
      shown: map.boolOr('shown', true),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackgroundEntry &&
          other.path == path &&
          other.shown == shown;

  @override
  int get hashCode => Object.hash(path, shown);
}

class BackgroundConfig {
  final BackgroundFit fit;
  final int intervalMinutes;
  final List<BackgroundEntry> entries;

  const BackgroundConfig({
    this.fit = BackgroundFit.fill,
    this.intervalMinutes = 5,
    this.entries = const [],
  });

  factory BackgroundConfig.fromMap(Map<String, dynamic> map) {
    return BackgroundConfig(
      fit: BackgroundFit.fromString(map.stringOr('fit', 'fill')),
      intervalMinutes: map.intOr('interval_minutes', 5, min: 1),
      // List order is the canonical presentation order — do not sort.
      entries: map.tableListOr('entries').map(BackgroundEntry.fromMap).toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackgroundConfig &&
          other.fit == fit &&
          other.intervalMinutes == intervalMinutes &&
          listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hash(
        fit,
        intervalMinutes,
        Object.hashAll(entries),
      );
}

class LayoutConfig {
  final List<String> left;
  final List<String> center;
  final List<String> right;

  const LayoutConfig({
    this.left = const ["workspaces"],
    this.center = const ["media_player"],
    this.right = const [
      "sound_control",
      "battery",
      "weather",
      "clock",
      "system",
    ],
  });

  factory LayoutConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const LayoutConfig();
    return LayoutConfig(
      left: map.stringListOr('left'),
      center: map.stringListOr('center'),
      right: map.stringListOr('right'),
    );
  }

  Set<String> get enabledModules => {...left, ...center, ...right};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutConfig &&
          listEquals(other.left, left) &&
          listEquals(other.center, center) &&
          listEquals(other.right, right);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(left),
        Object.hashAll(center),
        Object.hashAll(right),
      );
}

class PanelConfig {
  final String name;
  final int height;
  final int paddingHorizontal;
  final String anchor;
  final String layer;
  final LayoutConfig layout;

  const PanelConfig({
    this.name = 'default',
    this.height = 32,
    this.paddingHorizontal = 8,
    this.anchor = 'top',
    this.layer = 'top',
    this.layout = const LayoutConfig(),
  });

  factory PanelConfig.fromMap(String name, Map<String, dynamic> map) {
    return PanelConfig(
      name: name,
      height: map.intOr('height', 32),
      paddingHorizontal: map.intOr('padding_horizontal', 8),
      anchor: map.stringOr('anchor', 'top'),
      layer: map.stringOr('layer', 'top'),
      layout: LayoutConfig.fromMap(map.tableOrNull('layout')),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PanelConfig &&
          other.name == name &&
          other.height == height &&
          other.paddingHorizontal == paddingHorizontal &&
          other.anchor == anchor &&
          other.layer == layer &&
          other.layout == layout;

  @override
  int get hashCode => Object.hash(
        name,
        height,
        paddingHorizontal,
        anchor,
        layer,
        layout,
      );
}

/// One `[[calendar.world_clocks]]` entry: a row in the clock column on the
/// right of the calendar tab.
class WorldClock {
  /// An IANA zone name, e.g. `Europe/London`.
  ///
  /// Deliberately not validated here: this file is parsed at start-up and must
  /// not depend on the timezone database, and a name this build's database does
  /// not carry is still the user's data — the tab renders it as an unknown-zone
  /// row it can delete rather than dropping it on the next write.
  final String zone;

  /// Display override. Null falls back to the zone's city segment.
  final String? label;

  const WorldClock({required this.zone, this.label});

  /// Parses one table, or null when it names no zone.
  static WorldClock? fromMap(Map<String, dynamic> map) {
    final zone = map.stringOrNull('zone');
    if (zone == null) return null;
    return WorldClock(zone: zone, label: map.stringOrNull('label'));
  }

  /// The TOML table for this clock. `label` is omitted when the user has not
  /// renamed it, so a list that was never edited stays minimal.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'zone': zone,
        if (label != null) 'label': label,
      };

  /// Parses a raw `world_clocks` value into clocks, dropping the invalid ones.
  ///
  /// Shared by [CalendarConfig.fromMap] and the calendar tab's own `ConfigStore`
  /// read, so the two can never disagree about what a valid row is.
  static List<WorldClock> parseList(Object? raw) => raw is List
      ? raw
          .whereType<Map<String, dynamic>>()
          .map(WorldClock.fromMap)
          .whereType<WorldClock>()
          .toList()
      : const <WorldClock>[];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorldClock &&
          other.zone == zone &&
          other.label == label;

  @override
  int get hashCode => Object.hash(zone, label);
}

/// The `[calendar]` section: the month grid's own presentation plus the clocks
/// shown beside it. The Google events it can also show are `[google]`'s.
class CalendarConfig {
  /// A [DateTime] weekday constant: [DateTime.sunday] or [DateTime.monday].
  final int weekStart;

  /// The `[[calendar.world_clocks]]` list, in document order — which is also
  /// the order they are drawn in.
  final List<WorldClock> worldClocks;

  const CalendarConfig({
    this.weekStart = DateTime.sunday,
    this.worldClocks = const <WorldClock>[],
  });

  factory CalendarConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const CalendarConfig();

    final weekStart = map.stringOr('week_start', 'sunday').toLowerCase();

    return CalendarConfig(
      weekStart: weekStart == 'monday' ? DateTime.monday : DateTime.sunday,
      worldClocks: WorldClock.parseList(map['world_clocks']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarConfig &&
          other.weekStart == weekStart &&
          listEquals(other.worldClocks, worldClocks);

  @override
  int get hashCode => Object.hash(weekStart, Object.hashAll(worldClocks));
}

/// The on-screen indicator shown when volume, microphone volume, or screen
/// brightness changes, and the sound a volume change makes.
class OsdConfig {
  final bool enabled;

  /// Inactivity before the indicator fades out.
  final int hideDelayMs;

  /// Distance from the bottom edge of the screen, in logical pixels.
  final int margin;

  /// What plays when the default output's volume or mute moves: a shipped
  /// voice, a sound-theme name, a path, or `none`. See
  /// `lib/osd/volume_sound.dart`.
  final String volumeSound;

  /// How loud [volumeSound] is, 0 to 1, relative to the output's own level.
  final double volumeSoundVolume;

  const OsdConfig({
    this.enabled = true,
    this.hideDelayMs = 1500,
    this.margin = 96,
    this.volumeSound = kDefaultVolumeSound,
    this.volumeSoundVolume = kDefaultVolumeSoundVolume,
  });

  factory OsdConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const OsdConfig();
    return OsdConfig(
      enabled: map.boolOr('enabled', true),
      // A zero delay would hide the indicator before it finished fading in.
      hideDelayMs: map.intOr('hide_delay_ms', 1500, min: 100),
      margin: map.intOr('margin', 96),
      volumeSound: map.stringOr('volume_sound', kDefaultVolumeSound),
      volumeSoundVolume: map.doubleOr(
        'volume_sound_volume',
        kDefaultVolumeSoundVolume,
        min: 0.0,
        max: 1.0,
      ),
    );
  }

  /// What [VolumeSoundStore] is configured with.
  VolumeSoundConfig get volumeSoundConfig =>
      VolumeSoundConfig(sound: volumeSound, volume: volumeSoundVolume);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OsdConfig &&
          other.enabled == enabled &&
          other.hideDelayMs == hideDelayMs &&
          other.margin == margin &&
          other.volumeSound == volumeSound &&
          other.volumeSoundVolume == volumeSoundVolume;

  @override
  int get hashCode => Object.hash(
        enabled,
        hideDelayMs,
        margin,
        volumeSound,
        volumeSoundVolume,
      );
}

/// Screen sharing — the shell's xdg-desktop-portal ScreenCast backend.
class ScreenshareConfig {
  /// Whether to claim the ScreenCast backend bus name at all. Turning this
  /// off lets another backend (xdg-desktop-portal-wlr) take over without
  /// uninstalling anything.
  final bool enabled;

  /// Frame rate for the picker's live previews. Deliberately low: the picker
  /// runs one capture session per monitor *and* per window simultaneously.
  final int previewFps;

  /// Cap on the shared stream's frame rate. 0 follows the output's refresh
  /// rate; windows fall back to 60.
  final int maxFps;

  const ScreenshareConfig({
    this.enabled = true,
    this.previewFps = 10,
    this.maxFps = 0,
  });

  factory ScreenshareConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ScreenshareConfig();
    return ScreenshareConfig(
      enabled: map.boolOr('enabled', true),
      previewFps: map.intOr('preview_fps', 10, min: 1, max: 60),
      maxFps: map.intOr('max_fps', 0, min: 0),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScreenshareConfig &&
          other.enabled == enabled &&
          other.previewFps == previewFps &&
          other.maxFps == maxFps;

  @override
  int get hashCode => Object.hash(enabled, previewFps, maxFps);
}

/// The lock screen: its wallpaper and the chrome drawn over it.
///
/// Unlike [BackgroundConfig] this holds a single wallpaper rather than a
/// rotating list — a lock screen has no reason to cycle — but it accepts the
/// same image *and* video paths, rendered by the shared `MediaBackground`.
class LockConfig {
  /// Wallpaper path (image or video). Null falls back to the shipped default.
  final String? background;

  final BackgroundFit fit;

  /// Whether to show the account's name above the unlock control.
  final bool showUsername;

  /// Gaussian blur applied to the wallpaper once the password field is shown.
  final double blurSigma;

  const LockConfig({
    this.background,
    this.fit = BackgroundFit.fill,
    this.showUsername = true,
    this.blurSigma = 18.0,
  });

  factory LockConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const LockConfig();
    return LockConfig(
      background: map.stringOrNull('background'),
      fit: BackgroundFit.fromString(map.stringOr('fit', 'fill')),
      showUsername: map.boolOr('show_username', true),
      // A negative sigma throws inside ImageFilter.blur; clamp rather than
      // let a hand-edited config crash the lock screen.
      blurSigma: map.doubleOr('blur_sigma', 18.0, min: 0.0, max: 100.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LockConfig &&
          other.background == background &&
          other.fit == fit &&
          other.showUsername == showUsername &&
          other.blurSigma == blurSigma;

  @override
  int get hashCode => Object.hash(background, fit, showUsername, blurSigma);
}

/// Super+S. Spelled numerically because a const field cannot call a function;
/// `test/shortcut_parse_test.dart` asserts the two agree.
///
/// Unshifted (`s`, not `S`) — the shifted form is only what Mir matches when
/// Shift is part of the combination, [parseShortcut]'s rule.
const ShortcutSpec kDefaultOpenSettings =
    ShortcutSpec(modifiers: 0x800, keysym: 0x73);

/// Super+D.
const ShortcutSpec kDefaultOpenLauncher =
    ShortcutSpec(modifiers: 0x800, keysym: 0x64);

/// Ctrl+Shift+E, the emoji picker. The shifted keysym (`E`, not `e`) is what
/// Mir matches on once Shift is held — see [parseShortcut] — and it is spelled
/// numerically for [kDefaultOpenSettings]'s reason;
/// `test/shortcut_parse_test.dart` asserts the two agree.
const ShortcutSpec kDefaultOpenEmoji =
    ShortcutSpec(modifiers: 0x108, keysym: 0x45);

/// Super+N, the notification panel.
const ShortcutSpec kDefaultOpenNotifications =
    ShortcutSpec(modifiers: 0x800, keysym: 0x6e);

/// Super+Shift+E, the power menu. The shifted keysym (`E`, not `e`) is what
/// Mir matches on once Shift is held — see [parseShortcut] — and it is spelled
/// numerically for [kDefaultOpenSettings]'s reason;
/// `test/shortcut_parse_test.dart` asserts the two agree.
const ShortcutSpec kDefaultOpenPowerMenu =
    ShortcutSpec(modifiers: 0x808, keysym: 0x45);

/// Print Screen on its own: a screenshot of an area the user drags out.
const ShortcutSpec kDefaultScreenshotArea =
    ShortcutSpec(modifiers: 0, keysym: 0xff61);

/// Super+Print Screen: record the screen the user is on.
const ShortcutSpec kDefaultRecordScreen =
    ShortcutSpec(modifiers: 0x800, keysym: 0xff61);

/// Alt+Tab, the window switcher.
///
/// The one shortcut in this file that is a *held* gesture rather than a toggle:
/// the trigger opens the switcher and each further press moves the selection,
/// and letting go of Alt is what commits — which the overlay reads off the
/// keyboard, because the trigger's own `end` fires when Tab comes up rather
/// than when Alt does. So the modifier is not decoration here: a binding with
/// no modifier at all would have nothing to release, and the switcher would be
/// a menu the user has to dismiss.
const ShortcutSpec kDefaultSwitchWindows =
    ShortcutSpec(modifiers: 0x01, keysym: 0xff09);

/// Alt+Shift+Tab, the window switcher going the other way.
///
/// The keysym is `ISO_Left_Tab` (`0xfe20`), not `Tab`: xkb resolves Shift+Tab
/// to it on every layout and Mir matches the resolved keysym — see
/// [parseShortcut], which does that resolution, and
/// `test/shortcut_parse_test.dart`, which asserts this constant and the string
/// `"alt+shift+tab"` still agree.
const ShortcutSpec kDefaultSwitchWindowsBack =
    ShortcutSpec(modifiers: 0x09, keysym: kIsoLeftTabKeysym);

/// The machine's own power button — `XF86PowerOff`, no modifiers.
///
/// Bound like any other shortcut because to the compositor it *is* one: the ACPI
/// power button is an input device emitting `KEY_POWER`. What it is not is the
/// shell's alone — systemd-logind reads the same device and powers the machine
/// off on a press — so this is only half of intercepting the button;
/// `[power] inhibit_logind` is the other half.
const ShortcutSpec kDefaultPowerButton =
    ShortcutSpec(modifiers: 0, keysym: 0x1008ff2a);

/// Super+Z: show the scratchpad, or hide it again if it is showing.
///
/// A letter rather than sway's `minus`, because miracle already binds
/// Super+Minus and Super+Underscore (Super+Shift+Minus) to the magnifier.
const ShortcutSpec kDefaultToggleScratchpad =
    ShortcutSpec(modifiers: 0x800, keysym: 0x7a);

/// Super+Shift+Z: stash the focused window on the scratchpad. The shifted
/// keysym (`Z`, not `z`) for [kDefaultOpenEmoji]'s reason, and
/// [kDefaultToggleScratchpad]'s neighbour on the same key for
/// [kDefaultOpenPowerMenu]'s.
const ShortcutSpec kDefaultMoveToScratchpad =
    ShortcutSpec(modifiers: 0x808, keysym: 0x5a);

/// The compositor-level shortcuts the shell registers at start-up.
///
/// A null field means the shortcut is *disabled* (the user wrote `""`), which is
/// distinct from the key being absent — absent falls back to the default.
///
/// Registration latches on the first successful handshake, so these are read once
/// from the startup snapshot and editing them needs a restart. Which is why
/// `shortcuts` is part of `ConfigStore._restartSignature()`: the keybind cheat
/// sheet edits these in place (`keybinds/shell_keybind_store.dart`), and both
/// the sheet's own notice and the settings overlay's "restart to apply" banner
/// have to say so.
class ShortcutsConfig {
  final ShortcutSpec? openSettings;
  final ShortcutSpec? openLauncher;

  /// The emoji picker (Ctrl+Shift+E by default).
  final ShortcutSpec? openEmoji;

  /// The notification panel (Super+N by default). A toggle, exactly as the
  /// bell module's own click is: the root owns the one panel and decides.
  final ShortcutSpec? openNotifications;

  /// The power menu (Super+Shift+E by default). A toggle, exactly as the system
  /// module's own power button is: the root owns the one menu and decides.
  ///
  /// Distinct from [powerButton], which is where the machine's physical key is
  /// picked up and whose press is resolved through `[power] key_action`. This
  /// one always means the menu.
  final ShortcutSpec? openPowerMenu;

  /// A screenshot of an area the user drags out (Print Screen by default).
  final ShortcutSpec? screenshotArea;

  /// Recording the whole of the screen the user is on (Super+Print Screen by
  /// default). Pressing it again stops the recording — the shell records one
  /// screen at a time, and a shell whose bar carries no recorder module would
  /// otherwise have no way to end what this started.
  final ShortcutSpec? recordScreen;

  /// The key the machine's power button produces. What a press *does* is
  /// `[power] key_action`, which is live; this is only where the key is
  /// picked up, and like the others it latches at start-up.
  final ShortcutSpec? powerButton;

  /// The window switcher, forwards (Alt+Tab by default).
  final ShortcutSpec? switchWindows;

  /// The window switcher, backwards (Alt+Shift+Tab by default).
  ///
  /// Its own key rather than "the other one with Shift", because the two are
  /// registered as two triggers: a trigger fires only when *exactly* its
  /// modifier set is held, so the compositor cannot derive one from the other.
  final ShortcutSpec? switchWindowsBack;

  /// Shows the scratchpad, or hides it (Super+Z by default) — the scratchpad
  /// module's own click. What the key reaches is miracle's `scratchpad show`,
  /// so a shell with no IPC connection does nothing with it.
  final ShortcutSpec? toggleScratchpad;

  /// Stashes the focused window on the scratchpad (Super+Shift+Z by default).
  /// "Focused" is miracle's, not the shell's: a panel never takes the keyboard,
  /// so the window the user was typing in is still the one selected.
  final ShortcutSpec? moveToScratchpad;

  const ShortcutsConfig({
    this.openSettings = kDefaultOpenSettings,
    this.openLauncher = kDefaultOpenLauncher,
    this.openEmoji = kDefaultOpenEmoji,
    this.openNotifications = kDefaultOpenNotifications,
    this.openPowerMenu = kDefaultOpenPowerMenu,
    this.screenshotArea = kDefaultScreenshotArea,
    this.recordScreen = kDefaultRecordScreen,
    this.powerButton = kDefaultPowerButton,
    this.switchWindows = kDefaultSwitchWindows,
    this.switchWindowsBack = kDefaultSwitchWindowsBack,
    this.toggleScratchpad = kDefaultToggleScratchpad,
    this.moveToScratchpad = kDefaultMoveToScratchpad,
  });

  factory ShortcutsConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ShortcutsConfig();
    return ShortcutsConfig(
      openSettings: _read(map, 'open_settings', kDefaultOpenSettings),
      openLauncher: _read(map, 'open_launcher', kDefaultOpenLauncher),
      openEmoji: _read(map, 'open_emoji', kDefaultOpenEmoji),
      openNotifications:
          _read(map, 'open_notifications', kDefaultOpenNotifications),
      openPowerMenu: _read(map, 'open_power_menu', kDefaultOpenPowerMenu),
      screenshotArea: _read(map, 'screenshot_area', kDefaultScreenshotArea),
      recordScreen: _read(map, 'record_screen', kDefaultRecordScreen),
      powerButton: _read(map, 'power_button', kDefaultPowerButton),
      switchWindows: _read(map, 'switch_windows', kDefaultSwitchWindows),
      switchWindowsBack:
          _read(map, 'switch_windows_back', kDefaultSwitchWindowsBack),
      toggleScratchpad:
          _read(map, 'toggle_scratchpad', kDefaultToggleScratchpad),
      moveToScratchpad:
          _read(map, 'move_to_scratchpad', kDefaultMoveToScratchpad),
    );
  }

  /// Reads one shortcut, falling back to [fallback] on anything unusable. Each
  /// key is read independently so a typo in one does not disable the other —
  /// and, like every other config class here, a wrongly-typed value is tested
  /// for rather than cast, because a throw would discard the whole config.
  static ShortcutSpec? _read(
      Map<String, dynamic> map, String key, ShortcutSpec fallback) {
    if (!map.containsKey(key)) return fallback;
    final raw = map[key];
    if (raw is! String) {
      debugPrint('config: [shortcuts].$key is not a string; using the default');
      return fallback;
    }
    final trimmed = raw.trim().toLowerCase();
    // An explicit empty string (or "none") disables the shortcut entirely.
    if (trimmed.isEmpty || trimmed == 'none') return null;
    final spec = parseShortcut(raw);
    if (spec == null) {
      debugPrint('config: [shortcuts].$key ("$raw") is not a shortcut the '
          'shell understands; using the default');
      return fallback;
    }
    return spec;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShortcutsConfig &&
          other.openSettings == openSettings &&
          other.openLauncher == openLauncher &&
          other.openEmoji == openEmoji &&
          other.openNotifications == openNotifications &&
          other.openPowerMenu == openPowerMenu &&
          other.screenshotArea == screenshotArea &&
          other.recordScreen == recordScreen &&
          other.powerButton == powerButton &&
          other.switchWindows == switchWindows &&
          other.switchWindowsBack == switchWindowsBack &&
          other.toggleScratchpad == toggleScratchpad &&
          other.moveToScratchpad == moveToScratchpad;

  @override
  int get hashCode => Object.hash(
        openSettings,
        openLauncher,
        openEmoji,
        openNotifications,
        openPowerMenu,
        screenshotArea,
        recordScreen,
        powerButton,
        switchWindows,
        switchWindowsBack,
        toggleScratchpad,
        moveToScratchpad,
      );
}

class AppConfig {
  final Map<String, PanelConfig> panels;
  final BackgroundConfig? background;

  /// The name of the active theme — the basename of a file under
  /// `~/.config/moonswing/themes/`. Resolving it to a [ThemeConfig] is
  /// `ThemeStore`'s job, not this one's; nothing here touches the disk.
  final String themeName;

  /// The desktop icon grid. Never null — an absent `[desktop]` section is a
  /// disabled grid, not "no grid config", so callers never null-check it.
  final DesktopConfig desktop;

  final CalendarConfig calendar;
  final OsdConfig osd;
  final LockConfig lock;
  final ShortcutsConfig shortcuts;
  final ScreenshareConfig screenshare;

  /// What the physical power button does. Never null — an absent `[power]`
  /// section is the default (show the power menu), not "no power config".
  final PowerConfig power;

  /// Whether the shell is this session's polkit authentication agent. Never
  /// null — an absent `[polkit]` section is the default (be the agent), not
  /// "no polkit config".
  final PolkitConfig polkit;

  /// What the shell does with the Google account (Settings › Accounts). Never
  /// null; the account itself is not config, see `google_account_file.dart`.
  final GoogleConfig google;

  /// What the shell does with the CalDAV accounts (Settings › Accounts). Never
  /// null; the accounts themselves are not config, see
  /// `caldav_account_store.dart`.
  final CalDavConfig caldav;

  const AppConfig({
    this.panels = const {'default': PanelConfig()},
    this.background,
    this.desktop = const DesktopConfig(),
    this.themeName = kDefaultThemeName,
    this.calendar = const CalendarConfig(),
    this.osd = const OsdConfig(),
    this.lock = const LockConfig(),
    this.shortcuts = const ShortcutsConfig(),
    this.screenshare = const ScreenshareConfig(),
    this.power = const PowerConfig(),
    this.polkit = const PolkitConfig(),
    this.google = const GoogleConfig(),
    this.caldav = const CalDavConfig(),
  });

  /// Resolves the absolute path to `config.toml`, honouring
  /// `XDG_CONFIG_HOME`. Shared by the loader and the settings writer so the
  /// two never diverge.
  static String resolveConfigPath() {
    final homeDir = Platform.environment['HOME'] ?? '';
    final configHome =
        Platform.environment['XDG_CONFIG_HOME'] ?? '$homeDir/.config';
    return '$configHome/moonswing/config.toml';
  }

  static Future<AppConfig> load() async {
    final homeDir = Platform.environment['HOME'] ?? '';
    final configPath = resolveConfigPath();
    final file = File(configPath);

    if (!await file.exists()) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(buildDefaultConfig(homeDir));
      } catch (_) {
        // Could not write default config; proceed with defaults
      }
      try {
        final doc = TomlDocument.parse(buildDefaultConfig(homeDir));
        return AppConfig.fromMap(doc.toMap());
      } catch (_) {
        return const AppConfig();
      }
    }

    try {
      final document = await TomlDocument.load(configPath);
      final map = document.toMap();
      return AppConfig.fromMap(map);
    } catch (e) {
      // A TOML syntax error is the one failure that still costs the whole
      // file — everything past the parser degrades per field (TomlReader).
      // Say so on stderr: silently reverting every panel to defaults reads
      // as a broken shell, not a broken config.
      stderr.writeln('moonswing: failed to parse $configPath: $e — '
          'using the default configuration');
      return const AppConfig();
    }
  }

  /// Builds a typed config from an already-parsed TOML map. Also applies the
  /// module subtable to every registered module via [Module.loadAll], so
  /// rebuilding an [AppConfig] from a live config map re-applies per-module
  /// options as a side effect.
  factory AppConfig.fromMap(Map<String, dynamic> map) {
    Module.loadAll(map.tableOrNull('modules'));

    final panels = <String, PanelConfig>{};
    final panelsMap = map.tableOrNull('panels') ?? const <String, dynamic>{};
    for (final entry in panelsMap.entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) continue;
      panels[entry.key] = PanelConfig.fromMap(entry.key, value);
    }

    final backgroundMap = map.tableOrNull('background');
    final background =
        backgroundMap != null ? BackgroundConfig.fromMap(backgroundMap) : null;

    final desktopMap = map.tableOrNull('desktop');
    final desktop = desktopMap != null
        ? DesktopConfig.fromMap(desktopMap)
        : const DesktopConfig();

    // `theme` used to be a table and is now a name, so an un-migrated config
    // still has a map here — a stale [theme] table must cost the theme,
    // nothing else.
    final themeName = map.stringOrNull('theme') ?? kDefaultThemeName;

    return AppConfig(
      panels: panels.isEmpty ? const {'default': PanelConfig()} : panels,
      background: background,
      desktop: desktop,
      themeName: themeName,
      calendar: CalendarConfig.fromMap(map.tableOrNull('calendar')),
      osd: OsdConfig.fromMap(map.tableOrNull('osd')),
      lock: LockConfig.fromMap(map.tableOrNull('lock')),
      shortcuts: ShortcutsConfig.fromMap(map.tableOrNull('shortcuts')),
      screenshare: ScreenshareConfig.fromMap(map.tableOrNull('screenshare')),
      power: PowerConfig.fromMap(map.tableOrNull('power')),
      polkit: PolkitConfig.fromMap(map.tableOrNull('polkit')),
      google: GoogleConfig.fromMap(map.tableOrNull('google')),
      caldav: CalDavConfig.fromMap(map.tableOrNull('caldav')),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppConfig &&
          mapEquals(other.panels, panels) &&
          other.background == background &&
          other.themeName == themeName &&
          other.desktop == desktop &&
          other.calendar == calendar &&
          other.osd == osd &&
          other.lock == lock &&
          other.shortcuts == shortcuts &&
          other.screenshare == screenshare &&
          other.power == power &&
          other.polkit == polkit &&
          other.google == google &&
          other.caldav == caldav;

  /// Hashed on the panel count alone: equal maps have equal
  /// lengths, and two maps that are equal can still iterate in
  /// different orders, so anything finer would break the
  /// hashCode contract. Nothing here is ever a hash key.
  @override
  int get hashCode => Object.hash(
        panels.length,
        background,
        themeName,
        desktop,
        calendar,
        osd,
        lock,
        shortcuts,
        screenshare,
        power,
        polkit,
        google,
        caldav,
      );
}
