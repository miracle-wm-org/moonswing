import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:graceful_shell/system/file_read.dart';
import 'package:graceful_shell/system/format.dart';
import 'package:graceful_shell/system/proc_reader.dart';

/// A one-shot snapshot of the machine's static identity: hardware, software, and
/// the desktop environment it is running under.
///
/// Unlike [SystemStatsStore], nothing here changes over a session (uptime and
/// boot time are captured once, when the page is first opened), so there is no
/// store, no polling, and no lease. Every field is display-ready and null when
/// its source was missing or unparseable — the UI renders null as an em dash.
@immutable
class SystemInfo {
  const SystemInfo({
    this.hostname,
    this.osName,
    this.kernel,
    this.architecture,
    this.cpuModel,
    this.cpuCores,
    this.totalMemory,
    this.totalSwap,
    this.gpu,
    this.desktop,
    this.sessionType,
    this.shell,
    this.uptime,
    this.bootTime,
  });

  final String? hostname;
  final String? osName;
  final String? kernel;
  final String? architecture;
  final String? cpuModel;
  final String? cpuCores;
  final String? totalMemory;
  final String? totalSwap;
  final String? gpu;
  final String? desktop;
  final String? sessionType;
  final String? shell;
  final String? uptime;
  final String? bootTime;
}

/// Gathers a [SystemInfo] from `/proc`, `/etc`, the environment, and a couple of
/// best-effort shell-outs.
///
/// The roots, environment, and process runner are all constructor parameters —
/// the same shape [ProcReader] and [DiskReader] use — so tests point them at a
/// temp directory and a fake map and never touch the real machine. Every read is
/// best-effort: a missing file or a failed command leaves that field null rather
/// than throwing.
class SystemInfoReader {
  SystemInfoReader({
    this.procRoot = '/proc',
    this.etcRoot = '/etc',
    Map<String, String>? env,
    ProcReader? proc,
    Future<ProcessResult> Function(String, List<String>)? runner,
  }) : _env = env ?? Platform.environment,
       _proc = proc ?? ProcReader(procRoot: procRoot),
       _run = runner ?? Process.run;

  final String procRoot;
  final String etcRoot;
  final Map<String, String> _env;
  final ProcReader _proc;
  final Future<ProcessResult> Function(String, List<String>) _run;

  Future<SystemInfo> read() async {
    final memory = _proc.readMemory();
    final cpu = _proc.readCpu();
    final uptimeSeconds = _proc.readUptimeSeconds();

    return SystemInfo(
      hostname: readStringOrNull('$procRoot/sys/kernel/hostname')?.trim(),
      osName: parseOsReleasePrettyName(
        readStringOrNull('$etcRoot/os-release') ?? '',
      ),
      kernel: readStringOrNull('$procRoot/sys/kernel/osrelease')?.trim(),
      architecture: await _runFirstLine('uname', const ['-m']),
      cpuModel: _proc.readCpuModel(),
      cpuCores: cpu != null && cpu.coreCount > 0 ? '${cpu.coreCount}' : null,
      totalMemory: memory.totalKb > 0 ? formatBytesKb(memory.totalKb) : null,
      totalSwap: memory.swapTotalKb > 0
          ? formatBytesKb(memory.swapTotalKb)
          : null,
      gpu: parseLspciGpu(await _runFull('lspci', const []) ?? ''),
      desktop: _envValue('XDG_CURRENT_DESKTOP'),
      sessionType: _envValue('XDG_SESSION_TYPE'),
      shell: _envValue('SHELL'),
      uptime: uptimeSeconds != null
          ? formatUptime(Duration(seconds: uptimeSeconds.round()))
          : null,
      bootTime: cpu?.bootTime != null ? _formatBootTime(cpu!.bootTime!) : null,
    );
  }

  String? _envValue(String key) {
    final value = _env[key]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<String?> _runFull(String executable, List<String> args) async {
    try {
      final result = await _run(executable, args);
      if (result.exitCode != 0) return null;
      final out = result.stdout;
      return out is String ? out : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _runFirstLine(String executable, List<String> args) async {
    final out = await _runFull(executable, args);
    if (out == null) return null;
    final line = out.trim();
    return line.isEmpty ? null : line.split('\n').first.trim();
  }
}

/// Pulls `PRETTY_NAME` out of an `/etc/os-release` file, stripping the optional
/// surrounding quotes. Returns null if the key is absent or empty.
String? parseOsReleasePrettyName(String contents) {
  for (final line in contents.split('\n')) {
    if (!line.startsWith('PRETTY_NAME=')) continue;
    var value = line.substring('PRETTY_NAME='.length).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    return value.isEmpty ? null : value;
  }
  return null;
}

/// Picks the first display adapter out of `lspci` output — the description after
/// a "VGA compatible controller" or "3D controller" class. Returns null if no
/// such line is present.
String? parseLspciGpu(String contents) {
  for (final line in contents.split('\n')) {
    final lower = line.toLowerCase();
    if (!lower.contains('vga compatible controller') &&
        !lower.contains('3d controller') &&
        !lower.contains('display controller')) {
      continue;
    }
    // A line reads like: "01:00.0 VGA compatible controller: NVIDIA ...".
    final colon = line.indexOf(':', line.indexOf(':') + 1);
    final value = colon >= 0 ? line.substring(colon + 1).trim() : line.trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

String _formatBootTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
