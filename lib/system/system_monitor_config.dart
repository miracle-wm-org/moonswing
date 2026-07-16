import 'package:graceful_shell/system/process_reader.dart';

/// Everything under `[modules.system_monitor]`.
///
/// It lives here rather than with the bar module because the store reads it too,
/// and `lib/system/` must not depend on `lib/modules/`.
class SystemMonitorConfig {
  const SystemMonitorConfig({
    this.pollSeconds = 2,
    this.tempUnit = 'celsius',
    this.historySamples = 120,
    this.cpuPercentMode = CpuPercentMode.machine,
    this.showKernelThreads = false,
    this.confirmKill = true,
    this.killGraceSeconds = 5,
    this.diskPollSeconds = 30,
  });

  /// How often the light stats (CPU, memory, temperature, load, network) are
  /// read, and how often the process table refreshes while it is on screen.
  final int pollSeconds;

  /// `celsius` | `fahrenheit`.
  final String tempUnit;

  /// How many samples the overview graphs keep. 120 at the default cadence is
  /// four minutes of history.
  final int historySamples;

  final CpuPercentMode cpuPercentMode;

  /// Kernel threads are hidden by default: there are hundreds of them, they use
  /// no memory, and killing one is never a good idea.
  final bool showKernelThreads;

  final bool confirmKill;

  /// How long a process gets to honour a SIGTERM before the row offers to
  /// force-quit it.
  final int killGraceSeconds;

  /// Disks get their own slow cadence — `df` forks a process, and usage moves
  /// on the scale of minutes.
  final int diskPollSeconds;

  factory SystemMonitorConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SystemMonitorConfig();

    int intOr(String key, int fallback) {
      final v = map[key];
      return v is int ? v : fallback;
    }

    bool boolOr(String key, bool fallback) {
      final v = map[key];
      return v is bool ? v : fallback;
    }

    return SystemMonitorConfig(
      pollSeconds: intOr('poll_seconds', 2).clamp(1, 60),
      tempUnit: map['temp_unit'] as String? ?? 'celsius',
      historySamples: intOr('history_samples', 120).clamp(10, 600),
      cpuPercentMode: map['cpu_percent_mode'] == 'core'
          ? CpuPercentMode.core
          : CpuPercentMode.machine,
      showKernelThreads: boolOr('show_kernel_threads', false),
      confirmKill: boolOr('confirm_kill', true),
      killGraceSeconds: intOr('kill_grace_seconds', 5).clamp(1, 60),
      diskPollSeconds: intOr('disk_poll_seconds', 30).clamp(5, 600),
    );
  }
}
