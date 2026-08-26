// Turning a [CaptureTarget] — which is what the user picked — into a
// [CaptureSession], which is what the compositor understands.
//
// One file rather than two copies, because the screenshot path and the
// recorder path resolve identically and the *interesting* part is the same
// decision in both: a window is captured through its foreign-toplevel handle
// when we have one, and by cropping its output when we do not. Only the first
// follows the window as it moves, and only the second exists on a compositor
// without `ext-foreign-toplevel-list-v1`.

import 'package:graceful_shell/screencast/capture_connection.dart';
import 'package:graceful_shell/screencast/capture_session.dart';
import 'package:graceful_shell/wayland_ffi/wl_protocols.dart';

import 'capture_targets.dart';
import 'toplevel_match.dart';

/// A capture that could not be set up or could not finish, with a sentence the
/// user is shown.
class CaptureException implements Exception {
  const CaptureException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// How to open sessions on one target.
class CaptureSource {
  const CaptureSource({required this.open, required this.crop});

  /// Opens a session. [minFrameInterval] is the preview/recorder throttle;
  /// null streams as fast as the compositor produces.
  final CaptureSession Function({Duration? minFrameInterval}) open;

  /// The region of each frame to keep, in the *output's local logical* pixels
  /// — null when the session already produces exactly what was asked for
  /// (a whole output, or a window captured through its own handle).
  ///
  /// It is still logical rather than in buffer pixels because the buffer's
  /// size is not known until the first frame arrives;
  /// [CaptureRect.scaledInto] converts it there.
  final CaptureRect? crop;
}

/// Resolves [target] against the live [connection].
///
/// Throws a [CaptureException] when the source is gone — an output unplugged
/// between the pick and the shutter, or a compositor that never advertised the
/// capture protocol at all. That is a message worth showing rather than an
/// empty file.
CaptureSource resolveCaptureSource(
  CaptureConnection connection,
  CaptureTarget target, {
  required bool paintCursors,
}) {
  if (!connection.supported) {
    throw const CaptureException(
        'This compositor does not support screen capture '
        '(needs miracle-wm with MirAL >= 5.6).');
  }

  final identifier = target.toplevelIdentifier;
  if (identifier != null && connection.windowCaptureSupported) {
    final handle = connection.toplevelByIdentifier(identifier);
    if (handle != null) {
      return CaptureSource(
        open: ({Duration? minFrameInterval}) => CaptureSession.forToplevel(
          connection,
          handle,
          paintCursors: paintCursors,
          minFrameInterval: minFrameInterval,
        ),
        // Nothing to crop: the session is the window.
        crop: null,
      );
    }
    // The window closed between the pick and here, or the match named a
    // handle the list has since dropped. Falling through to the output crop
    // is the same degradation a compositor with no toplevel list gets.
  }

  final output = _outputNamed(connection, target.connector);
  if (output == null) {
    throw CaptureException(
        'The display ${target.connector} is no longer connected.');
  }
  return CaptureSource(
    open: ({Duration? minFrameInterval}) => CaptureSession.forOutput(
      connection,
      output,
      paintCursors: paintCursors,
      minFrameInterval: minFrameInterval,
    ),
    crop: target.crop,
  );
}

WlOutputFfi? _outputNamed(CaptureConnection connection, String connector) {
  for (final output in connection.outputs) {
    if (output.connector == connector) return output;
  }
  return null;
}

/// [target] with its foreign-toplevel handle joined on, when it is a window
/// capture and the compositor can name one for it.
///
/// Called as late as possible — at the shutter rather than at the pick —
/// because the delay a screenshot may be configured with sits between the two,
/// and a handle resolved before it could name a window that has since closed.
/// Everything but a [WindowCapture] is returned unchanged.
CaptureTarget withToplevelIdentifier(
  CaptureConnection connection,
  CaptureTarget target,
) {
  if (target is! WindowCapture) return target;
  if (!connection.windowCaptureSupported) return target;
  final identifier = matchToplevel(
    [
      for (final toplevel in connection.toplevels)
        ToplevelDescriptor(
          identifier: toplevel.identifier,
          appId: toplevel.appId,
          title: toplevel.title,
        ),
    ],
    appId: target.appId,
    title: target.title,
  );
  return identifier == null ? target : target.withToplevelIdentifier(identifier);
}
