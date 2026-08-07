import 'dart:ffi' as ffi;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/app_chooser.dart';
import 'package:graceful_shell/launcher/app_search.dart';
import 'package:graceful_shell/scopes.dart';

/// [AppEntry.appInfo] is a raw `GAppInfo*`, and nothing here launches anything,
/// so a null pointer stands in — the chooser only ever reads the Dart fields.
AppEntry _app(
  String name, {
  String? filename,
  String generic = '',
  List<String> keywords = const [],
}) {
  return AppEntry(
    id: name.toLowerCase(),
    name: name,
    iconName: '',
    categories: const [],
    genericName: generic,
    keywords: keywords,
    filename: filename ?? '/usr/share/applications/${name.toLowerCase()}.desktop',
    appInfo: ffi.nullptr,
  );
}

void main() {
  final apps = [
    _app('Firefox', generic: 'Web Browser', keywords: ['internet']),
    _app('Files', generic: 'File Manager'),
    _app('Text Editor'),
  ].map(SearchableApp.new).toList();

  Future<void> pumpChooser(
    WidgetTester tester, {
    List<SearchableApp>? entries,
    ValueChanged<AppEntry>? onSelected,
    VoidCallback? onCancel,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextEditingShortcuts(
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 14),
            child: ThemeScope(
              theme: const ThemeConfig(),
              child: SizedBox(
                width: 900,
                height: 700,
                child: AppChooserCard(
                  apps: entries ?? apps,
                  onSelected: onSelected ?? (_) {},
                  onCancel: onCancel ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('AppChooserCard', () {
    test('SearchableApp carries the entry through unchanged', () {
      final searchable = SearchableApp(_app('Firefox'));
      expect(searchable.entry.filename,
          '/usr/share/applications/firefox.desktop');
    });

    testWidgets('lists every application up front, with a row each',
        (tester) async {
      await pumpChooser(tester);
      expect(find.byType(AppChooserRow), findsNWidgets(3));
      expect(find.text('Firefox'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('Text Editor'), findsOneWidget);
    });

    testWidgets('shows the generic name beside the app name', (tester) async {
      await pumpChooser(tester);
      expect(find.text('Web Browser'), findsOneWidget);
      expect(find.text('File Manager'), findsOneWidget);
    });

    testWidgets('typing narrows the list by the shared ranking', (tester) async {
      await pumpChooser(tester);
      await tester.enterText(find.byType(EditableText), 'fire');
      await tester.pump();

      expect(find.byType(AppChooserRow), findsOneWidget);
      expect(find.text('Firefox'), findsOneWidget);
    });

    // Keywords are why searching "internet" finds Firefox; the chooser gets
    // that for free by reusing rankApps.
    testWidgets('matches on keywords, not just the name', (tester) async {
      await pumpChooser(tester);
      await tester.enterText(find.byType(EditableText), 'internet');
      await tester.pump();
      expect(find.text('Firefox'), findsOneWidget);
    });

    testWidgets('says so when nothing matches', (tester) async {
      await pumpChooser(tester);
      await tester.enterText(find.byType(EditableText), 'zzzznope');
      await tester.pump();
      expect(find.byType(AppChooserRow), findsNothing);
      expect(find.text('No matching applications.'), findsOneWidget);
    });

    testWidgets('clicking a row selects that application', (tester) async {
      AppEntry? chosen;
      await pumpChooser(tester, onSelected: (app) => chosen = app);

      await tester.tap(find.text('Files'));
      await tester.pump();
      expect(chosen?.name, 'Files');
      expect(chosen?.filename, '/usr/share/applications/files.desktop');
    });

    testWidgets('Down then Enter picks the second result', (tester) async {
      AppEntry? chosen;
      await pumpChooser(tester, onSelected: (app) => chosen = app);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(chosen?.name, 'Files');
    });

    testWidgets('the highlight cannot run off either end', (tester) async {
      AppEntry? chosen;
      await pumpChooser(tester, onSelected: (app) => chosen = app);

      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      }
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(chosen?.name, 'Firefox');

      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(chosen?.name, 'Text Editor');
    });

    testWidgets('Escape cancels', (tester) async {
      var cancelled = 0;
      await pumpChooser(tester, onCancel: () => cancelled++);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(cancelled, 1);
    });

    // DesktopItem.target is a path, so an entry with no .desktop file behind it
    // could not be pinned — better to omit it than to offer and then refuse.
    testWidgets('omits applications that have no .desktop path',
        (tester) async {
      await pumpChooser(
        tester,
        entries: [
          _app('Firefox'),
          _app('Phantom', filename: ''),
        ].map(SearchableApp.new).toList(),
      );
      expect(find.byType(AppChooserRow), findsOneWidget);
      expect(find.text('Phantom'), findsNothing);
    });

    testWidgets('an empty list is handled, not crashed on', (tester) async {
      await pumpChooser(tester, entries: const []);
      expect(find.text('No matching applications.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
    });
  });

  group('AppChooserOverlay', () {
    // The shell has no input-region support, so this surface swallows every
    // click on the monitor — without backdrop dismissal a mouse-only user
    // would have no way out.
    testWidgets('tapping the backdrop cancels', (tester) async {
      var cancelled = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 14),
            child: ThemeScope(
              theme: const ThemeConfig(),
              child: SizedBox(
                width: 900,
                height: 700,
                child: AppChooserOverlay(
                  apps: apps,
                  onSelected: (_) {},
                  onCancel: () => cancelled++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Top-left corner: outside the centred card.
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(cancelled, 1);
    });
  });
}
