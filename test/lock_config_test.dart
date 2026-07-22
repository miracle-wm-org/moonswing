import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/background.dart';
import 'package:graceful_shell/config.dart';

void main() {
  group('isVideoPath', () {
    test('accepts supported video extensions (case-insensitive)', () {
      expect(isVideoPath('/a/b.mp4'), isTrue);
      expect(isVideoPath('/a/b.MKV'), isTrue);
      expect(isVideoPath('/a/b.webm'), isTrue);
      expect(isVideoPath('/a/b.MoV'), isTrue);
      expect(isVideoPath('/a/b.avi'), isTrue);
      expect(isVideoPath('/a/b.m4v'), isTrue);
    });

    test('rejects images, extension-less, and empty paths', () {
      expect(isVideoPath('/a/b.jpg'), isFalse);
      expect(isVideoPath('/a/b.png'), isFalse);
      expect(isVideoPath('/a/wallpaper'), isFalse);
      expect(isVideoPath(''), isFalse);
    });

    test('image and video predicates never both match', () {
      for (final ext in [...imageExtensions, ...videoExtensions]) {
        final path = '/a/b$ext';
        expect(isImagePath(path) && isVideoPath(path), isFalse,
            reason: '$ext matched both predicates');
      }
    });
  });

  group('LockConfig.fromMap', () {
    test('returns defaults for a null table', () {
      const config = LockConfig();
      final parsed = LockConfig.fromMap(null);
      expect(parsed.background, config.background);
      expect(parsed.fit, config.fit);
      expect(parsed.showUsername, config.showUsername);
      expect(parsed.blurSigma, config.blurSigma);
    });

    test('defaults an absent background to null, not the empty string', () {
      expect(LockConfig.fromMap({}).background, isNull);
    });

    test('treats a blank background as unset so the default is used', () {
      expect(LockConfig.fromMap({'background': '   '}).background, isNull);
      expect(LockConfig.fromMap({'background': ''}).background, isNull);
    });

    test('trims a configured background path', () {
      expect(LockConfig.fromMap({'background': ' /a/b.jpg '}).background,
          '/a/b.jpg');
    });

    test('parses fit, falling back to fill for unknown values', () {
      expect(LockConfig.fromMap({'fit': 'contain'}).fit, BackgroundFit.contain);
      expect(LockConfig.fromMap({'fit': 'natural'}).fit, BackgroundFit.natural);
      expect(LockConfig.fromMap({'fit': 'nonsense'}).fit, BackgroundFit.fill);
    });

    test('parses show_username', () {
      expect(LockConfig.fromMap({'show_username': false}).showUsername, isFalse);
      expect(LockConfig.fromMap({'show_username': true}).showUsername, isTrue);
    });

    test('clamps blur_sigma into a range ImageFilter.blur accepts', () {
      // A negative sigma throws inside ImageFilter.blur, so a hand-edited
      // config must not be able to crash the lock screen.
      expect(LockConfig.fromMap({'blur_sigma': -5}).blurSigma, 0.0);
      expect(LockConfig.fromMap({'blur_sigma': 1000}).blurSigma, 100.0);
      expect(LockConfig.fromMap({'blur_sigma': 24}).blurSigma, 24.0);
      expect(LockConfig.fromMap({'blur_sigma': 12.5}).blurSigma, 12.5);
    });

    test('ignores wrongly-typed values rather than throwing', () {
      final parsed = LockConfig.fromMap({
        'background': 42,
        'show_username': 'yes',
        'blur_sigma': 'lots',
      });
      expect(parsed.background, isNull);
      expect(parsed.showUsername, isTrue);
      expect(parsed.blurSigma, 18.0);
    });
  });

  group('AppConfig lock section', () {
    test('defaults when no [lock] table is present', () {
      final config = AppConfig.fromMap({});
      expect(config.lock.background, isNull);
      expect(config.lock.showUsername, isTrue);
    });

    test('is parsed from the [lock] table', () {
      final config = AppConfig.fromMap({
        'lock': {
          'background': '/a/lock.mp4',
          'fit': 'contain',
          'show_username': false,
          'blur_sigma': 30,
        },
      });
      expect(config.lock.background, '/a/lock.mp4');
      expect(config.lock.fit, BackgroundFit.contain);
      expect(config.lock.showUsername, isFalse);
      expect(config.lock.blurSigma, 30.0);
    });
  });
}
