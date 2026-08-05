import 'capture_connection.dart';
import 'capture_session.dart';
import 'picker_controller.dart';
import 'picker_overlay.dart';
import 'preview.dart';

/// Builds the picker's tiles from the live capture connection.
///
/// Preview sessions are throttled to [previewFps] and are *not* handed over
/// when the user confirms — the portal builds fresh streaming sessions
/// instead, so a session's lifetime never spans the pick. Concurrent sessions
/// on one source are fine (verified against miracle-wm).
({List<PickerSource> monitors, List<PickerSource> windows}) buildPickerSources(
  CaptureConnection connection,
  PickRequest request, {
  int previewFps = 10,
}) {
  final interval = Duration(milliseconds: (1000 / previewFps).round());

  final monitors = <PickerSource>[];
  if (request.monitors) {
    for (final output in connection.outputs) {
      final connector = output.connector;
      if (connector == null || connector.isEmpty) continue;
      monitors.add(PickerSource(
        key: 'monitor:$connector',
        label: connector,
        sublabel: output.width > 0 ? '${output.width} x ${output.height}' : '',
        picked: PickedMonitor(connector),
        frames: CaptureSessionPreviewFrames(() => CaptureSession.forOutput(
              connection,
              output,
              paintCursors: false,
              minFrameInterval: interval,
            )),
      ));
    }
  }

  final windows = <PickerSource>[];
  if (request.windows && connection.windowCaptureSupported) {
    for (final toplevel in connection.toplevels) {
      if (toplevel.identifier.isEmpty) continue;
      windows.add(PickerSource(
        key: 'window:${toplevel.identifier}',
        label: toplevel.title.isEmpty ? toplevel.appId : toplevel.title,
        sublabel: toplevel.appId,
        picked: PickedWindow(toplevel.identifier, toplevel.title),
        frames: CaptureSessionPreviewFrames(() => CaptureSession.forToplevel(
              connection,
              toplevel,
              paintCursors: false,
              minFrameInterval: interval,
            )),
      ));
    }
  }

  return (monitors: monitors, windows: windows);
}
