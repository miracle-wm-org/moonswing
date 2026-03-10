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
  final Color sliderTrack;
  final Color muted;
  final Color divider;

  const ThemeConfig({
    this.foreground = const Color(0xFFE0E0E0),
    this.accent = const Color(0xFF4A90E2),
    this.surfaceHover = const Color(0xFF4A4A4A),
    this.surfacePressed = const Color(0xFF2A2A2A),
    this.workspaceBackground = const Color(0xFF3A3A3A),
    this.popupBackground = const Color(0xFF1E1E2E),
    this.popupForeground = const Color(0xFFCDD6F4),
    this.sliderTrack = const Color(0xFF45475A),
    this.muted = const Color(0xFFE06C75),
    this.divider = const Color(0x33FFFFFF),
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
          _parseColor(map['foreground'] as String?, const Color(0xFFE0E0E0)),
      accent: _parseColor(map['accent'] as String?, const Color(0xFF4A90E2)),
      surfaceHover:
          _parseColor(map['surface_hover'] as String?, const Color(0xFF4A4A4A)),
      surfacePressed: _parseColor(
          map['surface_pressed'] as String?, const Color(0xFF2A2A2A)),
      workspaceBackground: _parseColor(
          map['workspace_background'] as String?, const Color(0xFF3A3A3A)),
      popupBackground: _parseColor(
          map['popup_background'] as String?, const Color(0xFF1E1E2E)),
      popupForeground: _parseColor(
          map['popup_foreground'] as String?, const Color(0xFFCDD6F4)),
      sliderTrack:
          _parseColor(map['slider_track'] as String?, const Color(0xFF45475A)),
      muted: _parseColor(map['muted'] as String?, const Color(0xFFE06C75)),
      divider: _parseColor(map['divider'] as String?, const Color(0x33FFFFFF)),
    );
  }
}

class BackgroundEntry {
  final String path;
  final Duration timeOfDay;

  const BackgroundEntry({required this.path, required this.timeOfDay});

  factory BackgroundEntry.fromMap(Map<String, dynamic> map) {
    final path = map['path'] as String? ?? '';
    final timeStr = map['time'] as String? ?? '00:00';
    return BackgroundEntry(
      path: path,
      timeOfDay: _parseTime(timeStr),
    );
  }

  static Duration _parseTime(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return Duration.zero;
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    return Duration(hours: hours, minutes: minutes);
  }
}

class BackgroundConfig {
  final BackgroundFit fit;
  final List<BackgroundEntry> entries;

  const BackgroundConfig({
    this.fit = BackgroundFit.fill,
    this.entries = const [],
  });

  factory BackgroundConfig.fromMap(Map<String, dynamic> map) {
    final fitStr = map['fit'] as String? ?? 'fill';
    final rawEntries = map['entries'] as List<dynamic>? ?? [];
    final entries = rawEntries
        .whereType<Map<String, dynamic>>()
        .map(BackgroundEntry.fromMap)
        .toList()
      ..sort((a, b) => a.timeOfDay.compareTo(b.timeOfDay));
    return BackgroundConfig(
      fit: BackgroundFit.fromString(fitStr),
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

  static const _defaultConfig = '''
[panels.top]
height = 32
padding_horizontal = 40
anchor = "top"
layer = "top"

[panels.top.layout]
left = ["workspaces"]
center = ["media_player"]
right = ["sound_control", "battery", "weather", "clock", "system"]

[modules.weather]
unit = "fahrenheit"
refresh_minutes = 10

[modules.battery]
poll_seconds = 30

[modules.clock]
show_date = true

[modules.media_player]
max_text_width = 200.0
''';

  static Future<AppConfig> load() async {
    final configHome = Platform.environment['XDG_CONFIG_HOME'] ??
        '${Platform.environment['HOME']}/.config';
    final configPath = '$configHome/graceful-panel/config.toml';
    final file = File(configPath);

    if (!await file.exists()) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(_defaultConfig);
      } catch (_) {
        // Could not write default config; proceed with defaults
      }
      return const AppConfig(background: null);
    }

    try {
      final document = await TomlDocument.load(configPath);
      final map = document.toMap();
      return AppConfig._fromMap(map);
    } catch (_) {
      return const AppConfig();
    }
  }

  factory AppConfig._fromMap(Map<String, dynamic> map) {
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
