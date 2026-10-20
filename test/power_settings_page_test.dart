// Settings › Power over fakes: the modes render and switch, a missing daemon
// is a banner that leaves Fine Tuning usable, and tuning edits are one batch.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/power.dart';
import 'package:moonswing/power_profile/power_profile_store.dart';
import 'package:moonswing/power_profile/power_profiles_client.dart';
import 'package:moonswing/power_profile/tuned_client.dart';
import 'package:moonswing/scopes.dart';

import 'power_profile_fakes.dart';

void main() {
  Future<void> pump(WidgetTester tester, PowerProfileStore store) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Overlay(
            key: ObjectKey(store),
            initialEntries: [
              OverlayEntry(
                builder: (_) => SizedBox(
                  width: 760,
                  height: 1400,
                  child: PowerSettingsPage(store: store),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the modes and switches on a tap', (tester) async {
    final profiles = FakePowerProfilesClient();
    final store = fakePowerStore(profiles: profiles);
    await pump(tester, store);

    Finder mode(String label) => find.descendant(
      of: find.byType(SettingsOptionButton),
      matching: find.text(label),
    );
    expect(mode('Power Saver'), findsOneWidget);
    expect(mode('Balanced'), findsOneWidget);
    expect(mode('Performance'), findsOneWidget);
    // No TuneD on this machine: no TuneD section.
    expect(find.text('TUNED'), findsNothing);

    await tester.tap(mode('Performance'));
    await tester.pumpAndSettle();
    expect(profiles.setProfiles, ['performance']);
    expect(store.state!.active, 'performance');
  });

  testWidgets('holds and battery awareness render when the daemon has them', (
    tester,
  ) async {
    final profiles = FakePowerProfilesClient(
      state: const PowerProfilesState(
        active: 'performance',
        profiles: kThreeProfiles,
        batteryAware: false,
        holds: [
          PowerProfileHold(
            applicationId: 'org.example.Game',
            profile: 'performance',
            reason: 'Playing',
          ),
        ],
      ),
    );
    final store = fakePowerStore(profiles: profiles);
    await pump(tester, store);
    expect(
      find.text('org.example.Game wants Performance — Playing'),
      findsOneWidget,
    );
    expect(find.text('Adapt on battery'), findsOneWidget);
    await tester.tap(find.byType(SettingsToggle).first);
    await tester.pumpAndSettle();
    expect(profiles.setBatteryAwareCalls, [true]);
  });

  testWidgets('no daemon is a banner, and Fine Tuning still renders', (
    tester,
  ) async {
    final profiles = FakePowerProfilesClient()
      ..readFailure = mapPowerProfilesError(
        'org.freedesktop.DBus.Error.ServiceUnknown',
        '',
      );
    await pump(tester, fakePowerStore(profiles: profiles));
    expect(find.text('Power modes unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('CPU governor'), findsOneWidget);
    expect(find.text('Turbo boost'), findsOneWidget);
  });

  testWidgets('a tuning edit waits for Apply, which writes one batch', (
    tester,
  ) async {
    final fs = FakeSysfs(intelLaptopSysfs());
    final writer = FakeSysfsWriter(fs);
    final store = fakePowerStore(sysfs: fs, writer: writer);
    await pump(tester, store);

    expect(find.text('Apply'), findsNothing);
    // The turbo toggle is the last toggle on a page whose daemon has no
    // battery-aware row.
    await tester.tap(find.byType(SettingsToggle).last);
    await tester.pumpAndSettle();
    expect(find.text('Changed'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
    expect(writer.batches, isEmpty);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(writer.batches, hasLength(1));
    expect(store.tuning!.boost!.enabled, isFalse);
    expect(find.text('Changed'), findsNothing);
  });

  testWidgets('TuneD gets a section where it runs', (tester) async {
    final tuned = FakeTunedClient(
      state: const TunedState(
        active: 'balanced',
        profiles: [
          TunedProfile('balanced', 'General non-specialized'),
          TunedProfile('latency-performance', 'Optimize for low latency'),
        ],
        recommended: 'balanced',
      ),
    );
    await pump(tester, fakePowerStore(tuned: tuned));
    // Section labels are drawn upper-case.
    expect(find.text('TUNED'), findsOneWidget);
    expect(find.text('Let TuneD choose (balanced)'), findsOneWidget);
  });
}
