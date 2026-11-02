import 'dart:ffi' as ffi;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/app_info.dart';
import 'package:moonswing/modules/dock_launch.dart';
import 'package:moonswing/switcher/open_window.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_config.dart';

class _FakeWindows extends ChangeNotifier implements DockWindowSource {
  List<OpenWindow> list = const [];
  bool readable = true;
  int starts = 0;

  @override
  List<OpenWindow> get windows => list;

  @override
  bool get available => readable;

  @override
  void ensureStarted() => starts++;

  void open(String identifier, String appId) {
    list = [...list, OpenWindow(identifier: identifier, appId: appId, title: '')];
    notifyListeners();
  }

  // ignore: invalid_use_of_protected_member
  bool get listened => hasListeners;
}

AppEntry _entry(String id, {String wmClass = ''}) => AppEntry(
      id: id,
      name: id,
      iconName: id,
      categories: const [],
      appInfo: ffi.nullptr,
      startupWmClass: wmClass,
    );

OpenWindow _window(String appId) =>
    OpenWindow(identifier: 'x', appId: appId, title: '');

void main() {
  group('DockDoubleClick', () {
    test('two clicks inside the window open; one alone does not', () {
      var now = DateTime(2026);
      final clicks = DockDoubleClick(now: () => now);
      expect(clicks.click(), isFalse);
      now = now.add(const Duration(milliseconds: 200));
      expect(clicks.click(), isTrue);
    });

    test('a slow second click starts a new double click', () {
      var now = DateTime(2026);
      final clicks = DockDoubleClick(now: () => now);
      expect(clicks.click(), isFalse);
      now = now.add(const Duration(milliseconds: 400));
      expect(clicks.click(), isFalse);
      now = now.add(const Duration(milliseconds: 100));
      expect(clicks.click(), isTrue);
    });

    test('a triple click opens once', () {
      var now = DateTime(2026);
      final clicks = DockDoubleClick(now: () => now);
      final results = <bool>[];
      for (var i = 0; i < 3; i++) {
        results.add(clicks.click());
        now = now.add(const Duration(milliseconds: 50));
      }
      expect(results, [false, true, false]);
    });

    test('reset and a backwards clock both forget the first click', () {
      var now = DateTime(2026);
      final clicks = DockDoubleClick(now: () => now);
      clicks.click();
      clicks.reset();
      expect(clicks.click(), isFalse);
      now = now.subtract(const Duration(milliseconds: 50));
      expect(clicks.click(), isFalse);
    });
  });

  group('windowBelongsToApp', () {
    bool match(String appId, String desktopId, {String wmClass = ''}) =>
        windowBelongsToApp(
          _window(appId),
          desktopId: desktopId,
          startupWmClass: wmClass,
        );

    test('matches the spellings an app_id takes', () {
      expect(match('firefox', 'firefox'), isTrue);
      expect(match('org.gnome.Nautilus', 'org.gnome.Nautilus'), isTrue);
      expect(match('nautilus', 'org.gnome.Nautilus'), isTrue);
      expect(match('org.gnome.Nautilus', 'nautilus'), isTrue);
      expect(match('firefox', 'firefox_firefox'), isTrue);
      expect(match('Code', 'code'), isTrue);
      expect(match('jetbrains-idea', 'idea', wmClass: 'jetbrains-idea'),
          isTrue);
    });

    test('does not match another application or an empty app_id', () {
      expect(match('kitty', 'firefox'), isFalse);
      expect(match('', 'firefox'), isFalse);
      expect(match('org.gnome.Terminal', 'org.gnome.Nautilus'), isFalse);
    });
  });

  group('DockLaunchStore', () {
    late _FakeWindows windows;
    late DockLaunchStore store;
    late List<String> launched;

    // Widget tests for the fake clock alone: `tester.pump(duration)` is what
    // runs the store's one-shot timers.
    void storeTest(String description, Future<void> Function(WidgetTester) body) {
      testWidgets(description, (tester) async {
        windows = _FakeWindows();
        launched = [];
        store = DockLaunchStore.forTesting(
          windows: windows,
          launch: (entry) {
            launched.add(entry.id);
            return true;
          },
        );
        await body(tester);
        // Inside the body, so a timer left pending is the store's failure
        // rather than the harness's.
        store.dispose();
        windows.dispose();
      });
    }

    storeTest('a matching new window ends that launch only', (tester) async {
      expect(store.launch(_entry('firefox')), isTrue);
      expect(store.launch(_entry('kitty')), isTrue);
      expect(windows.starts, 2);
      expect(store.launchingOf('firefox').value, isTrue);
      expect(windows.listened, isTrue);

      windows.open('a', 'firefox');
      expect(store.launchingOf('firefox').value, isFalse);
      expect(store.launchingOf('kitty').value, isTrue);

      windows.open('b', 'kitty');
      expect(store.launchingOf('kitty').value, isFalse);
      expect(windows.listened, isFalse);
    });

    storeTest('an unrecognisable window answers the only launch waiting',
        (tester) async {
      store.launch(_entry('spotify'));
      windows.open('a', '');
      expect(store.isLaunching('spotify'), isFalse);
    });

    storeTest('an unrecognisable window answers neither of two launches',
        (tester) async {
      store.launch(_entry('spotify'));
      store.launch(_entry('steam'));
      windows.open('a', '');
      expect(store.isLaunching('spotify'), isTrue);
      expect(store.isLaunching('steam'), isTrue);
    });

    storeTest('a window open before the launch does not end it',
        (tester) async {
      windows.list = const [
        OpenWindow(identifier: 'old', appId: 'firefox', title: ''),
      ];
      store.launch(_entry('firefox'));
      windows.notifyListeners();
      expect(store.isLaunching('firefox'), isTrue);
      // Already running, so the shorter bound applies.
      await tester.pump(kDockRelaunchTimeout);
      expect(store.isLaunching('firefox'), isFalse);
    });

    storeTest('a launch nothing answers stops at the timeout', (tester) async {
      store.launch(_entry('firefox'));
      await tester.pump(kDockLaunchTimeout - const Duration(seconds: 1));
      expect(store.isLaunching('firefox'), isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(store.isLaunching('firefox'), isFalse);
      expect(store.launchingOf('firefox').value, isFalse);
      expect(windows.listened, isFalse);
    });

    storeTest('an unreadable window list spins only briefly', (tester) async {
      windows.readable = false;
      store.launch(_entry('firefox'));
      await tester.pump(kDockBlindLaunchTimeout);
      expect(store.isLaunching('firefox'), isFalse);
    });

    storeTest('a second launch while starting is declined', (tester) async {
      expect(store.launch(_entry('firefox')), isTrue);
      expect(store.launch(_entry('firefox')), isFalse);
      expect(launched, ['firefox']);
      windows.open('a', 'firefox');
      expect(store.launch(_entry('firefox')), isTrue);
      expect(launched, ['firefox', 'firefox']);
    });

    storeTest('a launch that never spawned does not spin', (tester) async {
      final failing = DockLaunchStore.forTesting(
        windows: windows,
        launch: (_) => false,
      );
      expect(failing.launch(_entry('firefox')), isFalse);
      expect(failing.launchingOf('firefox').value, isFalse);
      expect(windows.listened, isFalse);
      failing.dispose();
    });
  });

  group('DockLaunchIndicator', () {
    Widget host(ValueListenable<bool> launching, Widget icon) => ThemeScope(
          theme: const ThemeConfig(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: ValueListenableBuilder<bool>(
                valueListenable: launching,
                child: icon,
                builder: (context, value, child) =>
                    DockLaunchIndicator(launching: value, child: child!),
              ),
            ),
          ),
        );

    testWidgets('spins only while launching and keeps the icon mounted',
        (tester) async {
      final launching = ValueNotifier<bool>(false);
      addTearDown(launching.dispose);
      const iconKey = GlobalObjectKey('icon');
      await tester.pumpWidget(
        host(launching, const SizedBox(key: iconKey, width: 24, height: 24)),
      );
      final before = tester.element(find.byKey(iconKey));
      expect(find.byType(DockLaunchSpinner), findsNothing);
      expect(SchedulerBinding.instance.transientCallbackCount, 0);

      launching.value = true;
      await tester.pump();
      expect(find.byType(DockLaunchSpinner), findsOneWidget);
      expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));
      expect(tester.element(find.byKey(iconKey)), same(before));
      // The ring sits just outside the icon.
      expect(
        tester.getSize(find.byType(DockLaunchSpinner)),
        const Size(24 + 2 * DockLaunchIndicator.ringOutset,
            24 + 2 * DockLaunchIndicator.ringOutset),
      );

      launching.value = false;
      await tester.pump();
      expect(find.byType(DockLaunchSpinner), findsNothing);
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
      expect(tester.element(find.byKey(iconKey)), same(before));
    });
  });
}
