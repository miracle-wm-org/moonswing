// Shell › Modules: a list of the modules, each pushing a page of its
// own over it, rather than one page of every module's rows.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/overlay/settings/settings_highlight.dart';
import 'package:moonswing/overlay/settings/shell.dart';
import 'package:moonswing/overlay/settings/shell/modules.dart';
import 'package:moonswing/overlay/settings_route.dart';
import 'package:moonswing/scopes.dart';

void main() {
  late Directory tempDir;
  late ConfigStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gs_module_pages');
    final path = '${tempDir.path}/config.toml';
    await File(path).writeAsString('');
    store = await ConfigStore.loadFrom(path);
  });

  tearDown(() async {
    store.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Widget frame(Widget child, {SettingsHighlightController? highlight}) {
    final page = Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextEditingShortcuts(
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 14),
          child: ThemeScope(
            theme: const ThemeConfig(),
            // The test font draws every glyph a full em wide.
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(900, 1200),
                textScaler: TextScaler.linear(0.5),
              ),
              child: Overlay(
                initialEntries: [OverlayEntry(builder: (_) => child)],
              ),
            ),
          ),
        ),
      ),
    );
    if (highlight == null) return page;
    return SettingsHighlightScope(controller: highlight, child: page);
  }

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    SettingsHighlightController? highlight,
  }) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(child, highlight: highlight));
    await tester.pump();
  }

  group('the module pages', () {
    // Every row a page renders is a search result, and every result lands on
    // the page that renders it: the catalogue is assembled by hand, and this is
    // what stops a row added to a page being left unsearchable.
    test('hold exactly the catalogue\'s module rows, in order', () {
      expect(
        [
          for (final page in moduleSettingsPages)
            for (final field in page.fields) field.id,
        ],
        [for (final field in SettingsCatalog.moduleFields) field.id],
      );
    });

    test('are one per titled module, keyed on the config key', () {
      final keys = [for (final page in moduleSettingsPages) page.key];
      expect(keys.toSet(), hasLength(keys.length));
      expect(keys.toSet(), SettingsCatalog.moduleTitles.keys.toSet());
      for (final page in moduleSettingsPages) {
        expect(moduleSettingsPageByKey(page.key), same(page));
        expect(page.route, SettingsRoute.module(page.key));
        for (final field in page.fields) {
          expect(field.id.split('.')[1], page.key, reason: field.id);
          expect(field.route, page.route, reason: field.id);
          expect(field.section, endsWith('› ${page.title}'));
        }
      }
      expect(moduleSettingsPageByKey('nonexistent'), isNull);
      expect(moduleSettingsPageByKey(null), isNull);
    });
  });

  group('Modules', () {
    testWidgets('lists the modules instead of every row', (tester) async {
      await pump(
        tester,
        ShellSettingsPage(
          initialCategory: kModuleSettingsCategory,
          store: store,
        ),
      );
      for (final page in moduleSettingsPages) {
        expect(find.text(page.title), findsOneWidget, reason: page.title);
      }
      // No module's rows until its page is opened.
      expect(find.text(SettingsCatalog.clockShowDate.label), findsNothing);
      expect(find.text(SettingsCatalog.dockApps.label), findsNothing);
    });

    testWidgets('a module pushes its own page, and Back returns to the list', (
      tester,
    ) async {
      await pump(tester, ShellSettingsPage(store: store));

      await tester.tap(find.text(kModuleSettingsCategory));
      await tester.pump();
      await tester.tap(find.text('Clock'));
      await tester.pump();

      expect(find.text(SettingsCatalog.clockShowDate.label), findsOneWidget);
      expect(find.text(SettingsCatalog.clockTimerSound.label), findsOneWidget);
      // Another module's rows are on another page.
      expect(find.text(SettingsCatalog.dockApps.label), findsNothing);
      expect(find.text('Battery'), findsNothing);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pump();
      expect(find.text(SettingsCatalog.clockShowDate.label), findsNothing);
      expect(find.text('Battery'), findsOneWidget);

      navigator.pop();
      await tester.pump();
      expect(find.text('Moonswing'), findsOneWidget);
    });

    testWidgets('a route naming a module opens its page over the list', (
      tester,
    ) async {
      await pump(
        tester,
        ShellSettingsPage(
          initialCategory: SettingsRoute.stocks.shellCategory,
          initialModule: SettingsRoute.stocks.module,
          store: store,
        ),
      );
      expect(find.text(SettingsCatalog.stocksSymbols.label), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      expect(find.text('Stock market'), findsOneWidget);
      expect(find.text('Weather'), findsOneWidget);
    });

    testWidgets('a search jump to a module row lands on its page', (
      tester,
    ) async {
      final highlight = SettingsHighlightController();
      addTearDown(highlight.dispose);
      await pump(tester, ShellSettingsPage(store: store), highlight: highlight);
      expect(find.text('Moonswing'), findsOneWidget);

      highlight.jumpTo(SettingsCatalog.recorderFps);
      await tester.pump();
      await tester.pump();
      expect(find.text(SettingsCatalog.recorderFps.label), findsOneWidget);

      // Back goes to the module list, not straight to the landing page.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      expect(find.text('Screen recorder'), findsOneWidget);

      // Let the flash and the target's expiry run out.
      await tester.pump(kSettingsHighlightTimeout);
      await tester.pump(kSettingsHighlightFlash);
    });
  });
}
