import 'dart:io';
import 'package:toml/toml.dart';

enum ModuleName {
  workspaces,
  mediaPlayer,
  soundControl,
  battery,
  weather,
  clock;

  static ModuleName? fromString(String s) {
    switch (s) {
      case 'workspaces':
        return ModuleName.workspaces;
      case 'media_player':
        return ModuleName.mediaPlayer;
      case 'sound_control':
        return ModuleName.soundControl;
      case 'battery':
        return ModuleName.battery;
      case 'weather':
        return ModuleName.weather;
      case 'clock':
        return ModuleName.clock;
      default:
        return null;
    }
  }
}

class WeatherConfig {
  final String unit;
  final int refreshMinutes;

  const WeatherConfig({
    this.unit = 'fahrenheit',
    this.refreshMinutes = 10,
  });

  factory WeatherConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const WeatherConfig();
    return WeatherConfig(
      unit: map['unit'] as String? ?? 'fahrenheit',
      refreshMinutes: map['refresh_minutes'] as int? ?? 10,
    );
  }
}

class BatteryConfig {
  final int pollSeconds;

  const BatteryConfig({this.pollSeconds = 30});

  factory BatteryConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const BatteryConfig();
    return BatteryConfig(
      pollSeconds: map['poll_seconds'] as int? ?? 30,
    );
  }
}

class ClockConfig {
  final bool showDate;

  const ClockConfig({this.showDate = true});

  factory ClockConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ClockConfig();
    return ClockConfig(
      showDate: map['show_date'] as bool? ?? true,
    );
  }
}

class MediaPlayerConfig {
  final double maxTextWidth;

  const MediaPlayerConfig({this.maxTextWidth = 200.0});

  factory MediaPlayerConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const MediaPlayerConfig();
    return MediaPlayerConfig(
      maxTextWidth: (map['max_text_width'] as num?)?.toDouble() ?? 200.0,
    );
  }
}

class ModulesConfig {
  final WeatherConfig weather;
  final BatteryConfig battery;
  final ClockConfig clock;
  final MediaPlayerConfig mediaPlayer;

  const ModulesConfig({
    this.weather = const WeatherConfig(),
    this.battery = const BatteryConfig(),
    this.clock = const ClockConfig(),
    this.mediaPlayer = const MediaPlayerConfig(),
  });

  factory ModulesConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ModulesConfig();
    return ModulesConfig(
      weather: WeatherConfig.fromMap(map['weather'] as Map<String, dynamic>?),
      battery: BatteryConfig.fromMap(map['battery'] as Map<String, dynamic>?),
      clock: ClockConfig.fromMap(map['clock'] as Map<String, dynamic>?),
      mediaPlayer: MediaPlayerConfig.fromMap(
          map['media_player'] as Map<String, dynamic>?),
    );
  }
}

class LayoutConfig {
  final List<ModuleName> left;
  final List<ModuleName> center;
  final List<ModuleName> right;

  const LayoutConfig({
    this.left = const [ModuleName.workspaces],
    this.center = const [ModuleName.mediaPlayer],
    this.right = const [
      ModuleName.soundControl,
      ModuleName.battery,
      ModuleName.weather,
      ModuleName.clock,
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

  static List<ModuleName> _parseModuleList(dynamic value) {
    if (value == null) return [];
    if (value is! List) return [];
    return value
        .whereType<String>()
        .map(ModuleName.fromString)
        .whereType<ModuleName>()
        .toList();
  }

  Set<ModuleName> get enabledModules => {...left, ...center, ...right};
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
    this.paddingHorizontal = 40,
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
  final ModulesConfig modules;

  const AppConfig({
    this.panels = const {'default': PanelConfig()},
    this.modules = const ModulesConfig(),
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
right = ["sound_control", "battery", "weather", "clock"]

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
      return const AppConfig();
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
    final modules = ModulesConfig.fromMap(modulesMap);

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

    return AppConfig(
      panels: panels.isEmpty ? const {'default': PanelConfig()} : panels,
      modules: modules,
    );
  }
}
