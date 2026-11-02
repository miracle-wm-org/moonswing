import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/theme/theme_wallpaper.dart';

/// Where a theme's `wallpaper` key points: a path of its own, a file beside the
/// theme, or one of the shell's installed wallpapers — and nothing otherwise.
void main() {
  late Directory dir;
  late String themes;
  late String shippedDir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('gs_theme_wallpaper');
    themes = '${dir.path}/themes';
    shippedDir = '${dir.path}/share/moonswing';
    Directory(themes).createSync(recursive: true);
    Directory(shippedDir).createSync(recursive: true);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  String? shipped(String name) {
    final path = '$shippedDir/$name';
    return File(path).existsSync() ? path : null;
  }

  String? resolve(String value) => resolveThemeWallpaper(
    ThemeConfig(wallpaper: value),
    themesDirectory: themes,
    shipped: shipped,
  );

  test('an empty value is no wallpaper', () {
    expect(resolve(''), isNull);
    expect(resolve('   '), isNull);
  });

  test('an absolute path is that file, when it exists', () {
    final file = File('${dir.path}/mine.jpg')..writeAsBytesSync([1]);
    expect(resolve(file.path), file.path);
    expect(resolve('${dir.path}/gone.jpg'), isNull);
  });

  test('a bare name is one of the installed wallpapers', () {
    File('$shippedDir/wallpaper-forest.jpg').writeAsBytesSync([1]);
    expect(resolve('wallpaper-forest.jpg'), '$shippedDir/wallpaper-forest.jpg');
    expect(resolve('wallpaper-nowhere.jpg'), isNull);
  });

  test('a file beside the theme wins over the installed one', () {
    File('$shippedDir/wallpaper-forest.jpg').writeAsBytesSync([1]);
    File('$themes/wallpaper-forest.jpg').writeAsBytesSync([2]);
    expect(resolve('wallpaper-forest.jpg'), '$themes/wallpaper-forest.jpg');
  });

  test('a relative path never reaches into the install tree', () {
    Directory('$shippedDir/sub').createSync();
    File('$shippedDir/sub/x.jpg').writeAsBytesSync([1]);
    expect(resolve('sub/x.jpg'), isNull);
  });
}
