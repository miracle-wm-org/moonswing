// The overview's seam: the bar buttons that open it, and the controller that
// tells the root which tab they meant. The overview itself needs the whole
// shell's stores to pump; what is pinned here is what decides where a click
// lands.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/modules/clock.dart';
import 'package:moonswing/overlay/overlay.dart';
import 'package:moonswing/overlay/settings_route.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/timers/timer_store.dart';

void main() {
  group('SettingsController', () {
    test('a toggle carries its tab and output, and no route', () {
      final controller = SettingsController.forTesting();
      addTearDown(controller.dispose);
      var signals = 0;
      controller.addListener(() => signals++);

      controller.toggle(OverviewTab.todo, output: 'DP-1');
      expect(signals, 1);
      expect(controller.pendingToggle, OverviewTab.todo);
      expect(controller.output, 'DP-1');
      expect(controller.pending, isNull);

      controller.consume();
      expect(controller.pendingToggle, isNull);
    });

    test('a route supersedes a toggle, and forgets its output', () {
      final controller = SettingsController.forTesting();
      addTearDown(controller.dispose);
      controller.toggle(OverviewTab.shortcuts, output: 'HDMI-A-1');
      controller.open(SettingsRoute.accounts);
      expect(controller.pending, SettingsRoute.accounts);
      expect(controller.pendingToggle, isNull);
      expect(controller.output, isNull);
    });

    test('a tab route leaves the settings sidebar where it would start', () {
      const route = SettingsRoute.tab(OverviewTab.todo);
      expect(route.tab, OverviewTab.todo);
      expect(route.category, 'network');
      expect(route.shellCategory, isNull);
    });
  });

  test('every tab a bar button names is one the overview draws', () {
    for (final tab in [
      OverviewTab.calendar,
      OverviewTab.system,
      OverviewTab.systemInfo,
      OverviewTab.settings,
      OverviewTab.todo,
      OverviewTab.shortcuts,
    ]) {
      expect(isOverviewTab(tab), isTrue, reason: tab);
    }
    expect(isOverviewTab('board'), isFalse);
  });

  testWidgets('the clock asks for the calendar tab, opening no window', (
    tester,
  ) async {
    final controller = SettingsController.forTesting();
    addTearDown(controller.dispose);
    final timers = TimersStore.forTesting();
    addTearDown(timers.dispose);
    var signals = 0;
    controller.addListener(() => signals++);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Center(
            child: Clock(
              config: const ClockConfig(),
              timers: timers,
              overview: controller,
            ),
          ),
        ),
      ),
    );

    // A corner, for `test/tap_target_test.dart`'s reason.
    final box = tester.getRect(find.byType(Clock));
    await tester.tapAt(box.topLeft + const Offset(2, 2));
    await tester.pump();

    expect(signals, 1);
    expect(controller.pendingToggle, OverviewTab.calendar);
    // No DisplayScope above it: the root falls back to the focused output.
    expect(controller.output, isNull);
  });
}
