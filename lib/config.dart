/// The startup snapshot of `config.toml` — [AppConfig] and the per-section
/// config classes that still live here.
///
/// The sections that belong to a subsystem live beside it and are re-exported
/// below, so `import 'package:graceful_shell/config.dart'` keeps providing
/// every name it always has: the theme palette in `lib/theme/theme_config.dart`,
/// the desktop grid model in `lib/desktop/desktop_config.dart`, the generated
/// default config in `lib/default_config.dart`, and the media-extension
/// predicates in `lib/media_paths.dart` (whose `isVideoPath` is re-exported by
/// `lib/background.dart`, which historically defined it), and the power-button
/// policy in `lib/power/power_config.dart`.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:toml/toml.dart';

import 'package:graceful_shell/config_reader.dart';
import 'package:graceful_shell/default_config.dart';
import 'package:graceful_shell/desktop/desktop_config.dart';
import 'package:graceful_shell/input_trigger/keysym.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/polkit/polkit_config.dart';
import 'package:graceful_shell/power/power_config.dart';
import 'package:graceful_shell/theme/theme_config.dart';

export 'package:graceful_shell/default_config.dart';
export 'package:graceful_shell/desktop/desktop_config.dart';
export 'package:graceful_shell/keyboard/keyboard_config.dart';
export 'package:graceful_shell/media_paths.dart'
    show imageExtensions, videoExtensions, isImagePath;
export 'package:graceful_shell/polkit/polkit_config.dart';
export 'package:graceful_shell/power/power_config.dart';
export 'package:graceful_shell/theme/theme_config.dart';

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
  /// Deliberately not validated here. This file is parsed at start-up and must
  /// not depend on the timezone database, and a name this build's database
  /// variant does not carry is still the user's data: the tab renders it as an
  /// unknown-zone row it can delete rather than dropping it on the next write.
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

/// The `[calendar]` section. The calendar is a local month grid with no account
/// integration, so this is only the grid's own presentation plus the clocks
/// shown beside it.
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
/// brightness changes.
class OsdConfig {
  final bool enabled;

  /// Inactivity before the indicator fades out.
  final int hideDelayMs;

  /// Distance from the bottom edge of the screen, in logical pixels.
  final int margin;

  const OsdConfig({
    this.enabled = true,
    this.hideDelayMs = 1500,
    this.margin = 96,
  });

  factory OsdConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const OsdConfig();
    return OsdConfig(
      enabled: map.boolOr('enabled', true),
      // A zero delay would hide the indicator before it finished fading in.
      hideDelayMs: map.intOr('hide_delay_ms', 1500, min: 100),
      margin: map.intOr('margin', 96),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OsdConfig &&
          other.enabled == enabled &&
          other.hideDelayMs == hideDelayMs &&
          other.margin == margin;

  @override
  int get hashCode => Object.hash(enabled, hideDelayMs, margin);
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

/// Ctrl+Shift+S. The shifted keysym (`S`, not `s`) is what Mir matches on —
/// see [parseShortcut]. Spelled numerically because a const field cannot call a
/// function; `test/shortcut_parse_test.dart` asserts the two agree.
const ShortcutSpec kDefaultOpenSettings =
    ShortcutSpec(modifiers: 0x108, keysym: 0x53);

/// Ctrl+Space.
const ShortcutSpec kDefaultOpenLauncher =
    ShortcutSpec(modifiers: 0x100, keysym: 0x20);

/// Ctrl+Shift+E, the emoji picker. Shifted keysym (`E`, not `e`) for
/// [kDefaultOpenSettings]'s reason, and spelled numerically for the same one;
/// `test/shortcut_parse_test.dart` asserts the two agree.
const ShortcutSpec kDefaultOpenEmoji =
    ShortcutSpec(modifiers: 0x108, keysym: 0x45);

/// The machine's own power button — `XF86PowerOff`, no modifiers.
///
/// Bound like any other shortcut because to the compositor it *is* one: the
/// ACPI power button is an input device emitting `KEY_POWER`. What it is not
/// is the shell's alone — systemd-logind reads the same device and powers the
/// machine off on a press — so registering this is only half of intercepting
/// the button; `[power] inhibit_logind` is the other half. Spelled numerically
/// for the reason [kDefaultOpenSettings] is; `test/shortcut_parse_test.dart`
/// asserts it agrees with `parseShortcut('poweroff')`.
const ShortcutSpec kDefaultPowerButton =
    ShortcutSpec(modifiers: 0, keysym: 0x1008ff2a);

/// The compositor-level shortcuts the shell registers at start-up.
///
/// A null field means the shortcut is *disabled* (the user wrote `""`), which
/// is distinct from the key being absent — absent falls back to the default.
///
/// Registration latches on the first successful handshake
/// (`InputTriggerManager._registered`), so these are read once from the startup
/// snapshot and editing them needs a restart. If the settings UI ever grows a
/// shortcut editor, add `shortcuts` to `ConfigStore._restartSignature()` so the
/// "restart to apply" banner tells the truth.
class ShortcutsConfig {
  final ShortcutSpec? openSettings;
  final ShortcutSpec? openLauncher;

  /// The emoji picker (Ctrl+Shift+E by default).
  final ShortcutSpec? openEmoji;

  /// The key the machine's power button produces. What a press *does* is
  /// `[power] key_action`, which is live; this is only where the key is
  /// picked up, and like the other three it latches at start-up.
  final ShortcutSpec? powerButton;

  const ShortcutsConfig({
    this.openSettings = kDefaultOpenSettings,
    this.openLauncher = kDefaultOpenLauncher,
    this.openEmoji = kDefaultOpenEmoji,
    this.powerButton = kDefaultPowerButton,
  });

  factory ShortcutsConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ShortcutsConfig();
    return ShortcutsConfig(
      openSettings: _read(map, 'open_settings', kDefaultOpenSettings),
      openLauncher: _read(map, 'open_launcher', kDefaultOpenLauncher),
      openEmoji: _read(map, 'open_emoji', kDefaultOpenEmoji),
      powerButton: _read(map, 'power_button', kDefaultPowerButton),
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
          other.powerButton == powerButton;

  @override
  int get hashCode =>
      Object.hash(openSettings, openLauncher, openEmoji, powerButton);
}

class AppConfig {
  final Map<String, PanelConfig> panels;
  final BackgroundConfig? background;

  /// The name of the active theme — the basename of a file under
  /// `~/.config/graceful-shell/themes/`. Resolving it to a [ThemeConfig] is
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
  });

  /// Resolves the absolute path to `config.toml`, honouring
  /// `XDG_CONFIG_HOME`. Shared by the loader and the settings writer so the
  /// two never diverge.
  static String resolveConfigPath() {
    final homeDir = Platform.environment['HOME'] ?? '';
    final configHome =
        Platform.environment['XDG_CONFIG_HOME'] ?? '$homeDir/.config';
    return '$configHome/graceful-shell/config.toml';
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
      stderr.writeln('graceful-shell: failed to parse $configPath: $e — '
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
          other.polkit == polkit;

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
      );
}
