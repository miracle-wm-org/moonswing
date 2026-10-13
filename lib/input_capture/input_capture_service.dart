import 'dart:async';

import '../portal_bus.dart';
import 'capture_controller.dart';
import 'consent_types.dart';
import 'eis_ffi.dart';
import 'eis_server.dart';
import 'input_capture_connection.dart';
import 'input_capture_log.dart';
import 'input_capture_portal.dart';
import 'wayland_capture_surfaces.dart';

InputCaptureService? _service;

/// The running service, if input capture came up.
InputCaptureService? get inputCaptureService => _service;

/// Starts the InputCapture portal backend.
///
/// One graceful decline, ScreenCast's: the shared backend name already owned by
/// somebody else. Everything else throws, so `ShellServices.run` records the
/// feature as failed with the reason — no libeis (the package is `libeis1`), no
/// display, or a compositor missing one of the protocols capture is built from
/// (`input_capture_connection.dart` says which and why).
///
/// [consent] is how the user is asked: the shell passes
/// `InputCaptureConsentController.instance`, the spike tool a stand-in that
/// says yes. Required, for the reason `startScreencastService`'s picker is.
///
/// [attachToGlibLoop] drives the Wayland connection and every libeis context
/// from the GTK main loop; the spike tool pumps by hand.
Future<void> startInputCaptureService({
  required InputCaptureConsent consent,
  bool attachToGlibLoop = true,
}) async {
  if (EisFfi.instance == null) {
    throw StateError('libeis is not installed (package libeis1)');
  }
  final connection =
      InputCaptureConnection.connect(attachToGlibLoop: attachToGlibLoop);
  if (connection == null) throw StateError('cannot reach the display');
  final missing = connection.missing;
  if (missing != null) {
    connection.dispose();
    throw StateError('the compositor does not offer $missing');
  }

  final PortalBus? bus;
  try {
    bus = await PortalBus.acquire();
  } catch (_) {
    connection.dispose();
    rethrow;
  }
  if (bus == null) {
    inputCaptureLog('unavailable: $kPortalBusName is already taken');
    connection.dispose();
    return;
  }

  InputCapturePortalBackend? served;
  try {
    final surfaces = WaylandCaptureSurfaces(connection);
    final controller = CaptureController(
      surfaces: surfaces,
      eisFactory: (capabilities, appId) => EisServer.create(
        capabilities: capabilities,
        name: appId.isEmpty ? 'an unsandboxed application' : appId,
        attachToGlibLoop: attachToGlibLoop,
      ),
    );
    surfaces.controller = controller;
    controller.updateZones(surfaces.currentZones());

    final backend = InputCapturePortalBackend(
      bus.client,
      controller,
      consent,
      emitSignal: bus.emitSignal,
    );
    await backend.init();
    bus.serve(backend);
    served = backend;

    final service =
        InputCaptureService._(connection, surfaces, controller, bus, backend);
    connection.onDied = service._onConnectionDied;
    _service = service;
    inputCaptureLog('portal backend up as $kPortalBusName '
        '(zones: ${controller.zones})');
  } catch (_) {
    final part = served;
    unawaited(part != null ? bus.withdraw(part) : bus.release());
    connection.dispose();
    rethrow;
  }
}

class InputCaptureService {
  InputCaptureService._(this._connection, this._surfaces, this.controller,
      this._bus, this._backend);

  final InputCaptureConnection _connection;
  final WaylandCaptureSurfaces _surfaces;
  final CaptureController controller;
  final PortalBus _bus;
  final InputCapturePortalBackend _backend;

  bool _dead = false;

  /// Every capture ends and every barrier goes; the backend stays on the bus,
  /// answering with an empty zone list, so an application learns from
  /// `ZonesChanged` rather than from a backend that vanished.
  void _onConnectionDied() {
    if (_dead) return;
    _dead = true;
    inputCaptureLog('input-capture Wayland connection lost');
    controller.connectionLost();
  }

  /// Pumps the Wayland connection and every EI socket by hand — only for a
  /// caller that started the service with `attachToGlibLoop: false`.
  void pumpManually() {
    if (!_dead) _connection.conn.pumpOnce();
    for (final endpoint in controller.endpoints.toList()) {
      endpoint.dispatch();
    }
  }

  Future<void> dispose() async {
    await _backend.dispose();
    controller.dispose();
    _surfaces.dispose();
    _connection.dispose();
    await _bus.withdraw(_backend);
    _service = null;
  }
}
