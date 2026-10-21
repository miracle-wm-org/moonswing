// Settings › Default Apps, over a fake GIO: what the rows show, what a pick
// writes, the full list and its filter, and the failure states.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/default_apps/default_apps_store.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/default_apps.dart';
import 'package:moonswing/scopes.dart';

import 'default_apps_fakes.dart';

void main() {
  late FakeAssociations gio;
  late DefaultAppsStore store;

  setUp(() {
    gio = FakeAssociations();
    store = DefaultAppsStore(associations: gio);
  });

  tearDown(() => store.dispose());

  Future<void> pump(WidgetTester tester) async {
    // Tall enough for every "Defaults" row and the full list's first rows, so
    // nothing here has to scroll to find what it taps.
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextEditingShortcuts(
          child: ThemeScope(
            theme: const ThemeConfig(),
            // The dropdowns float in the root overlay, as they do in the
            // settings window.
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => SizedBox(
                    width: 900,
                    height: 1800,
                    child: DefaultAppsSettingsPage(store: store),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder resetButtons() => find.byWidgetPredicate(
    (w) =>
        w is SettingsIconButton && w.icon == ShellGlyph.undo,
  );

  testWidgets('shows what opens each kind of file now', (tester) async {
    await pump(tester);
    expect(find.text('Web browser'), findsOneWidget);
    expect(find.text('Chromium'), findsOneWidget);
    expect(find.text('Text Editor'), findsOneWidget);
    expect(find.text('GIMP'), findsOneWidget);
    // Nothing on this machine opens a folder.
    expect(find.text('No application installed'), findsWidgets);
    // Nothing is the user's own choice yet.
    expect(resetButtons(), findsNothing);
  });

  testWidgets('picking an application writes it, and offers a reset', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Chromium'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Firefox').last);
    await tester.pumpAndSettle();

    expect(gio.writes, [
      'x-scheme-handler/https=firefox.desktop',
      'x-scheme-handler/http=firefox.desktop',
      'text/html=firefox.desktop',
    ]);
    expect(find.text('Firefox'), findsOneWidget);
    expect(find.text('Chromium'), findsNothing);
    expect(resetButtons(), findsOneWidget);

    await tester.tap(resetButtons());
    await tester.pumpAndSettle();
    expect(gio.user, isEmpty);
    expect(find.text('Chromium'), findsOneWidget);
    expect(resetButtons(), findsNothing);
  });

  testWidgets('re-picking the current application writes nothing', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Chromium'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chromium').last);
    await tester.pumpAndSettle();
    expect(gio.writes, isEmpty);
  });

  testWidgets('the full list appears on request and filters', (tester) async {
    await pump(tester);
    expect(find.text('image/x-xcf'), findsNothing);
    await tester.tap(find.text('Show all file types'));
    await tester.pumpAndSettle();
    expect(find.text('Show all file types'), findsNothing);
    expect(find.text('image/x-xcf'), findsOneWidget);
    expect(find.text('PNG image'), findsOneWidget);
    expect(find.text('https: links'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'xcf');
    await tester.pumpAndSettle();
    expect(find.text('image/x-xcf'), findsOneWidget);
    expect(find.text('image/png'), findsNothing);

    await tester.enterText(find.byType(EditableText), 'no such type');
    await tester.pumpAndSettle();
    expect(find.text('No file type matches "no such type".'), findsOneWidget);
  });

  testWidgets('a type picked in the full list changes that type alone', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Show all file types'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'image/png');
    await tester.pumpAndSettle();

    // PNG has no default yet, so its dropdown shows a dash.
    await tester.tap(find.text('—'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image Viewer').last);
    await tester.pumpAndSettle();
    expect(gio.writes, ['image/png=loupe.desktop']);
    // The Images row reads JPEG, which this did not touch.
    expect(find.text('GIMP'), findsOneWidget);
  });

  testWidgets('a write that does not take is a banner', (tester) async {
    gio.pinned['x-scheme-handler/https'] = 'chromium.desktop';
    await pump(tester);
    await tester.tap(find.text('Chromium'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Firefox').last);
    await tester.pumpAndSettle();

    expect(find.text('Firefox was saved but is not in effect'), findsOneWidget);
    expect(find.textContaining('miracle-wm-mimeapps.list'), findsOneWidget);

    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is SettingsIconButton && w.icon == ShellGlyph.close,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Firefox was saved but is not in effect'), findsNothing);
  });

  testWidgets('an unreadable system is a banner with a retry', (tester) async {
    gio.failReads = StateError('no GIO');
    await pump(tester);
    expect(find.text('Default applications unavailable'), findsOneWidget);
    expect(find.text('Web browser'), findsNothing);

    gio.failReads = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Default applications unavailable'), findsNothing);
    expect(find.text('Web browser'), findsOneWidget);
  });

  // The full list is a fixed extent, so the extent has to grow with the
  // theme's font size or every row overflows it — which a test reports.
  for (final scale in [1.0, 1.4, 2.0]) {
    testWidgets('a full-list row fits its extent at ${scale}x type', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      store.acquire();
      addTearDown(store.release);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: DefaultTextEditingShortcuts(
              child: ThemeScope(
                theme: const ThemeConfig(),
                child: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => SizedBox(
                        width: 1200,
                        height: 1800,
                        child: DefaultAppsSettingsPage(store: store),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      store.showAllTypes();
      await tester.pumpAndSettle();
      expect(find.text('image/x-xcf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
