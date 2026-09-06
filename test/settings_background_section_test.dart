import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/overlay/settings/shell/background.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/wallpaper_catalog.dart';

/// The two sources of the wallpaper list, and the rule that separates them: a
/// wallpaper the machine ships is always offered and can never be deleted, while
/// one the user added can be.
///
/// The catalogue is injected and pointed at a temp tree, so this never walks the
/// real `/usr/share`.
void main() {
  /// A 1x1 transparent PNG, so the tiles decode instead of falling through to
  /// the error placeholder.
  final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQAB'
      'DQottAAAAABJRU5ErkJggg==');

  late Directory tempDir;
  late String configPath;
  late String systemA;
  late String systemB;
  late String userPath;
  late ConfigStore store;

  Future<String> writePng(String relative) async {
    final path = '${tempDir.path}/$relative';
    await Directory(path.substring(0, path.lastIndexOf('/')))
        .create(recursive: true);
    await File(path).writeAsBytes(pngBytes);
    return path;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gs_background_section');
    configPath = '${tempDir.path}/config.toml';
    // Named so the sorted catalogue order is stable and obvious.
    systemA = await writePng('backgrounds/a-warty.png');
    systemB = await writePng('backgrounds/b-adwaita.png');
    userPath = await writePng('pictures/mine.png');
    await File(configPath).writeAsString('theme = "graceful"\n');
    store = await ConfigStore.loadFrom(configPath);
  });

  tearDown(() async {
    store.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  List<Map> entries() =>
      (store.get<List>(['background', 'entries']) ?? const []).cast<Map>();

  /// Pumps the section the way the settings pane does — inside a scroll view,
  /// under a [ThemeScope], with the catalogue pointed at the temp tree — and
  /// settles the catalogue's async walk.
  Future<void> pumpSection(WidgetTester tester) async {
    final catalog =
        SystemWallpaperCatalog(roots: ['${tempDir.path}/backgrounds']);
    // The walk is real file I/O, which a `testWidgets` fake-async zone never
    // pumps — resolving it here leaves the section's `then` a microtask away.
    await tester.runAsync(catalog.list);
    // Tall enough that every tile is inside the viewport, so a tap is not
    // silently swallowed by the scroll view's clip.
    tester.view.physicalSize = const Size(560, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 14),
          child: ThemeScope(
            theme: const ThemeConfig(),
            // The settings content pane is a nested Navigator, so the section
            // always builds under an Overlay — which the shown grid's
            // `Draggable` tiles require.
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 520,
                      height: 1700,
                      // A `CustomScrollView`, because the section is a sliver —
                      // `_ShellCategoryView` builds it the same way. No
                      // `ListenableBuilder` around it either: the section
                      // subscribes to the entry list itself.
                      //
                      // `cacheExtent` matches the page's, and the viewport above
                      // is deliberately taller than the content: the grids are
                      // lazy, so a tile scrolled out of range would be unmounted
                      // and `find.byKey` would miss it.
                      child: CustomScrollView(
                        scrollCacheExtent: const ScrollCacheExtent.pixels(600),
                        slivers: [
                          BackgroundSection(store: store, catalog: catalog),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // The catalogue's future was completed outside the fake-async zone, so its
    // `then` lands on the real microtask queue — `runAsync` is what drains it.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    // One pump for the resulting setState, one for the image frames.
    await tester.pump();
    await tester.pump();
  }

  /// Moves a mouse onto [path]'s tile, which is what reveals the remove button.
  Future<TestGesture> hoverTile(WidgetTester tester, String path) async {
    await tester.ensureVisible(find.byKey(ValueKey(path)));
    await tester.pump();
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byKey(ValueKey(path))));
    await tester.pump();
    return gesture;
  }

  /// Clicks [path]'s tile, which is what moves it between Shown and Available.
  Future<void> tapTile(WidgetTester tester, String path) async {
    await tester.ensureVisible(find.byKey(ValueKey(path)));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey(path)));
    await tester.pump();
  }

  Finder removeButtonIn(String path) => find.descendant(
        of: find.byKey(ValueKey(path)),
        // Compared on the code point: `FaIcon` normalizes the icon it is given,
        // so the styled `IconDataSolid` constant is not `==` what it holds.
        matching: find.byWidgetPredicate((w) =>
            w is FaIcon &&
            w.icon?.codePoint == FontAwesomeIcons.xmark.codePoint),
      );

  /// Lets the store's debounced write fire so no timer outlives the test.
  Future<void> settleWrite(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 500));

  testWidgets('lists the installed wallpapers with no config entries at all',
      (tester) async {
    await pumpSection(tester);

    expect(find.byKey(ValueKey(systemA)), findsOneWidget);
    expect(find.byKey(ValueKey(systemB)), findsOneWidget);
    // Discovery alone must not write anything: the config is still untouched,
    // which is what keeps these undeletable rather than merely undeleted.
    expect(entries(), isEmpty);
  });

  testWidgets('offers no remove button on an installed wallpaper',
      (tester) async {
    await pumpSection(tester);
    await hoverTile(tester, systemA);

    expect(removeButtonIn(systemA), findsNothing);
  });

  testWidgets('offers one on a wallpaper the user added', (tester) async {
    store.set(['background', 'entries'], [
      {'path': userPath, 'shown': false},
    ]);
    await pumpSection(tester);
    await hoverTile(tester, userPath);

    expect(removeButtonIn(userPath), findsOneWidget);

    await tester.tap(removeButtonIn(userPath));
    await tester.pump();

    expect(entries(), isEmpty);
    expect(find.byKey(ValueKey(userPath)), findsNothing);
    await settleWrite(tester);
  });

  testWidgets('selecting an installed wallpaper adds it to the rotation',
      (tester) async {
    await pumpSection(tester);

    await tapTile(tester, systemA);

    expect(entries(), [
      {'path': systemA, 'shown': true},
    ]);
    await settleWrite(tester);
  });

  testWidgets('deselecting one drops its entry instead of hiding it',
      (tester) async {
    store.set(['background', 'entries'], [
      {'path': systemA, 'shown': true},
    ]);
    await pumpSection(tester);

    await tapTile(tester, systemA);

    // A hidden entry would list the wallpaper twice — once from the config and
    // once from the catalogue — and leave an undeletable path in the file.
    expect(entries(), isEmpty);
    expect(find.byKey(ValueKey(systemA)), findsOneWidget);
    await settleWrite(tester);
  });

  testWidgets('keeps a deselected user wallpaper in the list', (tester) async {
    store.set(['background', 'entries'], [
      {'path': userPath, 'shown': true},
    ]);
    await pumpSection(tester);

    await tapTile(tester, userPath);

    expect(entries(), [
      {'path': userPath, 'shown': false},
    ]);
    expect(find.byKey(ValueKey(userPath)), findsOneWidget);
    await settleWrite(tester);
  });
}
