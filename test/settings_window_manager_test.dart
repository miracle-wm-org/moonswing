// Settings › Window Manager on a compositor that is not Miracle WM.
//
// The pane edits miracle-wm's own configuration, so anywhere else its sidebar
// row is greyed out and says why on hover, and nothing — a search result, a
// route — can send the user into it.

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/miracle_manager.dart';
import 'package:moonswing/overlay/overlay.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_search_bar.dart';
import 'package:moonswing/scopes.dart';

MiracleManager _sway() =>
    MiracleManager(environment: const {'XDG_CURRENT_DESKTOP': 'sway'});

MiracleManager _miracle() =>
    MiracleManager(environment: const {'XDG_CURRENT_DESKTOP': 'miracle-wm'});

Widget _chrome(MiracleManager manager, Widget child) => MiracleScope(
  manager: manager,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: DefaultTextEditingShortcuts(
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14),
        child: ThemeScope(theme: const ThemeConfig(), child: child),
      ),
    ),
  ),
);

/// The sidebar under a root [Overlay], the way the settings window has one —
/// [SettingsTooltip] floats its card there.
Future<String?> _pumpSidebar(
  WidgetTester tester,
  MiracleManager manager,
) async {
  String? selected;
  await tester.pumpWidget(
    _chrome(
      manager,
      // The test font draws every glyph a full em wide, which "Window Manager"
      // at 13px does not fit the 180px sidebar in.
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(0.5)),
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => Align(
                alignment: Alignment.topLeft,
                child: SettingsSidebar(
                  selectedCategory: 'network',
                  onCategorySelected: (category) => selected = category,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.tap(find.text('Window Manager'), warnIfMissed: false);
  await tester.pump();
  return selected;
}

Future<void> _hover(WidgetTester tester, Finder target) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: tester.getCenter(target));
  await tester.pump();
  await tester.pump(kSettingsTooltipDelay);
}

Future<List<String>> _searchSections(
  WidgetTester tester,
  MiracleManager manager,
  String query,
) async {
  final focus = FocusNode();
  addTearDown(focus.dispose);
  await tester.pumpWidget(
    _chrome(manager, SettingsSearchBar(focusNode: focus, onJump: (_) {})),
  );
  await tester.enterText(find.byType(EditableText), query);
  await tester.pump();
  return [
    for (final text in tester.widgetList<Text>(
      find.descendant(
        of: find.byType(SettingsSearchResults),
        matching: find.byType(Text),
      ),
    ))
      text.data ?? '',
  ];
}

void main() {
  group('the sidebar row', () {
    testWidgets('is inert on another compositor and says why on hover', (
      tester,
    ) async {
      expect(await _pumpSidebar(tester, _sway()), isNull);

      await _hover(tester, find.text('Window Manager'));
      expect(find.text(kWindowManagerUnavailable), findsOneWidget);
    });

    testWidgets('opens the pane, and explains nothing, under Miracle WM', (
      tester,
    ) async {
      expect(await _pumpSidebar(tester, _miracle()), 'miracle');

      await _hover(tester, find.text('Window Manager'));
      expect(find.text(kWindowManagerUnavailable), findsNothing);
    });

    testWidgets('leaves every other row alone', (tester) async {
      await _pumpSidebar(tester, _sway());
      await _hover(tester, find.text('Keyboard'));
      expect(find.text(kWindowManagerUnavailable), findsNothing);
    });
  });

  group('settings search', () {
    testWidgets('offers no Window Manager result on another compositor', (
      tester,
    ) async {
      final sections = await _searchSections(tester, _sway(), 'terminal');
      expect(sections, isNot(contains(startsWith('Window Manager'))));
    });

    testWidgets('offers them under Miracle WM', (tester) async {
      final sections = await _searchSections(tester, _miracle(), 'terminal');
      expect(sections, contains(startsWith('Window Manager')));
    });
  });
}
