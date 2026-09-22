import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/capture/capture_config.dart';
import 'package:moonswing/capture/recorder.dart' show ffmpegArguments;

/// `[modules.screenshot]` and `[modules.screen_recorder]`, plus the ffmpeg
/// command line — the part of the recorder that can be checked without a
/// compositor and the part most likely to be wrong.
void main() {
  group('ScreenshotConfig', () {
    test('an absent table is the compiled-in default', () {
      expect(ScreenshotConfig.fromMap(null), const ScreenshotConfig());
    });

    test('reads every key', () {
      final config = ScreenshotConfig.fromMap(const {
        'directory': '~/shots',
        'filename_prefix': 'Shot',
        'copy_to_clipboard': false,
        'delay_seconds': 3,
        'show_cursor': true,
      });
      expect(config.directory, '~/shots');
      expect(config.filenamePrefix, 'Shot');
      expect(config.copyToClipboard, isFalse);
      expect(config.delaySeconds, 3);
      expect(config.showCursor, isTrue);
    });

    test('a wrongly typed value costs that key and nothing else', () {
      final config = ScreenshotConfig.fromMap(const {
        'directory': 42,
        'copy_to_clipboard': 'yes',
        'delay_seconds': 2,
      });
      expect(config.directory, const ScreenshotConfig().directory);
      expect(config.copyToClipboard, const ScreenshotConfig().copyToClipboard);
      expect(config.delaySeconds, 2, reason: 'the good key survives');
    });

    test('a mistyped delay is clamped rather than obeyed', () {
      expect(ScreenshotConfig.fromMap(const {'delay_seconds': 600}).delaySeconds,
          60);
      expect(ScreenshotConfig.fromMap(const {'delay_seconds': -5}).delaySeconds,
          0);
    });

    test('carries value equality, which is what stops keystroke churn', () {
      expect(ScreenshotConfig.fromMap(const {'delay_seconds': 3}),
          ScreenshotConfig.fromMap(const {'delay_seconds': 3}));
      expect(ScreenshotConfig.fromMap(const {'delay_seconds': 3}),
          isNot(ScreenshotConfig.fromMap(const {'delay_seconds': 4})));
    });
  });

  group('RecorderConfig', () {
    test('fps is floored and capped: it is bytes a second through a pipe', () {
      expect(RecorderConfig.fromMap(const {'fps': 0}).fps, 1);
      expect(RecorderConfig.fromMap(const {'fps': 1000}).fps, 120);
    });

    test('an unknown container falls back rather than reaching ffmpeg', () {
      final config = RecorderConfig.fromMap(const {'container': 'rmvb'});
      expect(config.container, 'rmvb', reason: 'the user value is kept as read');
      expect(config.resolvedContainer, 'mp4');
    });

    test('the encoder follows the container when none is named', () {
      expect(RecorderConfig.fromMap(const {'container': 'webm'}).resolvedEncoder,
          'libvpx-vp9');
      expect(RecorderConfig.fromMap(const {'container': 'mkv'}).resolvedEncoder,
          'libx264');
      expect(
        RecorderConfig.fromMap(
            const {'container': 'webm', 'encoder': 'libvpx'}).resolvedEncoder,
        'libvpx',
      );
    });
  });

  group('resolveCaptureDirectory', () {
    test(r'empty is the default under $HOME', () {
      expect(
        resolveCaptureDirectory('', home: '/home/ada', fallback: 'Pictures/S'),
        '/home/ada/Pictures/S',
      );
    });

    test(r'expands ~ and $HOME, which is what a person types', () {
      expect(
        resolveCaptureDirectory('~/shots', home: '/home/ada', fallback: 'x'),
        '/home/ada/shots',
      );
      expect(
        resolveCaptureDirectory(r'$HOME/shots',
            home: '/home/ada', fallback: 'x'),
        '/home/ada/shots',
      );
      expect(resolveCaptureDirectory('~', home: '/home/ada', fallback: 'x'),
          '/home/ada');
    });

    test('an absolute path is taken as it is', () {
      expect(
        resolveCaptureDirectory('/mnt/shots', home: '/home/ada', fallback: 'x'),
        '/mnt/shots',
      );
    });

    test(
        r'a relative path is relative to $HOME, not the working directory', () {
      // The shell's working directory is wherever the session manager started
      // it, which is never what somebody typing `Pictures/shots` meant.
      expect(
        resolveCaptureDirectory('Pictures/shots',
            home: '/home/ada', fallback: 'x'),
        '/home/ada/Pictures/shots',
      );
    });
  });

  group('captureFileName', () {
    test('is sortable, to the second', () {
      final name = captureFileName(
          'Screenshot', DateTime(2026, 8, 26, 9, 5, 3), 'png');
      expect(name, 'Screenshot_2026-08-26_09-05-03.png');
    });

    test('an empty prefix still produces a name', () {
      expect(captureFileName('   ', DateTime(2026), 'mp4'),
          startsWith('Capture_'));
    });
  });

  group('ffmpegArguments', () {
    List<String> argsFor(RecorderConfig config) => ffmpegArguments(
          config: config,
          width: 1920,
          height: 1080,
          pixelFormat: 'bgra',
          path: '/tmp/out.${config.resolvedContainer}',
        );

    test('describes the raw stream it is about to be fed', () {
      final args = argsFor(const RecorderConfig(fps: 25));
      expect(args, containsAllInOrder(['-f', 'rawvideo']));
      expect(args, containsAllInOrder(['-pix_fmt', 'bgra']));
      expect(args, containsAllInOrder(['-video_size', '1920x1080']));
      expect(args, containsAllInOrder(['-framerate', '25']));
      expect(args, containsAllInOrder(['-i', 'pipe:0']));
      expect(args, contains('-an'));
      expect(args.last, '/tmp/out.mp4');
    });

    test('x264 gets a preset and mp4 gets faststart', () {
      final args = argsFor(const RecorderConfig(quality: 18));
      expect(args, containsAllInOrder(['-c:v', 'libx264']));
      expect(args, containsAllInOrder(['-preset', 'ultrafast']));
      expect(args, containsAllInOrder(['-crf', '18']));
      expect(args, containsAllInOrder(['-movflags', '+faststart']));
    });

    test('VP9 gets neither a preset nor faststart, which it would reject', () {
      final args = argsFor(const RecorderConfig(container: 'webm'));
      expect(args, containsAllInOrder(['-c:v', 'libvpx-vp9']));
      expect(args, isNot(contains('-preset')));
      expect(args, isNot(contains('-movflags')));
      expect(args, containsAllInOrder(['-b:v', '0']));
    });

    test('an unrecognised encoder is handed no quality flags at all', () {
      // A hardware encoder takes neither `-crf` nor `-preset`; guessing at one
      // would stop it from starting, which reads as recording being broken.
      final args = argsFor(const RecorderConfig(encoder: 'h264_vaapi'));
      expect(args, containsAllInOrder(['-c:v', 'h264_vaapi']));
      expect(args, isNot(contains('-crf')));
      expect(args, isNot(contains('-preset')));
    });

    test('the byte order comes from the frame, not from an assumption', () {
      final args = ffmpegArguments(
        config: const RecorderConfig(),
        width: 800,
        height: 600,
        pixelFormat: 'rgba',
        path: '/tmp/out.mp4',
      );
      expect(args, containsAllInOrder(['-pix_fmt', 'rgba']));
    });
  });
}
