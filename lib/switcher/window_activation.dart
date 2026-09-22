// Switching to the window the user let go of Alt on.
//
// Two protocols meet here and neither can do the job alone. The switcher's list
// comes from `ext-foreign-toplevel-list-v1`, which says what is open and
// nothing else: it carries no workspace, no focus state, and — unlike
// `wlr-foreign-toplevel-management` — no `activate` request. So the act of
// switching goes through miracle's IPC, which is where the workspace is known
// anyway.
//
// **Why not xdg-activation-v1.** It cannot reach another client's window, by
// construction rather than by omission: `xdg_activation_v1.activate` takes a
// `wl_surface`, and a `wl_surface` is a client-side object, so a shell can only
// ever name one of its own. Mir enforces exactly that — `activate` resolves the
// argument with `WlSurface::from(surface)` and raises *that* scene surface (see
// `src/server/frontend_wayland/xdg_activation_v1.cpp`) — and the token minted
// for a global shortcut is the permission to raise a window, not a way of
// naming somebody else's. A shell that wants a Wayland-native activate needs
// `zwlr_foreign_toplevel_handle_v1.activate`, a second foreign-toplevel
// protocol with a second set of handles to join to these ones.
//
// The join itself is `capture/toplevel_match.dart`, the matcher the window
// picker already uses: miracle's tree and the toplevel list share no id, only
// what the window calls itself. Everything above [activateWindow] is pure, so
// the whole join is a unit test with no socket.

import 'package:flutter/foundation.dart';
import 'package:miracle/miracle.dart';

import 'package:moonswing/capture/toplevel_match.dart';
import 'package:moonswing/modules/workspace_apps.dart' show containerAppId;
import 'package:moonswing/switcher/open_window.dart';

/// Where a window the switcher can see lives in miracle's tree.
@immutable
class WindowLocation {
  const WindowLocation({
    required this.containerId,
    required this.workspace,
    required this.workspaceFocused,
  });

  /// miracle's container id — what `[con_id=N] focus` names.
  final int containerId;

  /// How a `workspace` command names the workspace it is on, or null when
  /// miracle reported neither a usable number nor a name. Null is not a
  /// failure: it costs the hop, not the focus.
  final String? workspace;

  /// Whether that workspace is the one already being looked at, in which case
  /// there is no hop to make.
  final bool workspaceFocused;

  @override
  bool operator ==(Object other) =>
      other is WindowLocation &&
      other.containerId == containerId &&
      other.workspace == workspace &&
      other.workspaceFocused == workspaceFocused;

  @override
  int get hashCode => Object.hash(containerId, workspace, workspaceFocused);

  @override
  String toString() => 'WindowLocation($containerId, workspace: $workspace, '
      'focused: $workspaceFocused)';
}

/// How a `workspace` command names [workspace].
///
/// `workspaceSelector` in `modules/workspace_apps.dart` is the same rule
/// against miracle's `GET_WORKSPACES` reply, which spells a workspace
/// differently from the tree: there both fields are nullable and a named
/// workspace's number is the placeholder `-1`, here both are non-null and the
/// placeholder is the only thing to guard against.
String? treeWorkspaceSelector(WorkspaceNode workspace) {
  if (workspace.num >= 0) return workspace.num.toString();
  return workspace.name.isNotEmpty ? workspace.name : null;
}

/// Where in [tree] the toplevel [identifier] is, or null when no single
/// container is it.
///
/// [toplevels] is the whole foreign-toplevel list, not just the one being
/// looked for: [matchToplevel] answers a container only when exactly one
/// toplevel can be it, and it needs the others to know that. The same
/// narrowing runs the other way round here — a container whose match is
/// ambiguous is skipped rather than guessed at, and two containers resolving to
/// the one identifier is a refusal too, because switching to somebody's *other*
/// Firefox window is worse than the switcher appearing not to have worked.
WindowLocation? locateWindow(
  BaseNode tree,
  List<ToplevelDescriptor> toplevels,
  String identifier,
) {
  if (identifier.isEmpty) return null;
  WindowLocation? found;
  for (final workspace in tree.workspaces) {
    for (final node in workspace.descendants.whereType<ContainerNode>()) {
      final appId = containerAppId(node);
      if (appId == null && node.name.isEmpty) continue;
      final match = matchToplevel(
        toplevels,
        appId: appId ?? '',
        title: node.name,
      );
      if (match != identifier) continue;
      if (found != null) return null; // ambiguous — decline rather than guess
      found = WindowLocation(
        containerId: node.id,
        workspace: treeWorkspaceSelector(workspace),
        workspaceFocused: workspace.focused,
      );
    }
  }
  return found;
}

/// The commands that switch to [location], in the order they must run.
///
/// The workspace first and the window second, which is what the two halves of
/// the act actually are: miracle's `focus` selects a container, and a container
/// on a workspace nobody is looking at is a focus the user cannot see. A
/// workspace already focused contributes no command — `workspace <n>` on the
/// current one is miracle's own back-and-forth toggle, so sending it anyway
/// would switch *away* from the window we are switching to.
///
/// Both go out in one [MiracleConnection.runAll] payload, so nothing can land
/// between the hop and the focus.
List<MiracleCommand> switchToWindowCommands(WindowLocation location) => [
  if (!location.workspaceFocused && location.workspace != null)
    MiracleCommand.workspace(location.workspace!, noAutoBackAndForth: true),
  MiracleCommand.focusMatching(Criteria(containerId: location.containerId)),
];

/// The best-effort commands for a window the tree could not be joined to.
///
/// By `app_id` alone, which is the only thing left that miracle can match on:
/// `title` is a regular expression in criteria, so a window called `Untitled —
/// Foo (2/3) [modified]` would be asking miracle to parse the user's document
/// name as a pattern. miracle focuses the first container the criteria select,
/// so this lands on *a* window of the right application rather than on none at
/// all; an empty `app_id` has nothing to say and asks for nothing.
List<MiracleCommand> switchToAppCommands(String appId) => [
  if (appId.isNotEmpty) MiracleCommand.focusMatching(Criteria(appId: appId)),
];

/// Switches to [window]: its workspace first, then the window itself.
///
/// Never throws. Every way this can fail — no IPC connection, a tree that will
/// not arrive, a window the join cannot resolve, a command miracle refuses —
/// costs the switch and nothing else, because the overlay has already gone and
/// there is nothing left to tell the user with.
///
/// [toplevels] is the switcher's whole list at the moment the user let go, not
/// the compositor's list now: the join has to be made against the same set the
/// selection was made from, or a window that opened during the gesture could
/// turn a clean match into an ambiguous one.
Future<void> activateWindow(
  MiracleConnection? connection,
  OpenWindow window,
  List<OpenWindow> toplevels,
) async {
  if (connection == null) {
    debugPrint('switcher: not connected to miracle; cannot switch to '
        '"${window.label}"');
    return;
  }
  final descriptors = [for (final w in toplevels) w.descriptor];
  List<MiracleCommand> commands;
  try {
    final tree = await connection.getTree();
    final location = locateWindow(tree, descriptors, window.identifier);
    if (location == null) {
      debugPrint('switcher: no single window in miracle\'s tree is '
          '"${window.label}"; falling back to its application');
      commands = switchToAppCommands(window.appId);
    } else {
      commands = switchToWindowCommands(location);
    }
  } catch (error) {
    debugPrint('switcher: could not read the window tree: $error');
    commands = switchToAppCommands(window.appId);
  }

  if (commands.isEmpty) return;
  try {
    for (final result in await connection.runAll(commands)) {
      if (result.success) continue;
      debugPrint('switcher: could not switch to "${window.label}": '
          '${result.error ?? 'refused'}');
    }
  } catch (error) {
    debugPrint('switcher: could not switch to "${window.label}": $error');
  }
}
