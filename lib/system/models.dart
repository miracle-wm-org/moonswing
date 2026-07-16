import 'package:flutter/foundation.dart';

/// Kernel jiffies per second. `USER_HZ` is 100 on every mainstream Linux kernel
/// configuration; there is no way to read `sysconf(_SC_CLK_TCK)` from Dart
/// without FFI, and no desktop distribution ships anything else.
const int kUserHz = 100;

/// Page size assumed when converting `/proc/<pid>/stat`'s RSS (which the kernel
/// reports in pages) to bytes. 4 KiB on x86-64 and on every aarch64 desktop
/// kernel in practice.
const int kPageSizeBytes = 4096;

/// One `cpuN` (or the aggregate `cpu`) line of `/proc/stat`, in raw jiffies.
@immutable
class CpuTimes {
  const CpuTimes({
    required this.user,
    required this.nice,
    required this.system,
    required this.idle,
    required this.total,
  });

  final int user;
  final int nice;
  final int system;

  /// idle + iowait — the part of [total] that was not doing work.
  final int idle;

  /// Every field on the line summed, including the ones we don't break out.
  final int total;

  /// Busy fraction between this snapshot and a later one, as 0..100.
  static double usageBetween(CpuTimes prev, CpuTimes curr) {
    final deltaTotal = curr.total - prev.total;
    if (deltaTotal <= 0) return 0;
    final deltaIdle = curr.idle - prev.idle;
    return ((deltaTotal - deltaIdle) / deltaTotal * 100).clamp(0.0, 100.0);
  }
}

/// A full `/proc/stat` reading: the aggregate line, every core, and boot time.
@immutable
class CpuSample {
  const CpuSample({
    required this.aggregate,
    required this.cores,
    required this.bootTime,
  });

  /// The `cpu ` line. The old module skipped it and averaged the per-core lines
  /// instead; per-process CPU% needs the real aggregate jiffy total, so it is
  /// parsed now.
  final CpuTimes aggregate;

  /// `cpu0`, `cpu1`, … in order.
  final List<CpuTimes> cores;

  /// From `btime`: the wall-clock instant the machine booted, or null if the
  /// field is absent.
  final DateTime? bootTime;

  int get coreCount => cores.length;
}

/// Per-core usage, derived from two [CpuSample]s.
@immutable
class CoreUsage {
  const CoreUsage({
    required this.index,
    required this.percent,
    required this.busyTime,
  });

  final int index;
  final double percent;

  /// Accumulated user + nice + system time since boot.
  final Duration busyTime;
}

/// A `/proc/meminfo` reading. All values in KiB, as the file reports them.
@immutable
class MemorySample {
  const MemorySample({
    this.totalKb = 0,
    this.availableKb = 0,
    this.freeKb = 0,
    this.buffersKb = 0,
    this.cachedKb = 0,
    this.swapTotalKb = 0,
    this.swapFreeKb = 0,
  });

  final int totalKb;
  final int availableKb;
  final int freeKb;
  final int buffersKb;
  final int cachedKb;
  final int swapTotalKb;
  final int swapFreeKb;

  /// What the system actually has committed — total minus what it could hand
  /// out on demand. `MemAvailable` already discounts reclaimable cache, which
  /// is why it, and not `MemFree`, is the right basis.
  int get usedKb => (totalKb - availableKb).clamp(0, totalKb);

  int get swapUsedKb => (swapTotalKb - swapFreeKb).clamp(0, swapTotalKb);

  double get usedFraction => totalKb > 0 ? usedKb / totalKb : 0;

  double get swapUsedFraction => swapTotalKb > 0 ? swapUsedKb / swapTotalKb : 0;
}

/// `/proc/loadavg`'s first three fields.
@immutable
class LoadAverage {
  const LoadAverage(this.one, this.five, this.fifteen);

  final double one;
  final double five;
  final double fifteen;
}

/// Cumulative interface byte counters from `/proc/net/dev`, summed across every
/// interface except loopback.
@immutable
class NetSample {
  const NetSample({required this.rxBytes, required this.txBytes});

  final int rxBytes;
  final int txBytes;
}

/// Instantaneous throughput, derived from two [NetSample]s and the interval.
@immutable
class NetRate {
  const NetRate({required this.rxBytesPerSecond, required this.txBytesPerSecond});

  final double rxBytesPerSecond;
  final double txBytesPerSecond;

  static const NetRate zero =
      NetRate(rxBytesPerSecond: 0, txBytesPerSecond: 0);
}

/// One mounted filesystem's usage, as reported by `df`.
@immutable
class DiskUsage {
  const DiskUsage({
    required this.mountPoint,
    required this.totalBytes,
    required this.usedBytes,
  });

  final String mountPoint;
  final int totalBytes;
  final int usedBytes;

  double get usedFraction => totalBytes > 0 ? usedBytes / totalBytes : 0;
}

/// A process exactly as `/proc/<pid>/stat` reports it — raw counters, no
/// arithmetic. This is what crosses the isolate boundary, so every field is a
/// primitive.
@immutable
class ProcessRaw {
  const ProcessRaw({
    required this.pid,
    required this.name,
    required this.ppid,
    required this.state,
    required this.threads,
    required this.utimeTicks,
    required this.stimeTicks,
    required this.starttimeTicks,
    required this.rssKb,
    this.cmdline,
  });

  final int pid;
  final String name;
  final int ppid;

  /// Single-letter scheduler state: `R`, `S`, `D`, `Z`, `T`, …
  final String state;
  final int threads;
  final int utimeTicks;
  final int stimeTicks;

  /// Ticks between boot and this process starting. Together with [pid] this is
  /// a stable process identity: PIDs are recycled, but a recycled PID will not
  /// have the same start time.
  final int starttimeTicks;
  final int rssKb;

  /// Null when the sampler was told to skip it (already cached by the store).
  /// Empty means a kernel thread — they have no command line at all.
  final String? cmdline;

  int get cpuTicks => utimeTicks + stimeTicks;

  /// Kernel threads are children of kthreadd (pid 2) and have an empty cmdline.
  bool get isKernelThread => cmdline != null && cmdline!.isEmpty;
}

/// A process as the table renders it: raw counters resolved into rates and
/// durations against the surrounding samples.
@immutable
class ProcessRow {
  const ProcessRow({
    required this.pid,
    required this.name,
    required this.ppid,
    required this.state,
    required this.threads,
    required this.rssKb,
    required this.starttimeTicks,
    required this.cpuPercent,
    required this.uptime,
    required this.cmdline,
    required this.isKernelThread,
  });

  final int pid;
  final String name;
  final int ppid;
  final String state;
  final int threads;
  final int rssKb;
  final int starttimeTicks;

  /// 0 the first time a PID is seen — there is no previous snapshot to diff
  /// against, and inventing one from [starttimeTicks] would report the
  /// process's lifetime average as if it were current load.
  final double cpuPercent;

  /// How long the process has been running.
  final Duration uptime;
  final String cmdline;
  final bool isKernelThread;
}

/// One point on the overview graphs.
@immutable
class HistorySample {
  const HistorySample({
    required this.cpuPercent,
    required this.memoryFraction,
    required this.swapFraction,
    required this.netRate,
  });

  final double cpuPercent;
  final double memoryFraction;
  final double swapFraction;
  final NetRate netRate;
}
