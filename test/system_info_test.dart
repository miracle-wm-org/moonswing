import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/system/input_devices.dart';
import 'package:graceful_shell/system/proc_reader.dart';
import 'package:graceful_shell/system/system_info.dart';

/// A fake `/proc` and `/etc` in a temp directory, a fake environment map, and a
/// fake process runner, so no test reads the real machine.
void main() {
  late Directory proc;
  late Directory etc;

  setUp(() {
    proc = Directory.systemTemp.createTempSync('system_info_proc');
    etc = Directory.systemTemp.createTempSync('system_info_etc');
  });

  tearDown(() {
    proc.deleteSync(recursive: true);
    etc.deleteSync(recursive: true);
  });

  void writeProc(String path, String contents) {
    final file = File('${proc.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  Future<ProcessResult> Function(String, List<String>) runnerReturning(
    Map<String, String> byExecutable,
  ) {
    return (executable, args) async {
      final out = byExecutable[executable];
      if (out == null) return ProcessResult(0, 1, '', 'not found');
      return ProcessResult(0, 0, out, '');
    };
  }

  SystemInfoReader reader({
    Map<String, String>? env,
    Future<ProcessResult> Function(String, List<String>)? runner,
  }) {
    return SystemInfoReader(
      procRoot: proc.path,
      etcRoot: etc.path,
      // The input-device roots are pointed at the fakes too, or the reader
      // would walk the real machine's `/sys/class/video4linux` and the test
      // would pass or fail by whether the runner has a webcam.
      sysRoot: proc.path,
      env: env ?? const {},
      proc: ProcReader(procRoot: proc.path, sysRoot: proc.path),
      runner: runner ?? (_, _) async => ProcessResult(0, 1, '', ''),
    );
  }

  group('SystemInfoReader.read', () {
    test('resolves every field from its source', () async {
      writeProc('sys/kernel/hostname', 'gracebox\n');
      writeProc('sys/kernel/osrelease', '6.8.0-generic\n');
      writeProc('cpuinfo', 'model name : Test CPU X1\nprocessor : 0\n');
      writeProc('stat', 'cpu 1 0 0 0\ncpu0 1 0 0 0\nbtime 1700000000\n');
      writeProc('meminfo', 'MemTotal: 16384000 kB\nSwapTotal: 2048000 kB\n');
      writeProc('uptime', '3600.0 1000.0\n');
      writeProc(
        'bus/input/devices',
        'N: Name="Logitech USB Receiver Mouse"\n'
            'H: Handlers=mouse1 event8\n'
            'B: PROP=0\n'
            'B: EV=17\n'
            'B: KEY=ffff0000 0 0 0 0\n',
      );
      File('${etc.path}/os-release')
          .writeAsStringSync('PRETTY_NAME="Test Linux 42"\nID=test\n');

      final info = await reader(
        env: const {
          'XDG_CURRENT_DESKTOP': 'Miracle',
          'XDG_SESSION_TYPE': 'wayland',
          'SHELL': '/bin/bash',
        },
        runner: runnerReturning({
          'uname': 'x86_64\n',
          'lspci': '01:00.0 VGA compatible controller: Test GPU 3000\n',
        }),
      ).read();

      expect(info.hostname, 'gracebox');
      expect(info.kernel, '6.8.0-generic');
      expect(info.cpuModel, 'Test CPU X1');
      expect(info.cpuCores, '1');
      expect(info.totalMemory, isNotNull);
      expect(info.totalSwap, isNotNull);
      expect(info.osName, 'Test Linux 42');
      expect(info.architecture, 'x86_64');
      expect(info.gpu, 'Test GPU 3000');
      expect(info.desktop, 'Miracle');
      expect(info.sessionType, 'wayland');
      expect(info.shell, '/bin/bash');
      expect(info.uptime, isNotNull);
      expect(info.bootTime, isNotNull);
      expect(
        info.inputDevices,
        const [
          InputDevice(
            kind: InputDeviceKind.mouse,
            name: 'Logitech USB Receiver Mouse',
          ),
        ],
      );
    });

    test('every field is null when nothing is available', () async {
      final info = await reader().read();

      expect(info.hostname, isNull);
      expect(info.kernel, isNull);
      expect(info.cpuModel, isNull);
      expect(info.cpuCores, isNull);
      expect(info.totalMemory, isNull);
      expect(info.totalSwap, isNull);
      expect(info.osName, isNull);
      expect(info.architecture, isNull);
      expect(info.gpu, isNull);
      expect(info.desktop, isNull);
      expect(info.sessionType, isNull);
      expect(info.shell, isNull);
      expect(info.uptime, isNull);
      expect(info.bootTime, isNull);
      expect(info.inputDevices, isEmpty);
    });

    test('a non-zero command exit leaves the field null', () async {
      final info = await reader(
        runner: (_, _) async => ProcessResult(0, 2, 'garbage', 'boom'),
      ).read();

      expect(info.architecture, isNull);
      expect(info.gpu, isNull);
    });
  });

  group('parseOsReleasePrettyName', () {
    test('strips double quotes', () {
      expect(
        parseOsReleasePrettyName('ID=arch\nPRETTY_NAME="Arch Linux"\n'),
        'Arch Linux',
      );
    });

    test('handles an unquoted value', () {
      expect(parseOsReleasePrettyName('PRETTY_NAME=Debian\n'), 'Debian');
    });

    test('returns null when absent', () {
      expect(parseOsReleasePrettyName('ID=void\n'), isNull);
    });
  });

  group('parseLspciGpu', () {
    test('takes the description after a VGA controller line', () {
      const out = '00:02.0 Host bridge: Intel Corp\n'
          '01:00.0 VGA compatible controller: NVIDIA GeForce RTX 4090\n';
      expect(parseLspciGpu(out), 'NVIDIA GeForce RTX 4090');
    });

    test('matches a 3D controller when there is no VGA line', () {
      expect(
        parseLspciGpu('02:00.0 3D controller: NVIDIA A100\n'),
        'NVIDIA A100',
      );
    });

    test('returns null when no display adapter is present', () {
      expect(parseLspciGpu('00:1f.0 ISA bridge: Intel Corp\n'), isNull);
    });
  });
}
