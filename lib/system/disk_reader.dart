import 'dart:io';

import 'package:graceful_shell/system/models.dart';

/// Filesystem usage, via `df`.
///
/// Shelling out costs a fork, which is why this runs on its own slow cadence
/// rather than with the other stats — disk usage moves on the scale of minutes.
/// The alternative, calling `statvfs` through `dart:ffi`, avoids the fork but
/// hardcodes a struct layout that differs across architecture and libc; a
/// segfault in the shell process is a steep price for a number this static.
class DiskReader {
  DiskReader({
    Future<ProcessResult> Function(String, List<String>)? runner,
  }) : _run = runner ?? Process.run;

  final Future<ProcessResult> Function(String, List<String>) _run;

  /// Real filesystems only. Every desktop has a dozen pseudo-filesystems
  /// (tmpfs, /snap loops, overlay mounts) that are noise in a usage list.
  static const _excludedTypes = [
    'tmpfs',
    'devtmpfs',
    'squashfs',
    'overlay',
    'efivarfs',
  ];

  Future<List<DiskUsage>> read() async {
    try {
      final result = await _run('df', [
        '-B1', // bytes, so we don't have to guess at df's block size
        '-P', // POSIX output: one line per filesystem, never wrapped
        for (final type in _excludedTypes) ...['-x', type],
      ]);
      if (result.exitCode != 0) return const [];
      return parseDfOutput(result.stdout.toString());
    } catch (_) {
      // No df (a minimal container, say). Disks simply aren't shown.
      return const [];
    }
  }
}

/// Parses POSIX `df -B1 -P` output.
///
/// Columns: filesystem, 1-blocks, used, available, capacity, mount point. The
/// mount point is last and may contain spaces, so it is taken as the remainder
/// of the line rather than as a field.
List<DiskUsage> parseDfOutput(String stdout) {
  final lines = stdout.split('\n');
  final disks = <DiskUsage>[];

  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) continue;
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 6) continue;

    final total = int.tryParse(parts[1]);
    final used = int.tryParse(parts[2]);
    if (total == null || used == null || total <= 0) continue;

    final mount = parts.sublist(5).join(' ');
    disks.add(DiskUsage(
      mountPoint: mount,
      totalBytes: total,
      usedBytes: used,
    ));
  }

  disks.sort((a, b) => a.mountPoint.compareTo(b.mountPoint));
  return disks;
}
