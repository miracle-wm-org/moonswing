import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/desktop_actions.dart';

// Only the pure half is covered here. Everything that reaches GIO — launching,
// content-type guessing, handler enumeration — needs a live GLib and is
// verified by hand; `lib/app_info.dart` has no unit tests for the same reason.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('gs_desktop_actions_test');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('desktopBasename', () {
    test('returns the last segment', () {
      expect(desktopBasename('/home/me/notes.txt'), 'notes.txt');
      expect(desktopBasename('/home/me/Documents'), 'Documents');
    });

    test('tolerates a trailing slash, which a folder path often has', () {
      expect(desktopBasename('/home/me/Documents/'), 'Documents');
      expect(desktopBasename('/home/me/Documents///'), 'Documents');
    });

    test('handles the root and a bare name', () {
      expect(desktopBasename('/'), '/');
      expect(desktopBasename('notes.txt'), 'notes.txt');
    });
  });

  group('labelForItem', () {
    test('a user rename wins over everything', () {
      const item = DesktopItem(
        kind: DesktopItemKind.file,
        target: '/home/me/notes.txt',
        label: 'Shopping list',
      );
      expect(labelForItem(item), 'Shopping list');
    });

    test('a blank rename falls through to the derived name', () {
      const item = DesktopItem(
        kind: DesktopItemKind.file,
        target: '/home/me/notes.txt',
        label: '   ',
      );
      expect(labelForItem(item), 'notes.txt');
    });

    test('files and folders fall back to the basename', () {
      expect(
        labelForItem(const DesktopItem(
          kind: DesktopItemKind.folder,
          target: '/home/me/Documents',
        )),
        'Documents',
      );
    });

    // A pinned .desktop whose entry no longer resolves must still read as
    // something, rather than rendering a blank tile.
    test('an unresolvable app falls back to the filename minus .desktop', () {
      expect(
        labelForItem(const DesktopItem(
          kind: DesktopItemKind.app,
          target: '/usr/share/applications/firefox.desktop',
        )),
        'firefox',
      );
    });
  });

  group('desktopItemExists', () {
    test('is true for a file that is there and false once it is gone', () {
      final file = File('${dir.path}/a.txt')..writeAsStringSync('x');
      final item = DesktopItem(kind: DesktopItemKind.file, target: file.path);
      expect(desktopItemExists(item), isTrue);
      file.deleteSync();
      expect(desktopItemExists(item), isFalse);
    });

    // A folder is not a File, so the check has to branch on the kind.
    test('checks a folder as a directory, not as a file', () {
      final sub = Directory('${dir.path}/docs')..createSync();
      expect(
        desktopItemExists(
            DesktopItem(kind: DesktopItemKind.folder, target: sub.path)),
        isTrue,
      );
      expect(
        desktopItemExists(
            DesktopItem(kind: DesktopItemKind.file, target: sub.path)),
        isFalse,
      );
    });
  });

  group('desktopItemForPath', () {
    test('infers each kind from the path', () {
      final sub = Directory('${dir.path}/docs')..createSync();
      final file = File('${dir.path}/a.txt')..writeAsStringSync('x');
      final entry = File('${dir.path}/app.desktop')
        ..writeAsStringSync('[Desktop Entry]\n');

      expect(desktopItemForPath(sub.path).kind, DesktopItemKind.folder);
      expect(desktopItemForPath(file.path).kind, DesktopItemKind.file);
      expect(desktopItemForPath(entry.path).kind, DesktopItemKind.app);
    });

    test('a new item starts at the origin for the placer to move', () {
      final item = desktopItemForPath('${dir.path}/a.txt');
      expect((item.column, item.row), (0, 0));
      expect(item.label, isNull);
    });
  });

  group('openWithCandidates', () {
    // "Open with" is meaningless for an application, and asking GIO would
    // return handlers for the .desktop file itself — text editors.
    test('is empty for an application', () {
      expect(
        openWithCandidates(const DesktopItem(
          kind: DesktopItemKind.app,
          target: '/usr/share/applications/firefox.desktop',
        )),
        isEmpty,
      );
    });
  });
}
