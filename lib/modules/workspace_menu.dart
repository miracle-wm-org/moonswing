// The workspace button's right-click menu: how a workspace places the windows
// opened on it, and which output it lives on.
//
// The card is `DesktopMenuCard`, the same surface the desktop's own menus and
// the app directory's pin menu render into — a context menu is a context menu,
// and the theme's popup shape reaches all of them from one place. Only the
// entries are this file's, and the two pages follow `DesktopItemMenu`'s rule:
// "Move to output…" is a *second page of the same popup* rather than a child
// popup, because a child popup is a second Wayland surface for a list that is
// mutually exclusive with the page behind it.
//
// The command-building half is pure and lives here rather than in
// `workspace_apps.dart`, which is about what is *open* on a workspace. It is
// where the decisions worth pinning are: `test/workspace_menu_test.dart`
// reaches it without a compositor.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:moonswing/desktop/desktop_menu.dart';
import 'package:miracle/miracle.dart';

// ---------------------------------------------------------------------------
// The pure half
// ---------------------------------------------------------------------------

/// How a workspace is named in the menu's header.
///
/// Its name when it has one, otherwise its number — the same thing the button
/// itself draws, so the menu says what the user right-clicked rather than the
/// selector a command happens to use. `?` for the workspace miracle reported
/// neither for, which is the one the button labels that way too.
String workspaceMenuTitle(WorkspaceResult workspace) {
  final name = workspace.name;
  if (name != null && name.isNotEmpty) return name;
  final number = workspace.num;
  if (number != null && number >= 0) return number.toString();
  return '?';
}

/// The outputs [workspace] could be moved to, in the order miracle reported
/// them.
///
/// Its own output is left out — moving a workspace where it already is means
/// nothing — as is any output miracle marks inactive, which cannot hold a
/// workspace, and any that reported no name, which no `move` command could
/// address.
///
/// **Not filtered on power.** A monitor that is merely asleep is a perfectly
/// good place to send a workspace, and miracle wakes it to show one.
List<OutputResult> outputsToMoveTo(
  List<OutputResult> outputs,
  WorkspaceResult workspace,
) =>
    outputs
        .where((output) =>
            output.active &&
            output.name.isNotEmpty &&
            output.name != workspace.output)
        .toList(growable: false);

/// How one of those outputs is named in the menu.
///
/// The connector name leads, because it is the string the user sees in every
/// other tool and the one miracle is being sent; the make and model follow when
/// miracle knows them, because a row of `DP-1`/`DP-2`/`HDMI-A-1` says nothing
/// about which monitor is which. miracle spells an unknown one `Unknown`
/// literally, which is worth no pixels.
String outputMenuLabel(OutputResult output) {
  final description = <String>[
    if (output.make.isNotEmpty && output.make != 'Unknown') output.make,
    if (output.model.isNotEmpty && output.model != 'Unknown') output.model,
  ].join(' ');
  return description.isEmpty ? output.name : '${output.name} — $description';
}

/// The commands that move the workspace [selector] names onto [output].
///
/// miracle's `move workspace to output` acts on the **focused** workspace and
/// takes no selector of its own, so a workspace that is not focused has to be
/// focused first. Three things follow, and each is why this is a list rather
/// than one command:
///
/// - **The focusing hop is skipped when the workspace is already focused.** Not
///   an optimisation: `workspace <n>` on the workspace one is already on is
///   what `auto_back_and_forth` acts on, and sending it would move the *wrong*
///   workspace to the other monitor.
/// - **`--no-auto-back-and-forth` on every hop this builds**, for the same
///   reason one step down: the restore hop names the workspace the user was on,
///   and a compositor with that option set would read it as "go back" and land
///   somewhere else again. The workspace button's own left-click deliberately
///   does *not* pass it — going back and forth is what a second click on the
///   focused workspace is for.
/// - **Focus is put back where it was.** The user right-clicked a button that is
///   not the one they are working on; being dragged to another monitor because
///   of it is the shell taking a liberty. [restore] is the workspace to return
///   to, and is null when there is none to name — a move from the focused
///   workspace stays on that workspace, which is where miracle would have left
///   it anyway.
List<MiracleCommand> moveWorkspaceCommands({
  required String selector,
  required String output,
  required bool focused,
  String? restore,
}) =>
    <MiracleCommand>[
      if (!focused)
        MiracleCommand.workspace(selector, noAutoBackAndForth: true),
      MiracleCommand.moveWorkspaceToOutput(OutputSelector.named([output])),
      if (!focused && restore != null)
        MiracleCommand.workspace(restore, noAutoBackAndForth: true),
    ];

// ---------------------------------------------------------------------------
// The menu
// ---------------------------------------------------------------------------

/// The two-page menu a right-click on a workspace button opens.
///
/// Both actions are about the workspace that was clicked rather than the
/// focused one, which is the whole reason they are here: `workspace <n> policy`
/// and the focus-move-restore hop of [moveWorkspaceCommands] both name their
/// workspace, so a menu can offer for any button what a glyph in the bar could
/// only have offered for one.
class WorkspaceMenu extends StatefulWidget {
  const WorkspaceMenu({
    super.key,
    required this.workspace,
    required this.outputs,
    required this.onSetPolicy,
    required this.onMoveToOutput,
    this.showPolicy = true,
  });

  final WorkspaceResult workspace;

  /// Every output miracle knows about, unfiltered — [outputsToMoveTo] decides
  /// which of them this workspace could go to.
  ///
  /// Passed in rather than fetched here: the row that opens this menu already
  /// holds the list, refreshed off miracle's own `output` event, so the menu
  /// opens with its second page already answerable instead of on a round-trip.
  final List<OutputResult> outputs;

  /// Sets the workspace's window placement policy.
  ///
  /// The checked row stays tappable, because that is how a menu behaves — so
  /// this is called with the policy the workspace already has, and the host is
  /// what decides that means closing the menu rather than a round-trip.
  final void Function(WindowPlacementPolicy policy) onSetPolicy;

  /// Moves the workspace onto the named output.
  final void Function(String outputName) onMoveToOutput;

  /// Whether the placement rows are drawn at all
  /// (`[modules.workspaces] show_policy_toggle`).
  final bool showPolicy;

  @override
  State<WorkspaceMenu> createState() => _WorkspaceMenuState();
}

class _WorkspaceMenuState extends State<WorkspaceMenu> {
  bool _choosingOutput = false;

  @override
  Widget build(BuildContext context) {
    final workspace = widget.workspace;
    final targets = outputsToMoveTo(widget.outputs, workspace);

    if (_choosingOutput) {
      return DesktopMenuCard(
        header: 'Move workspace ${workspaceMenuTitle(workspace)} to',
        onBack: () => setState(() => _choosingOutput = false),
        entries: [
          // Unreachable while the row that opens this page is disabled on an
          // empty list, and kept anyway: [outputs] is a snapshot taken when the
          // popup opened, so the day something makes this page reachable with
          // nothing on it, it says so rather than rendering an empty card.
          if (targets.isEmpty)
            DesktopMenuEntry(
              label: 'No other outputs',
              enabled: false,
              onTap: () {},
            ),
          for (final output in targets)
            DesktopMenuEntry(
              label: outputMenuLabel(output),
              icon: FontAwesomeIcons.display,
              onTap: () => widget.onMoveToOutput(output.name),
            ),
        ],
      );
    }

    return DesktopMenuCard(
      header: 'Workspace ${workspaceMenuTitle(workspace)}',
      entries: [
        if (widget.showPolicy) ...[
          // Both placements, always, with the current one checked, rather than
          // one row that flips: a menu is read before it is clicked, and "Float
          // new windows" alone cannot say whether that is what the workspace
          // does now or what it would start doing.
          DesktopMenuEntry(
            label: 'Tile new windows',
            icon: FontAwesomeIcons.tableCells,
            selected: workspace.policy == WindowPlacementPolicy.tile,
            onTap: () => widget.onSetPolicy(WindowPlacementPolicy.tile),
          ),
          DesktopMenuEntry(
            label: 'Float new windows',
            icon: FontAwesomeIcons.solidClone,
            selected: workspace.policy == WindowPlacementPolicy.float,
            onTap: () => widget.onSetPolicy(WindowPlacementPolicy.float),
          ),
        ],
        // Greyed rather than hidden on a single-monitor session, the rule
        // [DesktopMenuEntry.enabled] exists for: the menu keeps its shape, and
        // a user who is about to plug a second monitor in can see that the
        // shell will have somewhere to put this.
        DesktopMenuEntry(
          label: 'Move to output…',
          icon: FontAwesomeIcons.display,
          enabled: targets.isNotEmpty,
          onTap: () => setState(() => _choosingOutput = true),
        ),
      ],
    );
  }
}
