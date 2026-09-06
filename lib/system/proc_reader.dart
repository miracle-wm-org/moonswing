import 'dart:io';

import 'package:graceful_shell/system/file_read.dart';
import 'package:graceful_shell/system/models.dart';

/// The cheap `/proc` and `/sys` reads: six small files, fast enough to do on the
/// UI isolate at the poll cadence. The expensive per-process walk lives in
/// [ProcessReader] and runs off-isolate.
///
/// The roots are constructor parameters — [BrightnessMonitor]'s shape — so tests
/// point them at a temp directory. Every method returns null or an empty value
/// when a file is missing or unparseable: a shell must not crash a panel because
/// it landed on a kernel that does not expose a thermal zone.
class ProcReader {
  ProcReader({this.procRoot = '/proc', this.sysRoot = '/sys'});

  final String procRoot;
  final String sysRoot;

  /// Parses `/proc/stat`: the aggregate `cpu` line, every `cpuN` line, and
  /// `btime`.
  CpuSample? readCpu() {
    final lines = readLinesOrNull('$procRoot/stat');
    if (lines == null) return null;

    CpuTimes? aggregate;
    final cores = <CpuTimes>[];
    DateTime? bootTime;

    for (final line in lines) {
      if (line.startsWith('cpu')) {
        final times = _parseCpuLine(line);
        if (times == null) continue;
        // "cpu " (with the trailing space) is the aggregate; "cpu0", "cpu1", …
        // are the individual cores.
        if (line.startsWith('cpu ')) {
          aggregate = times;
        } else {
          cores.add(times);
        }
      } else if (line.startsWith('btime ')) {
        final seconds = int.tryParse(line.substring(6).trim());
        if (seconds != null) {
          bootTime = DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          ).toLocal();
        }
      }
    }

    if (aggregate == null) return null;
    return CpuSample(aggregate: aggregate, cores: cores, bootTime: bootTime);
  }

  static CpuTimes? _parseCpuLine(String line) {
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 5) return null;

    int at(int i) => parts.length > i ? (int.tryParse(parts[i]) ?? 0) : 0;

    final user = at(1);
    final nice = at(2);
    final system = at(3);
    final idle = at(4);
    final iowait = at(5);

    // Sum every field the kernel gave us, not just the ones we name. Newer
    // kernels append columns (guest, guest_nice); leaving them out of the total
    // would make the busy fraction drift high.
    var total = 0;
    for (var i = 1; i < parts.length; i++) {
      total += int.tryParse(parts[i]) ?? 0;
    }

    return CpuTimes(
      user: user,
      nice: nice,
      system: system,
      // A core waiting on I/O is not doing work, so iowait counts as idle.
      idle: idle + iowait,
      total: total,
    );
  }

  MemorySample readMemory() {
    final lines = readLinesOrNull('$procRoot/meminfo');
    if (lines == null) return const MemorySample();

    var total = 0,
        available = 0,
        free = 0,
        buffers = 0,
        cached = 0,
        swapTotal = 0,
        swapFree = 0;

    for (final line in lines) {
      final value = parseMemInfoValue(line);
      if (line.startsWith('MemTotal:')) {
        total = value;
      } else if (line.startsWith('MemAvailable:')) {
        available = value;
      } else if (line.startsWith('MemFree:')) {
        free = value;
      } else if (line.startsWith('Buffers:')) {
        buffers = value;
      } else if (line.startsWith('Cached:')) {
        cached = value;
      } else if (line.startsWith('SwapTotal:')) {
        swapTotal = value;
      } else if (line.startsWith('SwapFree:')) {
        swapFree = value;
      }
    }

    return MemorySample(
      totalKb: total,
      // Ancient kernels (< 3.14) have no MemAvailable. Free is a poor stand-in,
      // but it beats reporting the machine as 100% used.
      availableKb: available > 0 ? available : free + buffers + cached,
      freeKb: free,
      buffersKb: buffers,
      cachedKb: cached,
      swapTotalKb: swapTotal,
      swapFreeKb: swapFree,
    );
  }

  LoadAverage? readLoad() {
    final text = readStringOrNull('$procRoot/loadavg');
    if (text == null) return null;
    final parts = text.trim().split(RegExp(r'\s+'));
    if (parts.length < 3) return null;
    final one = double.tryParse(parts[0]);
    final five = double.tryParse(parts[1]);
    final fifteen = double.tryParse(parts[2]);
    if (one == null || five == null || fifteen == null) return null;
    return LoadAverage(one, five, fifteen);
  }

  /// System uptime in seconds. Also the basis for every process's uptime:
  /// a process started `starttimeTicks / kUserHz` seconds after boot, so it has
  /// been alive for `uptime - starttimeTicks / kUserHz`.
  double? readUptimeSeconds() {
    final text = readStringOrNull('$procRoot/uptime');
    if (text == null) return null;
    return double.tryParse(text.trim().split(RegExp(r'\s+')).first);
  }

  /// The CPU's marketing name, from the first `model name` line of
  /// `/proc/cpuinfo`.
  String? readCpuModel() {
    final lines = readLinesOrNull('$procRoot/cpuinfo');
    if (lines == null) return null;
    for (final line in lines) {
      if (line.startsWith('model name')) {
        final colon = line.indexOf(':');
        if (colon >= 0) return line.substring(colon + 1).trim();
      }
    }
    return null;
  }

  /// Cumulative rx/tx bytes summed over every interface except loopback.
  ///
  /// Summing rather than picking "the" interface is deliberate: a laptop with
  /// Docker or a VPN has a dozen `veth*`/`tun*` devices, and any heuristic that
  /// chooses one of them is wrong on somebody's machine.
  NetSample? readNet() {
    final lines = readLinesOrNull('$procRoot/net/dev');
    if (lines == null) return null;

    var rx = 0, tx = 0;
    for (final line in lines) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final name = line.substring(0, colon).trim();
      if (name == 'lo' || name.isEmpty) continue;

      final fields = line.substring(colon + 1).trim().split(RegExp(r'\s+'));
      if (fields.length < 9) continue;
      rx += int.tryParse(fields[0]) ?? 0; // receive bytes
      tx += int.tryParse(fields[8]) ?? 0; // transmit bytes
    }
    return NetSample(rxBytes: rx, txBytes: tx);
  }

  /// The first usable thermal zone, in Celsius. Prefers a zone whose type looks
  /// like a CPU package sensor; falls back to the first zone that reads.
  double? readTemperatureCelsius() {
    final root = Directory('$sysRoot/class/thermal');
    List<Directory> zones;
    try {
      if (!root.existsSync()) return null;
      zones =
          root
              .listSync()
              .whereType<Directory>()
              .where((d) => d.path.split('/').last.startsWith('thermal_zone'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
    } catch (_) {
      return null;
    }

    Directory? preferred;
    Directory? fallback;

    for (final zone in zones) {
      final type = readStringOrNull('${zone.path}/type')?.trim().toLowerCase();
      if (type == null) continue;
      if (!File('${zone.path}/temp').existsSync()) continue;

      if (type.contains('pkg') ||
          type.contains('cpu') ||
          type.contains('x86') ||
          type.contains('core')) {
        preferred = zone;
        break;
      }
      fallback ??= zone;
    }

    final zone = preferred ?? fallback;
    if (zone == null) return null;

    final milliCelsius = int.tryParse(
      readStringOrNull('${zone.path}/temp')?.trim() ?? '',
    );
    return milliCelsius == null ? null : milliCelsius / 1000.0;
  }
}

/// Pulls the numeric value out of a `Key:   1234 kB` line.
int parseMemInfoValue(String line) {
  final parts = line.split(RegExp(r'\s+'));
  return parts.length >= 2 ? (int.tryParse(parts[1]) ?? 0) : 0;
}

/// Per-core usage between two `/proc/stat` readings.
List<CoreUsage> computeCoreUsage(CpuSample prev, CpuSample curr) {
  final result = <CoreUsage>[];
  for (var i = 0; i < curr.cores.length && i < prev.cores.length; i++) {
    final core = curr.cores[i];
    result.add(
      CoreUsage(
        index: i,
        percent: CpuTimes.usageBetween(prev.cores[i], core),
        busyTime: Duration(
          seconds: (core.user + core.nice + core.system) ~/ kUserHz,
        ),
      ),
    );
  }
  return result;
}

/// Throughput between two `/proc/net/dev` readings.
///
/// Counters are 64-bit on modern kernels but can still reset when an interface is
/// torn down and recreated, which shows up as a negative delta; report zero rather
/// than a negative rate.
NetRate computeNetRate(NetSample prev, NetSample curr, Duration interval) {
  final seconds = interval.inMicroseconds / Duration.microsecondsPerSecond;
  if (seconds <= 0) return NetRate.zero;
  final rx = (curr.rxBytes - prev.rxBytes).clamp(0, 1 << 62) / seconds;
  final tx = (curr.txBytes - prev.txBytes).clamp(0, 1 << 62) / seconds;
  return NetRate(rxBytesPerSecond: rx, txBytesPerSecond: tx);
}
