// Turning a [CaptureTarget] — what the user picked — into a [CaptureSession],
// which is what the compositor understands.
//
// One file rather than two copies: the screenshot and recorder paths resolve
// identically, and the interesting part is the same decision in both — a window
// is captured through its foreign-toplevel handle when we have one, and by
// cropping its output when we do not. Only the first follows the window as it
// moves, and only the second exists without `ext-foreign-toplevel-list-v1`.

import 'package:graceful_shell/screencast/capture_connection.dart';
import 'package:graceful_shell/screencast/capture_session.dart';

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

  /// The region of each frame to keep, in the *output's local logical* pixels —
  /// null when the session already produces exactly what was asked for.
  ///
  /// Still logical rather than in buffer pixels because the buffer's size is not
  /// known until the first frame arrives; [CaptureRect.scaledInto] converts there.
  final CaptureRect? crop;
}

/// Resolves [target] against the live [connection].
///
/// Throws a [CaptureException] when the source is gone — an output unplugged
/// between the pick and the shutter, or a compositor that never advertised the
/// capture protocol — which is a message worth showing rather than an empty file.
/// Which output it *is* comes from [indexOfCaptureOutput].
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

  final index = indexOfCaptureOutput(
    [
      for (final output in connection.outputs)
        (connector: output.connector ?? '', x: output.x, y: output.y),
    ],
    connector: target.connector,
    origin: target.outputOrigin,
  );
  if (index < 0) throw CaptureException(_unresolvedOutputMessage(target));
  final output = connection.outputs[index];
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

/// Which of [outputs] the target on [connector] — whose top-left corner is
/// [origin], when the shell knows it — is captured from, or -1.
///
/// Split out as a pure function over the two fields that decide it, because
/// everything either side is FFI and this is the half worth pinning.
///
/// Three passes, and the order is the whole of it:
///
/// - **A name answers whenever both sides have one.** That is the ordinary case,
///   and unlike a position it survives the displays being rearranged.
/// - **Failing that, the corner does.** `wl_output.name` is a version 4 event and
///   GDK learns its connector from `xdg-output`, so a compositor missing either
///   leaves one end holding an empty string — and two empty strings are not a
///   match, which is a capture reporting the display as unplugged while the user
///   is looking at it. Two monitors cannot share a corner.
/// - **Failing that, a lone display is the answer**, `resolveOutput`'s rule.
///
/// The last two passes only consider outputs the *name* could not have answered
/// for: a named output that is not the one asked for has already said "not me",
/// so a display genuinely unplugged still resolves to nothing rather than to
/// whichever screen has since taken over its corner.
int indexOfCaptureOutput(
  List<({String connector, int x, int y})> outputs, {
  required String connector,
  CapturePoint? origin,
}) {
  if (connector.isNotEmpty) {
    for (var i = 0; i < outputs.length; i++) {
      if (outputs[i].connector == connector) return i;
    }
  }
  final candidates = <int>[
    for (var i = 0; i < outputs.length; i++)
      if (connector.isEmpty || outputs[i].connector.isEmpty) i,
  ];
  if (origin != null) {
    for (final i in candidates) {
      if (outputs[i].x == origin.x && outputs[i].y == origin.y) return i;
    }
  }
  return candidates.length == 1 ? candidates.first : -1;
}

/// What the user is told when no output answered.
///
/// The unplugged wording is only honest about a display the shell can name;
/// with no name on either side "gone" is a guess, and the sentence says what
/// actually happened instead.
String _unresolvedOutputMessage(CaptureTarget target) =>
    target.connector.isNotEmpty
        ? 'The display ${target.connector} is no longer connected.'
        : 'That capture could not be matched to a connected display.';

/// [target] with its foreign-toplevel handle joined on, when it is a window
/// capture and the compositor can name one for it.
///
/// Called at the shutter rather than at the pick, because a configured delay sits
/// between the two and a handle resolved before it could name a window that has
/// since closed. Everything but a [WindowCapture] is returned unchanged.
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
