import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/overlay/file_picker.dart';

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
}
