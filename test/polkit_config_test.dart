import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';

void main() {
  group('PolkitConfig', () {
    // With no agent registered polkitd cannot ask anybody anything, so every
    // `auth_admin` action on the machine comes back AccessDenied with no
    // prompt at all. On is the only default that makes those actions work.
    test('defaults to being the session agent', () {
      const config = PolkitConfig();
      expect(config.enabled, isTrue);
      expect(config.maxAttempts, 3);
      expect(PolkitConfig.fromMap(null), config);
      expect(PolkitConfig.fromMap(<String, dynamic>{}), config);
    });

    test('reads both keys', () {
      final config = PolkitConfig.fromMap(<String, dynamic>{
        'enabled': false,
        'max_attempts': 1,
      });
      expect(config.enabled, isFalse);
      expect(config.maxAttempts, 1);
    });

    // TomlReader's rule: a wrongly-typed value costs that one key, never the
    // section — and never the whole config file, since a throw out of any
    // `fromMap` makes `AppConfig.load` discard everything the user wrote.
    test('a wrongly-typed value costs that key alone', () {
      final config = PolkitConfig.fromMap(<String, dynamic>{
        'enabled': 'yes please',
        'max_attempts': 2,
      });
      expect(config.enabled, isTrue);
      expect(config.maxAttempts, 2);
    });

    // Zero attempts is a dialog that cannot be answered; a large number is a
    // password oracle left sitting on the screen.
    test('clamps the attempt count at both ends', () {
      expect(
        PolkitConfig.fromMap(<String, dynamic>{'max_attempts': 0}).maxAttempts,
        1,
      );
      expect(
        PolkitConfig.fromMap(<String, dynamic>{'max_attempts': 99}).maxAttempts,
        5,
      );
    });

    test('carries value equality, as every AppConfig section must', () {
      expect(const PolkitConfig(), const PolkitConfig());
      expect(
        const PolkitConfig().hashCode,
        const PolkitConfig().hashCode,
      );
      expect(
        const PolkitConfig(enabled: false) == const PolkitConfig(),
        isFalse,
      );
    });
  });

  group('AppConfig', () {
    test('an absent [polkit] section is the default, not a null', () {
      final config = AppConfig.fromMap(<String, dynamic>{});
      expect(config.polkit.enabled, isTrue);
    });

    test('reads [polkit] and keeps it in the section equality', () {
      final off = AppConfig.fromMap(<String, dynamic>{
        'polkit': <String, dynamic>{'enabled': false},
      });
      expect(off.polkit.enabled, isFalse);
      expect(off == AppConfig.fromMap(<String, dynamic>{}), isFalse);
    });
  });
}
