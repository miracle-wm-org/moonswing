// The windowing environment as the selection overlay needs it: where every
// visible window is, and where every output is, in one global logical space.
//
// miracle's `GET_TREE` read a second way. `modules/workspace_apps.dart` walks the
// same reply for *which* applications are on a workspace; this one wants *where*
// each window is, because a window picker that cannot draw a rectangle around
// what the pointer is over is a list rather than a picker.
//
// The walk is deliberately explicit about outputs rather than a flat
// `whereType<ContainerNode>()`: a window has to be attributed to the output it is
// on, since that is the surface the capture comes from.

import 'package:miracle/miracle.dart';

import 'package:moonswing/modules/workspace_apps.dart' show containerAppId;

import 'capture_targets.dart';

/// One connected output, in global logical coordinates.
class ScreenOutput {
  const ScreenOutput({required this.name, required this.rect});

  /// `wl_output.name` — the connector, and the identity every layer of this
  /// feature keys on.
  final String name;

  final CaptureRect rect;

  CaptureSize get size => rect.size;

  @override
  String toString() => 'ScreenOutput($name, $rect)';
}

/// One window the user can point at, in global logical coordinates.
class SelectableWindow {
  const SelectableWindow({
    required this.id,
    required this.rect,
    required this.title,
    required this.appId,
    required this.output,
  });

  /// miracle's container id. Stable for the life of the window, and the key
  /// the overlay uses for "is the pointer still over the same one".
  final int id;

  final CaptureRect rect;
  final String title;
  final String appId;

  /// The connector of the output this window is on.
  final String output;

  @override
  String toString() => 'SelectableWindow($id, $appId, $rect)';
}

/// Every active output in [tree].
///
/// An output with no area is dropped rather than returned empty: it is disabled
/// or mid-reconfiguration, and a zero-sized rectangle would make every hit test
/// against it answer false while still offering the user a screen to pick.
List<ScreenOutput> collectOutputs(BaseNode tree) => [
      for (final output in tree.outputs)
        if (output.active && !_rectOf(output.rect).isEmpty)
          ScreenOutput(name: output.name, rect: _rectOf(output.rect)),
    ];

/// Every window on a *visible* workspace of an active output, back to front.
///
/// Three filters, each the difference between a usable picker and a confusing
/// one. Only visible workspaces, or the list carries every window ever opened on
/// every workspace. Only containers with an `app_id` ([containerAppId], which
/// also covers XWayland's `window_properties.class`), or the split containers
/// holding them come back as windows of their own. And only non-empty rectangles,
/// because a window mid-map reports none.
///
/// Order is the tree's own, which puts a workspace's floating children after its
/// tiled ones — so later is nearer the front, which [windowAt] relies on.
List<SelectableWindow> collectWindows(BaseNode tree) {
  final windows = <SelectableWindow>[];
  for (final output in tree.outputs) {
    if (!output.active) continue;
    for (final workspace in output.workspaces) {
      if (!workspace.visible) continue;
      for (final node in workspace.descendants.whereType<ContainerNode>()) {
        final appId = containerAppId(node);
        if (appId == null) continue;
        final rect = _rectOf(node.rect);
        if (rect.isEmpty) continue;
        windows.add(SelectableWindow(
          id: node.id,
          rect: rect,
          title: node.name,
          appId: appId,
          output: output.name,
        ));
      }
    }
  }
  return windows;
}

/// The output the user is working on — the one holding the focused workspace —
/// or null when [tree] names none.
///
/// What "the current screen" means to the recording shortcut, and the only
/// place the shell answers that question without asking the user to point at a
/// display. Miracle focuses exactly one workspace at a time, so the first match
/// is the answer; an output that is inactive or has no area is skipped for
/// [collectOutputs]'s reason, and a tree whose focused workspace sits on one of
/// those is a tree with no answer rather than a wrong one.
ScreenOutput? focusedOutput(BaseNode tree) {
  for (final output in tree.outputs) {
    if (!output.active) continue;
    final rect = _rectOf(output.rect);
    if (rect.isEmpty) continue;
    for (final workspace in output.workspaces) {
      if (workspace.focused) {
        return ScreenOutput(name: output.name, rect: rect);
      }
    }
  }
  return null;
}

/// The frontmost window in [windows] containing the global logical point ([x],
/// [y]), or null.
///
/// Iterated in reverse, because [collectWindows] returns back to front: a
/// floating window over a tiled one is later in the list.
SelectableWindow? windowAt(List<SelectableWindow> windows, int x, int y) {
  for (var i = windows.length - 1; i >= 0; i--) {
    if (windows[i].rect.contains(x, y)) return windows[i];
  }
  return null;
}

/// The output named [connector], or null when it is not connected.
ScreenOutput? outputNamed(List<ScreenOutput> outputs, String connector) {
  for (final output in outputs) {
    if (output.name == connector) return output;
  }
  return null;
}

/// The output a surface on [connector], whose top-left corner is [origin], is
/// covering — or null when nothing in [outputs] answers for it.
///
/// `capture_source.dart`'s `indexOfCaptureOutput` passes, against miracle's tree
/// instead of the capture connection's outputs and for the same reason: GDK
/// reports no connector at all without an `xdg-output` manager, and an empty
/// string matches none of miracle's names. Without the second pass a window
/// selection on such a machine finds no windows to point at.
ScreenOutput? resolveScreenOutput(
  List<ScreenOutput> outputs,
  String connector, {
  CapturePoint? origin,
}) {
  if (connector.isNotEmpty) {
    final named = outputNamed(outputs, connector);
    if (named != null) return named;
    // miracle names every output it reports, so a connector that matched none
    // of them names a display this tree does not have; guessing past that
    // would put another monitor's windows on this surface.
    return null;
  }
  if (origin != null) {
    for (final output in outputs) {
      if (output.rect.x == origin.x && output.rect.y == origin.y) return output;
    }
  }
  return outputs.length == 1 ? outputs.first : null;
}

CaptureRect _rectOf(Rect rect) =>
    CaptureRect(rect.x, rect.y, rect.width, rect.height);

/// One read of the windowing environment, taken when a selection starts.
///
/// A snapshot rather than a live view, and one for the machine rather than one
/// per surface: the selection surfaces are a window per output and each would
/// otherwise open its own `GET_TREE`. It is also *right* that it does not update
/// — the rectangles the user is pointing at have to be the ones being drawn, and
/// a window that opens behind the surface cannot be clicked through it anyway.
class CaptureScene {
  const CaptureScene({required this.outputs, required this.windows});

  /// What the surfaces show when miracle is not connected: every output can
  /// still be picked whole (that needs only the connector the panel already
  /// knows) and an area can still be dragged (that is measured in the
  /// surface's own space), but there are no window rectangles to point at.
  static const CaptureScene empty =
      CaptureScene(outputs: <ScreenOutput>[], windows: <SelectableWindow>[]);

  factory CaptureScene.fromTree(BaseNode tree) => CaptureScene(
        outputs: collectOutputs(tree),
        windows: collectWindows(tree),
      );

  final List<ScreenOutput> outputs;
  final List<SelectableWindow> windows;

  bool get isEmpty => outputs.isEmpty && windows.isEmpty;

  /// The output a surface on [connector] — at [origin], when the shell knows
  /// where it is — covers. See [resolveScreenOutput].
  ScreenOutput? outputFor(String connector, {CapturePoint? origin}) =>
      resolveScreenOutput(outputs, connector, origin: origin);

  /// The windows on [connector], in the same back-to-front order.
  List<SelectableWindow> windowsOn(String connector) =>
      [for (final window in windows) if (window.output == connector) window];
}
