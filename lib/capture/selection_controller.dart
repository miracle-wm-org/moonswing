// The seam between a bar module (which is three levels inside a panel's widget
// tree and cannot create a window) and `_GracefulShellRootState` (which owns
// every window the shell has).
//
// [RequestController]'s three rules are the ones that matter here, and the
// first is the reason this is that shape rather than a [SignalController]:
// **no listener means an immediate decline**, so a headless run or a widget
// test never awaits a selection surface that will not appear. The other two
// come free and are both right for this: a second selection supersedes the
// first as cancelled (two full-screen selection surfaces have no defined focus
// order), and teardown answers whoever was awaiting.

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/request_controller.dart';

import 'capture_targets.dart';

export 'capture_targets.dart';

/// Whether the selection is for a still capture or a recording.
///
/// It reaches the selection surface only to word its instructions and colour
/// its rim — nothing about *picking* differs between the two — but that is
/// worth carrying: a full-screen surface that has taken over the pointer
/// should say which of the two the user is about to do.
enum CaptureKind {
  screenshot('Screenshot'),
  video('Recording');

  const CaptureKind(this.label);

  final String label;
}

/// How the user is being asked to choose.
enum SelectionMode {
  /// Drag a rectangle out on one output.
  area('Select an area', 'Drag to select an area'),

  /// Point at a window and click it.
  window('Select a window', 'Click a window to select it'),

  /// Click anywhere on the output to take all of it.
  output('Select a screen', 'Click a screen to select it');

  const SelectionMode(this.label, this.instruction);

  /// The menu row's wording.
  final String label;

  /// What the selection surface tells the user to do.
  final String instruction;
}

/// What the root is being asked for.
class SelectionRequest {
  const SelectionRequest({required this.kind, required this.mode});

  final CaptureKind kind;
  final SelectionMode mode;
}

/// Asks the root to put a selection surface on every output and answers with
/// what the user picked, or null when they backed out.
class CaptureSelectionController
    extends RequestController<SelectionRequest, CaptureTarget> {
  CaptureSelectionController._();

  static final CaptureSelectionController instance =
      CaptureSelectionController._();

  @visibleForTesting
  factory CaptureSelectionController.forTesting() =>
      CaptureSelectionController._();

  /// Called by the selection surface on Escape, a right-click, or an empty
  /// drag, and by the root when the surfaces come down unanswered. A dismissal
  /// is a *cancellation*, not a capture of everything.
  void cancel() => complete(null);
}
