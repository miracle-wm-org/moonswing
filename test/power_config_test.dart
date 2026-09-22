import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/input_trigger/keysym.dart';
import 'package:moonswing/power/power_actions.dart';

void main() {
  group('PowerConfig.fromMap', () {
    test('an absent section shows the power menu and holds the lock', () {
      const config = PowerConfig();
      expect(PowerConfig.fromMap(null), config);
      expect(config.keyAction, PowerKeyAction.menu);
      expect(config.inhibitLogind, isTrue);
      expect(config.handlesKey, isTrue);
      expect(config.inhibitsLogind, isTrue);
    });

    test('an action is read by name', () {
      expect(PowerConfig.fromMap({'key_action': 'shutdown'}).keyAction,
          PowerKeyAction.shutdown);
      expect(PowerConfig.fromMap({'key_action': 'none'}).keyAction,
          PowerKeyAction.none);
    });

    test('the spellings a user reaches for resolve', () {
      for (final (raw, expected) in const [
        ('off', PowerKeyAction.shutdown),
        ('poweroff', PowerKeyAction.shutdown),
        ('restart', PowerKeyAction.reboot),
        ('sleep', PowerKeyAction.suspend),
        ('  MENU  ', PowerKeyAction.menu),
        ('ignore', PowerKeyAction.none),
        ('', PowerKeyAction.none),
      ]) {
        expect(PowerConfig.fromMap({'key_action': raw}).keyAction, expected,
            reason: raw);
      }
    });

    // TomlReader's rule, and the reason it matters more here than elsewhere: a
    // typo that silently disabled the button would be indistinguishable from
    // the hardware failing.
    test('a typo or a wrongly-typed value keeps the menu', () {
      expect(PowerConfig.fromMap({'key_action': 'shutdwn'}).keyAction,
          PowerKeyAction.menu);
      expect(PowerConfig.fromMap({'key_action': 42}).keyAction,
          PowerKeyAction.menu);
      expect(PowerConfig.fromMap({'inhibit_logind': 'yes'}).inhibitLogind,
          isTrue);
    });

    // Inhibiting the key and then ignoring it is a power button that does
    // nothing at all — worse than either behaviour on its own.
    test('"none" never holds the inhibitor, whatever the flag says', () {
      const config = PowerConfig(keyAction: PowerKeyAction.none);
      expect(config.inhibitsLogind, isFalse);
      expect(
        PowerConfig.fromMap({'key_action': 'none', 'inhibit_logind': true})
            .inhibitsLogind,
        isFalse,
      );
    });

    test('the flag turns the lock off on its own', () {
      const config = PowerConfig(inhibitLogind: false);
      expect(config.handlesKey, isTrue);
      expect(config.inhibitsLogind, isFalse);
    });

    test('value equality, so a live config edit can be compared away', () {
      expect(const PowerConfig(), const PowerConfig());
      expect(const PowerConfig().hashCode, const PowerConfig().hashCode);
      expect(const PowerConfig(),
          isNot(const PowerConfig(keyAction: PowerKeyAction.lock)));
      expect(
          const PowerConfig(), isNot(const PowerConfig(inhibitLogind: false)));
    });
  });

  group('AppConfig', () {
    test('[power] is read into the typed config', () {
      final config = AppConfig.fromMap({
        'power': {'key_action': 'reboot', 'inhibit_logind': false},
      });
      expect(config.power.keyAction, PowerKeyAction.reboot);
      expect(config.power.inhibitLogind, isFalse);
    });

    test('an absent section is the default rather than null', () {
      expect(AppConfig.fromMap(<String, dynamic>{}).power, const PowerConfig());
    });

    // The [power] section is live config: without equality every keystroke
    // anywhere in the settings UI would look like a change to it.
    test('AppConfig equality covers the power section', () {
      final a = AppConfig.fromMap({
        'power': {'key_action': 'menu'},
      });
      final b = AppConfig.fromMap({
        'power': {'key_action': 'lock'},
      });
      expect(a, AppConfig.fromMap({'power': {'key_action': 'menu'}}));
      expect(a, isNot(b));
    });
  });

  // The binding itself (and `parseShortcut('poweroff')` agreeing with
  // [kDefaultPowerButton]) is pinned by `test/shortcut_parse_test.dart`.
  group('the power key binding', () {
    test('[shortcuts] power_button parses, defaults, and disables', () {
      expect(ShortcutsConfig.fromMap(null).powerButton, kDefaultPowerButton);
      expect(ShortcutsConfig.fromMap(<String, dynamic>{}).powerButton,
          kDefaultPowerButton);
      expect(ShortcutsConfig.fromMap({'power_button': 'code:116'}).powerButton,
          parseShortcut('code:116'));
      expect(
          ShortcutsConfig.fromMap({'power_button': ''}).powerButton, isNull);
      // A typo falls back rather than disabling, like the other two keys.
      expect(ShortcutsConfig.fromMap({'power_button': 'ctrl+nosuchkey'})
          .powerButton, kDefaultPowerButton);
    });
  });

  group('powerActionFor', () {
    test('the acting values map to a verb', () {
      expect(powerActionFor(PowerKeyAction.shutdown), PowerAction.shutdown);
      expect(powerActionFor(PowerKeyAction.reboot), PowerAction.reboot);
      expect(powerActionFor(PowerKeyAction.suspend), PowerAction.suspend);
      expect(powerActionFor(PowerKeyAction.lock), PowerAction.lock);
      expect(powerActionFor(PowerKeyAction.logout), PowerAction.logout);
    });

    // The two that are not verbs: one opens a window, the other does nothing.
    test('menu and none map to no verb', () {
      expect(powerActionFor(PowerKeyAction.menu), isNull);
      expect(powerActionFor(PowerKeyAction.none), isNull);
    });
  });
}
