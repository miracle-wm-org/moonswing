import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/system/process_killer.dart';
import 'package:moonswing/system/process_reader.dart';

import 'system_process_reader_test.dart' show statLine;

/// Drives every kill outcome against a fake `/proc`, so no test signals anything
/// real.
void main() {
  late Directory proc;

  setUp(() => proc = Directory.systemTemp.createTempSync('process_killer'));
  tearDown(() => proc.deleteSync(recursive: true));

  void writeProcess(int pid, {int starttime = 500}) {
    final dir = Directory('${proc.path}/$pid')..createSync(recursive: true);
    File('${dir.path}/stat').writeAsStringSync(
      statLine(pid: pid, comm: 'victim', starttime: starttime),
    );
  }

  /// [sendResult] is what the fake `kill(2)` returns; [onSend] can mutate the
  /// fake /proc to model the process actually dying.
  ProcessKiller killer({
    bool sendResult = true,
    void Function()? onSend,
    List<(int, ProcessSignal)>? log,
    int selfPid = 999,
  }) {
    return ProcessKiller(
      reader: ProcessReader(procRoot: proc.path),
      selfPid: selfPid,
      send: (pid, signal) {
        log?.add((pid, signal));
        onSend?.call();
        return sendResult;
      },
    );
  }

  test('terminate sends SIGTERM to the right pid', () async {
    writeProcess(3412);
    final log = <(int, ProcessSignal)>[];

    final outcome = await killer(log: log)
        .terminate(3412, expectedStarttimeTicks: 500);

    expect(outcome, KillOutcome.signalled);
    expect(log, [(3412, ProcessSignal.sigterm)]);
  });

  test('forceKill sends SIGKILL', () async {
    writeProcess(3412);
    final log = <(int, ProcessSignal)>[];

    await killer(log: log).forceKill(3412, expectedStarttimeTicks: 500);

    expect(log, [(3412, ProcessSignal.sigkill)]);
  });

  test('a recycled PID is refused without signalling anything', () async {
    // The user clicked kill on PID 3412; by the time they confirmed, it had
    // exited and the kernel had handed 3412 to something else. Signalling now
    // would kill an innocent process.
    writeProcess(3412, starttime: 999);
    final log = <(int, ProcessSignal)>[];

    final outcome = await killer(log: log)
        .terminate(3412, expectedStarttimeTicks: 500);

    expect(outcome, KillOutcome.pidReused);
    expect(log, isEmpty);
  });

  test('a process that already exited reports alreadyGone', () async {
    final outcome =
        await killer().terminate(3412, expectedStarttimeTicks: 500);

    expect(outcome, KillOutcome.alreadyGone);
  });

  test('kill failing with the process still there is a permission problem',
      () async {
    writeProcess(812);

    final outcome = await killer(sendResult: false)
        .terminate(812, expectedStarttimeTicks: 500);

    expect(outcome, KillOutcome.permissionDenied);
  });

  test('kill failing because the process just exited is not an error', () async {
    // killPid returns false for both EPERM and ESRCH and tells us nothing about
    // which. Re-statting is the only way to tell them apart.
    writeProcess(812);

    final outcome = await killer(
      sendResult: false,
      onSend: () => Directory('${proc.path}/812').deleteSync(recursive: true),
    ).terminate(812, expectedStarttimeTicks: 500);

    expect(outcome, KillOutcome.alreadyGone);
  });

  test('killing the shell itself is refused', () async {
    // Signalling our own PID would take every panel, the wallpaper, and the tray
    // down with it.
    writeProcess(999);
    final log = <(int, ProcessSignal)>[];

    final outcome = await killer(log: log, selfPid: 999)
        .terminate(999, expectedStarttimeTicks: 500);

    expect(outcome, KillOutcome.refused);
    expect(log, isEmpty);
  });

  test('killing init is refused', () async {
    writeProcess(1);
    final log = <(int, ProcessSignal)>[];

    final outcome =
        await killer(log: log).terminate(1, expectedStarttimeTicks: 500);

    expect(outcome, KillOutcome.refused);
    expect(log, isEmpty);
  });

  test('isStillRunning distinguishes a survivor from a recycled pid', () {
    writeProcess(3412, starttime: 500);
    final k = killer();

    expect(k.isStillRunning(3412, 500), isTrue);
    expect(k.isStillRunning(3412, 999), isFalse); // same pid, different process
    expect(k.isStillRunning(9999, 500), isFalse); // gone
  });
}
