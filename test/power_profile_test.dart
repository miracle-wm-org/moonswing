// The Power pane's Flutter-free layer: reading power-profiles-daemon and
// TuneD replies, reading the sysfs knobs, planning a batch of root writes and
// running it through pkexec.

import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/overlay/settings/power.dart';
import 'package:moonswing/power_profile/power_profiles_client.dart';
import 'package:moonswing/power_profile/power_tuning.dart';
import 'package:moonswing/power_profile/tuned_client.dart';

import 'power_profile_fakes.dart';

DBusDict _dict(Map<String, DBusValue> entries) =>
    DBusDict.stringVariant(entries);

void main() {
  group('parsePowerProfilesProperties', () {
    test('reads every property', () {
      final state = parsePowerProfilesProperties({
        'ActiveProfile': const DBusString('performance'),
        'PerformanceDegraded': const DBusString('lap-detected'),
        'Profiles': DBusArray(DBusSignature('a{sv}'), [
          _dict({
            'Profile': const DBusString('power-saver'),
            'Driver': const DBusString('multiple'),
            'PlatformDriver': const DBusString('platform_profile'),
            'CpuDriver': const DBusString('amd_pstate'),
          }),
          _dict({
            'Profile': const DBusString('balanced'),
            'Driver': const DBusString('multiple'),
          }),
        ]),
        'ActiveProfileHolds': DBusArray(DBusSignature('a{sv}'), [
          _dict({
            'ApplicationId': const DBusString('org.gnome.Games'),
            'Profile': const DBusString('performance'),
            'Reason': const DBusString('Playing'),
          }),
        ]),
        'Actions': DBusArray.string(['trickle_charge']),
        'BatteryAware': const DBusBoolean(true),
        'Version': const DBusString('0.30'),
      });
      expect(state.active, 'performance');
      expect(state.degraded, 'lap-detected');
      expect(state.profiles.map((p) => p.profile), ['power-saver', 'balanced']);
      expect(
        state.profiles.first.driverSummary,
        'amd_pstate · platform_profile',
      );
      expect(state.holds.single.applicationId, 'org.gnome.Games');
      expect(state.actions, ['trickle_charge']);
      expect(state.batteryAware, isTrue);
      expect(state.version, '0.30');
    });

    test('a wrongly typed property costs that property, not the read', () {
      final state = parsePowerProfilesProperties({
        'ActiveProfile': const DBusString('balanced'),
        'Profiles': const DBusString('nonsense'),
        'Actions': const DBusUint32(3),
        'BatteryAware': const DBusString('yes'),
      });
      expect(state.active, 'balanced');
      expect(state.profiles, isEmpty);
      expect(state.actions, isEmpty);
      // An older daemon, or tuned-ppd, has no BatteryAware: no row.
      expect(state.batteryAware, isNull);
    });

    test('a profile with no name is dropped', () {
      final state = parsePowerProfilesProperties({
        'ActiveProfile': const DBusString('balanced'),
        'Profiles': DBusArray(DBusSignature('a{sv}'), [
          _dict({'Driver': const DBusString('placeholder')}),
          _dict({
            'Profile': const DBusString('balanced'),
            'Driver': const DBusString('placeholder'),
          }),
        ]),
      });
      expect(state.profiles.single.profile, 'balanced');
      expect(state.profiles.single.isPlaceholder, isTrue);
    });
  });

  test('labels and reasons fall back for values the shell does not know', () {
    expect(powerProfileLabel('power-saver'), 'Power Saver');
    expect(powerProfileLabel('extra-quiet'), 'Extra quiet');
    expect(powerDegradedReason(''), isEmpty);
    expect(powerDegradedReason('lap-detected'), contains('lap'));
    expect(powerDegradedReason('aliens'), contains('aliens'));
    expect(humanizeIdentifier('balance_performance'), 'Balance performance');
  });

  test('D-Bus errors map to something the pane can word', () {
    expect(
      mapPowerProfilesError(
        'org.freedesktop.DBus.Error.ServiceUnknown',
        '',
      ).kind,
      PowerProfilesFailureKind.unavailable,
    );
    expect(
      mapPowerProfilesError('org.freedesktop.DBus.Error.AccessDenied', '').kind,
      PowerProfilesFailureKind.denied,
    );
    final other = mapPowerProfilesError('com.example.Weird', 'it broke');
    expect(other.kind, PowerProfilesFailureKind.failed);
    expect(other.message, 'it broke');
  });

  test('TuneD profile lists drop malformed rows', () {
    final profiles = parseTunedProfiles2(
      DBusArray(DBusSignature('(ss)'), [
        DBusStruct([
          const DBusString('balanced'),
          const DBusString('General non-specialized'),
        ]),
        DBusStruct([const DBusString(''), const DBusString('no name')]),
      ]),
    );
    expect(profiles, [
      const TunedProfile('balanced', 'General non-specialized'),
    ]);
    expect(parseTunedProfiles(DBusArray.string(['powersave', ''])), [
      const TunedProfile('powersave'),
    ]);
  });

  group('readPowerTuning', () {
    test('reads an intel_pstate laptop', () async {
      final tuning = await readPowerTuning(FakeSysfs(intelLaptopSysfs()));
      expect(tuning.cpuDriver, 'intel_pstate');
      expect(tuning.policyCount, 2);
      expect(tuning.platformProfile!.value, 'balanced');
      expect(tuning.platformProfile!.choices, contains('quiet'));
      expect(tuning.governor!.value, 'powersave');
      expect(tuning.governor!.paths, hasLength(2));
      expect(tuning.energyPreference!.value, 'balance_performance');
      expect(tuning.boost!.enabled, isTrue);
      expect(tuning.boost!.inverted, isTrue);
      expect(tuning.maxFrequency!.percent, 100);
      expect(tuning.maxFrequency!.minPercent, 10);
    });

    test('policies that disagree read as mixed', () async {
      final files = intelLaptopSysfs()
        ..['$kCpufreqDir/policy1/scaling_governor'] = 'performance'
        ..['$kCpufreqDir/policy1/scaling_max_freq'] = '2000000';
      final tuning = await readPowerTuning(FakeSysfs(files));
      expect(tuning.governor!.mixed, isTrue);
      expect(tuning.maxFrequency!.percent, isNull);
    });

    test('choices are the ones every policy accepts', () async {
      final files = intelLaptopSysfs()
        ..['$kCpufreqDir/policy1/scaling_available_governors'] = 'powersave';
      final tuning = await readPowerTuning(FakeSysfs(files));
      expect(tuning.governor!.choices, ['powersave']);
    });

    test('a machine with nothing to tune reads empty', () async {
      final tuning = await readPowerTuning(FakeSysfs({}));
      expect(tuning.isEmpty, isTrue);
    });

    test('per-policy boost, as newer amd-pstate spells it', () async {
      final files = intelLaptopSysfs()
        ..remove(kIntelNoTurboPath)
        ..['$kCpufreqDir/policy0/boost'] = '1'
        ..['$kCpufreqDir/policy1/boost'] = '0';
      final boost = (await readPowerTuning(FakeSysfs(files))).boost!;
      expect(boost.inverted, isFalse);
      expect(boost.enabled, isNull);
      expect(boost.paths, hasLength(2));
    });
  });

  group('planPowerTuning', () {
    test('writes the governor before the energy preference', () async {
      final tuning = await readPowerTuning(FakeSysfs(intelLaptopSysfs()));
      final plan = planPowerTuning(
        tuning,
        const PowerTuningEdits(
          energyPreference: 'power',
          governor: 'performance',
          boost: false,
          maxFrequencyPercent: 50,
        ),
      );
      expect(plan.map((w) => w.toString()), [
        '$kCpufreqDir/policy0/scaling_governor=performance',
        '$kCpufreqDir/policy1/scaling_governor=performance',
        '$kCpufreqDir/policy0/energy_performance_preference=power',
        '$kCpufreqDir/policy1/energy_performance_preference=power',
        // no_turbo is inverted: boost off is a 1.
        '$kIntelNoTurboPath=1',
        '$kCpufreqDir/policy0/scaling_max_freq=2000000',
        '$kCpufreqDir/policy1/scaling_max_freq=2000000',
      ]);
      expect(plan.every(isWritableSysfsWrite), isTrue);
    });

    test('drops a value the knob does not offer', () async {
      final tuning = await readPowerTuning(FakeSysfs(intelLaptopSysfs()));
      expect(
        planPowerTuning(
          tuning,
          const PowerTuningEdits(platformProfile: 'turbo-mode'),
        ),
        isEmpty,
      );
    });

    test('an edit back to the current value is no edit', () async {
      final tuning = await readPowerTuning(FakeSysfs(intelLaptopSysfs()));
      final edits = const PowerTuningEdits(
        governor: 'powersave',
        boost: true,
        maxFrequencyPercent: 100,
        platformProfile: 'quiet',
      ).against(tuning);
      expect(edits.count, 1);
      expect(edits.platformProfile, 'quiet');
    });
  });

  test('only the known files and plain values are writable', () {
    expect(
      isWritableSysfsWrite(
        const SysfsWrite('/sys/firmware/acpi/platform_profile', 'quiet'),
      ),
      isTrue,
    );
    expect(isWritableSysfsWrite(const SysfsWrite('/etc/passwd', 'x')), isFalse);
    expect(
      isWritableSysfsWrite(
        const SysfsWrite(
          '/sys/devices/system/cpu/cpufreq/policy0/scaling_governor',
          'powersave; reboot',
        ),
      ),
      isFalse,
    );
  });

  group('PkexecSysfsWriter', () {
    const writes = [
      SysfsWrite(kPlatformProfilePath, 'quiet'),
      SysfsWrite(kIntelNoTurboPath, '1'),
    ];

    test('runs one pkexec with the pairs as arguments', () async {
      final calls = <List<String>>[];
      final writer = PkexecSysfsWriter(
        runner: (exe, args) async {
          calls.add([exe, ...args]);
          return ProcessResult(1, 0, '', '');
        },
      );
      await writer.write(writes);
      expect(calls, hasLength(1));
      final call = calls.single;
      expect(call.take(3), ['pkexec', '/bin/sh', '-c']);
      expect(call[3], kSysfsWriteScript);
      expect(call.skip(5), [
        kPlatformProfilePath,
        'quiet',
        kIntelNoTurboPath,
        '1',
      ]);
    });

    Future<SysfsWriteFailure> failureFor(int code, [String stderr = '']) async {
      final writer = PkexecSysfsWriter(
        runner: (_, _) async => ProcessResult(1, code, '', stderr),
      );
      try {
        await writer.write(writes);
      } on SysfsWriteFailure catch (e) {
        return e;
      }
      fail('expected a failure');
    }

    test('maps pkexec and script exit codes', () async {
      expect((await failureFor(126)).kind, SysfsWriteFailureKind.dismissed);
      expect((await failureFor(127)).kind, SysfsWriteFailureKind.unavailable);
      final refused = await failureFor(3, 'refused: $kIntelNoTurboPath\n');
      expect(refused.kind, SysfsWriteFailureKind.rejected);
      expect(refused.paths, [kIntelNoTurboPath]);
    });

    test('refuses an unlisted path without running anything', () async {
      var ran = false;
      final writer = PkexecSysfsWriter(
        runner: (_, _) async {
          ran = true;
          return ProcessResult(1, 0, '', '');
        },
      );
      await expectLater(
        writer.write(const [SysfsWrite('/etc/shadow', 'x')]),
        throwsA(isA<SysfsWriteFailure>()),
      );
      expect(ran, isFalse);
    });

    test('a missing pkexec names the package', () async {
      final writer = PkexecSysfsWriter(
        runner: (_, _) async => throw const ProcessException('pkexec', []),
      );
      try {
        await writer.write(writes);
        fail('expected a failure');
      } on SysfsWriteFailure catch (e) {
        expect(e.kind, SysfsWriteFailureKind.unavailable);
        expect(e.message, contains('polkit'));
      }
    });
  });

  test('frequency steps and labels', () async {
    final knob = (await readPowerTuning(
      FakeSysfs(intelLaptopSysfs()),
    )).maxFrequency!;
    final steps = frequencySteps(knob);
    expect(steps.first, 100);
    expect(steps.last, 10);
    expect(formatFrequency(4000), '4.0 GHz');
    expect(formatFrequency(800), '800 MHz');
  });
}
