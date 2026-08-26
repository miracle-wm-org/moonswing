// Ask, wait for the surfaces to go, then capture.
//
// The middle step is the one worth a file. `CaptureSelectionController` is
// answered the moment the root has *asked* for its selection surfaces to be
// torn down, and a layer-shell surface is not gone when its controller is
// destroyed — `WindowTeardown` waits for Flutter to let go of the view and the
// compositor then has to recomposite the output without it. Firing the shutter
// on the same turn photographs the dimmed selection surface, complete with its
// own rectangle and banner, which is the single most obvious way this feature
// could be wrong.
//
// So there is a settle. It is deliberately a fixed wait rather than something
// cleverer: nothing in the stack reports "that surface is off the screen now"
// — no frame callback, no protocol event, nothing the shell can subscribe to —
// so the alternatives are a wait or a guess dressed up as a signal.

import 'dart:async';

import 'capture_store.dart';
import 'selection_controller.dart';

/// How long the shell waits between the selection surfaces coming down and the
/// capture starting.
///
/// Long enough for the compositor to have recomposited the output without
/// them, short enough that the shutter still feels like it belongs to the
/// click. A recording pays it too — its first frames would otherwise open on
/// the selector.
const Duration kSelectorSettleDelay = Duration(milliseconds: 250);

/// Runs one capture end to end: put the selection surfaces up, wait for an
/// answer, and act on it.
///
/// Returns when the still capture has been written, or when the recording has
/// started — a recording's own end is [CaptureStore.stopRecording]. A
/// cancelled selection returns having done nothing at all.
Future<void> runCaptureFlow(
  CaptureKind kind,
  SelectionMode mode, {
  CaptureStore? store,
  CaptureSelectionController? controller,
  Duration settle = kSelectorSettleDelay,
}) async {
  final selection = controller ?? CaptureSelectionController.instance;
  final target =
      await selection.pick(SelectionRequest(kind: kind, mode: mode));
  if (target == null) return;

  await Future<void>.delayed(settle);

  final captures = store ?? CaptureStore.instance;
  switch (kind) {
    case CaptureKind.screenshot:
      await captures.capture(target);
    case CaptureKind.video:
      await captures.startRecording(target);
  }
}
