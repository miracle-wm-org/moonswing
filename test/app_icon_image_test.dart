import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/app_info.dart';
import 'package:xdg_icons/xdg_icons.dart';

/// Pins how [AppIconImage] reads an icon name. snapd hands GIO an absolute
/// path for nearly every snap (`/snap/<name>/current/meta/gui/icon.svg`), and
/// an SVG one went through `Image.file`, which cannot decode it — every snap
/// with a vector icon drew its first letter.
void main() {
  group('appIconFilePath', () {
    test('an absolute path is its own file', () {
      expect(appIconFilePath('/snap/firefox/current/default256.png'),
          '/snap/firefox/current/default256.png');
    });

    test('a file:// URI is decoded to its path', () {
      expect(appIconFilePath('file:///snap/foo/current/meta/gui/my%20icon.svg'),
          '/snap/foo/current/meta/gui/my icon.svg');
    });

    test('a themed name is not a file', () {
      expect(appIconFilePath('firefox'), isNull);
      expect(appIconFilePath('snap.foo.bar'), isNull);
      expect(appIconFilePath(''), isNull);
    });
  });

  group('AppIconImage', () {
    late Directory dir;
    // No icon theme under flutter_tester: answer the plugin's lookup with "not
    // found" rather than leave it to throw MissingPluginException.
    const channel = MethodChannel('xdg_icons');
    setUp(() {
      dir = Directory.systemTemp.createTempSync('app_icon_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      dir.deleteSync(recursive: true);
    });

    Widget host(String iconName) => Directionality(
          textDirection: TextDirection.ltr,
          child: AppIconImage(
            iconName: iconName,
            name: 'Snap',
            size: 32,
            foreground: const Color(0xFFFFFFFF),
          ),
        );

    testWidgets('an SVG path is drawn as SVG, not handed to Image.file',
        (tester) async {
      final svg = File('${dir.path}/icon.svg')
        ..writeAsStringSync('<svg xmlns="http://www.w3.org/2000/svg" '
            'viewBox="0 0 10 10"><rect width="10" height="10"/></svg>');
      await tester.pumpWidget(host(svg.path));
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(XdgIcon), findsNothing);
    });

    testWidgets('an upper-case extension is still SVG', (tester) async {
      await tester.pumpWidget(host('${dir.path}/ICON.SVG'));
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('a raster path is drawn with Image.file', (tester) async {
      await tester.pumpWidget(host('${dir.path}/icon.png'));
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
    });

    testWidgets('a file:// URI is drawn from its file', (tester) async {
      await tester.pumpWidget(host('file://${dir.path}/icon.svg'));
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(XdgIcon), findsNothing);
    });

    testWidgets('a themed name goes to the icon theme', (tester) async {
      await tester.pumpWidget(host('firefox'));
      expect(find.byType(XdgIcon), findsOneWidget);
    });
  });
}
