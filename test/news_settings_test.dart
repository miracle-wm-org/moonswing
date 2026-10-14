import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/shell/desktop.dart';
import 'package:moonswing/scopes.dart';

/// The News widget's rows on the Desktop page: presets are chips, feeds of
/// the user's own a list, and both are one `[news] sources` key that neither
/// control may clobber the other's half of.
void main() {
  late Directory tempDir;
  late ConfigStore store;

  Future<void> load(String toml) async {
    tempDir = await Directory.systemTemp.createTemp('news_settings');
    final path = '${tempDir.path}/config.toml';
    await File(path).writeAsString(toml);
    store = await ConfigStore.loadFrom(path);
  }

  // Loaded inside each test through `runAsync`: real file I/O never completes
  // in a `testWidgets` fake-async zone.
  tearDown(() async {
    store.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(640, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 14),
          child: ThemeScope(
            theme: const ThemeConfig(),
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => CustomScrollView(
                    slivers: [NewsSettingsSection(store: store)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Lets the store's debounced write fire so no timer outlives the test.
  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 500));

  bool selected(WidgetTester tester, String label) => tester
      .widget<SettingsOptionButton>(
        find.widgetWithText(SettingsOptionButton, label),
      )
      .selected;

  List<String>? sources() =>
      store.get<List>(['news', 'sources'])?.cast<String>();

  testWidgets('with no key, the default pair shows chosen', (tester) async {
    await tester.runAsync(() => load(''));
    await pumpSection(tester);
    expect(selected(tester, 'AP'), isTrue);
    expect(selected(tester, 'Reuters'), isTrue);
    expect(selected(tester, 'NPR'), isFalse);

    await tester.tap(find.text('NPR'));
    await tester.pump();
    expect(sources(), ['ap', 'reuters', 'npr']);
    await settle(tester);
  });

  testWidgets('a chip leaves a feed of the user\'s own where it was', (
    tester,
  ) async {
    await tester.runAsync(
      () => load('[news]\nsources = ["https://example.com/feed.xml", "bbc"]\n'),
    );
    await pumpSection(tester);
    expect(find.text('https://example.com/feed.xml'), findsOneWidget);

    await tester.tap(find.text('AP'));
    await tester.pump();
    expect(sources(), ['ap', 'bbc', 'https://example.com/feed.xml']);

    await tester.tap(find.text('BBC'));
    await tester.pump();
    expect(sources(), ['ap', 'https://example.com/feed.xml']);
    expect(selected(tester, 'BBC'), isFalse);
    await settle(tester);
  });
}
