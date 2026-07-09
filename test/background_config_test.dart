import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/background.dart';
import 'package:graceful_shell/config.dart';

void main() {
  group('isImagePath', () {
    test('accepts supported image extensions (case-insensitive)', () {
      expect(isImagePath('/a/b.jpg'), isTrue);
      expect(isImagePath('/a/b.JPEG'), isTrue);
      expect(isImagePath('/a/b.png'), isTrue);
      expect(isImagePath('/a/b.WebP'), isTrue);
      expect(isImagePath('/a/b.gif'), isTrue);
      expect(isImagePath('/a/b.bmp'), isTrue);
    });

    test('rejects videos, extension-less, and empty paths', () {
      expect(isImagePath('/a/b.mp4'), isFalse);
      expect(isImagePath('/a/b.mkv'), isFalse);
      expect(isImagePath('/a/wallpaper'), isFalse);
      expect(isImagePath(''), isFalse);
    });
  });

  group('BackgroundEntry.fromMap', () {
    test('defaults shown to true when absent', () {
      final e = BackgroundEntry.fromMap({'path': '/a/b.png'});
      expect(e.path, '/a/b.png');
      expect(e.shown, isTrue);
    });

    test('parses the shown flag when present', () {
      expect(BackgroundEntry.fromMap({'path': '/x', 'shown': false}).shown,
          isFalse);
      expect(BackgroundEntry.fromMap({'path': '/x', 'shown': true}).shown,
          isTrue);
    });
  });

  group('BackgroundConfig.fromMap', () {
    test('preserves entry order (no time-based sort)', () {
      final cfg = BackgroundConfig.fromMap({
        'entries': [
          {'path': '/c.png'},
          {'path': '/a.png'},
          {'path': '/b.png'},
        ],
      });
      expect(cfg.entries.map((e) => e.path).toList(),
          ['/c.png', '/a.png', '/b.png']);
    });

    test('parses interval_minutes and clamps to >= 1', () {
      expect(BackgroundConfig.fromMap({'interval_minutes': 12}).intervalMinutes,
          12);
      expect(BackgroundConfig.fromMap({'interval_minutes': 0}).intervalMinutes,
          1);
      // Default when absent.
      expect(BackgroundConfig.fromMap({}).intervalMinutes, 5);
    });
  });

  group('shownEntries', () {
    late Directory dir;
    late File img;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('gs_bg_test');
      img = File('${dir.path}/wall.png')..writeAsBytesSync([0, 1, 2, 3]);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    BackgroundConfig cfg(List<BackgroundEntry> entries) =>
        BackgroundConfig(entries: entries);

    test('is empty when nothing is shown', () {
      final out = shownEntries(cfg([
        BackgroundEntry(path: img.path, shown: false),
      ]));
      expect(out, isEmpty);
    });

    test('keeps shown, existing image entries in order', () {
      final img2 = File('${dir.path}/wall2.png')..writeAsBytesSync([9]);
      final out = shownEntries(cfg([
        BackgroundEntry(path: img2.path),
        BackgroundEntry(path: img.path),
      ]));
      expect(out.map((e) => e.path).toList(), [img2.path, img.path]);
    });

    test('drops missing files and non-image paths', () {
      final out = shownEntries(cfg([
        BackgroundEntry(path: img.path), // valid
        BackgroundEntry(path: '${dir.path}/nope.png'), // missing
        BackgroundEntry(path: '${dir.path}/clip.mp4'), // not an image
      ]));
      expect(out.map((e) => e.path).toList(), [img.path]);
    });
  });
}
