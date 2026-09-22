import 'package:flutter_test/flutter_test.dart';
import 'package:miracle/miracle.dart';

import 'package:moonswing/switcher/open_window.dart';
import 'package:moonswing/switcher/open_window_store.dart';
import 'package:moonswing/switcher/switcher_controller.dart';
import 'package:moonswing/switcher/window_activation.dart';

/// The window switcher, minus its Wayland and its socket: the ordering, the
/// cycling, the grid arithmetic, the join back to miracle's tree, and the
/// session the overlay is drawn from.
///
/// The tree is built as JSON and parsed by `miracle.dart`'s own `fromJson`, so
/// this also fails if the reply shape [locateWindow] walks stops being the one
/// the library produces — `workspace_apps_test.dart`'s rule.
void main() {
  group('orderByRecency', () {
    test('puts the recency list first and keeps the rest in place', () {
      final windows = [_w('a'), _w('b'), _w('c'), _w('d')];
      expect(
        orderByRecency(windows, ['c', 'a']).map((w) => w.identifier),
        ['c', 'a', 'b', 'd'],
      );
    });

    test('ignores identifiers whose window has closed', () {
      final windows = [_w('a'), _w('b')];
      expect(
        orderByRecency(windows, ['gone', 'b']).map((w) => w.identifier),
        ['b', 'a'],
      );
    });

    test('an empty recency list is the compositor\'s own order', () {
      // What a shell with no IPC connection has all the time — which must be a
      // working switcher, not an empty one.
      final windows = [_w('a'), _w('b')];
      expect(orderByRecency(windows, const []), same(windows));
    });
  });

  group('promoteRecent', () {
    test('moves an identifier to the front without duplicating it', () {
      expect(promoteRecent(['a', 'b', 'c'], 'c'), ['c', 'a', 'b']);
    });

    test('a focus on what is already first changes nothing', () {
      final recent = ['a', 'b'];
      // Identity, not equality: the store skips its own work on this.
      expect(promoteRecent(recent, 'a'), same(recent));
    });

    test('is bounded, so a long session does not grow it forever', () {
      var recent = <String>[];
      for (var i = 0; i < 200; i++) {
        recent = promoteRecent(recent, 'w$i', limit: 8);
      }
      expect(recent.length, 8);
      expect(recent.first, 'w199');
    });

    test('an empty identifier is not a window', () {
      final recent = ['a'];
      expect(promoteRecent(recent, ''), same(recent));
    });
  });

  group('OpenWindowStore', () {
    test('a focus reorders the list it matches a window in', () {
      // The half of the recency order the foreign-toplevel protocol cannot
      // report: `ext-foreign-toplevel-list-v1` carries no focus state at all,
      // so it comes from miracle's `window` events joined on what the window
      // calls itself.
      final store = OpenWindowStore.forTesting();
      addTearDown(store.dispose);
      store.setWindowsForTesting([
        _w('a', appId: 'kitty', title: 'shell'),
        _w('b', appId: 'firefox', title: 'Inbox'),
      ]);
      expect(store.windows.map((w) => w.identifier), ['a', 'b']);

      final focused = matchOpenWindow(
        store.windows,
        appId: 'firefox',
        title: 'Inbox',
      );
      expect(focused, 'b');
      store.promoteForTesting(focused!);
      expect(store.windows.map((w) => w.identifier), ['b', 'a']);
    });

    test('a focus it cannot attribute leaves the order alone', () {
      final store = OpenWindowStore.forTesting();
      addTearDown(store.dispose);
      store.setWindowsForTesting([
        _w('a', appId: 'firefox', title: 'Mozilla Firefox'),
        _w('b', appId: 'firefox', title: 'Mozilla Firefox'),
      ]);
      // Two indistinguishable windows: the matcher declines rather than
      // guessing, and the order is simply not improved.
      expect(
        matchOpenWindow(
          store.windows,
          appId: 'firefox',
          title: 'Mozilla Firefox',
        ),
        isNull,
      );
      expect(store.windows.map((w) => w.identifier), ['a', 'b']);
    });

    test('a read that finds nothing new does not notify', () {
      // Every overlay surface on every monitor listens, and `done` fires on
      // every retitle — which for a browser is every tab switch.
      final store = OpenWindowStore.forTesting();
      addTearDown(store.dispose);
      var notifications = 0;
      store.addListener(() => notifications++);

      store.setWindowsForTesting([_w('a')]);
      expect(notifications, 1);
      store.setWindowsForTesting([_w('a')]);
      expect(notifications, 1);
      store.setWindowsForTesting([_w('a', title: 'renamed')]);
      expect(notifications, 2);
    });
  });

  group('cycleIndex', () {
    test('wraps in both directions', () {
      expect(cycleIndex(2, 1, 3), 0);
      expect(cycleIndex(0, -1, 3), 2);
      expect(cycleIndex(0, 5, 3), 2);
      expect(cycleIndex(0, -5, 3), 1);
    });

    test('an empty list has nowhere to go and does not throw', () {
      expect(cycleIndex(0, 1, 0), 0);
    });
  });

  group('the grid', () {
    test('wraps at five', () {
      expect(kSwitcherColumns, 5);
      expect(switcherRowOf(4), 0);
      expect(switcherRowOf(5), 1);
      expect(switcherRowCount(0), 0);
      expect(switcherRowCount(5), 1);
      expect(switcherRowCount(6), 2);
    });

    test('scrolls the least that brings the row into view', () {
      // A viewport two rows tall over four rows of 100.
      double offsetFor(int row, double offset) => switcherScrollOffset(
        row: row,
        rowExtent: 100,
        viewportExtent: 200,
        offset: offset,
        rowCount: 4,
      );

      // Already visible: no move at all, so cycling along a row does not
      // nudge the grid under the user.
      expect(offsetFor(0, 0), 0);
      expect(offsetFor(1, 0), 0);
      // Below: just enough to sit at the bottom edge.
      expect(offsetFor(2, 0), 100);
      // Above: just enough to sit at the top edge.
      expect(offsetFor(0, 150), 0);
      // Never past the end of the list.
      expect(offsetFor(3, 0), 200);
    });

    test('a grid shorter than its viewport never scrolls', () {
      expect(
        switcherScrollOffset(
          row: 1,
          rowExtent: 100,
          viewportExtent: 400,
          offset: 0,
          rowCount: 2,
        ),
        0,
      );
    });
  });

  group('OpenWindow.label', () {
    test('is the title, because that is what tells two windows apart', () {
      expect(_w('a', appId: 'firefox', title: 'Inbox').label, 'Inbox');
    });

    test('falls back to the app id, then to something readable', () {
      expect(_w('a', appId: 'firefox', title: '').label, 'firefox');
      expect(_w('a', appId: '', title: '').label, isNotEmpty);
    });
  });

  group('locateWindow', () {
    test('finds the container, its workspace and whether it is focused', () {
      final tree = BaseNode.fromJson(_root([
        _output('DP-1', [
          _workspace(1, '1', 'DP-1', focused: true, nodes: [
            _window(id: 10, appId: 'kitty', title: 'shell'),
          ]),
          _workspace(2, '2', 'DP-1', nodes: [
            _window(id: 11, appId: 'firefox', title: 'Inbox'),
          ]),
        ]),
      ]));
      final toplevels = [
        _w('t1', appId: 'kitty', title: 'shell').descriptor,
        _w('t2', appId: 'firefox', title: 'Inbox').descriptor,
      ];

      expect(
        locateWindow(tree, toplevels, 't2'),
        const WindowLocation(
          containerId: 11,
          workspace: '2',
          workspaceFocused: false,
        ),
      );
      expect(
        locateWindow(tree, toplevels, 't1'),
        const WindowLocation(
          containerId: 10,
          workspace: '1',
          workspaceFocused: true,
        ),
      );
    });

    test('descends split containers and floating nodes', () {
      final tree = BaseNode.fromJson(_root([
        _output('DP-1', [
          _workspace(1, '1', 'DP-1', nodes: [
            _split([_window(id: 20, appId: 'kitty', title: 'shell')]),
          ], floating: [
            _window(id: 21, appId: 'org.gnome.Calculator', title: 'Calculator'),
          ]),
        ]),
      ]));
      final toplevels = [
        _w('t1', appId: 'kitty', title: 'shell').descriptor,
        _w('t2', appId: 'org.gnome.Calculator', title: 'Calculator').descriptor,
      ];

      expect(locateWindow(tree, toplevels, 't1')?.containerId, 20);
      expect(locateWindow(tree, toplevels, 't2')?.containerId, 21);
    });

    test('two indistinguishable windows are a refusal, not a coin toss', () {
      // Switching to somebody's *other* Firefox window is worse than the
      // gesture appearing not to have worked.
      final tree = BaseNode.fromJson(_root([
        _output('DP-1', [
          _workspace(1, '1', 'DP-1', nodes: [
            _window(id: 30, appId: 'firefox', title: 'Mozilla Firefox'),
            _window(id: 31, appId: 'firefox', title: 'Mozilla Firefox'),
          ]),
        ]),
      ]));
      final toplevels = [
        _w('t1', appId: 'firefox', title: 'Mozilla Firefox').descriptor,
        _w('t2', appId: 'firefox', title: 'Mozilla Firefox').descriptor,
      ];

      expect(locateWindow(tree, toplevels, 't1'), isNull);
    });

    test('a named workspace is addressed by its name', () {
      // miracle reports a named workspace's number as the placeholder -1,
      // which addresses nothing.
      final tree = BaseNode.fromJson(_root([
        _output('DP-1', [
          _workspace(-1, 'mail', 'DP-1', nodes: [
            _window(id: 40, appId: 'thunderbird', title: 'Inbox'),
          ]),
        ]),
      ]));
      final toplevels = [
        _w('t1', appId: 'thunderbird', title: 'Inbox').descriptor,
      ];

      expect(locateWindow(tree, toplevels, 't1')?.workspace, 'mail');
    });

    test('an empty identifier matches nothing', () {
      final tree = BaseNode.fromJson(_root([_output('DP-1', const [])]));
      expect(locateWindow(tree, const [], ''), isNull);
    });
  });

  group('the commands a switch sends', () {
    test('hops to the workspace first, then focuses the window', () {
      final commands = switchToWindowCommands(const WindowLocation(
        containerId: 7,
        workspace: '3',
        workspaceFocused: false,
      ));
      expect(commands.length, 2);
      expect(commands.first.toString(), contains('workspace'));
      expect(commands.first.toString(), contains('3'));
      expect(commands.last.toString(), contains('con_id=7'));
      expect(commands.last.toString(), contains('focus'));
    });

    test('no hop when the workspace is already the focused one', () {
      // `workspace <n>` on the current one is miracle's back-and-forth toggle,
      // so sending it anyway would switch away from the window being switched
      // to.
      final commands = switchToWindowCommands(const WindowLocation(
        containerId: 7,
        workspace: '3',
        workspaceFocused: true,
      ));
      expect(commands.single.toString(), contains('con_id=7'));
    });

    test('no hop when miracle named the workspace nothing addressable', () {
      final commands = switchToWindowCommands(const WindowLocation(
        containerId: 7,
        workspace: null,
        workspaceFocused: false,
      ));
      expect(commands.single.toString(), contains('con_id=7'));
    });

    test('the fallback is the application, and nothing for a nameless one', () {
      expect(switchToAppCommands('firefox').single.toString(),
          contains('app_id='));
      expect(switchToAppCommands(''), isEmpty);
    });
  });

  group('WindowSwitcherController', () {
    test('the first press opens on the previous window', () {
      // The list is most-recently-used first, so index 0 is the window the
      // user is already in: one step from there is "go back".
      final controller = WindowSwitcherController.forTesting(
        readWindows: () => [_w('a'), _w('b'), _w('c')],
      );
      addTearDown(controller.dispose);

      controller.cycle(forward: true);
      expect(controller.isOpen, isTrue);
      expect(controller.selection.value, 1);
      expect(controller.selected?.identifier, 'b');
    });

    test('backwards from closed lands on the last window', () {
      final controller = WindowSwitcherController.forTesting(
        readWindows: () => [_w('a'), _w('b'), _w('c')],
      );
      addTearDown(controller.dispose);

      controller.cycle(forward: false);
      expect(controller.selection.value, 2);
    });

    test('later presses move without reopening or re-reading', () {
      var reads = 0;
      final controller = WindowSwitcherController.forTesting(
        readWindows: () {
          reads++;
          return [_w('a'), _w('b'), _w('c')];
        },
      );
      addTearDown(controller.dispose);

      controller.cycle(forward: true);
      controller.cycle(forward: true);
      controller.cycle(forward: true);
      expect(reads, 1);
      expect(controller.selection.value, 0);
    });

    test('cycling notifies nobody — only the session does', () {
      // The root builds a native window per output off this notifier; a notify
      // per press of Tab would rebuild all of them several times a second.
      final controller = WindowSwitcherController.forTesting(
        readWindows: () => [_w('a'), _w('b')],
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.cycle(forward: true);
      expect(notifications, 1);
      controller.cycle(forward: true);
      controller.cycle(forward: true);
      expect(notifications, 1);
    });

    test('committing switches to the highlighted window and ends', () {
      OpenWindow? switched;
      final controller = WindowSwitcherController.forTesting(
        readWindows: () => [_w('a'), _w('b')],
        activate: (window, _) async {
          switched = window;
        },
      );
      addTearDown(controller.dispose);

      controller.cycle(forward: true);
      controller.commit();
      expect(switched?.identifier, 'b');
      expect(controller.isOpen, isFalse);
    });

    test('the keyboard grab goes back before the switch is asked for', () {
      // The surface that read the release holds the keyboard exclusively, which
      // is `mir_focus_mode_grabbing` to Mir, and miral refuses every focus
      // change while a grabbing window is the active one. A switch sent with
      // the grab still up is accepted, reported successful and dropped, so the
      // order of these two is the whole of the fix.
      final order = <String>[];
      final controller = WindowSwitcherController.forTesting(
        readWindows: () => [_w('a'), _w('b')],
        activate: (_, _) async {
          order.add('switch');
        },
      );
      addTearDown(controller.dispose);
      controller.onReleaseKeyboard = () => order.add('release');

      controller.cycle(forward: true);
      controller.commit();
      expect(order, ['release', 'switch']);
    });

    test('a commit with nothing highlighted still gives the grab back', () {
      // No window to switch to is not a session that keeps the keyboard: the
      // gesture is over either way, and a grab nobody hands back is one the
      // compositor only drops when the surface goes.
      var releases = 0;
      final controller = WindowSwitcherController.forTesting(
        readWindows: () => <OpenWindow>[],
      );
      addTearDown(controller.dispose);
      controller.onReleaseKeyboard = () => releases++;

      controller.cycle(forward: true);
      expect(controller.selected, isNull);
      controller.commit();
      expect(releases, 1);
    });

    test('a commit on a session that already ended asks for nothing', () {
      var releases = 0;
      var switches = 0;
      final controller = WindowSwitcherController.forTesting(
        readWindows: () => [_w('a'), _w('b')],
        activate: (_, _) async {
          switches++;
        },
      );
      addTearDown(controller.dispose);
      controller.onReleaseKeyboard = () => releases++;

      controller.cycle(forward: true);
      controller.commit();
      controller.commit();
      expect(releases, 1);
      expect(switches, 1);
    });

    test('cancelling switches to nothing', () {
      var switches = 0;
      final controller = WindowSwitcherController.forTesting(
        readWindows: () => [_w('a'), _w('b')],
        activate: (_, _) async {
          switches++;
        },
      );
      addTearDown(controller.dispose);

      controller.cycle(forward: true);
      controller.cancel();
      expect(switches, 0);
      expect(controller.isOpen, isFalse);
    });

    test('the session outlives itself, so the exit animation has a list', () {
      // The overlay stays mounted through its fade; a controller that emptied
      // itself on commit would blank the grid the user is watching leave.
      final controller = WindowSwitcherController.forTesting(
        readWindows: () => [_w('a'), _w('b')],
        activate: (_, _) async {},
      );
      addTearDown(controller.dispose);

      controller.cycle(forward: true);
      controller.commit();
      expect(controller.windows, hasLength(2));
      expect(controller.selection.value, 1);
    });

    test('nothing open is a session that can still be cancelled', () {
      final controller = WindowSwitcherController.forTesting(
        readWindows: () => const [],
        activate: (_, _) async => fail('there was nothing to switch to'),
      );
      addTearDown(controller.dispose);

      controller.cycle(forward: true);
      expect(controller.isOpen, isTrue);
      expect(controller.selected, isNull);
      controller.commit();
      expect(controller.isOpen, isFalse);
    });

    test('the pointer cannot select outside the list', () {
      final controller = WindowSwitcherController.forTesting(
        readWindows: () => [_w('a'), _w('b')],
      );
      addTearDown(controller.dispose);

      controller.cycle(forward: true);
      controller.select(9);
      expect(controller.selection.value, 1);
      controller.select(0);
      expect(controller.selection.value, 0);
    });
  });
}

OpenWindow _w(String identifier, {String appId = 'app', String title = 'w'}) =>
    OpenWindow(identifier: identifier, appId: appId, title: title);

// ---------------------------------------------------------------------------
// A `GET_TREE` reply, as JSON
// ---------------------------------------------------------------------------

int _nextId = 1000;

Map<String, dynamic> _rect() => {
  'x': 0,
  'y': 0,
  'width': 1920,
  'height': 1080,
};

Map<String, dynamic> _root(List<Map<String, dynamic>> outputs) => {
  'id': _nextId++,
  'name': 'root',
  'type': 'root',
  'rect': _rect(),
  'nodes': outputs,
};

Map<String, dynamic> _output(String name, List<Map<String, dynamic>> spaces) {
  const mode = {'width': 1920, 'height': 1080, 'refresh': 60000.0};
  return {
    'id': _nextId++,
    'name': name,
    'type': 'output',
    'rect': _rect(),
    'active': true,
    'dpkms': true,
    'scale': 1.0,
    'scale_filter': 'nearest',
    'adaptive_sync_status': false,
    'make': 'Make',
    'model': 'Model',
    'serial': 'Serial',
    'transform': 'normal',
    'layout': 'output',
    'orientation': 'none',
    'visible': true,
    'focused': false,
    'urgent': false,
    'border': 'none',
    'current_border_width': 0,
    'window_rect': _rect(),
    'deco_rect': _rect(),
    'geometry': _rect(),
    'modes': [mode],
    'current_mode': mode,
    'nodes': spaces,
  };
}

Map<String, dynamic> _workspace(
  int num,
  String name,
  String output, {
  bool focused = false,
  List<Map<String, dynamic>> nodes = const [],
  List<Map<String, dynamic>> floating = const [],
}) => {
  'id': _nextId++,
  'name': name,
  'type': 'workspace',
  'rect': _rect(),
  'num': num,
  'visible': true,
  'focused': focused,
  'urgent': false,
  'output': output,
  'border': 'none',
  'current_border_width': 0,
  'layout': 'splith',
  'orientation': 'horizontal',
  'window_rect': _rect(),
  'deco_rect': _rect(),
  'geometry': _rect(),
  'nodes': nodes,
  'floating_nodes': floating,
};

/// A container holding other containers — no `app_id` and no title of its own.
Map<String, dynamic> _split(List<Map<String, dynamic>> children) =>
    _window(id: _nextId++, appId: null, title: '', nodes: children);

Map<String, dynamic> _window({
  required int id,
  required String? appId,
  required String title,
  Map<String, dynamic>? properties,
  List<Map<String, dynamic>> nodes = const [],
  List<Map<String, dynamic>> floating = const [],
}) => {
  'id': id,
  'name': title,
  'type': 'con',
  'rect': _rect(),
  'focused': false,
  'focus': <int>[],
  'border': 'none',
  'current_border_width': 0,
  'layout': 'none',
  'orientation': 'none',
  'percent': null,
  'window_rect': _rect(),
  'deco_rect': _rect(),
  'geometry': _rect(),
  'window': null,
  'urgent': false,
  'sticky': false,
  'fullscreen_mode': 0,
  'pid': null,
  'app_id': appId,
  'visible': true,
  'shell': 'xdg_shell',
  'inhibit_idle': false,
  'idle_inhibitors': null,
  'window_properties': properties ?? <String, dynamic>{},
  'nodes': nodes,
  'floating_nodes': floating,
  'scratchpad_state': null,
};
