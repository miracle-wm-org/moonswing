import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/modules/workspace_apps.dart';
import 'package:miracle/miracle.dart';

import 'workspace_result.dart';

/// Pins how the workspace row names a workspace to miracle, and which
/// workspaces its right-click menu offers the tiling/floating rows for.
///
/// Both are pure, which is the point: the decisions live below the widget, so
/// the menu that renders them (`test/workspace_menu_test.dart`) and the row that
/// sends them need no compositor to be tested. `WorkspaceResult`s are built
/// through `miracle.dart`'s own `fromJson`, so this also fails if the reply
/// shape the row reads stops being the one the library produces — including the
/// `policy` field itself, which a miracle that predates it simply omits.
void main() {
  group('workspaceSelector', () {
    test('names a numbered workspace by its number', () {
      expect(workspaceSelector(workspaceResult(num: 3, name: '3')), '3');
    });

    test('falls back to the name when the number is the placeholder', () {
      // miracle reports a named workspace's number as `-1`, which addresses
      // nothing — a bare `num != null` would spell `workspace -1`.
      expect(workspaceSelector(workspaceResult(num: -1, name: 'mail')), 'mail');
      expect(
          workspaceSelector(workspaceResult(num: null, name: 'mail')), 'mail');
    });

    test('answers null for the workspace no command could address', () {
      // Which is the whole reason it is nullable: interpolating this case
      // sends miracle the word `null` as a workspace.
      expect(workspaceSelector(workspaceResult(num: -1, name: null)), isNull);
      expect(workspaceSelector(workspaceResult(num: null, name: '')), isNull);
    });
  });

  group('shouldShowPolicyToggle', () {
    const on = WorkspacesConfig();
    const off = WorkspacesConfig(showPolicyToggle: false);

    test('is every workspace, not just the focused one', () {
      // It used to be the focused one alone, because the toggle was a glyph in
      // the bar. In a menu that cost is gone and `workspace <num> policy` names
      // its workspace, so the rows are offered wherever they can be acted on.
      expect(
          shouldShowPolicyToggle(on, workspaceResult(num: 1, focused: true)),
          isTrue);
      expect(
          shouldShowPolicyToggle(on, workspaceResult(num: 2, focused: false)),
          isTrue);
    });

    test('is off when the option is', () {
      expect(shouldShowPolicyToggle(off, workspaceResult(num: 1)), isFalse);
    });

    test('is off for a workspace no command could address', () {
      // Rows that cannot name their workspace are rows that do nothing.
      expect(
        shouldShowPolicyToggle(on, workspaceResult(num: -1, name: null)),
        isFalse,
      );
    });
  });

  group('the policy on a GET_WORKSPACES entry', () {
    test('is read off the reply', () {
      expect(workspaceResult(num: 1, policy: 'float').policy,
          WindowPlacementPolicy.float);
      expect(workspaceResult(num: 1, policy: 'tile').policy,
          WindowPlacementPolicy.tile);
    });

    test('reads as tiling on a miracle that predates the field', () {
      // Which is what that compositor actually does, so the checked row is
      // right rather than merely defaulted — and the command it then sends is
      // the one that gets rejected, visibly.
      expect(workspaceResult(num: 1).policy, WindowPlacementPolicy.tile);
    });
  });
}
