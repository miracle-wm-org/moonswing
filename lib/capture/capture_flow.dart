// Ask, wait for the surfaces to go, then capture.
//
// The middle step is the one worth a file. `CaptureSelectionController` is
// answered the moment the root has *asked* for its selection surfaces to be torn
// down, and a layer-shell surface is not gone when its controller is destroyed —
// `WindowTeardown` waits for Flutter to let go of the view, and the compositor
// then has to recomposite the output without it. Firing the shutter on the same
// turn photographs the dimmed selection surface, rectangle and banner included.
//
// So there is a settle, deliberately a fixed wait: nothing in the stack reports
// "that surface is off the screen now", so the alternatives are a wait or a guess
// dressed up as a signal.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'capture_store.dart';
import 'selection_controller.dart';
import 'window_targets.dart';

/// How long the shell waits between the selection surfaces coming down and the
/// capture starting.
///
/// Long enough for the compositor to have recomposited the output without them,
/// short enough that the shutter still feels like it belongs to the click. A
/// recording pays it too — its first frames would otherwise open on the selector.
const Duration kSelectorSettleDelay = Duration(milliseconds: 250);

/// Runs one capture end to end: put the selection surfaces up, wait for an
/// answer, and act on it.
///
/// Returns when the still capture has been written, or when the recording has
/// started — a recording's own end is [CaptureStore.stopRecording]. A cancelled
/// selection returns having done nothing.
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

/// The screen-recording shortcut: start recording the screen the user is on, or
/// stop the recording that is already running.
///
/// A toggle, unlike every other way into [runCaptureFlow], and deliberately so:
/// a recording is the one thing the shell can be doing that the user cannot
/// see, and a key that could only ever start one would leave a shell with no
/// recorder module in its bar no way of ending it. A recording that is still
/// closing its file answers the same way — [CaptureStore.stopRecording] is a
/// no-op then, which is the right no-op: it is what stops a second press
/// during the encode from opening a second recording behind the first.
///
/// "The screen the user is on" is the output holding miracle's focused
/// workspace. A shell that cannot ask — no connection, a tree that will not
/// parse, a compositor that named no focused workspace — falls back to the
/// selection surface rather than guessing at a display, which is the same
/// choice [CaptureScene.empty] makes one layer down.
Future<void> runScreenRecordingShortcut({
  CaptureStore? store,
  CaptureSelectionController? controller,
  Duration settle = kSelectorSettleDelay,
}) async {
  final captures = store ?? CaptureStore.instance;
  if (captures.recording || captures.stopping) {
    await captures.stopRecording();
    return;
  }

  final screen = await _focusedScreen(captures);
  if (screen == null) {
    await runCaptureFlow(
      CaptureKind.video,
      SelectionMode.output,
      store: captures,
      controller: controller,
      settle: settle,
    );
    return;
  }

  // No settle: nothing of the shell's went up to be photographed, so the
  // recording opens on the screen as it already is.
  await captures.startRecording(OutputCapture(
    connector: screen.name,
    outputSize: screen.size,
    outputOrigin: CapturePoint(screen.rect.x, screen.rect.y),
  ));
}

/// The output the user is working on, or null when the shell cannot tell.
///
/// Never throws: a `GET_TREE` that fails costs the shortcut its aim and
/// nothing else, and the caller then asks the user instead.
Future<ScreenOutput?> _focusedScreen(CaptureStore store) async {
  try {
    final tree = await store.readTree();
    return tree == null ? null : focusedOutput(tree);
  } catch (error) {
    debugPrint('capture: could not read the window tree: $error');
    return null;
  }
}
