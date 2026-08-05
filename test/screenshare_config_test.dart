import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:toml/toml.dart';

void main() {
  group('ScreenshareConfig.fromMap', () {
    test('an absent section is the shipped default', () {
      const config = ScreenshareConfig();
      expect(config.enabled, isTrue);
      expect(config.previewFps, 10);
      expect(config.maxFps, 0);
      expect(ScreenshareConfig.fromMap(null).previewFps, 10);
    });

    test('reads every key', () {
      final config = ScreenshareConfig.fromMap({
        'enabled': false,
        'preview_fps': 5,
        'max_fps': 30,
      });
      expect(config.enabled, isFalse);
      expect(config.previewFps, 5);
      expect(config.maxFps, 30);
    });

    test('clamps a preview rate that would melt the picker', () {
      // The picker runs one capture session per monitor and per window at
      // once, so an unbounded rate here is a very different cost than for a
      // single shared stream.
      expect(ScreenshareConfig.fromMap({'preview_fps': 0}).previewFps, 1);
      expect(ScreenshareConfig.fromMap({'preview_fps': -4}).previewFps, 1);
      expect(ScreenshareConfig.fromMap({'preview_fps': 500}).previewFps, 60);
    });

    test('a negative frame cap means "follow the output", not a bad pod', () {
      expect(ScreenshareConfig.fromMap({'max_fps': -1}).maxFps, 0);
    });

    test('a wrongly-typed value falls back instead of throwing', () {
      // A throw here would propagate out of AppConfig.fromMap, whose caller
      // answers by discarding the *entire* config.
      final config = ScreenshareConfig.fromMap({
        'enabled': 'yes',
        'preview_fps': 'fast',
        'max_fps': [60],
      });
      expect(config.enabled, isTrue);
      expect(config.previewFps, 10);
      expect(config.maxFps, 0);
    });
  });

  group('AppConfig', () {
    test('parses a [screenshare] table', () {
      final doc = TomlDocument.parse('''
[screenshare]
enabled = false
preview_fps = 15
max_fps = 24
''').toMap();
      final config = AppConfig.fromMap(doc);
      expect(config.screenshare.enabled, isFalse);
      expect(config.screenshare.previewFps, 15);
      expect(config.screenshare.maxFps, 24);
    });

    test('a config with no [screenshare] table still enables sharing', () {
      final config = AppConfig.fromMap(TomlDocument.parse('''
theme = "graceful"
''').toMap());
      expect(config.screenshare.enabled, isTrue);
    });

    test('the stanza the default config ships parses back to the defaults',
        () {
      // Kept in step with AppConfig._buildDefaultConfig by hand — a default
      // file whose own values do not round-trip would be a confusing first
      // run.
      final shipped = AppConfig.fromMap(TomlDocument.parse('''
[screenshare]
enabled = true
preview_fps = 10
max_fps = 0
''').toMap());
      const defaults = ScreenshareConfig();
      expect(shipped.screenshare.enabled, defaults.enabled);
      expect(shipped.screenshare.previewFps, defaults.previewFps);
      expect(shipped.screenshare.maxFps, defaults.maxFps);
    });
  });
}
