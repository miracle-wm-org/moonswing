import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gs_desktop_config_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('inferDesktopItemKind', () {
    test('treats a .desktop file as an application, not a file', () {
      final path = '${tempDir.path}/firefox.desktop';
      File(path).writeAsStringSync('[Desktop Entry]\n');
      expect(inferDesktopItemKind(path), DesktopItemKind.app);
      expect(inferDesktopItemKind('/nowhere/x.DESKTOP'), DesktopItemKind.app);
    });

    test('distinguishes a directory from a file', () {
      final dir = Directory('${tempDir.path}/docs')..createSync();
      final file = File('${tempDir.path}/note.txt')..writeAsStringSync('x');
      expect(inferDesktopItemKind(dir.path), DesktopItemKind.folder);
      expect(inferDesktopItemKind(file.path), DesktopItemKind.file);
    });

    test('a path that does not exist is a file, not an error', () {
      expect(inferDesktopItemKind('${tempDir.path}/gone'), DesktopItemKind.file);
    });
  });

  group('DesktopItem.fromMap', () {
    test('defaults column, row and label when absent', () {
      final item = DesktopItem.fromMap({'target': '/a/b.txt'})!;
      expect(item.target, '/a/b.txt');
      expect(item.column, 0);
      expect(item.row, 0);
      expect(item.label, isNull);
    });

    test('returns null for an entry that names no target', () {
      expect(DesktopItem.fromMap({'kind': 'file'}), isNull);
      expect(DesktopItem.fromMap({'target': ''}), isNull);
      expect(DesktopItem.fromMap({'target': '   '}), isNull);
      expect(DesktopItem.fromMap({'target': 42}), isNull);
    });

    // A path that was a file when it was pinned and is now a directory must
    // open the file manager, not its old default handler.
    test('re-derives a stale kind from the target', () {
      final dir = Directory('${tempDir.path}/nowdir')..createSync();
      final item = DesktopItem.fromMap({
        'target': dir.path,
        'kind': 'file',
      })!;
      expect(item.kind, DesktopItemKind.folder);
    });

    test('trusts a stored app kind, since a .desktop is also a file', () {
      final path = '${tempDir.path}/thing.desktop';
      File(path).writeAsStringSync('[Desktop Entry]\n');
      final item = DesktopItem.fromMap({'target': path, 'kind': 'app'})!;
      expect(item.kind, DesktopItemKind.app);
    });

    test('negative and non-numeric cells clamp to 0', () {
      final item = DesktopItem.fromMap({
        'target': '/a/b.txt',
        'column': -3,
        'row': 'nonsense',
      })!;
      expect(item.column, 0);
      expect(item.row, 0);
    });

    test('a blank label is dropped rather than stored', () {
      final item = DesktopItem.fromMap({'target': '/a/b.txt', 'label': '  '})!;
      expect(item.label, isNull);
    });
  });

  group('DesktopItem.toMap', () {
    test('round-trips through fromMap', () {
      const original = DesktopItem(
        kind: DesktopItemKind.file,
        target: '/a/b.txt',
        label: 'Notes',
        column: 3,
        row: 2,
      );
      final restored = DesktopItem.fromMap(original.toMap())!;
      expect(restored.target, original.target);
      expect(restored.label, 'Notes');
      expect(restored.column, 3);
      expect(restored.row, 2);
    });

    test('omits label entirely when the item was never renamed', () {
      const item = DesktopItem(kind: DesktopItemKind.file, target: '/a/b.txt');
      expect(item.toMap().containsKey('label'), isFalse);
    });
  });

  group('DesktopConfig.fromMap', () {
    test('defaults to an enabled grid with the documented geometry', () {
      final config = DesktopConfig.fromMap({});
      expect(config.enabled, isTrue);
      expect(config.cellWidth, 96);
      expect(config.cellHeight, 96);
      expect(config.spacing, 12);
      expect(config.padding, 24);
      expect(config.iconSize, 48);
      expect(config.showLabels, isTrue);
      expect(config.items, isEmpty);
    });

    // A hand-edited config with an absurd cell size should still render a
    // usable grid rather than being rejected outright.
    test('clamps dimensions to their floors', () {
      final config = DesktopConfig.fromMap({
        'cell_width': 4,
        'cell_height': 0,
        'spacing': -10,
        'padding': -1,
        'icon_size': 1,
      });
      expect(config.cellWidth, 32);
      expect(config.cellHeight, 32);
      expect(config.spacing, 0);
      expect(config.padding, 0);
      expect(config.iconSize, 8);
    });

    test('drops unparseable items instead of throwing', () {
      final config = DesktopConfig.fromMap({
        'items': [
          {'target': '/a/b.txt', 'column': 1, 'row': 1},
          {'no_target': true},
          'not a table',
          42,
        ],
      });
      expect(config.items, hasLength(1));
      expect(config.items.single.target, '/a/b.txt');
    });

    test('preserves item document order', () {
      final config = DesktopConfig.fromMap({
        'items': [
          {'target': '/c'},
          {'target': '/a'},
          {'target': '/b'},
        ],
      });
      expect(config.items.map((e) => e.target), ['/c', '/a', '/b']);
    });
  });

  group('AppConfig.fromMap', () {
    test('an absent [desktop] section is an empty enabled grid, never null',
        () {
      final config = AppConfig.fromMap({});
      expect(config.desktop.enabled, isTrue);
      expect(config.desktop.items, isEmpty);
    });

    test('an explicit `enabled = false` still turns the grid off', () {
      final config = AppConfig.fromMap({
        'desktop': {'enabled': false},
      });
      expect(config.desktop.enabled, isFalse);
    });

    test('reads the [desktop] section when present', () {
      final config = AppConfig.fromMap({
        'desktop': {
          'enabled': true,
          'cell_width': 120,
          'items': [
            {'target': '/a/b.txt', 'column': 2, 'row': 1},
          ],
        },
      });
      expect(config.desktop.enabled, isTrue);
      expect(config.desktop.cellWidth, 120);
      expect(config.desktop.items.single.column, 2);
    });
  });
}
