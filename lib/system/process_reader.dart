import 'dart:io';

import 'package:graceful_shell/system/file_read.dart';
import 'package:graceful_shell/system/models.dart';

/// How a process's CPU percentage is scaled.
enum CpuPercentMode {
  /// 0..100 across the whole machine, so the rows in the table sum to roughly
  /// the total CPU gauge above them. This is what a reader of a system monitor
  /// expects, and it is the default.
  machine,

  /// `top`-style: 100% means one core saturated, so a threaded process can
  /// report several hundred percent.
  core,
}

/// Walks `/proc/<pid>` and returns raw counters. This is the expensive read —
/// one file per process, hundreds of processes — so it runs off the UI isolate
/// (see [ProcessSampler]) and does no arithmetic: everything it returns is a
/// primitive that can cross an isolate boundary cheaply.
class ProcessReader {
  ProcessReader({this.procRoot = '/proc'});

  final String procRoot;

  /// Reads every process.
  ///
  /// [skipCmdlineFor] names PIDs whose command line the caller already has.
  /// A command line never changes for the life of a process, so re-reading it
  /// every poll would double the syscall count for data we already know.
  List<ProcessRaw> sample({Set<int> skipCmdlineFor = const {}}) {
    final List<FileSystemEntity> entries;
    try {
      final root = Directory(procRoot);
      if (!root.existsSync()) return const [];
      entries = root.listSync(followLinks: false);
    } catch (_) {
      return const [];
    }

    final processes = <ProcessRaw>[];
    for (final entry in entries) {
      final pid = int.tryParse(entry.path.split('/').last);
      if (pid == null) continue;

      // A process can exit between listSync() and the read below, which makes
      // its whole directory vanish mid-walk. That is normal, not an error.
      final statLine = readStringOrNull('${entry.path}/stat');
      if (statLine == null) continue;

      final cmdline = skipCmdlineFor.contains(pid)
          ? null
          : _readCmdline('${entry.path}/cmdline');

      final process = parseStatLine(statLine, cmdline: cmdline);
      if (process != null) processes.add(process);
    }
    return processes;
  }

  /// Re-reads one process, for the kill path's identity check.
  ProcessRaw? statOf(int pid) {
    final line = readStringOrNull('$procRoot/$pid/stat');
    if (line == null) return null;
    return parseStatLine(line, cmdline: null);
  }

  /// `/proc/<pid>/cmdline` is NUL-separated, and is *empty* for kernel threads —
  /// which is the cheapest kernel-thread test there is.
  String? _readCmdline(String path) {
    final raw = readStringOrNull(path);
    if (raw == null) return null;
    return raw.split('\x00').where((s) => s.isNotEmpty).join(' ').trim();
  }
}

/// Parses one `/proc/<pid>/stat` line.
///
/// The `comm` field is the executable's name as the kernel captured it, and it
/// is *not* sanitised: it can contain spaces and parentheses (Firefox's content
/// processes are the usual offender — `1234 (Isolated Web Co) S 1 …`). Splitting
/// the line on whitespace is the classic bug here. The only correct anchor is
/// the **last** `)`, because everything after it is guaranteed
/// space-separated.
ProcessRaw? parseStatLine(String line, {String? cmdline}) {
  final open = line.indexOf('(');
  final close = line.lastIndexOf(')');
  if (open < 0 || close <= open || close + 2 >= line.length) return null;

  final pid = int.tryParse(line.substring(0, open).trim());
  if (pid == null) return null;
  final name = line.substring(open + 1, close);

  // Fields after ") " start at proc(5) field 3, so field N is at index N - 3.
  final f = line.substring(close + 2).trim().split(RegExp(r'\s+'));
  if (f.length < 22) return null;

  int at(int field) => int.tryParse(f[field - 3]) ?? 0;

  return ProcessRaw(
    pid: pid,
    name: name,
    state: f[0], // field 3
    ppid: at(4),
    utimeTicks: at(14),
    stimeTicks: at(15),
    threads: at(20),
    starttimeTicks: at(22),
    // Field 24 is RSS in pages. The alternative — VmRSS from
    // /proc/<pid>/status — is authoritative in KiB but costs a second file read
    // per process, doubling the walk for a number we already have here.
    rssKb: at(24) * kPageSizeBytes ~/ 1024,
    cmdline: cmdline,
  );
}

/// Resolves raw samples into table rows.
///
/// Pure: it takes both snapshots and the surrounding system state, and does no
/// I/O. That is what lets the isolate return raw counters and the arithmetic be
/// unit-tested without a fake `/proc`.
///
/// CPU% comes from tick deltas against the aggregate `cpu` line, never from
/// wall-clock elapsed time — `DateTime.now()` is not monotonic, and an NTP step
/// mid-poll would render a process at 4000%.
List<ProcessRow> computeProcessRows({
  required List<ProcessRaw> current,
  required Map<int, ProcessRaw> previous,
  required int deltaTotalJiffies,
  required int coreCount,
  required double systemUptimeSeconds,
  required Map<int, String> cmdlineCache,
  CpuPercentMode mode = CpuPercentMode.machine,
}) {
  final scale = mode == CpuPercentMode.core ? coreCount : 1;
  final rows = <ProcessRow>[];

  for (final process in current) {
    final prev = previous[process.pid];

    // A PID we have not seen before, or one that was recycled onto a different
    // process since the last poll, has no valid baseline. Report 0 rather than
    // a number derived from the wrong process's counters.
    final hasBaseline =
        prev != null && prev.starttimeTicks == process.starttimeTicks;

    var cpuPercent = 0.0;
    if (hasBaseline && deltaTotalJiffies > 0) {
      final deltaTicks = process.cpuTicks - prev.cpuTicks;
      if (deltaTicks > 0) {
        cpuPercent = deltaTicks / deltaTotalJiffies * 100 * scale;
      }
    }

    final uptimeSeconds =
        systemUptimeSeconds - process.starttimeTicks / kUserHz;
    final cmdline = process.cmdline ?? cmdlineCache[process.pid] ?? '';

    rows.add(
      ProcessRow(
        pid: process.pid,
        name: process.name,
        ppid: process.ppid,
        state: process.state,
        threads: process.threads,
        rssKb: process.rssKb,
        starttimeTicks: process.starttimeTicks,
        cpuPercent: cpuPercent,
        uptime: Duration(
          seconds: uptimeSeconds.clamp(0, double.maxFinite).round(),
        ),
        cmdline: cmdline,
        // A process with no command line at all is a kernel thread. Everything
        // else — including one whose cmdline we skipped and have cached — is not.
        isKernelThread: cmdline.isEmpty,
      ),
    );
  }

  return rows;
}

/// The wall-clock instant a process started, for the row detail strip.
DateTime processStartTime(int starttimeTicks, DateTime bootTime) => bootTime
    .add(Duration(milliseconds: (starttimeTicks / kUserHz * 1000).round()));
