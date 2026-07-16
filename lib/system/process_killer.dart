import 'dart:io';

import 'package:graceful_shell/system/models.dart';
import 'package:graceful_shell/system/process_reader.dart';

enum KillOutcome {
  /// The signal was delivered. Whether the process honours it is up to it.
  signalled,

  /// The process had already exited before we signalled.
  alreadyGone,

  /// The PID is now a *different* process than the one the user asked to kill.
  /// Nothing was signalled.
  pidReused,

  /// Not ours to kill (a root-owned process, typically).
  permissionDenied,

  /// Killing it would take the shell or the init system down with it.
  refused,
}

/// Sends signals to processes, with the three guards that make it safe to wire
/// a kill button to a desktop shell.
///
/// The `send` and `statOf` seams exist so tests can drive every outcome without
/// signalling anything real.
class ProcessKiller {
  ProcessKiller({
    ProcessReader? reader,
    bool Function(int pid, ProcessSignal signal)? send,
    int? selfPid,
  })  : _reader = reader ?? ProcessReader(),
        _send = send ?? ((pid, signal) => Process.killPid(pid, signal)),
        _selfPid = selfPid ?? pid;

  final ProcessReader _reader;
  final bool Function(int, ProcessSignal) _send;
  final int _selfPid;

  /// Asks a process to exit.
  ///
  /// [expectedStarttimeTicks] is the identity check. Between the table
  /// rendering a row and the user confirming the kill — and, worse, between a
  /// SIGTERM and a later SIGKILL — the target can exit and the kernel can
  /// recycle its PID onto something else. Signalling by PID alone would then
  /// kill an innocent process, so a start-time mismatch refuses outright.
  Future<KillOutcome> terminate(int pid, {required int expectedStarttimeTicks}) =>
      _signal(pid, expectedStarttimeTicks, ProcessSignal.sigterm);

  /// Kills a process outright. Only reachable after a SIGTERM has been ignored
  /// and the user has confirmed a second time — see the note on escalation in
  /// the kill confirmation UI.
  Future<KillOutcome> forceKill(int pid, {required int expectedStarttimeTicks}) =>
      _signal(pid, expectedStarttimeTicks, ProcessSignal.sigkill);

  /// Whether the process is still alive and still the same process.
  bool isStillRunning(int pid, int expectedStarttimeTicks) {
    final now = _reader.statOf(pid);
    return now != null && now.starttimeTicks == expectedStarttimeTicks;
  }

  Future<KillOutcome> _signal(
    int pid,
    int expectedStarttimeTicks,
    ProcessSignal signal,
  ) async {
    // Killing our own process takes the whole desktop shell down — every panel,
    // the wallpaper, the tray. PID 1 takes the machine down. Neither is ever
    // what the user meant, so the refusal lives here rather than in the UI,
    // where it could be bypassed.
    if (pid == _selfPid || pid <= 1) return KillOutcome.refused;

    final ProcessRaw? before = _reader.statOf(pid);
    if (before == null) return KillOutcome.alreadyGone;
    if (before.starttimeTicks != expectedStarttimeTicks) {
      return KillOutcome.pidReused;
    }

    if (_send(pid, signal)) return KillOutcome.signalled;

    // killPid returns false for both EPERM and ESRCH and gives us no way to
    // tell them apart. Re-stat: if the process is gone it exited on its own; if
    // it is still there, the kernel refused us.
    return _reader.statOf(pid) == null
        ? KillOutcome.alreadyGone
        : KillOutcome.permissionDenied;
  }
}
