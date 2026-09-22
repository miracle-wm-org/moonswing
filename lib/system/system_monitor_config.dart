import 'package:moonswing/config_reader.dart';
import 'package:moonswing/system/process_reader.dart';

/// Everything under `[modules.system_monitor]`.
///
/// It lives here rather than with the bar module because the store reads it too,
/// and `lib/system/` must not depend on `lib/modules/`.
class SystemMonitorConfig {
  const SystemMonitorConfig({
    this.pollSeconds = 1,
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
  /// two minutes of history.
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
    return SystemMonitorConfig(
      pollSeconds: map.intOr('poll_seconds', 1, min: 1, max: 60),
      tempUnit: map.stringOr('temp_unit', 'celsius'),
      historySamples: map.intOr('history_samples', 120, min: 10, max: 600),
      cpuPercentMode: map['cpu_percent_mode'] == 'core'
          ? CpuPercentMode.core
          : CpuPercentMode.machine,
      showKernelThreads: map.boolOr('show_kernel_threads', false),
      confirmKill: map.boolOr('confirm_kill', true),
      killGraceSeconds: map.intOr('kill_grace_seconds', 5, min: 1, max: 60),
      diskPollSeconds: map.intOr('disk_poll_seconds', 30, min: 5, max: 600),
    );
  }
}
