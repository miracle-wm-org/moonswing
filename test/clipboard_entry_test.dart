// The clipboard history's pure half: which offered type is recorded, how a
// copied file list is read, how an entry is described and stored, and the
// `[modules.clipboard]` table.

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/clipboard/clipboard_config.dart';
import 'package:moonswing/clipboard/clipboard_entry.dart';
import 'package:moonswing/clipboard/wl_clipboard.dart';

void main() {
  group('pickClipboardType', () {
    test('a file manager copy is files, not the text of the paths', () {
      expect(
        pickClipboardType([
          'x-special/gnome-copied-files',
          'text/uri-list',
          'text/plain;charset=utf-8',
        ]),
        (kind: ClipboardKind.files, mime: 'text/uri-list'),
      );
      expect(
        pickClipboardType(['x-special/gnome-copied-files', 'UTF8_STRING']),
        (kind: ClipboardKind.files, mime: 'x-special/gnome-copied-files'),
      );
    });

    test('text beats a bitmap rendering of the same selection', () {
      expect(pickClipboardType(['image/png', 'text/html', 'UTF8_STRING']), (
        kind: ClipboardKind.text,
        mime: 'UTF8_STRING',
      ));
      // The charset-qualified spelling wins over the bare one.
      expect(pickClipboardType(['text/plain', 'text/plain;charset=utf-8']), (
        kind: ClipboardKind.text,
        mime: 'text/plain;charset=utf-8',
      ));
    });

    test('a browser\'s Copy Image is a picture', () {
      expect(pickClipboardType(['text/html', 'image/png', 'image/jpeg']), (
        kind: ClipboardKind.image,
        mime: 'image/png',
      ));
      expect(pickClipboardType(['image/avif']), (
        kind: ClipboardKind.image,
        mime: 'image/avif',
      ));
    });

    test('media, html-only text and real documents are kept', () {
      expect(pickClipboardType(['video/mp4']), (
        kind: ClipboardKind.media,
        mime: 'video/mp4',
      ));
      expect(pickClipboardType(['text/html']), (
        kind: ClipboardKind.text,
        mime: 'text/html',
      ));
      expect(pickClipboardType(['application/pdf']), (
        kind: ClipboardKind.binary,
        mime: 'application/pdf',
      ));
    });

    test('private formats, bookkeeping and secrets are not', () {
      expect(
        pickClipboardType([
          'TARGETS',
          'application/x-qt-image',
          'application/vnd.oasis.opendocument.text',
        ]),
        isNull,
      );
      expect(
        pickClipboardType(['text/plain', kSecretClipboardHint]),
        isNull,
        reason: 'a password manager asked for it not to be remembered',
      );
      expect(pickClipboardType(const []), isNull);
    });
  });

  group('parseFileUris', () {
    test('reads file URIs, decoding escapes, skipping comments', () {
      expect(
        parseFileUris(
          '# a comment\r\nfile:///home/me/My%20Video.mp4\r\nfile:///tmp/a.png\r\n',
        ),
        ['/home/me/My Video.mp4', '/tmp/a.png'],
      );
    });

    test('drops GNOME\'s leading operation', () {
      expect(parseFileUris('copy\nfile:///tmp/x'), ['/tmp/x']);
      expect(parseFileUris('cut\nfile:///tmp/x'), ['/tmp/x']);
    });

    test('a list with any web link in it is not files', () {
      expect(parseFileUris('file:///tmp/x\nhttps://example.com/'), isEmpty);
    });

    test('round-trips through fileUriList', () {
      const paths = ['/home/me/a b.txt', '/tmp/ü.png'];
      expect(parseFileUris(fileUriList(paths)), paths);
    });
  });

  group('describing an entry', () {
    ClipboardEntry entry(ClipboardKind kind, String mime, {String? text}) =>
        ClipboardEntry(
          id: '1',
          kind: kind,
          mime: mime,
          copiedAt: DateTime(2026),
          size: 0,
          hash: 'h',
          text: text,
        );

    test('names what it is', () {
      expect(
        describeClipboardEntry(entry(ClipboardKind.text, 'x', text: 'a')),
        'Text',
      );
      expect(
        describeClipboardEntry(entry(ClipboardKind.image, 'image/png')),
        'PNG image',
      );
      expect(
        describeClipboardEntry(entry(ClipboardKind.media, 'video/mp4')),
        'MP4 video',
      );
      expect(
        describeClipboardEntry(
          entry(ClipboardKind.files, 'text/uri-list', text: 'file:///a.mkv'),
        ),
        'Video file',
      );
      expect(
        describeClipboardEntry(
          entry(
            ClipboardKind.files,
            'text/uri-list',
            text: 'file:///a\nfile:///b\nfile:///c',
          ),
        ),
        '3 files',
      );
    });

    test('sizes read like sizes', () {
      expect(formatClipboardSize(512), '512 B');
      expect(formatClipboardSize(1536), '1.5 KB');
      expect(formatClipboardSize(5 * 1024 * 1024), '5.0 MB');
      expect(formatClipboardSize(300 * 1024 * 1024), '300 MB');
    });

    test('a copy time is a time, not an age', () {
      final now = DateTime(2026, 10, 15, 18, 0);
      expect(formatCopiedAt(DateTime(2026, 10, 15, 9, 5), now), '09:05');
      expect(
        formatCopiedAt(DateTime(2026, 10, 14, 23, 59), now),
        'Yesterday 23:59',
      );
      expect(formatCopiedAt(DateTime(2026, 10, 12, 8, 0), now), 'Mon 08:00');
      expect(formatCopiedAt(DateTime(2026, 9, 1, 8, 0), now), '1 Sep');
      expect(formatCopiedAt(DateTime(2025, 9, 1, 8, 0), now), '1 Sep 2025');
    });
  });

  group('the index', () {
    test('an entry round-trips', () {
      final original = ClipboardEntry(
        id: '17-0',
        kind: ClipboardKind.text,
        mime: kClipboardTextMime,
        copiedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        size: 5,
        hash: 'text:abc',
        text: 'hello',
        pinned: true,
      );
      expect(ClipboardEntry.fromJson(original.toJson()), original);
    });

    test('a bad row costs that row', () {
      expect(ClipboardEntry.fromJson('nope'), isNull);
      expect(ClipboardEntry.fromJson({'id': '1'}), isNull);
      // A text entry with no text.
      expect(
        ClipboardEntry.fromJson({
          'id': '1',
          'kind': 'text',
          'mime': 'text/plain',
          'copied_at': 0,
          'size': 0,
          'hash': 'h',
        }),
        isNull,
      );
      // An id that would name a file outside the history's directory.
      expect(
        ClipboardEntry.fromJson({
          'id': '../../.bashrc',
          'kind': 'image',
          'mime': 'image/png',
          'copied_at': 0,
          'size': 0,
          'hash': 'h',
        }),
        isNull,
      );
    });
  });

  group('[modules.clipboard]', () {
    test('defaults: the left edge, kept across restarts', () {
      const config = ClipboardConfig();
      expect(ClipboardConfig.fromMap(null), config);
      expect(config.side, ClipboardSide.left);
      expect(config.persist, isTrue);
    });

    test('reads every key, clamping and degrading per key', () {
      final config = ClipboardConfig.fromMap({
        'side': 'Right',
        'width': 10,
        'max_entries': 25.0,
        'persist': 'yes',
        'max_item_mb': 4,
      });
      expect(config.side, ClipboardSide.right);
      expect(config.width, 240, reason: 'clamped to the floor');
      expect(config.maxEntries, 25);
      expect(config.persist, isTrue, reason: 'a wrongly-typed value is absent');
      expect(config.maxItemBytes, 4 * 1024 * 1024);
      expect(ClipboardConfig.fromMap({'side': 'top'}).side, ClipboardSide.left);
    });
  });

  group('watchFailureFor', () {
    test('names a compositor without data-control as such', () {
      final failure = watchFailureFor(
        1,
        'Watch mode requires a compositor that supports the wlroots '
        'data-control protocol',
      );
      expect(failure.unsupported, isTrue);
      expect(failure.missing, isFalse);
    });

    test('anything else says what the watcher said', () {
      final failure = watchFailureFor(
        1,
        'Failed to connect to a Wayland server\n',
      );
      expect(failure.unsupported, isFalse);
      expect(failure.message, contains('Failed to connect'));
      expect(watchFailureFor(3, '').message, contains('exit code 3'));
    });
  });
}
