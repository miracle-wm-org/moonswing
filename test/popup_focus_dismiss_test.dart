import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/popup_coordinator.dart';
import 'package:graceful_shell/popup_focus_dismiss.dart';
import 'package:miracle/miracle.dart';

/// [PopupFocusDismisser] talks to the process-wide [PopupCoordinator] — that is
/// the point of it, the way `PopupDismissArea` does — so each test registers
/// into that instance and unregisters after.
///
/// The guard's expiry is a `testWidgets` rather than a plain `test`: the widget
/// binding runs the body under a fake clock, so `tester.pump` is what moves a
/// real [Timer] on without waiting for one.
void main() {
  late PopupFocusDismisser dismisser;
  final registered = <TransientHandle>[];

  setUp(() => dismisser = PopupFocusDismisser.forTesting());

  tearDown(() {
    dismisser.disposeForTesting();
    for (final handle in registered) {
      PopupCoordinator.instance.close(handle);
    }
    registered.clear();
  });

  ({TransientHandle handle, List<String> dismissed}) register(
    String name, {
    TransientPolicy policy = TransientPolicy.menu,
    TransientHandle? parent,
    List<String>? into,
  }) {
    final log = into ?? <String>[];
    final handle = PopupCoordinator.instance.open(
      owner: Object(),
      parent: parent,
      policy: policy,
      onDismiss: () => log.add(name),
    );
    registered.add(handle);
    return (handle: handle, dismissed: log);
  }

  group('dismissesPopupsOn', () {
    test('a window focus is the one window change that dismisses', () {
      for (final change in WindowChange.values) {
        expect(
          dismissesPopupsOn(_windowEvent(change)),
          change == WindowChange.focused,
          reason: 'WindowChange.${change.name}',
        );
      }
    });

    test('a workspace focus is the one workspace change that dismisses', () {
      for (final change in WorkspaceChange.values) {
        expect(
          dismissesPopupsOn(_workspaceEvent(change)),
          change == WorkspaceChange.focus,
          reason: 'WorkspaceChange.${change.name}',
        );
      }
    });

    test('an unmodelled change dismisses nothing', () {
      // The opposite of `wakesWorkspaceApps`, deliberately: a stale row costs a
      // re-read, a popup torn down under the user's hand costs the gesture.
      expect(dismissesPopupsOn(_windowEvent(WindowChange.unknown)), isFalse);
      expect(
        dismissesPopupsOn(_workspaceEvent(WorkspaceChange.unknown)),
        isFalse,
      );
    });

    test('an event that is not about focus at all dismisses nothing', () {
      expect(dismissesPopupsOn(_outputEvent()), isFalse);
      expect(dismissesPopupsOn(_tickEvent()), isFalse);
    });
  });

  group('dismissal', () {
    test('a window focus dismisses an open popup', () {
      final popup = register('popup');
      dismisser.handleEvent(_windowEvent(WindowChange.focused));
      expect(popup.dismissed, <String>['popup']);
    });

    test('a workspace focus dismisses an open popup', () {
      final popup = register('popup');
      dismisser.handleEvent(_workspaceEvent(WorkspaceChange.focus));
      expect(popup.dismissed, <String>['popup']);
    });

    test('a change that is not a focus leaves it alone', () {
      final popup = register('popup');
      dismisser.handleEvent(_windowEvent(WindowChange.created));
      dismisser.handleEvent(_windowEvent(WindowChange.closed));
      dismisser.handleEvent(_workspaceEvent(WorkspaceChange.init));
      expect(popup.dismissed, isEmpty);
    });

    test('a modal survives; a menu beside it does not', () {
      // Alt-tabbing away from the polkit prompt or the screencast picker must
      // not answer it. `dismissOutside` honours `dismissable`; `dismissAll`
      // would not, which is why the dismisser never calls it.
      final log = <String>[];
      register('modal', policy: TransientPolicy.modal, into: log);
      register('menu', into: log);

      dismisser.handleEvent(_windowEvent(WindowChange.focused));

      expect(log, <String>['menu']);
    });

    test('a surface nested in a modal inherits its refusal', () {
      final log = <String>[];
      final modal = register('modal', policy: TransientPolicy.modal, into: log);
      register('child', parent: modal.handle, into: log);

      dismisser.handleEvent(_windowEvent(WindowChange.focused));

      expect(log, isEmpty);
    });

    test('a whole chain goes, children first', () {
      final log = <String>[];
      final parent = register('parent', into: log);
      final child = register('child', parent: parent.handle, into: log);
      register('grandchild', parent: child.handle, into: log);

      dismisser.handleEvent(_windowEvent(WindowChange.focused));

      expect(log, <String>['grandchild', 'child', 'parent']);
    });
  });

  group('the self-focus guard', () {
    test('swallows the focus the shell asked for itself', () {
      final popup = register('popup');
      dismisser.expectSelfFocus();
      dismisser.handleEvent(_windowEvent(WindowChange.focused));
      expect(popup.dismissed, isEmpty);
    });

    test('swallows both events one switch emits', () {
      // `switchToWindowCommands` sends a `workspace` hop and a `focus` in one
      // payload, so a one-shot guard would consume the first and let the
      // second through.
      final popup = register('popup');
      dismisser.expectSelfFocus();
      dismisser.handleEvent(_workspaceEvent(WorkspaceChange.focus));
      dismisser.handleEvent(_windowEvent(WindowChange.focused));
      expect(popup.dismissed, isEmpty);
    });

    testWidgets('expires, so a refused focus command cannot wedge it',
        (tester) async {
      final popup = register('popup');
      dismisser.expectSelfFocus();
      expect(dismisser.expectingSelfFocus, isTrue);

      await tester.pump(const Duration(seconds: 2));

      expect(dismisser.expectingSelfFocus, isFalse);
      dismisser.handleEvent(_windowEvent(WindowChange.focused));
      expect(popup.dismissed, <String>['popup']);
    });

    testWidgets('re-arming restarts the window rather than stacking one',
        (tester) async {
      final popup = register('popup');
      dismisser.expectSelfFocus();
      await tester.pump(const Duration(milliseconds: 800));
      dismisser.expectSelfFocus();
      await tester.pump(const Duration(milliseconds: 800));

      // Still armed 1.6s in, because the second call restarted the second.
      dismisser.handleEvent(_windowEvent(WindowChange.focused));
      expect(popup.dismissed, isEmpty);

      await tester.pump(const Duration(milliseconds: 400));
      dismisser.handleEvent(_windowEvent(WindowChange.focused));
      expect(popup.dismissed, <String>['popup']);
    });
  });
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------
//
// `Event.fromJson` over the wire shape, `test/workspace_apps_test.dart`'s
// fixtures: there is no fake `MiracleConnection` in the repo and this needs
// none, because `handleEvent` is the seam `attach`'s listener calls.

Event _windowEvent(WindowChange change) =>
    Event.fromJson(IpcType.ipcEventWindow, {
      'change': change.wireName,
      'container': <String, dynamic>{
        'id': 1,
        'name': 'Mozilla Firefox',
        'type': 'window',
        'app_id': 'firefox',
        'rect': _rect(),
      },
    });

Event _workspaceEvent(WorkspaceChange change) =>
    Event.fromJson(IpcType.ipcEventWorkspace, {
      'change': change.wireName,
      'old': null,
      'current': <String, dynamic>{
        'id': 2,
        'num': 1,
        'name': '1',
        'type': 'workspace',
        'output': 'DP-1',
        'rect': _rect(),
      },
    });

Event _outputEvent() =>
    Event.fromJson(IpcType.ipcEventOutput, {'change': 'unspecified'});

Event _tickEvent() =>
    Event.fromJson(IpcType.ipcEventTick, {'first': false, 'payload': ''});

Map<String, dynamic> _rect() =>
    <String, dynamic>{'x': 0, 'y': 0, 'width': 1920, 'height': 1080};
