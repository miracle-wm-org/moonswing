import 'dart:async';

import 'package:dbus/dbus.dart';

import '../pipewire/spa_pod.dart';
import '../pipewire/video_stream.dart';
import 'capture_connection.dart';
import 'capture_host.dart';
import 'capture_session.dart';
import 'pick_types.dart';
import 'portal_frontend.dart';
import 'screencast_log.dart';
import 'screencast_portal.dart';

const String kScreencastBusName =
    'org.freedesktop.impl.portal.desktop.graceful_shell';

ScreencastService? _service;

/// The running service, if screen sharing came up. The picker overlay reads
/// the capture connection off this for previews.
ScreencastService? get screencastService => _service;

/// Starts the ScreenCast portal backend.
///
/// One graceful decline: [kScreencastBusName] already taken means another backend
/// owns it, so this logs and returns. Everything else — PipeWire missing, no
/// display to reach, a compositor without ext-image-copy-capture, a bus or export
/// error — throws, so `ShellServices.run` records the service as failed rather
/// than "ready with screen sharing dead". A `[screenshare] enabled = false`
/// config never reaches here: `main.dart` skips the service.
///
/// [picker] is how consent is obtained — the shell passes
/// `ScreencastPickerController.instance`; the spike tool passes a headless
/// stand-in. There is deliberately no default: a backend that could start without
/// asking would be one that can silently record the screen.
///
/// [attachToGlibLoop] drives the capture connection's event pump from the GTK
/// main loop; the spike tool pumps manually.
///
/// [reconcileFrontend] repairs an xdg-desktop-portal frontend that started before
/// this backend owned its name (see `portal_frontend.dart`). It restarts somebody
/// else's service, so the spike tool passes false.
Future<void> startScreencastService({
  required SourcePicker picker,
  bool attachToGlibLoop = true,
  int maxFrameRate = 0,
  bool reconcileFrontend = true,
}) async {
  if (!PipewireVideoStream.ensureInit()) {
    throw StateError('PipeWire not present');
  }
  // Borrowed, not created: `lib/capture/` binds the same globals for the
  // shell's own screenshots and recordings, and one compositor connection is
  // enough for both. [CaptureHost] owns it for the life of the process, which
  // is also why nothing below disposes it on the way out of here.
  final connection = CaptureHost.connect(attachToGlibLoop: attachToGlibLoop);
  if (connection == null) {
    throw StateError('cannot reach the display');
  }

  DBusClient? client;
  try {
    if (!connection.supported) {
      throw StateError('compositor lacks ext-image-copy-capture '
          '(needs miracle-wm with MirAL >= 5.6)');
    }

    client = DBusClient.session();
    final reply = await client.requestName(kScreencastBusName,
        flags: {DBusRequestNameFlag.doNotQueue});
    if (reply != DBusRequestNameReply.primaryOwner &&
        reply != DBusRequestNameReply.alreadyOwner) {
      // The one graceful decline: yield the name to whoever owns it.
      screencastLog('unavailable: $kScreencastBusName is already taken');
      await client.close();
      return;
    }

    final engine = ShellScreencastEngine(connection, picker,
        maxFrameRate: maxFrameRate, driveWithGlib: attachToGlibLoop);
    final backend = ScreenCastPortalBackend(client, engine);
    await backend.init();
    await client.registerObject(backend);

    // Through the host's fan-out rather than `connection.onDied` directly:
    // that is one callback and there are two features listening now.
    CaptureHost.addDiedListener(backend.closeAllSessions);

    _service = ScreencastService._(connection, client, backend);
    screencastLog('portal backend up as $kScreencastBusName '
        '(windows: ${connection.windowCaptureSupported})');

    // Owning the name is not the same as being *seen*. xdg-desktop-portal caches
    // this backend's `AvailableSourceTypes` when its frontend starts, and the
    // shell claims the name off a post-frame callback — so a frontend that came up
    // first publishes 0 forever, which is invisible to an app that just shares and
    // fatal to one that asks first. See `portal_frontend.dart`.
    //
    // Unawaited on purpose: this backend is already up and serving, and the repair
    // restarts somebody else's service. Holding `ShellService.screencast` on a
    // loader for that would report the shell's own work as unfinished.
    if (reconcileFrontend) {
      final bus = client;
      unawaited(() async {
        try {
          await reconcilePortalFrontend(
            client: bus,
            backendSourceTypes: engine.availableSourceTypes,
          );
        } catch (e) {
          screencastLog('portal frontend reconcile failed: $e');
        }
      }());
    }
  } catch (_) {
    final failedClient = client;
    if (failedClient != null) unawaited(failedClient.close());
    rethrow;
  }
}

class ScreencastService {
  ScreencastService._(this.connection, this._client, this._backend);

  final CaptureConnection connection;
  final DBusClient _client;
  final ScreenCastPortalBackend _backend;

  /// Drives the Wayland connection and every running PipeWire loop by hand.
  /// Only for callers that started the service with `attachToGlibLoop: false`
  /// — inside the shell the GLib main loop does all of this.
  void pumpManually() {
    connection.conn.pumpOnce();
    PipewireVideoStream.iterateManuallyDriven();
  }

  Future<void> dispose() async {
    CaptureHost.removeDiedListener(_backend.closeAllSessions);
    await _backend.dispose();
    await _client.close();
    // Deliberately not `connection.dispose()`: [CaptureHost] owns it and the
    // shell's screenshot and recording features are still using it.
    _service = null;
  }
}

/// The real [ScreencastEngine]: consent via the injected [SourcePicker],
/// streams via [CaptureSession] + [PipewireVideoStream].
class ShellScreencastEngine implements ScreencastEngine {
  ShellScreencastEngine(
    this._connection,
    this._picker, {
    this.maxFrameRate = 0,
    this.driveWithGlib = true,
  });

  final CaptureConnection _connection;
  final SourcePicker _picker;

  /// 0 = follow the output's refresh rate.
  final int maxFrameRate;

  /// False when the caller pumps the PipeWire loops itself.
  final bool driveWithGlib;

  @override
  int get availableSourceTypes => sourceTypeMonitor |
      (_connection.windowCaptureSupported ? sourceTypeWindow : 0);

  @override
  Future<PickResult?> pick(PickRequest request) => _picker.pick(request);

  @override
  void cancelPick() => _picker.cancel();

  @override
  Future<ActiveCast> startCast(
    PickResult picked, {
    required bool paintCursors,
    required void Function() onStopped,
  }) async {
    final cast = _ShellActiveCast(onStopped);
    try {
      for (final source in picked.sources) {
        await cast.addSource(_connection, source,
            paintCursors: paintCursors,
            maxFrameRate: maxFrameRate,
            driveWithGlib: driveWithGlib);
      }
    } catch (e) {
      cast.stop();
      rethrow;
    }
    return cast;
  }
}

class _ShellActiveCast implements ActiveCast {
  _ShellActiveCast(this._onStopped);

  final void Function() _onStopped;
  final List<CaptureSession> _sessions = [];
  final List<PipewireVideoStream> _streams = [];
  final List<PortalStreamInfo> _streamInfos = [];
  bool _stopped = false;

  @override
  List<PortalStreamInfo> get streams => List.unmodifiable(_streamInfos);

  Future<void> addSource(
    CaptureConnection connection,
    PickedSource source, {
    required bool paintCursors,
    required int maxFrameRate,
    bool driveWithGlib = true,
  }) async {
    final CaptureSession session;
    final int sourceType;
    int? x;
    int? y;
    var refresh = 60;

    switch (source) {
      case PickedMonitor(:final connector):
        final output = connection.outputs
            .where((o) => o.connector == connector)
            .firstOrNull;
        if (output == null) {
          throw StateError('monitor $connector is gone');
        }
        session = CaptureSession.forOutput(connection, output,
            paintCursors: paintCursors);
        sourceType = sourceTypeMonitor;
        x = output.x;
        y = output.y;
        if (output.refreshMHz > 0) refresh = (output.refreshMHz / 1000).ceil();
      case PickedWindow(:final identifier):
        final toplevel = connection.toplevelByIdentifier(identifier);
        if (toplevel == null) {
          throw StateError('window $identifier is gone');
        }
        session = CaptureSession.forToplevel(connection, toplevel,
            paintCursors: paintCursors);
        sourceType = sourceTypeWindow;
    }
    _sessions.add(session);

    // The stream can only be created once the capture constraints are known
    // (size + shm format); the first onSizeChanged marks that moment.
    final sized = Completer<(int, int)>();
    PipewireVideoStream? stream;
    session.onSizeChanged = (w, h) {
      if (!sized.isCompleted) {
        sized.complete((w, h));
      } else {
        stream?.updateSize(w, h);
      }
    };
    session.onStopped = (_) => _sourceStopped();
    session.start();

    final (width, height) =
        await sized.future.timeout(const Duration(seconds: 5));
    final spaFormat = spaVideoFormatForShm(session.shmFormat);
    if (spaFormat == null) {
      throw StateError(
          'unmappable shm format 0x${session.shmFormat.toRadixString(16)}');
    }

    stream = PipewireVideoStream(
      width: width,
      height: height,
      spaVideoFormat: spaFormat,
      maxFrameRate: maxFrameRate > 0 ? maxFrameRate : refresh.clamp(1, 240),
      driveWithGlib: driveWithGlib,
    );
    _streams.add(stream);
    final pushTarget = stream;
    session.onFrame = (frame) => pushTarget.pushFrame(frame);
    stream.onError = (_) => _sourceStopped();
    if (!stream.start()) {
      throw StateError('PipeWire stream failed to start');
    }
    final nodeId = await stream.nodeId.timeout(const Duration(seconds: 5));

    _streamInfos.add(PortalStreamInfo(
      nodeId: nodeId,
      sourceType: sourceType,
      width: width,
      height: height,
      x: x,
      y: y,
    ));
  }

  void _sourceStopped() {
    if (_stopped) return;
    // One source dying ends the whole cast — the portal has no way to shrink
    // a running session's stream list.
    _onStopped();
  }

  @override
  void stop() {
    if (_stopped) return;
    _stopped = true;
    for (final s in _sessions) {
      s.dispose();
    }
    _sessions.clear();
    for (final s in _streams) {
      s.dispose();
    }
    _streams.clear();
  }
}
