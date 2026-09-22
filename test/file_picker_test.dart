import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/overlay/file_picker.dart';

/// Exercises the picker's pure filesystem helpers against a temp directory, so
/// no test touches the real filesystem or home directory.
void main() {
  group('FilePickerFilter.matches', () {
    test('empty extension set matches everything', () {
      const all = FilePickerFilter(label: 'All', extensions: {});
      expect(all.matches('/x/y.png'), isTrue);
      expect(all.matches('/x/y'), isTrue);
      expect(all.matches('/x/.hidden'), isTrue);
    });

    test('matches by extension, case-insensitively', () {
      final images = FilePickerFilter.images;
      expect(images.matches('/a/b/photo.JPG'), isTrue);
      expect(images.matches('/a/b/photo.png'), isTrue);
      expect(images.matches('/a/b/photo.webp'), isTrue);
      expect(images.matches('/a/b/notes.txt'), isFalse);
      expect(images.matches('/a/b/noext'), isFalse);
    });
  });

  group('basenameOf', () {
    test('returns the last segment', () {
      expect(basenameOf('/home/user/photo.png'), 'photo.png');
      expect(basenameOf('/home/user'), 'user');
    });

    test('tolerates a trailing slash', () {
      expect(basenameOf('/home/user/'), 'user');
    });

    test('root stays root', () {
      expect(basenameOf('/'), '/');
    });
  });

  group('iconForFile', () {
    test('does not throw and returns distinct icons per family', () {
      final img = iconForFile('/a/b.png');
      final vid = iconForFile('/a/b.mp4');
      final generic = iconForFile('/a/b.unknownext');
      expect(img, isNot(equals(vid)));
      expect(generic, isNotNull);
    });
  });

  group('readDir / sortEntries / subDirs', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('file_picker_test');
      Directory('${root.path}/beta').createSync();
      Directory('${root.path}/Alpha').createSync();
      Directory('${root.path}/.hidden_dir').createSync();
      File('${root.path}/zebra.png').writeAsStringSync('x');
      File('${root.path}/apple.txt').writeAsStringSync('x');
      File('${root.path}/.hidden_file').writeAsStringSync('x');
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('readDir hides dot-entries by default', () {
      final names =
          readDir(root.path).map((e) => basenameOf(e.path)).toSet();
      expect(names.contains('.hidden_dir'), isFalse);
      expect(names.contains('.hidden_file'), isFalse);
      expect(names.contains('beta'), isTrue);
    });

    test('readDir includes dot-entries when showHidden', () {
      final names =
          readDir(root.path, showHidden: true).map((e) => basenameOf(e.path)).toSet();
      expect(names.contains('.hidden_dir'), isTrue);
      expect(names.contains('.hidden_file'), isTrue);
    });

    test('readDir on a missing directory returns empty', () {
      expect(readDir('${root.path}/does-not-exist'), isEmpty);
    });

    test('sortEntries puts directories first, then case-insensitive name', () {
      final sorted = sortEntries(readDir(root.path));
      final names = sorted.map((e) => basenameOf(e.path)).toList();
      // Directories (Alpha, beta) before files (apple.txt, zebra.png), each
      // group alphabetised without regard to case.
      expect(names, ['Alpha', 'beta', 'apple.txt', 'zebra.png']);
    });

    test('subDirs returns only directories, sorted, no files', () {
      final dirs = subDirs(root.path).map((d) => basenameOf(d.path)).toList();
      expect(dirs, ['Alpha', 'beta']);
    });
  });

  group('matchesSearch', () {
    test('an empty query matches everything', () {
      expect(matchesSearch('photo.png', ''), isTrue);
      expect(matchesSearch('photo.png', '   '), isTrue);
    });

    test('matches a substring without regard to case', () {
      expect(matchesSearch('Sunset-4K.PNG', 'sunset'), isTrue);
      expect(matchesSearch('Sunset-4K.PNG', 'PNG'), isTrue);
      expect(matchesSearch('Sunset-4K.PNG', 'moon'), isFalse);
    });

    test('every token has to appear, in any order', () {
      expect(matchesSearch('4K-sunset-02.png', 'sun 4k'), isTrue);
      expect(matchesSearch('4K-sunset-02.png', '4k sun'), isTrue);
      expect(matchesSearch('4K-sunset-02.png', 'sun 8k'), isFalse);
    });
  });

  group('filterEntries', () {
    PickerEntry entry(String path, {bool dir = false}) => PickerEntry(
          path: path,
          isDirectory: dir,
          size: dir ? -1 : 10,
          modified: null,
        );

    final entries = [
      entry('/w/Pictures', dir: true),
      entry('/w/sunset.png'),
      entry('/w/notes.txt'),
      entry('/w/moon.PNG'),
    ];

    test('the type filter reaches files and not folders', () {
      final kept = filterEntries(
        entries,
        filter: FilePickerFilter.images,
        includeDirectories: true,
      ).map((e) => e.name).toList();
      // Pictures survives despite having no extension to match.
      expect(kept, ['Pictures', 'sunset.png', 'moon.PNG']);
    });

    test('folders are dropped entirely when they are not selectable', () {
      final kept = filterEntries(
        entries,
        filter: FilePickerFilter.all,
        includeDirectories: false,
      ).map((e) => e.name).toList();
      expect(kept, ['sunset.png', 'notes.txt', 'moon.PNG']);
    });

    test('the search reaches folders as well as files', () {
      final kept = filterEntries(
        entries,
        filter: FilePickerFilter.all,
        includeDirectories: true,
        query: 'PIC',
      ).map((e) => e.name).toList();
      expect(kept, ['Pictures']);
    });

    test('search and type filter compose', () {
      final kept = filterEntries(
        entries,
        filter: FilePickerFilter.images,
        includeDirectories: false,
        query: 'moon',
      ).map((e) => e.name).toList();
      expect(kept, ['moon.PNG']);
    });
  });

  group('listDirectory', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('file_picker_list_test');
      Directory('${root.path}/Alpha').createSync();
      File('${root.path}/apple.txt').writeAsStringSync('hello');
      File('${root.path}/.hidden').writeAsStringSync('x');
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('folders first, then files, each statted', () {
      final entries = listDirectory(root.path);
      expect(entries.map((e) => e.name).toList(), ['Alpha', 'apple.txt']);

      final dir = entries.first;
      expect(dir.isDirectory, isTrue);
      expect(dir.size, -1);
      expect(dir.modified, isNotNull);

      final file = entries.last;
      expect(file.isDirectory, isFalse);
      expect(file.size, 5);
      expect(file.modified, isNotNull);
    });

    test('honours showHidden', () {
      expect(
        listDirectory(root.path, showHidden: true).map((e) => e.name),
        contains('.hidden'),
      );
    });

    test('a missing directory lists as empty', () {
      expect(listDirectory('${root.path}/nope'), isEmpty);
    });
  });

  group('the list form\'s columns', () {
    PickerEntry sized(int bytes) => PickerEntry(
          path: '/w/a.bin',
          isDirectory: false,
          size: bytes,
          modified: null,
        );

    test('a folder says so and an unreadable entry says nothing', () {
      expect(
        formatEntrySize(const PickerEntry(
          path: '/w/d',
          isDirectory: true,
          size: -1,
          modified: null,
        )),
        'Folder',
      );
      expect(formatEntrySize(sized(-1)), '');
      expect(formatEntrySize(sized(2048)), '2.0K');
    });

    test('today is a clock, anything else is an ISO date', () {
      final now = DateTime(2026, 8, 26, 12, 0);
      expect(formatEntryModified(DateTime(2026, 8, 26, 9, 5), now: now), '09:05');
      expect(
        formatEntryModified(DateTime(2026, 8, 25, 23, 59), now: now),
        '2026-08-25',
      );
      // Same day-of-year, a year back: the year is what tells them apart.
      expect(
        formatEntryModified(DateTime(2025, 8, 26, 9, 5), now: now),
        '2025-08-26',
      );
    });
  });
}
