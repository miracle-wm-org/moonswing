import 'dart:io';
import 'dart:ui';
import 'package:toml/toml.dart';
import 'package:graceful_shell/module.dart';

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

class ThemeConfig {
  final Color foreground;
  final Color accent;
  final Color surfaceHover;
  final Color surfacePressed;
  final Color workspaceBackground;
  final Color popupBackground;
  final Color popupForeground;
  final Color controlSurface;
  final Color sliderTrack;
  final Color muted;
  final Color divider;
  final String fontFamily;

  const ThemeConfig({
    this.foreground = const Color(0xFFF3F4F4),
    this.accent = const Color(0xFF853953),
    this.surfaceHover = const Color(0xFF853953),
    this.surfacePressed = const Color(0xFF612D53),
    this.workspaceBackground = const Color(0xFF2C2C2C),
    this.popupBackground = const Color(0xFF2C2C2C),
    this.popupForeground = const Color(0xFFF3F4F4),
    this.controlSurface = const Color(0xFF39393D),
    this.sliderTrack = const Color(0xFF612D53),
    this.muted = const Color(0xFF853953),
    this.divider = const Color(0x33F3F4F4),
    this.fontFamily = 'Ubuntu Sans',
  });

  static Color _parseColor(String? hex, Color fallback) {
    if (hex == null) return fallback;
    final s = hex.startsWith('#') ? hex.substring(1) : hex;
    final value = int.tryParse(s.length == 6 ? 'FF$s' : s, radix: 16);
    return value != null ? Color(value) : fallback;
  }

  factory ThemeConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ThemeConfig();
    return ThemeConfig(
      foreground:
          _parseColor(map['foreground'] as String?, const Color(0xFFF3F4F4)),
      accent: _parseColor(map['accent'] as String?, const Color(0xFF853953)),
      surfaceHover:
          _parseColor(map['surface_hover'] as String?, const Color(0xFF853953)),
      surfacePressed: _parseColor(
          map['surface_pressed'] as String?, const Color(0xFF612D53)),
      workspaceBackground: _parseColor(
          map['workspace_background'] as String?, const Color(0xFF2C2C2C)),
      popupBackground: _parseColor(
          map['popup_background'] as String?, const Color(0xFF2C2C2C)),
      popupForeground: _parseColor(
          map['popup_foreground'] as String?, const Color(0xFFF3F4F4)),
      controlSurface: _parseColor(
          map['control_surface'] as String?, const Color(0xFF39393D)),
      sliderTrack:
          _parseColor(map['slider_track'] as String?, const Color(0xFF612D53)),
      muted: _parseColor(map['muted'] as String?, const Color(0xFF853953)),
      divider: _parseColor(map['divider'] as String?, const Color(0x33F3F4F4)),
      fontFamily: map['font'] as String? ?? 'Ubuntu Sans',
    );
  }
}

/// File extensions considered valid image wallpapers. Paths with any other
/// extension (or none) are treated as invalid and auto-pruned by the selector.
const Set<String> imageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.bmp',
};

/// Whether [path] points at a supported image file, judged purely by its
/// extension. Existence is checked separately at call sites so this stays a
/// pure, unit-testable predicate.
bool isImagePath(String path) {
  final lower = path.toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot < 0) return false;
  return imageExtensions.contains(lower.substring(dot));
}

class BackgroundEntry {
  final String path;
  final bool shown;

  const BackgroundEntry({required this.path, this.shown = true});

  factory BackgroundEntry.fromMap(Map<String, dynamic> map) {
    final path = map['path'] as String? ?? '';
    final shown = map['shown'] as bool? ?? true;
    return BackgroundEntry(path: path, shown: shown);
  }
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
    final fitStr = map['fit'] as String? ?? 'fill';
    final rawInterval = map['interval_minutes'];
    final interval = rawInterval is num ? rawInterval.toInt() : 5;
    final rawEntries = map['entries'] as List<dynamic>? ?? [];
    // List order is the canonical presentation order — do not sort.
    final entries = rawEntries
        .whereType<Map<String, dynamic>>()
        .map(BackgroundEntry.fromMap)
        .toList();
    return BackgroundConfig(
      fit: BackgroundFit.fromString(fitStr),
      intervalMinutes: interval < 1 ? 1 : interval,
      entries: entries,
    );
  }
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
      left: _parseModuleList(map['left']),
      center: _parseModuleList(map['center']),
      right: _parseModuleList(map['right']),
    );
  }

  static List<String> _parseModuleList(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];
    return value.whereType<String>().toList();
  }

  Set<String> get enabledModules => {...left, ...center, ...right};
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
    this.paddingHorizontal = 12,
    this.anchor = 'top',
    this.layer = 'top',
    this.layout = const LayoutConfig(),
  });

  factory PanelConfig.fromMap(String name, Map<String, dynamic> map) {
    final layoutMap = map['layout'] as Map<String, dynamic>?;
    return PanelConfig(
      name: name,
      height: map['height'] as int? ?? 32,
      paddingHorizontal: map['padding_horizontal'] as int? ?? 40,
      anchor: map['anchor'] as String? ?? 'top',
      layer: map['layer'] as String? ?? 'top',
      layout: LayoutConfig.fromMap(layoutMap),
    );
  }
}

class AppConfig {
  final Map<String, PanelConfig> panels;
  final BackgroundConfig? background;
  final ThemeConfig theme;

  const AppConfig({
    this.panels = const {'default': PanelConfig()},
    this.background,
    this.theme = const ThemeConfig(),
  });

  static String _buildDefaultConfig(String homeDir) => '''
[panels.top]
height = 32
padding_horizontal = 40
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
right = ["media_player"]

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

[background]
fit = "fill"
interval_minutes = 5

[[background.entries]]
path = "$homeDir/.local/share/graceful-shell/wallpaper.jpg"
shown = true
''';

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
        await file.writeAsString(_buildDefaultConfig(homeDir));
      } catch (_) {
        // Could not write default config; proceed with defaults
      }
      try {
        final doc = TomlDocument.parse(_buildDefaultConfig(homeDir));
        return AppConfig.fromMap(doc.toMap());
      } catch (_) {
        return const AppConfig();
      }
    }

    try {
      final document = await TomlDocument.load(configPath);
      final map = document.toMap();
      return AppConfig.fromMap(map);
    } catch (_) {
      return const AppConfig();
    }
  }

  /// Builds a typed config from an already-parsed TOML map. Also applies the
  /// module subtable to every registered module via [Module.loadAll], so
  /// rebuilding an [AppConfig] from a live config map re-applies per-module
  /// options as a side effect.
  factory AppConfig.fromMap(Map<String, dynamic> map) {
    final modulesMap = map['modules'] as Map<String, dynamic>?;
    Module.loadAll(modulesMap);

    final panels = <String, PanelConfig>{};

    if (map.containsKey('panels')) {
      final panelsMap = map['panels'] as Map<String, dynamic>;
      for (final entry in panelsMap.entries) {
        panels[entry.key] = PanelConfig.fromMap(
          entry.key,
          entry.value as Map<String, dynamic>,
        );
      }
    }

    final backgroundMap = map['background'] as Map<String, dynamic>?;
    final background =
        backgroundMap != null ? BackgroundConfig.fromMap(backgroundMap) : null;

    final themeMap = map['theme'] as Map<String, dynamic>?;

    return AppConfig(
      panels: panels.isEmpty ? const {'default': PanelConfig()} : panels,
      background: background,
      theme: ThemeConfig.fromMap(themeMap),
    );
  }
}
