import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/background.dart';
import 'package:moonswing/config.dart';

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

  group('BackgroundWindow rotation', () {
    late Directory dir;
    late File first;
    late File second;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('gs_bg_rotation_test');
      first = File('${dir.path}/a.png')..writeAsBytesSync([1]);
      second = File('${dir.path}/b.png')..writeAsBytesSync([2]);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    BackgroundConfig cfg({int intervalMinutes = 1}) => BackgroundConfig(
          intervalMinutes: intervalMinutes,
          entries: [
            BackgroundEntry(path: first.path),
            BackgroundEntry(path: second.path),
          ],
        );

    Future<void> pump(WidgetTester tester, BackgroundConfig config) {
      return tester.pumpWidget(BackgroundWindow(config: config));
    }

    /// The wallpaper currently on screen.
    ///
    /// `.last`, not `.first`: the AnimatedSwitcher's layoutBuilder stacks the
    /// outgoing children *under* the incoming one, so during a crossfade the
    /// first Image is the one being faded out.
    String shownPath(WidgetTester tester) {
      final image = tester.widget<Image>(find.byType(Image).last);
      return (image.image as FileImage).file.path;
    }

    // Every ConfigStore write rebuilds the whole shell with a new but equal
    // BackgroundConfig. Restarting the timer on each one reset the rotation
    // clock, so on a 5-minute interval a user rearranging desktop icons would
    // never see the wallpaper advance.
    testWidgets('an unrelated rebuild does not reset the rotation clock',
        (tester) async {
      await pump(tester, cfg());
      await tester.pump(const Duration(seconds: 40));

      // A fresh, equal config — what a ConfigStore write produces.
      await pump(tester, cfg());
      await tester.pump(const Duration(seconds: 40));

      // 80s elapsed against a 60s interval: the timer must have fired, which it
      // could not have done if the rebuild had restarted it.
      expect(shownPath(tester), second.path);
    });

    testWidgets('a real interval change does restart the timer',
        (tester) async {
      await pump(tester, cfg(intervalMinutes: 1));
      await tester.pump(const Duration(seconds: 40));

      await pump(tester, cfg(intervalMinutes: 2));
      await tester.pump(const Duration(seconds: 40));

      // The clock restarted at 40s, so at 80s the 2-minute timer has not fired.
      expect(shownPath(tester), first.path);
    });
  });
}
