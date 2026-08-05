// Standalone smoke test for the screencast capture stack. Run inside a
// Wayland session with the ext-image-copy-capture protocols (miracle-wm):
//
//   dart compile exe tool/screencast_spike.dart -o /tmp/spike
//   WAYLAND_DISPLAY=wayland-99 /tmp/spike            # registry + outputs
//   WAYLAND_DISPLAY=wayland-99 /tmp/spike --capture  # + stream 3 frames/output
//
// Compiled `dart` has no Flutter engine, which is why the whole
// lib/screencast + lib/wayland_ffi stack is Flutter-free. Blocking roundtrips
// stand in for the GLib pump. Note the compositor only completes a copy when
// the content changes — wiggle something on screen if --capture stalls.
// WAYLAND_DEBUG=1 shows the wire traffic.

import 'dart:async';
import 'dart:ffi'; // for the Pointer.asTypedList extension
import 'dart:io';

import 'package:graceful_shell/pipewire/spa_pod.dart';
import 'package:graceful_shell/pipewire/video_stream.dart';
import 'package:graceful_shell/screencast/capture_connection.dart';
import 'package:graceful_shell/screencast/capture_session.dart';
import 'package:graceful_shell/screencast/pick_types.dart';
import 'package:graceful_shell/screencast/screencast_log.dart';
import 'package:graceful_shell/screencast/screencast_service.dart';
import 'package:graceful_shell/wayland_ffi/wl_protocols.dart';

Future<void> main(List<String> argv) async {
  screencastLog = say;

  final connection = CaptureConnection.connect(attachToGlibLoop: false);
  if (connection == null) {
    say('FAIL: could not connect to Wayland display');
    exit(1);
  }
  say('connected, fd=${connection.conn.fd}');

  say('outputs:');
  for (final o in connection.outputs) {
    say('  ${o.connector ?? "<no name>"}: ${o.width}x${o.height}'
        '@${o.refreshMHz / 1000}Hz at (${o.x},${o.y}) — ${o.make} ${o.model}');
  }

  connection.conn.roundtrip(); // flush toplevel property batches
  say('toplevels:');
  for (final t in connection.toplevels) {
    say('  "${t.title}" (${t.appId}) id=${t.identifier}');
  }

  if (!connection.supported) {
    say('FAIL: compositor lacks the capture globals');
    exit(1);
  }
  say('capture supported; window capture: ${connection.windowCaptureSupported}');

  if (argv.contains('--capture')) {
    for (final output in connection.outputs) {
      _streamFrames(connection, output);
    }
  }
  if (argv.contains('--multi')) {
    _multiSession(connection, connection.outputs.first);
  }
  if (argv.contains('--pipewire')) {
    await _pipewireStream(connection, connection.outputs.first);
  }
  if (argv.contains('--portal')) {
    connection.dispose();
    await _runPortal(argv);
    return; // _runPortal owns the process from here
  }
  connection.dispose();
  exit(0);
}

/// Runs the real ScreenCast portal backend headlessly: same D-Bus objects,
/// same capture/PipeWire engine, but consent is auto-granted by
/// [_AutoPicker] instead of the layer-shell overlay (which needs a Flutter
/// engine). This is how the portal contract is verified against a real
/// xdg-desktop-portal frontend and a real application.
Future<void> _runPortal(List<String> argv) async {
  final windowsFirst = argv.contains('--prefer-window');
  final slowPick = argv.contains('--slow-pick');
  say('\nstarting ScreenCast portal backend (headless auto-accept)...');
  await startScreencastService(
    picker: _AutoPicker(
      windowsFirst: windowsFirst,
      thinkTime: slowPick ? const Duration(seconds: 5) : Duration.zero,
    ),
    attachToGlibLoop: false,
  );
  final service = screencastService;
  if (service == null) {
    say('FAIL: service did not start');
    exit(1);
  }
  say('bus name: $kScreencastBusName — Ctrl-C to stop');

  // No GLib loop here, so the Wayland connection and every PipeWire loop are
  // pumped by hand. The interval doubles as the frame cadence.
  Timer.periodic(const Duration(milliseconds: 8), (_) => service.pumpManually());
  await Completer<void>().future; // run until killed
}

/// Grants every request, choosing the first available source of the
/// requested kind. Stands in for the picker overlay in headless runs.
///
/// [thinkTime] leaves the pick outstanding for a while, which is what makes
/// the `Request.Close` cancellation path observable — with an instant answer
/// the Request object is already gone by the time a client can close it.
class _AutoPicker implements SourcePicker {
  _AutoPicker({this.windowsFirst = false, this.thinkTime = Duration.zero});

  final bool windowsFirst;
  final Duration thinkTime;
  Completer<PickResult?>? _pending;

  @override
  Future<PickResult?> pick(PickRequest request) async {
    say('  pick requested by "${request.appId}" '
        '(monitors=${request.monitors} windows=${request.windows} '
        'multiple=${request.multiple})');

    if (thinkTime > Duration.zero) {
      final pending = Completer<PickResult?>();
      _pending = pending;
      Timer(thinkTime, () {
        if (!pending.isCompleted) pending.complete(_choose(request));
      });
      final answer = await pending.future;
      _pending = null;
      return answer;
    }
    return _choose(request);
  }

  /// Picks the first source of a requested kind. `--prefer-window` only
  /// changes the *order*: a request for windows alone must still be answered
  /// with a window, or the harness would report a refusal the backend never
  /// made.
  PickResult? _choose(PickRequest request) {
    final connection = screencastService!.connection;

    PickResult? window() {
      if (!request.windows) return null;
      final toplevel =
          connection.toplevels.where((t) => t.identifier.isNotEmpty).firstOrNull;
      if (toplevel == null) return null;
      say('  auto-picking window "${toplevel.title}"');
      return PickResult([PickedWindow(toplevel.identifier, toplevel.title)]);
    }

    PickResult? monitor() {
      if (!request.monitors) return null;
      final output =
          connection.outputs.where((o) => (o.connector ?? '').isNotEmpty).firstOrNull;
      if (output == null) return null;
      say('  auto-picking monitor ${output.connector}');
      return PickResult([PickedMonitor(output.connector!)]);
    }

    final result =
        windowsFirst ? (window() ?? monitor()) : (monitor() ?? window());
    if (result == null) say('  nothing to pick');
    return result;
  }

  @override
  void cancel() {
    say('  pick cancelled by the portal');
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete(null);
  }
}

/// Full M2 path: capture → PipeWire video stream. Prints the node id (feed
/// it to `gst-launch-1.0 pipewiresrc path=<id> ! ...` to verify) and pushes
/// frames for ~20 seconds.
Future<void> _pipewireStream(
    CaptureConnection connection, WlOutputFfi output) async {
  say('\npipewire stream from ${output.connector}...');
  PipewireVideoStream? stream;
  var pushed = 0;
  var stopped = false;

  final session = CaptureSession.forOutput(connection, output);
  session.onSizeChanged = (w, h) {
    if (stream != null) {
      stream!.updateSize(w, h);
      return;
    }
    final spaFormat = spaVideoFormatForShm(session.shmFormat);
    if (spaFormat == null) {
      say('  FAIL: unmappable shm format ${session.shmFormat}');
      stopped = true;
      return;
    }
    stream = PipewireVideoStream(
      width: w,
      height: h,
      spaVideoFormat: spaFormat,
      maxFrameRate: (output.refreshMHz / 1000).round().clamp(1, 240),
      driveWithGlib: false,
    );
    if (!stream!.start()) {
      say('  FAIL: stream did not start');
      stopped = true;
    }
  };
  session.onFrame = (frame) {
    if (stream?.pushFrame(frame) ?? false) pushed++;
  };
  session.onStopped = (reason) {
    stopped = true;
    say('  capture stopped: $reason');
  };
  session.start();

  int? announcedNode;
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!stopped && DateTime.now().isBefore(deadline)) {
    connection.conn.roundtrip();
    stream?.iterate();
    if (announcedNode == null && stream?.nodeIdSync != null) {
      announcedNode = stream!.nodeIdSync;
      say('  NODE_ID=$announcedNode');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  say(pushed > 0
      ? '  OK: pushed $pushed frames to PipeWire'
      : '  NOTE: 0 frames pushed (no consumer connected or no damage)');
  session.dispose();
  stream?.dispose();
  connection.conn.roundtrip();
}

void _streamFrames(CaptureConnection connection, WlOutputFfi output) {
  say('\nstreaming from ${output.connector}...');
  var frames = 0;
  var stopped = false;
  final session = CaptureSession.forOutput(connection, output);
  session.onFrame = (frame) {
    frames++;
    final bytes = frame.data.asTypedList(frame.sizeBytes);
    var nonZero = 0;
    for (var i = 0; i < frame.sizeBytes; i += 4097) {
      if (bytes[i] != 0) nonZero++;
    }
    say('  frame $frames: ${frame.width}x${frame.height} '
        'format=0x${frame.shmFormat.toRadixString(16)} '
        't=${frame.presentationTimeNs} '
        '$nonZero/${frame.sizeBytes ~/ 4097} sampled bytes non-zero');
  };
  session.onStopped = (reason) {
    stopped = true;
    say('  stopped: $reason');
  };
  session.onSizeChanged = (w, h) => say('  size changed: ${w}x$h');
  session.start();

  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (frames < 3 && !stopped && DateTime.now().isBefore(deadline)) {
    connection.conn.roundtrip();
    sleep(const Duration(milliseconds: 30));
  }
  say(frames >= 3 ? '  OK: $frames frames' : '  FAIL: only $frames frames');
  session.dispose();
  connection.conn.roundtrip();
}

/// Two concurrent sessions on one output — the picker shows previews of
/// every monitor while a stream may already be running, so the compositor
/// must tolerate N sessions per source.
void _multiSession(CaptureConnection connection, WlOutputFfi output) {
  say('\ntwo concurrent sessions on ${output.connector}...');
  final counts = [0, 0];
  var stopped = 0;
  final sessions = [
    for (var i = 0; i < 2; i++)
      CaptureSession.forOutput(connection, output)
        ..onStopped = ((reason) {
          stopped++;
          say('  session stopped: $reason');
        })
  ];
  for (var i = 0; i < 2; i++) {
    sessions[i].onFrame = (frame) => counts[i]++;
    sessions[i].start();
  }
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while ((counts[0] < 2 || counts[1] < 2) &&
      stopped == 0 &&
      DateTime.now().isBefore(deadline)) {
    connection.conn.roundtrip();
    sleep(const Duration(milliseconds: 30));
  }
  say(counts[0] >= 2 && counts[1] >= 2
      ? '  OK: both sessions streamed (${counts[0]}, ${counts[1]})'
      : '  FAIL: counts=$counts stopped=$stopped');
  for (final s in sessions) {
    s.dispose();
  }
  connection.conn.roundtrip();
}

/// stderr is unbuffered — survives the process being killed mid-hang.
void say(Object? message) => stderr.writeln(message);
