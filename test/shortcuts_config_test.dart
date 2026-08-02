import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/input_trigger/keysym.dart';

void main() {
  group('ShortcutsConfig.fromMap', () {
    test('an absent section keeps the built-in defaults', () {
      final config = ShortcutsConfig.fromMap(null);
      expect(config.openSettings, kDefaultOpenSettings);
      expect(config.openLauncher, kDefaultOpenLauncher);
    });

    test('an absent key keeps its default', () {
      final config = ShortcutsConfig.fromMap(<String, dynamic>{});
      expect(config.openSettings, kDefaultOpenSettings);
      expect(config.openLauncher, kDefaultOpenLauncher);
    });

    test('a typo in one key leaves the other alone', () {
      final config = ShortcutsConfig.fromMap({
        'open_settings': 'ctrl+nosuchkey',
        'open_launcher': 'super+space',
      });
      expect(config.openSettings, kDefaultOpenSettings);
      expect(config.openLauncher, parseShortcut('super+space'));
    });

    test('a valid string is parsed', () {
      final config =
          ShortcutsConfig.fromMap({'open_settings': 'super+shift+p'});
      expect(config.openSettings, parseShortcut('super+shift+p'));
    });

    test('an explicit empty string disables the shortcut', () {
      expect(ShortcutsConfig.fromMap({'open_settings': ''}).openSettings,
          isNull);
      expect(ShortcutsConfig.fromMap({'open_settings': 'none'}).openSettings,
          isNull);
    });

    test('a wrongly-typed or unparseable value falls back to the default', () {
      expect(ShortcutsConfig.fromMap({'open_settings': 42}).openSettings,
          kDefaultOpenSettings);
      expect(
          ShortcutsConfig.fromMap({'open_settings': 'ctrl+nosuchkey'})
              .openSettings,
          kDefaultOpenSettings);
    });
  });

  group('AppConfig.fromMap', () {
    test('a broken [shortcuts] table does not discard the rest of the config',
        () {
      // Every other config class type-tests rather than casts for this reason:
      // a throw out of fromMap makes the loader fall back to a bare AppConfig,
      // losing the user's theme and panels along with their typo.
      final config = AppConfig.fromMap({
        'shortcuts': {'open_settings': 42},
        'theme': {'font': 'Cantarell'},
        'panels': {
          'top': {'height': 40, 'anchor': 'top'},
        },
      });

      expect(config.shortcuts.openSettings, kDefaultOpenSettings);
      expect(config.theme.fontFamily, 'Cantarell');
      expect(config.panels['top']!.height, 40);
    });

    test('the section is picked up when present', () {
      final config = AppConfig.fromMap({
        'shortcuts': {'open_settings': 'ctrl+alt+s'},
      });
      expect(config.shortcuts.openSettings, parseShortcut('ctrl+alt+s'));
    });
  });
}
