import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/input_trigger/keysym.dart';

void main() {
  group('ShortcutsConfig.fromMap', () {
    test('an absent section keeps the built-in defaults', () {
      final config = ShortcutsConfig.fromMap(null);
      expect(config.openSettings, kDefaultOpenSettings);
      expect(config.openLauncher, kDefaultOpenLauncher);
      expect(config.openEmoji, kDefaultOpenEmoji);
      expect(config.openNotifications, kDefaultOpenNotifications);
      expect(config.openPowerMenu, kDefaultOpenPowerMenu);
      expect(config.screenshotArea, kDefaultScreenshotArea);
      expect(config.recordScreen, kDefaultRecordScreen);
      expect(config.switchWindows, kDefaultSwitchWindows);
      expect(config.switchWindowsBack, kDefaultSwitchWindowsBack);
      expect(config.toggleScratchpad, kDefaultToggleScratchpad);
      expect(config.moveToScratchpad, kDefaultMoveToScratchpad);
    });

    test('an absent key keeps its default', () {
      final config = ShortcutsConfig.fromMap(<String, dynamic>{});
      expect(config.openSettings, kDefaultOpenSettings);
      expect(config.openLauncher, kDefaultOpenLauncher);
      expect(config.openEmoji, kDefaultOpenEmoji);
      expect(config.openNotifications, kDefaultOpenNotifications);
      expect(config.openPowerMenu, kDefaultOpenPowerMenu);
      expect(config.screenshotArea, kDefaultScreenshotArea);
      expect(config.recordScreen, kDefaultRecordScreen);
      expect(config.switchWindows, kDefaultSwitchWindows);
      expect(config.switchWindowsBack, kDefaultSwitchWindowsBack);
      expect(config.toggleScratchpad, kDefaultToggleScratchpad);
      expect(config.moveToScratchpad, kDefaultMoveToScratchpad);
    });

    test('the scratchpad keys read, disable and degrade like the rest', () {
      expect(
        ShortcutsConfig.fromMap({'toggle_scratchpad': 'super+grave'})
            .toggleScratchpad,
        parseShortcut('super+grave'),
      );
      expect(
        ShortcutsConfig.fromMap({'move_to_scratchpad': ''}).moveToScratchpad,
        isNull,
      );
      expect(
        ShortcutsConfig.fromMap({'move_to_scratchpad': 42}).moveToScratchpad,
        kDefaultMoveToScratchpad,
      );
      expect(
        ShortcutsConfig.fromMap({'toggle_scratchpad': 'super+nonsense'})
            .toggleScratchpad,
        kDefaultToggleScratchpad,
      );
    });

    test('the switcher keys read, disable and degrade like the rest', () {
      expect(
        ShortcutsConfig.fromMap({'switch_windows': 'super+tab'}).switchWindows,
        parseShortcut('super+tab'),
      );
      expect(
        ShortcutsConfig.fromMap({'switch_windows_back': ''}).switchWindowsBack,
        isNull,
      );
      expect(
        ShortcutsConfig.fromMap({'switch_windows': 42}).switchWindows,
        kDefaultSwitchWindows,
      );
    });

    test('the capture and notification keys read, disable and degrade too', () {
      // The three newest keys go through the same `_read`, and the point of
      // the test is that they are actually wired to it rather than defaulted
      // somewhere else: every one of them reads, disables and degrades.
      expect(
        ShortcutsConfig.fromMap({'screenshot_area': 'super+shift+s'})
            .screenshotArea,
        parseShortcut('super+shift+s'),
      );
      expect(
        ShortcutsConfig.fromMap({'record_screen': ''}).recordScreen,
        isNull,
      );
      expect(
        ShortcutsConfig.fromMap({'open_notifications': 'ctrl+nosuchkey'})
            .openNotifications,
        kDefaultOpenNotifications,
      );
    });

    test('open_power_menu reads, disables and degrades like the others', () {
      expect(
        ShortcutsConfig.fromMap({'open_power_menu': 'super+shift+q'})
            .openPowerMenu,
        parseShortcut('super+shift+q'),
      );
      expect(
        ShortcutsConfig.fromMap({'open_power_menu': ''}).openPowerMenu,
        isNull,
      );
      expect(
        ShortcutsConfig.fromMap({'open_power_menu': 'ctrl+nosuchkey'})
            .openPowerMenu,
        kDefaultOpenPowerMenu,
      );
    });

    test('open_emoji reads, disables and degrades like the others', () {
      expect(
        ShortcutsConfig.fromMap({'open_emoji': 'super+period'}).openEmoji,
        parseShortcut('super+period'),
      );
      expect(ShortcutsConfig.fromMap({'open_emoji': ''}).openEmoji, isNull);
      expect(
        ShortcutsConfig.fromMap({'open_emoji': 42}).openEmoji,
        kDefaultOpenEmoji,
      );
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
        'theme': 'dracula',
        'panels': {
          'top': {'height': 40, 'anchor': 'top'},
        },
      });

      expect(config.shortcuts.openSettings, kDefaultOpenSettings);
      expect(config.themeName, 'dracula');
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
