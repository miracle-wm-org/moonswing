// Fakes for the Power pane: a profile daemon, TuneD, a sysfs tree and the
// privileged writer, none of which touches the machine running the tests.

import 'dart:async';

import 'package:moonswing/power_profile/power_profile_store.dart';
import 'package:moonswing/power_profile/power_profiles_client.dart';
import 'package:moonswing/power_profile/power_tuning.dart';
import 'package:moonswing/power_profile/tuned_client.dart';

const kThreeProfiles = [
  PowerProfileInfo(profile: 'power-saver', driver: 'intel_pstate'),
  PowerProfileInfo(profile: 'balanced', driver: 'intel_pstate'),
  PowerProfileInfo(profile: 'performance', driver: 'intel_pstate'),
];

class FakePowerProfilesClient implements PowerProfilesClient {
  FakePowerProfilesClient({
    PowerProfilesState state = const PowerProfilesState(
      active: 'balanced',
      profiles: kThreeProfiles,
    ),
  }) : _state = state;

  PowerProfilesState _state;
  PowerProfilesFailure? readFailure;
  PowerProfilesFailure? writeFailure;

  /// When true, a write is accepted but the daemon keeps its profile — what
  /// a hold or a refusal without an error looks like from outside.
  bool ignoreWrites = false;

  final List<String> setProfiles = [];
  final List<bool> setBatteryAwareCalls = [];
  final StreamController<PowerProfilesState> _changes =
      StreamController.broadcast();

  PowerProfilesState get state => _state;

  /// Something outside the shell moved the daemon.
  void emit(PowerProfilesState next) {
    _state = next;
    _changes.add(next);
  }

  @override
  Future<PowerProfilesState> read() async {
    final failure = readFailure;
    if (failure != null) throw failure;
    return _state;
  }

  @override
  Stream<PowerProfilesState> get changes => _changes.stream;

  @override
  Future<void> setActiveProfile(String profile) async {
    setProfiles.add(profile);
    final failure = writeFailure;
    if (failure != null) throw failure;
    if (!ignoreWrites) _state = _state.copyWith(active: profile);
  }

  @override
  Future<void> setBatteryAware(bool enabled) async {
    setBatteryAwareCalls.add(enabled);
    final failure = writeFailure;
    if (failure != null) throw failure;
    _state = _state.copyWith(batteryAware: enabled);
  }
}

class FakeTunedClient implements TunedClient {
  FakeTunedClient({this.state});

  /// Null is a machine without TuneD.
  TunedState? state;
  TunedFailure? writeFailure;
  final List<String> switched = [];
  int recommendedCalls = 0;
  final StreamController<void> _changes = StreamController.broadcast();

  @override
  Future<TunedState> read() async {
    final current = state;
    if (current == null) {
      throw const TunedFailure(
        TunedFailureKind.unavailable,
        'TuneD is not running.',
      );
    }
    return current;
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> switchProfile(String name) async {
    switched.add(name);
    final failure = writeFailure;
    if (failure != null) throw failure;
    final current = state!;
    state = TunedState(
      active: name,
      profiles: current.profiles,
      recommended: current.recommended,
    );
  }

  @override
  Future<void> useRecommended() async {
    recommendedCalls++;
    final current = state!;
    state = TunedState(
      active: current.recommended,
      profiles: current.profiles,
      automatic: true,
      recommended: current.recommended,
    );
  }
}

/// A sysfs tree as a map of path to contents.
class FakeSysfs implements SysfsReader {
  FakeSysfs(this.files);

  final Map<String, String> files;

  @override
  Future<String?> read(String path) async => files[path]?.trim();

  @override
  Future<List<String>> list(String dir) async {
    final prefix = '$dir/';
    return {
      for (final path in files.keys)
        if (path.startsWith(prefix))
          path.substring(prefix.length).split('/')[0],
    }.toList();
  }
}

/// A laptop with intel_pstate: two policies, a platform profile, EPP, turbo.
Map<String, String> intelLaptopSysfs() => {
  kPlatformProfilePath: 'balanced',
  kPlatformProfileChoicesPath: 'low-power quiet balanced performance',
  kIntelNoTurboPath: '0',
  for (final n in [0, 1]) ...{
    '$kCpufreqDir/policy$n/scaling_driver': 'intel_pstate',
    '$kCpufreqDir/policy$n/scaling_governor': 'powersave',
    '$kCpufreqDir/policy$n/scaling_available_governors':
        'performance powersave',
    '$kCpufreqDir/policy$n/energy_performance_preference':
        'balance_performance',
    '$kCpufreqDir/policy$n/energy_performance_available_preferences':
        'default performance balance_performance balance_power power',
    '$kCpufreqDir/policy$n/cpuinfo_min_freq': '400000',
    '$kCpufreqDir/policy$n/cpuinfo_max_freq': '4000000',
    '$kCpufreqDir/policy$n/scaling_max_freq': '4000000',
  },
};

/// Writes into the [FakeSysfs] it is given, as root would.
class FakeSysfsWriter implements PrivilegedSysfsWriter {
  FakeSysfsWriter(this.fs);

  final FakeSysfs fs;
  final List<List<SysfsWrite>> batches = [];
  SysfsWriteFailure? failure;

  @override
  Future<void> write(List<SysfsWrite> writes) async {
    batches.add(writes);
    final failure = this.failure;
    if (failure != null) throw failure;
    for (final write in writes) {
      fs.files[write.path] = write.value;
    }
  }
}

PowerProfileStore fakePowerStore({
  FakePowerProfilesClient? profiles,
  FakeTunedClient? tuned,
  FakeSysfs? sysfs,
  FakeSysfsWriter? writer,
}) {
  final fs = sysfs ?? FakeSysfs(intelLaptopSysfs());
  return PowerProfileStore.forTesting(
    profiles: profiles ?? FakePowerProfilesClient(),
    tuned: tuned ?? FakeTunedClient(),
    sysfs: fs,
    writer: writer ?? FakeSysfsWriter(fs),
  );
}
