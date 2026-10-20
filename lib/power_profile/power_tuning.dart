// The kernel's own power knobs, below whatever profile daemon is running.
//
// The fine-grained half of Settings › Power. Each is a sysfs file that any user
// can read and only root can write:
//
// * the ACPI **platform profile** — the firmware's fan and power-limit curve,
//   with as many choices as the vendor wrote (`low-power`, `cool`, `quiet`,
//   `balanced`, `balanced-performance`, `performance`, `custom`…);
// * the CPU frequency **governor**, per cpufreq policy;
// * the **energy/performance preference** (EPP) a hardware-managed P-state
//   driver — intel_pstate, amd-pstate — hands the CPU, per policy;
// * **turbo boost**, intel_pstate's `no_turbo` (inverted) or cpufreq's
//   `boost`, global or per policy;
// * a **frequency cap**, `scaling_max_freq` per policy, offered as a
//   percentage so one number means the same thing on a hybrid CPU's two core
//   types.
//
// The pane writes all of them uniformly across policies — a per-core table is
// what `cpupower` is for — and shows a knob whose policies disagree as mixed
// rather than picking one to report.
//
// Writes go through `pkexec`, so the shell's own polkit agent asks for the
// administrator's password, and are batched: every edit the user has made is
// one invocation and one prompt (see [PkexecSysfsWriter]). Nothing persists
// across a reboot, and a profile daemon rewrites the platform profile and the
// EPP whenever its mode changes — both of which the pane says.
//
// Flutter-free: the filesystem is injected, so the parse and the write plan are
// unit tests.

import 'dart:io';

import 'package:moonswing/host_process.dart';

const String kPlatformProfilePath = '/sys/firmware/acpi/platform_profile';
const String kPlatformProfileChoicesPath =
    '/sys/firmware/acpi/platform_profile_choices';
const String kCpufreqDir = '/sys/devices/system/cpu/cpufreq';
const String kIntelNoTurboPath =
    '/sys/devices/system/cpu/intel_pstate/no_turbo';
const String kCpufreqBoostPath = '/sys/devices/system/cpu/cpufreq/boost';

/// The one way the store reaches the filesystem.
abstract class SysfsReader {
  /// The file's contents trimmed, or null when it is missing or unreadable.
  Future<String?> read(String path);

  /// The names of the entries directly under [dir], or empty.
  Future<List<String>> list(String dir);
}

class IoSysfsReader implements SysfsReader {
  const IoSysfsReader();

  @override
  Future<String?> read(String path) async {
    try {
      return (await File(path).readAsString()).trim();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<String>> list(String dir) async {
    try {
      return [
        await for (final entity in Directory(dir).list())
          entity.path.substring(entity.path.lastIndexOf('/') + 1),
      ];
    } catch (_) {
      return const [];
    }
  }
}

/// A knob with a fixed set of values, written to one or more files.
class ChoiceKnob {
  const ChoiceKnob({
    required this.value,
    required this.choices,
    required this.paths,
  });

  /// The value every file holds, or null when they disagree.
  final String? value;

  /// The values every file accepts.
  final List<String> choices;

  final List<String> paths;

  bool get mixed => value == null;

  @override
  bool operator ==(Object other) =>
      other is ChoiceKnob &&
      other.value == value &&
      _listEquals(other.choices, choices) &&
      _listEquals(other.paths, paths);

  @override
  int get hashCode =>
      Object.hash(value, Object.hashAll(choices), Object.hashAll(paths));
}

/// Turbo boost, whichever file spells it.
class BoostKnob {
  const BoostKnob({
    required this.enabled,
    required this.paths,
    required this.inverted,
  });

  /// Null when per-policy files disagree.
  final bool? enabled;
  final List<String> paths;

  /// intel_pstate's `no_turbo`, where `1` means boost is *off*.
  final bool inverted;

  String valueFor(bool on) => (on != inverted) ? '1' : '0';

  @override
  bool operator ==(Object other) =>
      other is BoostKnob &&
      other.enabled == enabled &&
      other.inverted == inverted &&
      _listEquals(other.paths, paths);

  @override
  int get hashCode => Object.hash(enabled, inverted, Object.hashAll(paths));
}

/// One cpufreq policy's frequency range, in kHz as sysfs spells it.
class FrequencyPolicy {
  const FrequencyPolicy({
    required this.path,
    required this.hardwareMin,
    required this.hardwareMax,
    required this.currentMax,
  });

  /// The `scaling_max_freq` file.
  final String path;
  final int hardwareMin;
  final int hardwareMax;
  final int currentMax;

  /// The cap as a share of what the hardware can do.
  int get percent => (currentMax * 100 / hardwareMax).round().clamp(1, 100);

  /// The lowest percentage the policy will take — its hardware minimum.
  int get minPercent => (hardwareMin * 100 / hardwareMax).ceil().clamp(1, 100);

  /// The `scaling_max_freq` for [percent], never below the hardware minimum.
  int valueFor(int percent) {
    final khz = hardwareMax * percent ~/ 100;
    return khz < hardwareMin ? hardwareMin : khz;
  }

  @override
  bool operator ==(Object other) =>
      other is FrequencyPolicy &&
      other.path == path &&
      other.hardwareMin == hardwareMin &&
      other.hardwareMax == hardwareMax &&
      other.currentMax == currentMax;

  @override
  int get hashCode => Object.hash(path, hardwareMin, hardwareMax, currentMax);
}

class FrequencyKnob {
  const FrequencyKnob(this.policies);

  final List<FrequencyPolicy> policies;

  /// The cap every policy holds, or null when they differ by more than a
  /// rounding step.
  int? get percent {
    if (policies.isEmpty) return null;
    final first = policies.first.percent;
    for (final p in policies) {
      if ((p.percent - first).abs() > 1) return null;
    }
    return first;
  }

  int get minPercent => policies.fold(
    1,
    (lowest, p) => p.minPercent > lowest ? p.minPercent : lowest,
  );

  /// The highest frequency any policy can reach, in MHz, for the row's label.
  int get peakMhz => policies.fold(
    0,
    (peak, p) => p.hardwareMax ~/ 1000 > peak ? p.hardwareMax ~/ 1000 : peak,
  );

  @override
  bool operator ==(Object other) =>
      other is FrequencyKnob && _listEquals(other.policies, policies);

  @override
  int get hashCode => Object.hashAll(policies);
}

/// Everything the pane can tune on this machine. A knob the hardware or the
/// driver does not offer is null and its row is not drawn.
class PowerTuning {
  const PowerTuning({
    this.platformProfile,
    this.governor,
    this.energyPreference,
    this.boost,
    this.maxFrequency,
    this.cpuDriver = '',
    this.policyCount = 0,
  });

  final ChoiceKnob? platformProfile;
  final ChoiceKnob? governor;
  final ChoiceKnob? energyPreference;
  final BoostKnob? boost;
  final FrequencyKnob? maxFrequency;

  /// `scaling_driver` of the first policy: `intel_pstate`, `amd-pstate-epp`,
  /// `acpi-cpufreq`, `intel_cpufreq` (intel_pstate in passive mode)…
  final String cpuDriver;

  final int policyCount;

  bool get isEmpty =>
      platformProfile == null &&
      governor == null &&
      energyPreference == null &&
      boost == null &&
      maxFrequency == null;

  @override
  bool operator ==(Object other) =>
      other is PowerTuning &&
      other.platformProfile == platformProfile &&
      other.governor == governor &&
      other.energyPreference == energyPreference &&
      other.boost == boost &&
      other.maxFrequency == maxFrequency &&
      other.cpuDriver == cpuDriver &&
      other.policyCount == policyCount;

  @override
  int get hashCode => Object.hash(
    platformProfile,
    governor,
    energyPreference,
    boost,
    maxFrequency,
    cpuDriver,
    policyCount,
  );
}

List<String> _words(String? raw) => raw == null
    ? const []
    : raw.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// Reads one knob that lives in every policy, as `<file>` with choices in
/// `<choicesFile>`. Null when no policy has it.
Future<ChoiceKnob?> _perPolicyChoice(
  SysfsReader fs,
  List<String> policies,
  String file,
  String choicesFile,
) async {
  final paths = <String>[];
  final values = <String>{};
  List<String>? common;
  for (final policy in policies) {
    final path = '$kCpufreqDir/$policy/$file';
    final value = await fs.read(path);
    if (value == null || value.isEmpty) continue;
    final choices = _words(await fs.read('$kCpufreqDir/$policy/$choicesFile'));
    paths.add(path);
    values.add(value);
    common = common == null ? choices : common.where(choices.contains).toList();
  }
  if (paths.isEmpty || common == null || common.isEmpty) return null;
  return ChoiceKnob(
    value: values.length == 1 ? values.first : null,
    choices: common,
    paths: paths,
  );
}

/// Reads every knob. Never throws: a file that cannot be read costs its knob.
Future<PowerTuning> readPowerTuning(SysfsReader fs) async {
  ChoiceKnob? platform;
  final platformValue = await fs.read(kPlatformProfilePath);
  final platformChoices = _words(await fs.read(kPlatformProfileChoicesPath));
  if (platformValue != null &&
      platformValue.isNotEmpty &&
      platformChoices.isNotEmpty) {
    platform = ChoiceKnob(
      value: platformValue,
      choices: platformChoices,
      paths: const [kPlatformProfilePath],
    );
  }

  final policies =
      (await fs.list(
        kCpufreqDir,
      )).where((name) => RegExp(r'^policy\d+$').hasMatch(name)).toList()..sort(
        (a, b) =>
            int.parse(a.substring(6)).compareTo(int.parse(b.substring(6))),
      );

  final governor = await _perPolicyChoice(
    fs,
    policies,
    'scaling_governor',
    'scaling_available_governors',
  );
  final epp = await _perPolicyChoice(
    fs,
    policies,
    'energy_performance_preference',
    'energy_performance_available_preferences',
  );

  BoostKnob? boost;
  final noTurbo = await fs.read(kIntelNoTurboPath);
  final globalBoost = await fs.read(kCpufreqBoostPath);
  if (noTurbo == '0' || noTurbo == '1') {
    boost = BoostKnob(
      enabled: noTurbo == '0',
      paths: const [kIntelNoTurboPath],
      inverted: true,
    );
  } else if (globalBoost == '0' || globalBoost == '1') {
    boost = BoostKnob(
      enabled: globalBoost == '1',
      paths: const [kCpufreqBoostPath],
      inverted: false,
    );
  } else {
    final paths = <String>[];
    final values = <bool>{};
    for (final policy in policies) {
      final path = '$kCpufreqDir/$policy/boost';
      final value = await fs.read(path);
      if (value != '0' && value != '1') continue;
      paths.add(path);
      values.add(value == '1');
    }
    if (paths.isNotEmpty) {
      boost = BoostKnob(
        enabled: values.length == 1 ? values.first : null,
        paths: paths,
        inverted: false,
      );
    }
  }

  final frequencies = <FrequencyPolicy>[];
  for (final policy in policies) {
    final dir = '$kCpufreqDir/$policy';
    final min = int.tryParse(await fs.read('$dir/cpuinfo_min_freq') ?? '');
    final max = int.tryParse(await fs.read('$dir/cpuinfo_max_freq') ?? '');
    final current = int.tryParse(await fs.read('$dir/scaling_max_freq') ?? '');
    if (min == null || max == null || current == null) continue;
    if (max <= 0 || min <= 0 || min > max) continue;
    frequencies.add(
      FrequencyPolicy(
        path: '$dir/scaling_max_freq',
        hardwareMin: min,
        hardwareMax: max,
        currentMax: current,
      ),
    );
  }

  return PowerTuning(
    platformProfile: platform,
    governor: governor,
    energyPreference: epp,
    boost: boost,
    maxFrequency: frequencies.isEmpty ? null : FrequencyKnob(frequencies),
    cpuDriver: policies.isEmpty
        ? ''
        : await fs.read('$kCpufreqDir/${policies.first}/scaling_driver') ?? '',
    policyCount: policies.length,
  );
}

/// What the user has changed on the pane and not yet applied. A null field is
/// left as the machine has it.
class PowerTuningEdits {
  const PowerTuningEdits({
    this.platformProfile,
    this.governor,
    this.energyPreference,
    this.boost,
    this.maxFrequencyPercent,
  });

  final String? platformProfile;
  final String? governor;
  final String? energyPreference;
  final bool? boost;
  final int? maxFrequencyPercent;

  static const PowerTuningEdits none = PowerTuningEdits();

  bool get isEmpty =>
      platformProfile == null &&
      governor == null &&
      energyPreference == null &&
      boost == null &&
      maxFrequencyPercent == null;

  /// Each field replaced where given. `clear*` drops an edit back to "as the
  /// machine has it", which a nullable parameter alone cannot say.
  PowerTuningEdits copyWith({
    String? platformProfile,
    String? governor,
    String? energyPreference,
    bool? boost,
    int? maxFrequencyPercent,
  }) => PowerTuningEdits(
    platformProfile: platformProfile ?? this.platformProfile,
    governor: governor ?? this.governor,
    energyPreference: energyPreference ?? this.energyPreference,
    boost: boost ?? this.boost,
    maxFrequencyPercent: maxFrequencyPercent ?? this.maxFrequencyPercent,
  );

  /// Drops every edit that matches what [current] already holds, so a pending
  /// count — and the Apply button — reflect real changes only.
  PowerTuningEdits against(PowerTuning current) {
    String? choice(String? edit, ChoiceKnob? knob) =>
        edit == null || knob == null || edit == knob.value ? null : edit;
    final boostKnob = current.boost;
    final freq = current.maxFrequency;
    return PowerTuningEdits(
      platformProfile: choice(platformProfile, current.platformProfile),
      governor: choice(governor, current.governor),
      energyPreference: choice(energyPreference, current.energyPreference),
      boost: boost == null || boostKnob == null || boost == boostKnob.enabled
          ? null
          : boost,
      maxFrequencyPercent:
          maxFrequencyPercent == null ||
              freq == null ||
              maxFrequencyPercent == freq.percent
          ? null
          : maxFrequencyPercent,
    );
  }

  int get count => [
    platformProfile,
    governor,
    energyPreference,
    boost,
    maxFrequencyPercent,
  ].where((e) => e != null).length;

  @override
  bool operator ==(Object other) =>
      other is PowerTuningEdits &&
      other.platformProfile == platformProfile &&
      other.governor == governor &&
      other.energyPreference == energyPreference &&
      other.boost == boost &&
      other.maxFrequencyPercent == maxFrequencyPercent;

  @override
  int get hashCode => Object.hash(
    platformProfile,
    governor,
    energyPreference,
    boost,
    maxFrequencyPercent,
  );
}

/// One file and the value to write into it.
class SysfsWrite {
  const SysfsWrite(this.path, this.value);

  final String path;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is SysfsWrite && other.path == path && other.value == value;

  @override
  int get hashCode => Object.hash(path, value);

  @override
  String toString() => '$path=$value';
}

/// The files the shell will ever write as root. The writer refuses anything
/// else — the script runs with the administrator's authority, and a path
/// assembled from a directory listing is still a path.
final List<RegExp> _kWritablePaths = [
  RegExp(r'^/sys/firmware/acpi/platform_profile$'),
  RegExp(
    r'^/sys/devices/system/cpu/cpufreq/policy\d+/'
    r'(scaling_governor|energy_performance_preference|scaling_max_freq|boost)$',
  ),
  RegExp(r'^/sys/devices/system/cpu/intel_pstate/no_turbo$'),
  RegExp(r'^/sys/devices/system/cpu/cpufreq/boost$'),
];

final RegExp _kWritableValue = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

bool isWritableSysfsWrite(SysfsWrite write) =>
    _kWritablePaths.any((re) => re.hasMatch(write.path)) &&
    _kWritableValue.hasMatch(write.value);

/// The writes [edits] needs against [current], in the order that lets each
/// land.
///
/// The governor goes before the EPP because intel_pstate refuses any EPP but
/// `performance` while the `performance` governor is set, so switching from it
/// to `powersave` + `power` in the other order fails the second write. A
/// value a knob does not offer is dropped here rather than sent to be refused.
List<SysfsWrite> planPowerTuning(PowerTuning current, PowerTuningEdits edits) {
  final writes = <SysfsWrite>[];
  void choice(String? value, ChoiceKnob? knob) {
    if (value == null || knob == null || !knob.choices.contains(value)) return;
    for (final path in knob.paths) {
      writes.add(SysfsWrite(path, value));
    }
  }

  choice(edits.governor, current.governor);
  choice(edits.energyPreference, current.energyPreference);
  choice(edits.platformProfile, current.platformProfile);
  final boost = current.boost;
  final boostEdit = edits.boost;
  if (boost != null && boostEdit != null) {
    for (final path in boost.paths) {
      writes.add(SysfsWrite(path, boost.valueFor(boostEdit)));
    }
  }
  final freq = current.maxFrequency;
  final percent = edits.maxFrequencyPercent;
  if (freq != null && percent != null) {
    final clamped = percent.clamp(freq.minPercent, 100);
    for (final policy in freq.policies) {
      writes.add(SysfsWrite(policy.path, '${policy.valueFor(clamped)}'));
    }
  }
  return writes;
}

/// Why a privileged write did not land.
enum SysfsWriteFailureKind {
  /// The user closed the password prompt, or polkit said no.
  dismissed,

  /// No authentication agent could be reached, or pkexec is missing.
  unavailable,

  /// Authenticated, but the kernel refused some of the values.
  rejected,
}

class SysfsWriteFailure implements Exception {
  const SysfsWriteFailure(this.kind, this.message, {this.paths = const []});

  final SysfsWriteFailureKind kind;
  final String message;

  /// For [SysfsWriteFailureKind.rejected], the files that refused.
  final List<String> paths;

  @override
  String toString() => 'SysfsWriteFailure($kind): $message';
}

/// The seam a test replaces.
abstract class PrivilegedSysfsWriter {
  /// Writes every one of [writes], or throws [SysfsWriteFailure]. A partial
  /// failure still writes everything it can.
  Future<void> write(List<SysfsWrite> writes);
}

/// The script `pkexec` runs: each path/value pair in turn, every refusal
/// collected rather than stopping at the first, so one knob the firmware
/// rejects does not cost the rest of the batch.
const String kSysfsWriteScript = r'''
failed=''
while [ "$#" -ge 2 ]; do
  printf '%s' "$2" 2>/dev/null > "$1" || failed="$failed $1"
  shift 2
done
if [ -n "$failed" ]; then
  printf 'refused:%s\n' "$failed" >&2
  exit 3
fi
''';

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Writes through `pkexec /bin/sh`, under `org.freedesktop.policykit.exec` —
/// `auth_admin` out of the box, which the shell's own polkit agent answers
/// with its password dialog. One invocation per [write], so one batch of edits
/// is one prompt.
///
/// Every path and value is checked against [isWritableSysfsWrite] before
/// anything runs, and they reach the script as positional arguments, never
/// spliced into its text.
class PkexecSysfsWriter implements PrivilegedSysfsWriter {
  PkexecSysfsWriter({ProcessRunner? runner})
    : _runner = runner ?? runHostProcess;

  final ProcessRunner _runner;

  /// pkexec's own exit codes: 126 when the dialog was dismissed or the
  /// request denied, 127 when no authorization could be obtained at all.
  static const int _dismissed = 126;
  static const int _notAuthorized = 127;
  static const int _scriptRefused = 3;

  @override
  Future<void> write(List<SysfsWrite> writes) async {
    if (writes.isEmpty) return;
    for (final write in writes) {
      if (!isWritableSysfsWrite(write)) {
        throw SysfsWriteFailure(
          SysfsWriteFailureKind.rejected,
          'Refusing to write "${write.value}" to ${write.path}.',
          paths: [write.path],
        );
      }
    }
    final ProcessResult result;
    try {
      result = await _runner('pkexec', [
        '/bin/sh',
        '-c',
        kSysfsWriteScript,
        'moonswing-power',
        for (final write in writes) ...[write.path, write.value],
      ]);
    } on ProcessException {
      throw const SysfsWriteFailure(
        SysfsWriteFailureKind.unavailable,
        'pkexec is not installed. It is part of polkit (the pkexec package '
        'on Debian and Ubuntu).',
      );
    }
    switch (result.exitCode) {
      case 0:
        return;
      case _dismissed:
        throw const SysfsWriteFailure(
          SysfsWriteFailureKind.dismissed,
          'Authentication was cancelled, so nothing was changed.',
        );
      case _notAuthorized:
        throw const SysfsWriteFailure(
          SysfsWriteFailureKind.unavailable,
          'Administrator authorization could not be obtained. An '
          'authentication agent has to be running in this session.',
        );
      case _scriptRefused:
        final paths = parseRefusedPaths('${result.stderr}');
        throw SysfsWriteFailure(
          SysfsWriteFailureKind.rejected,
          'The kernel refused '
          '${paths.length == 1 ? 'one value' : '${paths.length} values'}'
          ': ${paths.join(', ')}.',
          paths: paths,
        );
      default:
        final stderr = '${result.stderr}'.trim();
        throw SysfsWriteFailure(
          SysfsWriteFailureKind.rejected,
          stderr.isEmpty
              ? 'The change could not be applied (exit ${result.exitCode}).'
              : stderr,
        );
    }
  }
}

/// The paths after the script's `refused:` marker.
List<String> parseRefusedPaths(String stderr) {
  for (final line in stderr.split('\n')) {
    if (!line.startsWith('refused:')) continue;
    return _words(line.substring('refused:'.length));
  }
  return const [];
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
