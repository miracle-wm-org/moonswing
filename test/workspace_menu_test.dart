import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/modules/workspace_menu.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:miracle/miracle.dart';

import 'workspace_result.dart';

/// Pins the workspace button's right-click menu: the commands it builds, the
/// outputs it offers, and the two things the card has to say out loud — which
/// placement the workspace is *already* in, and that a single-monitor session
/// has nowhere to move it to.
///
/// The command half is where the compositor's own quirks are encoded, so it is
/// asserted as wire strings rather than as a shape: `move workspace to output`
/// acts on the focused workspace and takes no selector, which is the whole
/// reason [moveWorkspaceCommands] returns a list.
void main() {
  group('workspaceMenuTitle', () {
    test('is what the button itself draws', () {
      expect(workspaceMenuTitle(workspaceResult(num: 3, name: null)), '3');
      expect(workspaceMenuTitle(workspaceResult(num: -1, name: 'mail')), 'mail');
      // The one workspace miracle named nothing. The button labels it this way
      // too, so the menu does not invent an identity the row does not show.
      expect(workspaceMenuTitle(workspaceResult(num: -1, name: null)), '?');
    });
  });

  group('outputsToMoveTo', () {
    final workspace = workspaceResult(num: 1, output: 'DP-1');

    test('leaves out the output the workspace is already on', () {
      final outputs = [
        outputResult(name: 'DP-1'),
        outputResult(name: 'HDMI-A-1'),
      ];
      expect(outputsToMoveTo(outputs, workspace).map((o) => o.name),
          ['HDMI-A-1']);
    });

    test('leaves out what no move command could reach', () {
      final outputs = [
        // Disabled: it cannot hold a workspace.
        outputResult(name: 'HDMI-A-1', active: false),
        // Unnamed: there is nothing to put in the command.
        outputResult(name: ''),
      ];
      expect(outputsToMoveTo(outputs, workspace), isEmpty);
    });

    test('keeps a sleeping monitor, which is a fine place to send one', () {
      // Filtering on power would hide exactly the monitor a user is about to
      // wake by putting something on it.
      final outputs = [outputResult(name: 'HDMI-A-1', power: false)];
      expect(outputsToMoveTo(outputs, workspace).map((o) => o.name),
          ['HDMI-A-1']);
    });

    test('keeps the order miracle reported', () {
      final outputs = [
        outputResult(name: 'HDMI-A-1'),
        outputResult(name: 'DP-1'),
        outputResult(name: 'DP-2'),
      ];
      expect(outputsToMoveTo(outputs, workspace).map((o) => o.name),
          ['HDMI-A-1', 'DP-2']);
    });
  });

  group('outputMenuLabel', () {
    test('adds the monitor to the connector when miracle knows it', () {
      expect(outputMenuLabel(outputResult(name: 'DP-1', make: 'Dell', model: 'U2415')),
          'DP-1 — Dell U2415');
    });

    test('is the connector alone when it does not', () {
      // miracle spells an unknown make or model `Unknown` literally, which is
      // worth no pixels.
      expect(outputMenuLabel(outputResult(name: 'DP-1')), 'DP-1');
      expect(outputMenuLabel(outputResult(name: 'DP-1', make: 'Dell')),
          'DP-1 — Dell');
    });
  });

  group('moveWorkspaceCommands', () {
    test('is one command for the workspace that is already focused', () {
      // And *must* be: `workspace <num>` on the workspace one is already on is
      // what auto_back_and_forth acts on, so a focusing hop here would move the
      // wrong workspace to the other monitor.
      final commands = moveWorkspaceCommands(
        selector: '2',
        output: 'HDMI-A-1',
        focused: true,
        restore: '2',
      );
      expect(commands.map((c) => c.toCommandString()),
          ['move workspace to output HDMI-A-1']);
    });

    test('focuses, moves and puts the focus back for one that is not', () {
      final commands = moveWorkspaceCommands(
        selector: '3',
        output: 'HDMI-A-1',
        focused: false,
        restore: '1',
      );
      expect(commands.map((c) => c.toCommandString()), [
        'workspace --no-auto-back-and-forth 3',
        'move workspace to output HDMI-A-1',
        'workspace --no-auto-back-and-forth 1',
      ]);
    });

    test('passes --no-auto-back-and-forth on every hop it builds', () {
      // The restore hop names the workspace the user was on, which is precisely
      // the name a compositor with that option set would read as "go back".
      final commands = moveWorkspaceCommands(
        selector: 'mail',
        output: 'DP-2',
        focused: false,
        restore: 'web',
      );
      final hops = commands
          .map((c) => c.toCommandString())
          .where((c) => c.startsWith('workspace '));
      expect(hops, everyElement(contains('--no-auto-back-and-forth')));
    });

    test('skips the restore when there is no workspace to name', () {
      // miracle reported the focused workspace neither a number nor a name;
      // there is nothing to go back to, and the move still has to happen.
      final commands = moveWorkspaceCommands(
        selector: '3',
        output: 'HDMI-A-1',
        focused: false,
        restore: null,
      );
      expect(commands.map((c) => c.toCommandString()), [
        'workspace --no-auto-back-and-forth 3',
        'move workspace to output HDMI-A-1',
      ]);
    });

    test('quotes an output whose name would not survive the wire', () {
      final commands = moveWorkspaceCommands(
        selector: '1',
        output: 'Virtual Output 1',
        focused: true,
      );
      expect(commands.single.toCommandString(),
          'move workspace to output "Virtual Output 1"');
    });
  });

  group('WorkspaceMenu', () {
    testWidgets('offers both placements and checks the current one',
        (tester) async {
      await _pump(tester,
          workspace: workspaceResult(num: 2, policy: 'float'));

      expect(find.text('Tile new windows'), findsOneWidget);
      expect(find.text('Float new windows'), findsOneWidget);
      // Exactly one row is marked, and it is the one the workspace is in — the
      // colour alone would not do, because a theme is free to make its accent
      // quiet.
      expect(find.byIcon(FontAwesomeIcons.check.data), findsOneWidget);
      const theme = ThemeConfig();
      expect(
        tester
            .widget<FaIcon>(find.byIcon(FontAwesomeIcons.solidClone.data))
            .color,
        theme.accent,
      );
      expect(
        tester
            .widget<FaIcon>(find.byIcon(FontAwesomeIcons.tableCells.data))
            .color,
        isNot(theme.accent),
      );
    });

    testWidgets('reports the placement that was chosen', (tester) async {
      final chosen = <WindowPlacementPolicy>[];
      await _pump(tester,
          workspace: workspaceResult(num: 2, policy: 'tile'),
          onSetPolicy: chosen.add);

      await tester.tap(find.text('Float new windows'));
      await tester.pump();
      expect(chosen, [WindowPlacementPolicy.float]);

      // The checked row stays tappable — re-choosing what is already chosen is
      // a no-op the host absorbs, not an error the menu refuses.
      await tester.tap(find.text('Tile new windows'));
      await tester.pump();
      expect(chosen, [WindowPlacementPolicy.float, WindowPlacementPolicy.tile]);
    });

    testWidgets('drops the placement rows when the option is off',
        (tester) async {
      await _pump(tester, showPolicy: false);
      expect(find.text('Tile new windows'), findsNothing);
      expect(find.text('Float new windows'), findsNothing);
      // And the menu is still a menu: the row that is left is the reason it
      // opens at all on a config with the toggle switched off.
      expect(find.text('Move to output…'), findsOneWidget);
    });

    testWidgets('greys the move row on a single-monitor session',
        (tester) async {
      var opened = 0;
      await _pump(
        tester,
        outputs: [outputResult(name: 'DP-1')],
        onMoveToOutput: (_) => opened++,
      );

      // Shown rather than hidden, so the menu keeps its shape — and inert, so
      // it cannot open a page with nothing on it.
      expect(find.text('Move to output…'), findsOneWidget);
      await tester.tap(find.text('Move to output…'));
      await tester.pump();
      expect(find.text('DP-1'), findsNothing);
      expect(opened, 0);
    });

    testWidgets('lists the other outputs on a second page of the same popup',
        (tester) async {
      final moved = <String>[];
      await _pump(
        tester,
        outputs: [
          outputResult(name: 'DP-1'),
          outputResult(name: 'HDMI-A-1', make: 'Dell', model: 'U2415'),
        ],
        onMoveToOutput: moved.add,
      );

      await tester.tap(find.text('Move to output…'));
      await tester.pump();

      // The page says which workspace it is about, because by now the button
      // that was clicked is behind another surface.
      expect(find.text('Move workspace 2 to'), findsOneWidget);
      expect(find.text('DP-1 — Dell U2415'), findsNothing);
      expect(find.text('HDMI-A-1 — Dell U2415'), findsOneWidget);

      await tester.tap(find.text('HDMI-A-1 — Dell U2415'));
      await tester.pump();
      // The connector name alone, never the label the user read.
      expect(moved, ['HDMI-A-1']);
    });

    testWidgets('comes back from that page without closing', (tester) async {
      await _pump(tester, outputs: [
        outputResult(name: 'DP-1'),
        outputResult(name: 'HDMI-A-1'),
      ]);

      await tester.tap(find.text('Move to output…'));
      await tester.pump();
      expect(find.text('Tile new windows'), findsNothing);

      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(find.text('Tile new windows'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------

/// Pumps the card bare, with no WindowManager: the popup machinery belongs to
/// the host, and this is what the host puts inside one.
Future<void> _pump(
  WidgetTester tester, {
  WorkspaceResult? workspace,
  List<OutputResult>? outputs,
  void Function(WindowPlacementPolicy)? onSetPolicy,
  void Function(String)? onMoveToOutput,
  bool showPolicy = true,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14),
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              height: 420,
              child: WorkspaceMenu(
                workspace: workspace ?? workspaceResult(num: 2),
                outputs: outputs ??
                    [outputResult(name: 'DP-1'), outputResult(name: 'DP-2')],
                showPolicy: showPolicy,
                onSetPolicy: onSetPolicy ?? (_) {},
                onMoveToOutput: onMoveToOutput ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
