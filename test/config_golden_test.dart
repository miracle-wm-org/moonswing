import 'package:flutter_test/flutter_test.dart';
import 'package:toml/toml.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/theme/builtin_themes.dart';

/// Pins today's parse behaviour so the config refactor (the shared TomlReader,
/// and later the file splits) cannot silently change a default, a clamp, or a
/// key mapping. When one of these fails after an intentional change, update
/// the expectation deliberately — never by re-recording blind.
void main() {
  group('fromMap on an empty table equals the const defaults', () {
    test('ThemeConfig', () {
      expect(ThemeConfig.fromMap(const {}), const ThemeConfig());
      expect(ThemeConfig.fromMap(null), const ThemeConfig());
    });

    test('AppConfig', () {
      final config = AppConfig.fromMap(const {});
      expect(config.panels.keys.toList(), ['default']);
      expect(config.themeName, kDefaultThemeName);
      expect(config.background, isNull);
      expect(config.desktop.enabled, isFalse);
      expect(config.calendar.weekStart, DateTime.sunday);
      expect(config.calendar.worldClocks, isEmpty);
      expect(config.osd.enabled, isTrue);
      expect(config.osd.hideDelayMs, 1500);
      expect(config.osd.margin, 96);
      expect(config.lock.background, isNull);
      expect(config.lock.fit, BackgroundFit.fill);
      expect(config.lock.showUsername, isTrue);
      expect(config.lock.blurSigma, 18.0);
      expect(config.shortcuts.openSettings, kDefaultOpenSettings);
      expect(config.shortcuts.openLauncher, kDefaultOpenLauncher);
      expect(config.screenshare.enabled, isTrue);
      expect(config.screenshare.previewFps, 10);
      expect(config.screenshare.maxFps, 0);
    });
  });

  group('the generated default config parses to what it says', () {
    late AppConfig config;
    setUpAll(() {
      final toml = buildDefaultConfig('/home/golden');
      config = AppConfig.fromMap(TomlDocument.parse(toml).toMap());
    });

    test('panels', () {
      expect(config.panels.keys.toSet(), {'top', 'bottom'});
      final top = config.panels['top']!;
      expect(top.height, 32);
      expect(top.paddingHorizontal, 8);
      expect(top.anchor, 'top');
      expect(top.layer, 'top');
      expect(top.layout.left, ['workspaces']);
      expect(top.layout.center, ['clock']);
      expect(top.layout.right,
          ['sound_control', 'system_tray', 'battery', 'weather', 'system']);
      final bottom = config.panels['bottom']!;
      expect(bottom.height, 32);
      expect(bottom.paddingHorizontal, 0);
      expect(bottom.anchor, 'bottom');
      expect(bottom.layer, 'top');
      expect(bottom.layout.left, isEmpty);
      expect(bottom.layout.center, ['dock']);
      expect(bottom.layout.right, ['media_player', 'launcher']);
    });

    test('background', () {
      final bg = config.background!;
      expect(bg.fit, BackgroundFit.fill);
      expect(bg.intervalMinutes, 5);
      expect(bg.entries, hasLength(1));
      expect(bg.entries.single.path, endsWith('wallpaper.jpg'));
      expect(bg.entries.single.shown, isTrue);
    });

    test('theme, desktop, lock, shortcuts, screenshare', () {
      expect(config.themeName, 'graceful');
      expect(config.desktop.enabled, isFalse);
      expect(config.desktop.cellWidth, 96);
      expect(config.desktop.cellHeight, 96);
      expect(config.desktop.spacing, 12);
      expect(config.desktop.padding, 24);
      expect(config.desktop.iconSize, 48);
      expect(config.desktop.showLabels, isTrue);
      expect(config.desktop.items, isEmpty);
      expect(config.lock.background, endsWith('lock-wallpaper.jpg'));
      expect(config.lock.fit, BackgroundFit.fill);
      expect(config.lock.showUsername, isTrue);
      expect(config.lock.blurSigma, 18.0);
      expect(config.shortcuts.openSettings, kDefaultOpenSettings);
      expect(config.shortcuts.openLauncher, kDefaultOpenLauncher);
      expect(config.screenshare.enabled, isTrue);
      expect(config.screenshare.previewFps, 10);
      expect(config.screenshare.maxFps, 0);
    });
  });

  group('a wrongly-typed field costs that field, never the config', () {
    // TOML distinguishes 32 from 32.0, and a hand-edited file can hold
    // either — or a string, or a whole table — where any field is expected.
    // The old `as int?` casts threw here, and AppConfig.load answered a throw
    // by silently discarding the user's entire config.

    test('a float where an int is expected coerces', () {
      final config = AppConfig.fromMap({
        'panels': {
          'top': {'height': 32.0, 'padding_horizontal': 8.5},
        },
      });
      expect(config.panels['top']!.height, 32);
      expect(config.panels['top']!.paddingHorizontal, 8);
    });

    test('a wrongly-typed field falls back alone', () {
      final config = AppConfig.fromMap({
        'panels': {
          'top': {'height': 'tall', 'anchor': 'bottom'},
        },
        'osd': {'enabled': 'yes', 'margin': 40},
        'calendar': {'week_start': 3},
      });
      // The bad key falls back; its neighbours in the same table survive.
      expect(config.panels['top']!.height, 32);
      expect(config.panels['top']!.anchor, 'bottom');
      expect(config.osd.enabled, isTrue);
      expect(config.osd.margin, 40);
      expect(config.calendar.weekStart, DateTime.sunday);
    });

    test('a wrongly-typed table costs that table alone', () {
      final config = AppConfig.fromMap({
        'panels': 'nope',
        'lock': {'blur_sigma': 4.0},
      });
      expect(config.panels.keys.toList(), ['default']);
      expect(config.lock.blurSigma, 4.0);
    });

    test('a non-table panel entry is skipped, not fatal', () {
      final config = AppConfig.fromMap({
        'panels': {
          'top': {'height': 40},
          'broken': 7,
        },
      });
      expect(config.panels.keys.toList(), ['top']);
      expect(config.panels['top']!.height, 40);
    });
  });

  group('built-in themes parse losslessly', () {
    // Renders values comparable across the TOML/typed boundary: colours are
    // normalized to #RRGGBB / #AARRGGBB uppercase, numbers to doubles.
    String normalize(Object? value) {
      if (value is String && value.startsWith('#')) {
        var hex = value.substring(1).toUpperCase();
        if (hex.length == 8 && hex.startsWith('FF')) hex = hex.substring(2);
        return '#$hex';
      }
      if (value is num) return value.toDouble().toString();
      return value.toString();
    }

    for (final entry in kBuiltInThemes.entries) {
      test(entry.key, () {
        final source = TomlDocument.parse(entry.value).toMap();
        final theme = ThemeConfig.fromMap(source);

        // Round trip: what toMap writes parses back to the same palette.
        expect(ThemeConfig.fromMap(theme.toMap()), theme);

        // And every key toMap writes carries the value the source spelled, so
        // fromMap and toMap cannot drift apart on any single key.
        for (final kv in theme.toMap().entries) {
          expect(source.containsKey(kv.key), isTrue,
              reason: '${entry.key} does not spell ${kv.key}');
          expect(normalize(kv.value), normalize(source[kv.key]),
              reason: '${entry.key}.${kv.key}');
        }
      });
    }
  });
}
