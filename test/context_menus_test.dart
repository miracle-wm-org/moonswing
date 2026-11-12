import 'dart:io';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/context_menus.dart';
import 'package:moonswing/desktop/desktop_menu.dart';
import 'package:moonswing/desktop/widgets/news_widget.dart';
import 'package:moonswing/desktop/widgets/stocks_widget.dart';
import 'package:moonswing/desktop/widgets/weather_widget.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/overlay/settings/shell.dart' show isShellCategory;
import 'package:moonswing/overlay/settings/shell/modules.dart';
import 'package:moonswing/overlay/settings_route.dart';
import 'package:moonswing/quick_settings.dart';
import 'package:moonswing/scopes.dart';

/// The rows a list of menu items draws, flattened through the live groups —
/// what a person reading the open menu would see, in order.
List<DesktopMenuItem> _flatten(List<DesktopMenuItem> items) => [
  for (final item in items)
    if (item is DesktopMenuLive) ..._flatten(item.build()) else item,
];

List<String> _labels(List<DesktopMenuItem> items) => [
  for (final item in _flatten(items))
    switch (item) {
      DesktopMenuEntry(:final label) => label,
      DesktopMenuHeading(:final text) => '# $text',
      DesktopMenuDivider() => '—',
      DesktopMenuLive() => throw StateError('flattened'),
    },
];

DesktopMenuEntry _entry(List<DesktopMenuItem> items, String label) =>
    _flatten(items).whereType<DesktopMenuEntry>().singleWhere(
      (entry) => entry.label == label,
    );

Future<void> _pumpCard(WidgetTester tester, List<DesktopMenuItem> items) =>
    tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Align(
            alignment: Alignment.topLeft,
            child: DesktopMenuCard(entries: items),
          ),
        ),
      ),
    );

void main() {
  late Directory tempDir;
  late ConfigStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('context_menus_test');
    final path = '${tempDir.path}/config.toml';
    await File(path).writeAsString('''
[modules.clock]
show_date = false
''');
    store = await ConfigStore.loadFrom(path);
  });

  tearDown(() async {
    store.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('a module\'s menu', () {
    test('is its quick settings, then its page and its panel', () {
      final items = moduleMenuItems(
        moduleKey: 'clock',
        panelName: 'top',
        close: () {},
        openSettings: (_) {},
        store: store,
      );
      expect(_labels(items), [
        'Show weekday',
        'Show date',
        'Show week number',
        'Show seconds',
        '# ${SettingsCatalog.clockHourFormat.label}',
        '24-hour (14:05)',
        '12-hour (2:05 PM)',
        '—',
        'Clock settings…',
        'Panel settings…',
      ]);
    });

    test('ends with the bar\'s own edits, each closing the menu first', () {
      final events = <String>[];
      final items = moduleMenuItems(
        moduleKey: 'sound_control',
        panelName: 'top',
        close: () => events.add('close'),
        openSettings: (_) {},
        store: store,
        onAddModule: () => events.add('add'),
        onRemove: () => events.add('remove'),
      );
      expect(_labels(items), [
        'Sound settings…',
        'Panel settings…',
        '—',
        'Add module…',
        'Remove from panel',
      ]);
      _entry(items, 'Add module…').onTap();
      _entry(items, 'Remove from panel').onTap();
      expect(events, ['close', 'add', 'close', 'remove']);
    });

    test('a toggle reads the file, falls back to the default, and writes', () {
      final items = moduleMenuItems(
        moduleKey: 'clock',
        panelName: null,
        close: () {},
        openSettings: (_) {},
        store: store,
      );
      // Written in the file as false.
      final date = _entry(items, 'Show date');
      expect(date.checked, isFalse);
      date.onTap();
      expect(store.get<bool>(['modules', 'clock', 'show_date']), isTrue);
      // Re-read off the store, as the open menu does on its notify.
      expect(_entry(items, 'Show date').checked, isTrue);

      // Absent from the file: the module's own default.
      expect(_entry(items, 'Show seconds').checked, isFalse);
    });

    test('a choice checks the current option and writes the one tapped', () {
      final items = moduleMenuItems(
        moduleKey: 'clock',
        panelName: null,
        close: () {},
        openSettings: (_) {},
        store: store,
      );
      expect(_entry(items, '24-hour (14:05)').selected, isTrue);
      expect(_entry(items, '12-hour (2:05 PM)').selected, isFalse);
      // Every option keeps room for the check, so moving it cannot widen the
      // card past the surface it was mapped at.
      expect(_entry(items, '12-hour (2:05 PM)').selectable, isTrue);

      _entry(items, '12-hour (2:05 PM)').onTap();
      expect(store.get<String>(['modules', 'clock', 'hour_format']), '12');
      expect(_entry(items, '12-hour (2:05 PM)').selected, isTrue);
    });

    test('a link closes the menu, then opens its page', () {
      final events = <Object>[];
      final items = moduleMenuItems(
        moduleKey: 'clock',
        panelName: 'top',
        close: () => events.add('close'),
        openSettings: events.add,
        store: store,
      );
      _entry(items, 'Clock settings…').onTap();
      _entry(items, 'Panel settings…').onTap();
      expect(events, [
        'close',
        SettingsRoute.module('clock'),
        'close',
        SettingsRoute.panel('top'),
      ]);
    });

    test('a module with no page of its own still reaches its settings', () {
      final opened = <SettingsRoute>[];
      final items = moduleMenuItems(
        moduleKey: 'sound_control',
        panelName: 'top',
        close: () {},
        openSettings: opened.add,
        store: store,
      );
      expect(_labels(items), ['Sound settings…', 'Panel settings…']);
      _entry(items, 'Sound settings…').onTap();
      expect(opened.single.category, 'audio');
    });

    test('config rows are left out with no store, rather than throwing', () {
      final items = moduleMenuItems(
        moduleKey: 'clock',
        panelName: 'top',
        close: () {},
        openSettings: (_) {},
      );
      expect(_labels(items), ['Clock settings…', 'Panel settings…']);
    });

    // A menu takes no keyboard, so only a switch or a short choice can be one
    // of its rows — and each must write the page its menu belongs to.
    test('every quick row on a module page is its own module\'s key', () {
      for (final page in moduleSettingsPages) {
        for (final setting in page.quickSettings) {
          final path = switch (setting) {
            QuickToggle(:final path) => path,
            QuickChoice(:final path) => path,
            QuickAction() => fail('a page row is a config key'),
          };
          expect(path.take(2), ['modules', page.key], reason: setting.label);
        }
      }
    });

    test('every related settings page is a real one', () {
      for (final route in relatedModuleSettingsRoutes) {
        if (route.shellCategory case final title?) {
          expect(isShellCategory(title), isTrue, reason: title);
        }
        expect(
          const {
            'network',
            'bluetooth',
            'display',
            'audio',
            'keyboard',
            'power',
            'miracle',
            'default_apps',
            'accounts',
            'shell',
          },
          contains(route.category),
        );
      }
    });
  });

  group('a quick action', () {
    testWidgets('a switch redraws after its own tap', (tester) async {
      var on = false;
      final items = quickSettingItems(
        [
          QuickAction(
            label: 'Thing',
            checked: () => on,
            onTap: () => on = !on,
          ),
        ],
        store: null,
        close: () => fail('a switch keeps the menu open'),
      );
      await _pumpCard(tester, items);
      await tester.tap(find.text('Thing'));
      await tester.pump();
      expect(on, isTrue);
      expect(_entry(items, 'Thing').checked, isTrue);
    });

    test('an action closes the menu before it runs', () {
      final events = <String>[];
      final items = quickSettingItems(
        [QuickAction(label: 'Go', onTap: () => events.add('run'))],
        store: null,
        close: () => events.add('close'),
      );
      _entry(items, 'Go').onTap();
      expect(events, ['close', 'run']);
    });
  });

  group('a bar\'s blank space', () {
    test('offers its own panel\'s settings and Settings', () {
      final opened = <SettingsRoute>[];
      final items = panelMenuItems(
        panelName: 'bottom',
        close: () {},
        openSettings: opened.add,
      );
      expect(_labels(items), ['Panel settings…', 'Settings…']);
      _entry(items, 'Panel settings…').onTap();
      _entry(items, 'Settings…').onTap();
      expect(opened, [SettingsRoute.panel('bottom'), const SettingsRoute()]);
      expect(panelMenuTitle('bottom'), 'Bottom panel');
    });

    test('adds a module to the section that was right-clicked', () {
      final events = <String>[];
      final items = panelMenuItems(
        panelName: 'top',
        close: () => events.add('close'),
        openSettings: (_) {},
        slotLabel: 'Center',
        onAddModule: () => events.add('add'),
      );
      expect(_labels(items), [
        'Add module to center…',
        '—',
        'Panel settings…',
        'Settings…',
      ]);
      _entry(items, 'Add module to center…').onTap();
      expect(events, ['close', 'add']);
    });

    test('the module list picks one, or says there is none left', () {
      final picked = <String>[];
      final items = addModuleMenuItems(
        keys: const ['battery', 'clock'],
        close: () => picked.add('close'),
        onPick: picked.add,
      );
      expect(_labels(items), ['Battery', 'Clock']);
      _entry(items, 'Clock').onTap();
      expect(picked, ['close', 'clock']);

      final none = addModuleMenuItems(
        keys: const [],
        close: () {},
        onPick: (_) => fail('nothing to pick'),
      );
      expect((none.single as DesktopMenuEntry).enabled, isFalse);
    });

    testWidgets('a long module list scrolls inside the card', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ThemeScope(
            theme: const ThemeConfig(),
            child: Align(
              alignment: Alignment.topLeft,
              // What a bar popup is offered.
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 320,
                  maxHeight: 300,
                ),
                child: DesktopMenuCard(
                  header: 'Add module to left',
                  scrollable: true,
                  entries: [
                    for (var i = 0; i < 40; i++)
                      DesktopMenuEntry(label: 'Module $i', onTap: () {}),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final card = tester.getSize(find.byType(DesktopMenuCard));
      expect(card.height, lessThanOrEqualTo(300));
      expect(card.width, lessThan(320));
      await tester.drag(find.text('Module 2'), const Offset(0, -3000));
      await tester.pump();
      expect(find.text('Module 39').hitTestable(), findsOneWidget);
    });

    test('a panel route lands on Panels & Layout, and names the panel', () {
      final route = SettingsRoute.panel('top');
      expect(isShellCategory(route.shellCategory!), isTrue);
      expect(route.panel, 'top');
      expect(route, SettingsRoute.panel('top'));
      expect(route, isNot(SettingsRoute.panel('left')));
      expect(route.hashCode, SettingsRoute.panel('top').hashCode);
    });
  });

  group('desktop widgets', () {
    test('a configurable widget names its page', () {
      expect(weatherDesktopWidget.settings, SettingsRoute.module('weather'));
      expect(weatherDesktopWidget.offersPageQuickSettings, isTrue);
      expect(stocksDesktopWidget.settings, SettingsRoute.stocks);
      // The stock crawl's quick rows are about the bar, not the card.
      expect(stocksDesktopWidget.offersPageQuickSettings, isFalse);
      expect(newsDesktopWidget.settings, SettingsRoute.desktop);
    });

    test('the news card offers nothing to flip with no config', () {
      expect(newsOutletQuickSettings(), isEmpty);
    });
  });

  // The rule the whole file rests on: the deeper right-click wins, so a module
  // with a menu of its own keeps it, and the bar's menu answers only where no
  // module is.
  group('which right-click answers', () {
    late List<String> opened;

    Future<void> rightClick(WidgetTester tester, Offset at) async {
      final gesture = await tester.startGesture(
        at,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      // Held past the tap-down deadline, where two nested tap-down handlers
      // would both have fired: this region answers on the arena's tap-up.
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pump();
    }

    Future<void> pumpBar(WidgetTester tester) async {
      opened = [];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PanelMenuRegion(
            panelName: 'top',
            debugOnMenu: (_) => opened.add('panel'),
            child: Align(
              alignment: Alignment.topLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ModuleMenuRegion(
                    moduleKey: 'clock',
                    panelName: 'top',
                    debugOnMenu: () => opened.add('clock'),
                    // Padding around the glyph is not hit-testable on its
                    // own; the region still claims it.
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(width: 20, height: 20),
                    ),
                  ),
                  ModuleMenuRegion(
                    moduleKey: 'dock',
                    panelName: 'top',
                    debugOnMenu: () => opened.add('dock'),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onSecondaryTapDown: (_) => opened.add('unpin'),
                      child: const SizedBox(width: 40, height: 40),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a module answers anywhere in its box', (tester) async {
      await pumpBar(tester);
      await rightClick(tester, const Offset(2, 2));
      expect(opened, ['clock']);
    });

    testWidgets('a module\'s own right-click wins over its menu',
        (tester) async {
      await pumpBar(tester);
      await rightClick(tester, const Offset(60, 20));
      expect(opened, ['unpin']);
    });

    testWidgets('blank bar opens the bar\'s menu', (tester) async {
      await pumpBar(tester);
      await rightClick(tester, const Offset(400, 300));
      expect(opened, ['panel']);
    });
  });
}
