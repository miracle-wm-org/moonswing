import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/system/models.dart';
import 'package:moonswing/system/process_reader.dart';

/// Builds a `/proc/<pid>/stat` line with the fields we read set, and plausible
/// filler in between. See proc(5): after the `)` the fields are space-separated
/// and start at field 3, so field N sits at index N - 3.
String statLine({
  required int pid,
  required String comm,
  String state = 'S',
  int ppid = 1,
  int utime = 0,
  int stime = 0,
  int threads = 1,
  int starttime = 0,
  int rssPages = 0,
}) {
  return [
    pid, // 1
    '($comm)', // 2
    state, // 3
    ppid, // 4
    0, 0, 0, -1, 0, // 5-9   pgrp session tty_nr tpgid flags
    0, 0, 0, 0, // 10-13  minflt cminflt majflt cmajflt
    utime, // 14
    stime, // 15
    0, 0, // 16-17 cutime cstime
    20, 0, // 18-19 priority nice
    threads, // 20
    0, // 21    itrealvalue
    starttime, // 22
    0, // 23    vsize
    rssPages, // 24
  ].join(' ');
}

void main() {
  group('parseStatLine', () {
    test('reads every field we care about', () {
      final process = parseStatLine(
        statLine(
          pid: 3412,
          comm: 'firefox',
          state: 'R',
          ppid: 1200,
          utime: 500,
          stime: 100,
          threads: 62,
          starttime: 90000,
          rssPages: 500000,
        ),
        cmdline: '/usr/lib/firefox/firefox',
      )!;

      expect(process.pid, 3412);
      expect(process.name, 'firefox');
      expect(process.state, 'R');
      expect(process.ppid, 1200);
      expect(process.utimeTicks, 500);
      expect(process.stimeTicks, 100);
      expect(process.cpuTicks, 600);
      expect(process.threads, 62);
      expect(process.starttimeTicks, 90000);
      // RSS arrives in pages, not KiB.
      expect(process.rssKb, 500000 * kPageSizeBytes ~/ 1024);
    });

    test('a comm containing spaces and parens still parses', () {
      // The classic /proc parsing bug: comm is not sanitised, so splitting the
      // line on whitespace — or anchoring on the *first* ')' — gets this wrong.
      // Firefox's content processes really do look like this.
      final process = parseStatLine(
        statLine(pid: 1234, comm: 'Isolated Web Co(1)', utime: 7, starttime: 42),
      )!;

      expect(process.pid, 1234);
      expect(process.name, 'Isolated Web Co(1)');
      expect(process.utimeTicks, 7);
      expect(process.starttimeTicks, 42);
    });

    test('a truncated line is skipped rather than throwing', () {
      expect(parseStatLine('123 (short) S 1 0 0'), isNull);
      expect(parseStatLine('garbage'), isNull);
      expect(parseStatLine(''), isNull);
    });
  });

  group('ProcessReader.sample', () {
    late Directory proc;

    setUp(() => proc = Directory.systemTemp.createTempSync('process_reader'));
    tearDown(() => proc.deleteSync(recursive: true));

    void writeProcess(
      int pid,
      String comm, {
      List<String>? cmdline,
      int rssPages = 100,
    }) {
      final dir = Directory('${proc.path}/$pid')..createSync(recursive: true);
      File('${dir.path}/stat')
          .writeAsStringSync(statLine(pid: pid, comm: comm, rssPages: rssPages));
      // The kernel NUL-separates the arguments and leaves a trailing NUL.
      File('${dir.path}/cmdline')
          .writeAsStringSync(cmdline == null ? '' : '${cmdline.join('\x00')}\x00');
    }

    test('reads every numeric directory and ignores the rest', () {
      writeProcess(1, 'systemd', cmdline: ['/sbin/init']);
      writeProcess(3412, 'firefox', cmdline: ['/usr/lib/firefox/firefox', '-P']);
      // /proc is full of non-PID entries — meminfo, self, sys, …
      File('${proc.path}/meminfo').writeAsStringSync('MemTotal: 1 kB\n');
      Directory('${proc.path}/sys').createSync();

      final processes = ProcessReader(procRoot: proc.path).sample();

      expect(processes.map((p) => p.pid).toSet(), {1, 3412});
    });

    test('joins the NUL-separated cmdline', () {
      writeProcess(3412, 'firefox',
          cmdline: ['/usr/lib/firefox/firefox', '-P', 'default']);

      final process = ProcessReader(procRoot: proc.path).sample().single;

      expect(process.cmdline, '/usr/lib/firefox/firefox -P default');
      expect(process.isKernelThread, isFalse);
    });

    test('an empty cmdline marks a kernel thread', () {
      writeProcess(2, 'kthreadd', cmdline: null, rssPages: 0);

      final process = ProcessReader(procRoot: proc.path).sample().single;

      expect(process.cmdline, '');
      expect(process.isKernelThread, isTrue);
    });

    test('skipCmdlineFor leaves the cmdline unread', () {
      writeProcess(3412, 'firefox', cmdline: ['/usr/lib/firefox/firefox']);

      final process = ProcessReader(procRoot: proc.path)
          .sample(skipCmdlineFor: {3412}).single;

      // Null, not empty — "we did not look" must be distinguishable from
      // "it has none", or every cached process would look like a kernel thread.
      expect(process.cmdline, isNull);
    });

    test('a directory with no stat file is skipped', () {
      // A process that exits mid-walk leaves a directory entry we can list but
      // not read. That is normal, not an error.
      Directory('${proc.path}/999').createSync();
      writeProcess(1, 'systemd', cmdline: ['/sbin/init']);

      final processes = ProcessReader(procRoot: proc.path).sample();

      expect(processes.map((p) => p.pid), [1]);
    });

    test('a missing /proc yields an empty list', () {
      expect(ProcessReader(procRoot: '/nonexistent-proc').sample(), isEmpty);
    });

    test('statOf re-reads a single process, for the kill identity check', () {
      writeProcess(3412, 'firefox', cmdline: ['/usr/lib/firefox/firefox']);
      final reader = ProcessReader(procRoot: proc.path);

      expect(reader.statOf(3412)!.name, 'firefox');
      expect(reader.statOf(9999), isNull);
    });
  });
}
