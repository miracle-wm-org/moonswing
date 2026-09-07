import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/modules/workspace_apps.dart';
import 'package:graceful_shell/modules/workspaces.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:miracle/miracle.dart';

import 'tap_target.dart';

/// Pins the workspace row's tiling/floating toggle: which button carries it,
/// which command it sends the workspace by, and the two things about the widget
/// that are not obvious from reading it — that its tap does not also switch
/// workspace, and that its target is its box rather than its glyph.
///
/// The pure half is where the decisions live, so most of this needs no widget at
/// all. `WorkspaceResult`s are built through `miracle.dart`'s own `fromJson`, so
/// this also fails if the reply shape the row reads stops being the one the
/// library produces — including the `policy` field itself, which a miracle that
/// predates it simply omits.
void main() {
  group('workspaceSelector', () {
    test('names a numbered workspace by its number', () {
      expect(workspaceSelector(_result(num: 3, name: '3')), '3');
    });

    test('falls back to the name when the number is the placeholder', () {
      // miracle reports a named workspace's number as `-1`, which addresses
      // nothing — a bare `num != null` would spell `workspace -1`.
      expect(workspaceSelector(_result(num: -1, name: 'mail')), 'mail');
      expect(workspaceSelector(_result(num: null, name: 'mail')), 'mail');
    });

    test('answers null for the workspace no command could address', () {
      // Which is the whole reason it is nullable: interpolating this case
      // sends miracle the word `null` as a workspace.
      expect(workspaceSelector(_result(num: -1, name: null)), isNull);
      expect(workspaceSelector(_result(num: null, name: '')), isNull);
    });
  });

  group('nextWorkspacePolicy', () {
    test('is its own inverse', () {
      expect(nextWorkspacePolicy(WindowPlacementPolicy.tile),
          WindowPlacementPolicy.float);
      expect(nextWorkspacePolicy(WindowPlacementPolicy.float),
          WindowPlacementPolicy.tile);
      for (final policy in WindowPlacementPolicy.values) {
        expect(nextWorkspacePolicy(nextWorkspacePolicy(policy)), policy);
      }
    });
  });

  group('shouldShowPolicyToggle', () {
    const on = WorkspacesConfig();
    const off = WorkspacesConfig(showPolicyToggle: false);

    test('is the focused workspace and nothing else', () {
      // Five more click targets in a bar are five switch-workspace clicks
      // waiting to be missed, and the toggle is about the workspace the next
      // window will open on.
      expect(shouldShowPolicyToggle(on, _result(num: 1, focused: true)), isTrue);
      expect(
          shouldShowPolicyToggle(on, _result(num: 2, focused: false)), isFalse);
    });

    test('is off when the option is', () {
      expect(shouldShowPolicyToggle(off, _result(num: 1, focused: true)),
          isFalse);
    });

    test('is off for a workspace no command could address', () {
      // A toggle that cannot name its workspace is a button that does nothing.
      expect(
        shouldShowPolicyToggle(on, _result(num: -1, name: null, focused: true)),
        isFalse,
      );
    });
  });

  group('the policy on a GET_WORKSPACES entry', () {
    test('is read off the reply', () {
      expect(_result(num: 1, policy: 'float').policy,
          WindowPlacementPolicy.float);
      expect(
          _result(num: 1, policy: 'tile').policy, WindowPlacementPolicy.tile);
    });

    test('reads as tiling on a miracle that predates the field', () {
      // Which is what that compositor actually does, so the glyph is right
      // rather than merely defaulted — and the command it then sends is the
      // one that gets rejected, visibly.
      expect(_result(num: 1).policy, WindowPlacementPolicy.tile);
    });
  });

  group('WorkspacePolicyToggle', () {
    testWidgets('draws what the workspace will do with the next window',
        (tester) async {
      await tester.pumpWidget(_host(const WorkspacePolicyToggle(
        policy: WindowPlacementPolicy.tile,
        onToggle: _nothing,
      )));
      expect(find.byIcon(FontAwesomeIcons.tableCells.data), findsOneWidget);

      await tester.pumpWidget(_host(const WorkspacePolicyToggle(
        policy: WindowPlacementPolicy.float,
        onToggle: _nothing,
      )));
      expect(find.byIcon(FontAwesomeIcons.solidClone.data), findsOneWidget);
    });

    testWidgets('accents the floating state, which is the departure',
        (tester) async {
      const theme = ThemeConfig();

      await tester.pumpWidget(_host(const WorkspacePolicyToggle(
        policy: WindowPlacementPolicy.float,
        onToggle: _nothing,
      )));
      expect(tester.widget<FaIcon>(find.byType(FaIcon)).color, theme.accent);

      await tester.pumpWidget(_host(const WorkspacePolicyToggle(
        policy: WindowPlacementPolicy.tile,
        onToggle: _nothing,
      )));
      expect(tester.widget<FaIcon>(find.byType(FaIcon)).color,
          isNot(theme.accent));
    });

    testWidgets('fires from every corner of its box, not just its glyph',
        (tester) async {
      // The house rule: hover box and tap box are one rect. The glyph is 9px
      // inside a 16px target, so a `deferToChild` detector would leave the
      // corners dead.
      var taps = 0;
      await tester.pumpWidget(_host(WorkspacePolicyToggle(
        policy: WindowPlacementPolicy.tile,
        onToggle: () => taps++,
      )));

      // Read as two numbers rather than compared to a `Size` literal:
      // `package:miracle` exports a `Size` of its own — an int-valued rect
      // size off the IPC — which is the one this file's imports resolve.
      final box = tester.getSize(find.byType(WorkspacePolicyToggle));
      expect(box.width, 16);
      expect(box.height, 16);
      await tapEveryCorner(tester, find.byType(WorkspacePolicyToggle));
      expect(taps, 4);
    });

    testWidgets('takes the tap the workspace button would otherwise switch on',
        (tester) async {
      // The toggle is nested inside `_WorkspaceButton`'s own opaque detector.
      // Hit testing runs deepest-first, so the toggle's recognizer enters the
      // arena first and wins the sweep — this pins that, because the arena is
      // the only thing standing between a policy flip and a workspace switch.
      var toggles = 0;
      var switches = 0;
      await tester.pumpWidget(_host(GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (_) => switches++,
        child: Padding(
          key: const Key('button'),
          padding: const EdgeInsets.all(8),
          child: WorkspacePolicyToggle(
            policy: WindowPlacementPolicy.tile,
            onToggle: () => toggles++,
          ),
        ),
      )));

      await tapEveryCorner(tester, find.byType(WorkspacePolicyToggle));
      expect(toggles, 4);
      expect(switches, 0, reason: 'the button beneath it stayed out of it');

      // And the button is still the button everywhere else: the toggle absorbs
      // its own 16px box and not one pixel of the padding around it.
      final button = tester.getRect(find.byKey(const Key('button')));
      await tester.tapAt(button.topLeft + const Offset(2, 2));
      await tester.pump();
      expect(switches, 1);
      expect(toggles, 4);
    });
  });
}

// ---------------------------------------------------------------------------

void _nothing() {}

Widget _host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: ThemeScope(
        theme: const ThemeConfig(),
        child: Center(child: child),
      ),
    );

/// A `GET_WORKSPACES` entry, through `miracle.dart`'s own decoder.
///
/// [policy] is left absent by default, which is what a miracle older than the
/// per-workspace policy sends.
WorkspaceResult _result({
  required int? num,
  String? name,
  String output = 'DP-1',
  bool focused = true,
  String? policy,
}) =>
    WorkspaceResult.fromJson({
      'num': num,
      'name': name,
      'visible': true,
      'focused': focused,
      'urgent': false,
      'output': output,
      'policy': ?policy,
      'rect': {'x': 0, 'y': 0, 'width': 1920, 'height': 1080},
    });
