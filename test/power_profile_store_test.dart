// PowerProfileStore over fakes: leases, a mode derived from the daemon rather
// than set optimistically, failures that stay visible, and fine-tuning edits
// held until one batched apply.

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/power_profile/power_profile_store.dart';
import 'package:moonswing/power_profile/power_profiles_client.dart';
import 'package:moonswing/power_profile/power_tuning.dart';
import 'package:moonswing/power_profile/tuned_client.dart';

import 'power_profile_fakes.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('a lease reads all three sources', () async {
    final store = fakePowerStore();
    store.acquire();
    expect(store.status, PowerProfilesStatus.loading);
    await _settle();
    expect(store.status, PowerProfilesStatus.ready);
    expect(store.state!.active, 'balanced');
    expect(store.tuned, isNull);
    expect(store.tuning!.governor!.value, 'powersave');
    store.release();
    expect(store.leaseCount, 0);
  });

  test('acquire notifies nothing synchronously', () {
    final store = fakePowerStore();
    var notified = 0;
    store.addListener(() => notified++);
    store.acquire();
    expect(notified, 0);
    store.release();
  });

  test('the mode follows what the daemon reports back', () async {
    final profiles = FakePowerProfilesClient()..ignoreWrites = true;
    final store = fakePowerStore(profiles: profiles);
    store.acquire();
    await _settle();
    await store.setProfile('performance');
    expect(profiles.setProfiles, ['performance']);
    // The daemon kept balanced (a hold, say), so the pane does too.
    expect(store.state!.active, 'balanced');
    expect(store.pendingProfile, isNull);
    store.release();
  });

  test('a refused write stays on screen through the read-back', () async {
    final profiles = FakePowerProfilesClient()
      ..writeFailure = const PowerProfilesFailure(
        PowerProfilesFailureKind.denied,
        'nope',
      );
    final store = fakePowerStore(profiles: profiles);
    store.acquire();
    await _settle();
    await store.setProfile('power-saver');
    expect(store.error, 'nope');
    expect(store.errorKind, PowerProfilesFailureKind.denied);
    // And a later success clears it.
    profiles.writeFailure = null;
    await store.setProfile('power-saver');
    expect(store.error, isEmpty);
    expect(store.state!.active, 'power-saver');
    store.release();
  });

  test('no daemon is unavailable, and Retry recovers', () async {
    final profiles = FakePowerProfilesClient()
      ..readFailure = mapPowerProfilesError(
        'org.freedesktop.DBus.Error.ServiceUnknown',
        '',
      );
    final store = fakePowerStore(profiles: profiles);
    store.acquire();
    await _settle();
    expect(store.status, PowerProfilesStatus.unavailable);
    expect(store.error, isNotEmpty);
    // Fine tuning does not need the daemon.
    expect(store.tuning, isNotNull);
    profiles.readFailure = null;
    await store.retry();
    expect(store.status, PowerProfilesStatus.ready);
    expect(store.error, isEmpty);
    store.release();
  });

  test('a change made elsewhere moves the store', () async {
    final profiles = FakePowerProfilesClient();
    final store = fakePowerStore(profiles: profiles);
    store.acquire();
    await _settle();
    profiles.emit(profiles.state.copyWith(active: 'performance'));
    await _settle();
    expect(store.state!.active, 'performance');
    store.release();
  });

  test('TuneD switches and hands the choice back', () async {
    final tuned = FakeTunedClient(
      state: const TunedState(
        active: 'balanced',
        profiles: [TunedProfile('balanced'), TunedProfile('powersave')],
        recommended: 'balanced',
      ),
    );
    final store = fakePowerStore(tuned: tuned);
    store.acquire();
    await _settle();
    expect(store.tuned!.active, 'balanced');
    await store.switchTuned('powersave');
    expect(store.tuned!.active, 'powersave');
    expect(store.tuned!.automatic, isFalse);
    await store.useTunedRecommended();
    expect(tuned.recommendedCalls, 1);
    expect(store.tuned!.automatic, isTrue);
    store.release();
  });

  group('fine tuning', () {
    test('edits wait for one batched apply', () async {
      final fs = FakeSysfs(intelLaptopSysfs());
      final writer = FakeSysfsWriter(fs);
      final store = fakePowerStore(sysfs: fs, writer: writer);
      store.acquire();
      await _settle();

      store.setGovernor('performance');
      store.setBoost(false);
      store.setPlatformProfile('quiet');
      expect(store.edits.count, 3);
      expect(writer.batches, isEmpty);

      await store.applyTuning();
      expect(writer.batches, hasLength(1));
      expect(store.edits.isEmpty, isTrue);
      expect(store.tuning!.governor!.value, 'performance');
      expect(store.tuning!.boost!.enabled, isFalse);
      expect(store.tuning!.platformProfile!.value, 'quiet');
      store.release();
    });

    test('an edit back to the machine\'s value cancels itself', () async {
      final store = fakePowerStore();
      store.acquire();
      await _settle();
      store.setGovernor('performance');
      expect(store.edits.count, 1);
      store.setGovernor('powersave');
      expect(store.edits.isEmpty, isTrue);
      store.release();
    });

    test('a cancelled prompt keeps the edits and says so', () async {
      final fs = FakeSysfs(intelLaptopSysfs());
      final writer = FakeSysfsWriter(fs)
        ..failure = const SysfsWriteFailure(
          SysfsWriteFailureKind.dismissed,
          'cancelled',
        );
      final store = fakePowerStore(sysfs: fs, writer: writer);
      store.acquire();
      await _settle();
      store.setEnergyPreference('power');
      await store.applyTuning();
      expect(store.tuningError!.kind, SysfsWriteFailureKind.dismissed);
      expect(store.edits.energyPreference, 'power');
      store.discardTuning();
      expect(store.edits.isEmpty, isTrue);
      expect(store.tuningError, isNull);
      store.release();
    });

    test('a mode change re-reads the knobs it rewrites', () async {
      final fs = FakeSysfs(intelLaptopSysfs());
      final profiles = FakePowerProfilesClient();
      final store = fakePowerStore(profiles: profiles, sysfs: fs);
      store.acquire();
      await _settle();
      fs.files[kPlatformProfilePath] = 'low-power';
      profiles.emit(profiles.state.copyWith(active: 'power-saver'));
      await _settle();
      await _settle();
      expect(store.tuning!.platformProfile!.value, 'low-power');
      store.release();
    });
  });
}
