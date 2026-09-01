import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/modules/workspace_apps.dart';
import 'package:miracle/miracle.dart';

/// Pins the workspace row's app icons: the tree walk that turns a `GET_TREE`
/// reply into "what is open on each workspace", the identity matching that
/// joins it to the `GET_WORKSPACES` list the row actually renders, and the
/// lease/notify discipline of the store between them.
///
/// The tree is built as JSON and parsed by `miracle.dart`'s own `fromJson`, so
/// this also fails if the reply shape the walk assumes stops being the one the
/// library produces.
void main() {
  group('collectWorkspaceApps', () {
    test('collects one entry per workspace, across outputs', () {
      final tree = BaseNode.fromJson(_root([
        _output('DP-1', [
          _workspace(1, '1', 'DP-1', nodes: [_window('firefox')]),
          _workspace(2, '2', 'DP-1'),
        ]),
        _output('HDMI-A-1', [
          _workspace(3, '3', 'HDMI-A-1', nodes: [_window('kitty')]),
        ]),
      ]));

      final apps = collectWorkspaceApps(tree);
      expect(apps.map((a) => (a.output, a.num, a.name)), [
        ('DP-1', 1, '1'),
        ('DP-1', 2, '2'),
        ('HDMI-A-1', 3, '3'),
      ]);
      expect(apps.map((a) => a.appIds), [
        ['firefox'],
        <String>[],
        ['kitty'],
      ]);
    });

    test('descends split containers and floating nodes', () {
      final tree = BaseNode.fromJson(_root([
        _output('DP-1', [
          _workspace(1, '1', 'DP-1', nodes: [
            // A split container carries no app_id of its own; the windows are
            // its children, which is the shape every tiled workspace has.
            _split([
              _window('firefox'),
              _split([_window('kitty')]),
            ]),
          ], floating: [
            _window('org.gnome.Calculator'),
          ]),
        ]),
      ]));

      expect(collectWorkspaceApps(tree).single.appIds,
          ['firefox', 'kitty', 'org.gnome.Calculator']);
    });

    test('reports an application once however many windows it has', () {
      final tree = BaseNode.fromJson(_root([
        _output('DP-1', [
          _workspace(1, '1', 'DP-1', nodes: [
            _window('firefox'),
            _window('firefox'),
            _window('kitty'),
          ]),
        ]),
      ]));

      expect(collectWorkspaceApps(tree).single.appIds, ['firefox', 'kitty']);
    });

    test('falls back to the WM class for a window with no app_id', () {
      // XWayland toplevels carry no `app_id` at all.
      final tree = BaseNode.fromJson(_root([
        _output('DP-1', [
          _workspace(1, '1', 'DP-1', nodes: [
            _window(null, properties: {'class': 'Steam', 'instance': 'steam'}),
            _window(null, properties: {'instance': 'gimp'}),
            // Neither: a container that is not a window at all.
            _window(null),
          ]),
        ]),
      ]));

      expect(collectWorkspaceApps(tree).single.appIds, ['Steam', 'gimp']);
    });

    test('reads urgency off the workspace and off its windows alike', () {
      // The two flags answer at different moments — miracle raises the
      // workspace's while the workspace is off screen and leaves the hint on
      // the container while it is on — so the walk has to take either.
      final tree = BaseNode.fromJson(_root([
        _output('DP-1', [
          _workspace(1, '1', 'DP-1', urgent: true),
          _workspace(2, '2', 'DP-1', nodes: [
            _split([_window('kitty', urgent: true)]),
          ]),
          // A floating window shouting is the dialog case, and `descendants`
          // is what reaches it.
          _workspace(3, '3', 'DP-1',
              floating: [_window('org.gnome.Calculator', urgent: true)]),
          _workspace(4, '4', 'DP-1', nodes: [_window('firefox')]),
        ]),
      ]));

      expect(collectWorkspaceApps(tree).map((a) => a.urgent),
          [true, true, true, false]);
    });

    test('an urgent workspace still reports what is open on it', () {
      // The flash is an adornment on the same button the icons are drawn in;
      // one must not cost the other.
      final tree = BaseNode.fromJson(_root([
        _output('DP-1', [
          _workspace(1, '1', 'DP-1',
              nodes: [_window('firefox', urgent: true), _window('kitty')]),
        ]),
      ]));

      final apps = collectWorkspaceApps(tree).single;
      expect(apps.urgent, isTrue);
      expect(apps.appIds, ['firefox', 'kitty']);
    });
  });

  group('isWorkspaceUrgent', () {
    final apps = [
      const WorkspaceApps(
          output: 'DP-1', num: 1, name: '1', appIds: [], urgent: true),
      const WorkspaceApps(
          output: 'HDMI-A-1', num: 1, name: '1', appIds: [], urgent: false),
    ];

    test('matches on the output as well as the workspace', () {
      // Workspace "1" exists on both outputs; flashing the quiet monitor's
      // button because the other one is shouting is the same bug the icons'
      // own output filter exists for.
      expect(isWorkspaceUrgent(apps, _result(num: 1, name: '1', output: 'DP-1')),
          isTrue);
      expect(
          isWorkspaceUrgent(
              apps, _result(num: 1, name: '1', output: 'HDMI-A-1')),
          isFalse);
    });

    test('a workspace the tree has never mentioned is quiet', () {
      // Unknown has to read as quiet, or a row that paints before its first
      // GET_TREE lands flashes every button on the bar.
      expect(isWorkspaceUrgent(apps, _result(num: 9, name: '9', output: 'DP-1')),
          isFalse);
      expect(isWorkspaceUrgent(const [], _result(num: 1, output: 'DP-1')),
          isFalse);
    });
  });

  group('appIdsForWorkspace', () {
    final apps = [
      const WorkspaceApps(
          output: 'DP-1', num: 1, name: '1', appIds: ['firefox']),
      const WorkspaceApps(output: 'DP-1', num: 2, name: 'chat', appIds: [
        'discord',
      ]),
      const WorkspaceApps(
          output: 'HDMI-A-1', num: 1, name: '1', appIds: ['kitty']),
    ];

    test('matches on the output as well as the workspace', () {
      // Workspace "1" exists on both outputs, and a bar must never draw the
      // other monitor's windows — the bug the row's own output filter exists
      // for, one level down.
      expect(appIdsForWorkspace(apps, _result(num: 1, name: '1', output: 'DP-1')),
          ['firefox']);
      expect(
          appIdsForWorkspace(
              apps, _result(num: 1, name: '1', output: 'HDMI-A-1')),
          ['kitty']);
    });

    test('prefers a name match to a number match', () {
      expect(
          appIdsForWorkspace(
              apps, _result(num: 1, name: 'chat', output: 'DP-1')),
          ['discord']);
    });

    test('falls back to the number when the list has no name', () {
      expect(appIdsForWorkspace(apps, _result(num: 2, output: 'DP-1')),
          ['discord']);
    });

    test('answers empty for a workspace it has never seen', () {
      expect(appIdsForWorkspace(apps, _result(num: 9, name: '9', output: 'DP-1')),
          isEmpty);
      expect(appIdsForWorkspace(const [], _result(num: 1, output: 'DP-1')),
          isEmpty);
    });
  });

  group('wakesWorkspaceApps', () {
    test('a workspace or output event always does', () {
      // miracle never says which output changed, and a removed output has its
      // workspaces re-homed with no workspace event of its own.
      expect(wakesWorkspaceApps(_workspaceEvent()), isTrue);
      expect(wakesWorkspaceApps(_outputEvent()), isTrue);
    });

    test('only the window changes that move a window between workspaces do',
        () {
      for (final change in [
        WindowChange.created,
        WindowChange.closed,
        WindowChange.moved,
      ]) {
        expect(wakesWorkspaceApps(_windowEvent(change)), isTrue,
            reason: change.name);
      }
      // `focused` is the load-bearing exclusion: it fires on every alt-tab,
      // and an unfiltered listener would re-read the whole tree each time.
      for (final change in [
        WindowChange.focused,
        WindowChange.fullscreenMode,
        WindowChange.floating,
        WindowChange.marked,
      ]) {
        expect(wakesWorkspaceApps(_windowEvent(change)), isFalse,
            reason: change.name);
      }
    });

    test('an unmodelled window change re-reads rather than going stale', () {
      expect(wakesWorkspaceApps(_windowEvent(WindowChange.unknown)), isTrue);
    });

    test('an event about something else does not', () {
      expect(wakesWorkspaceApps(_tickEvent()), isFalse);
    });
  });

  group('WorkspaceAppsStore', () {
    late WorkspaceAppsStore store;
    late StreamController<Event> events;
    late int fetches;
    late List<Map<String, dynamic>> workspaces;

    setUp(() {
      store = WorkspaceAppsStore.forTesting();
      events = StreamController<Event>.broadcast();
      fetches = 0;
      workspaces = [_workspace(1, '1', 'DP-1', nodes: [_window('firefox')])];
      store.attachSource(WorkspaceTreeSource(
        token: Object(),
        getTree: () async {
          fetches++;
          return BaseNode.fromJson(_root([_output('DP-1', workspaces)]));
        },
        events: events.stream,
      ));
    });

    tearDown(() {
      store.dispose();
      events.close();
    });

    test('reads nothing until something holds a lease', () async {
      events.add(_workspaceEvent());
      await pumpEventQueue();
      expect(fetches, 0, reason: 'the icons are switched off — no GET_TREE');

      store.acquire();
      await pumpEventQueue();
      expect(fetches, 1, reason: 'the first lease fetches straight away');
      expect(store.appIdsFor(_result(num: 1, name: '1', output: 'DP-1')),
          ['firefox']);
    });

    test('a second lease shares the first ones fetch', () async {
      store.acquire();
      await pumpEventQueue();
      store.acquire();
      await pumpEventQueue();
      expect(fetches, 1, reason: 'one poller for the machine, not one per bar');

      store.release();
      await pumpEventQueue();
      events.add(_workspaceEvent());
      await pumpEventQueue();
      expect(fetches, 2, reason: 'a bar is still holding the other lease');

      store.release();
      await pumpEventQueue();
      events.add(_workspaceEvent());
      await pumpEventQueue();
      expect(fetches, 2, reason: 'the last release stops the reads');
    });

    test('a window opening re-reads the tree', () async {
      store.acquire();
      await pumpEventQueue();

      workspaces = [
        _workspace(1, '1', 'DP-1', nodes: [_window('firefox'), _window('kitty')])
      ];
      // The event that replaced the poll: a window opening on a workspace that
      // already had one emits no workspace event at all.
      events.add(_windowEvent(WindowChange.created));
      await pumpEventQueue();

      expect(fetches, 2);
      expect(store.appIdsFor(_result(num: 1, name: '1', output: 'DP-1')),
          ['firefox', 'kitty']);
    });

    test('a focus change reads nothing', () async {
      store.acquire();
      await pumpEventQueue();

      events.add(_windowEvent(WindowChange.focused));
      events.add(_windowEvent(WindowChange.marked));
      await pumpEventQueue();

      expect(fetches, 1, reason: 'alt-tab must not cost a GET_TREE');
    });

    test('events arriving mid-flight coalesce into one more read', () async {
      final gate = Completer<void>();
      final coalescing = WorkspaceAppsStore.forTesting();
      addTearDown(coalescing.dispose);
      var reads = 0;
      final burst = StreamController<Event>.broadcast();
      addTearDown(burst.close);
      coalescing.attachSource(WorkspaceTreeSource(
        token: Object(),
        getTree: () async {
          reads++;
          // Only the first read is held open; the rest resolve at once.
          if (reads == 1) await gate.future;
          return BaseNode.fromJson(_root([_output('DP-1', workspaces)]));
        },
        events: burst.stream,
      ));

      coalescing.acquire();
      await pumpEventQueue();
      expect(reads, 1, reason: 'the lease read, and it is still in flight');

      // Opening three windows in a burst is three events over one round-trip.
      // With no timer behind this, dropping them would leave the row stale
      // until something unrelated happened.
      burst.add(_windowEvent(WindowChange.created));
      burst.add(_windowEvent(WindowChange.created));
      burst.add(_windowEvent(WindowChange.created));
      await pumpEventQueue();
      expect(reads, 1, reason: 'none of them started a second read');

      gate.complete();
      await pumpEventQueue();
      expect(reads, 2, reason: 'the three collapsed into exactly one more');

      coalescing.release();
    });

    test('notifies only when the tree actually moved', () async {
      var notifications = 0;
      store.addListener(() => notifications++);

      store.acquire();
      await pumpEventQueue();
      expect(notifications, 1);

      // The poll wakes on a timer and every panel on every monitor listens;
      // re-laying every bar to redraw the same icons is what this guard stops.
      events.add(_workspaceEvent());
      await pumpEventQueue();
      expect(fetches, 2);
      expect(notifications, 1, reason: 'same tree, no rebuild');

      workspaces = [_workspace(1, '1', 'DP-1', nodes: [_window('kitty')])];
      events.add(_workspaceEvent());
      await pumpEventQueue();
      expect(notifications, 2);

      store.release();
    });

    test('a window raising its urgency hint is a change worth publishing',
        () async {
      var notifications = 0;
      store.acquire();
      await pumpEventQueue();
      store.addListener(() => notifications++);

      final quiet = _result(num: 1, name: '1', output: 'DP-1');
      expect(store.isUrgent(quiet), isFalse);

      // Nothing about *which* applications are open moved, so a signature
      // carrying only the app ids would call this tree unchanged and the flash
      // would never start.
      workspaces = [
        _workspace(1, '1', 'DP-1', nodes: [_window('firefox', urgent: true)])
      ];
      // i3-style `window::urgent` is a change miracle.dart does not model, so
      // it arrives as `unknown` — which is exactly why that case re-reads.
      events.add(_windowEvent(WindowChange.unknown));
      await pumpEventQueue();

      expect(notifications, 1);
      expect(store.isUrgent(quiet), isTrue);

      workspaces = [
        _workspace(1, '1', 'DP-1', nodes: [_window('firefox')])
      ];
      events.add(_windowEvent(WindowChange.unknown));
      await pumpEventQueue();

      expect(notifications, 2, reason: 'and the flash has to be able to stop');
      expect(store.isUrgent(quiet), isFalse);

      store.release();
    });

    test('a tree that will not parse costs the icons, never the row', () async {
      final broken = WorkspaceAppsStore.forTesting();
      addTearDown(broken.dispose);
      broken.attachSource(WorkspaceTreeSource(
        token: Object(),
        getTree: () async => throw Exception('malformed node'),
        events: const Stream<Event>.empty(),
      ));

      broken.acquire();
      await pumpEventQueue();
      expect(broken.appIdsFor(_result(num: 1, output: 'DP-1')), isEmpty);
      broken.release();
    });

    test('a reconnect drops what the old connection was still fetching',
        () async {
      final slow = Completer<BaseNode>();
      final replaced = WorkspaceAppsStore.forTesting();
      addTearDown(replaced.dispose);
      replaced.attachSource(WorkspaceTreeSource(
        token: Object(),
        getTree: () => slow.future,
        events: const Stream<Event>.empty(),
      ));
      replaced.acquire();
      await pumpEventQueue();

      // A MiracleConnection is single-use, so a reconnect is a different
      // object; whatever the dead one is still holding is not this shell's
      // state any more.
      replaced.attachSource(WorkspaceTreeSource(
        token: Object(),
        getTree: () async =>
            BaseNode.fromJson(_root([_output('DP-1', const [])])),
        events: const Stream<Event>.empty(),
      ));
      slow.complete(BaseNode.fromJson(_root([
        _output('DP-1', [
          _workspace(1, '1', 'DP-1', nodes: [_window('firefox')])
        ])
      ])));
      await pumpEventQueue();

      expect(replaced.appIdsFor(_result(num: 1, name: '1', output: 'DP-1')),
          isEmpty);
      replaced.release();
    });
  });

  group('WorkspacesConfig', () {
    test('defaults to showing the icons', () {
      const config = WorkspacesConfig();
      expect(config.showAppIcons, isTrue);
      expect(WorkspacesConfig.fromMap(null).showAppIcons, isTrue);
      expect(WorkspacesConfig.fromMap({}).showAppIcons, isTrue);
    });

    test('reads its keys, and degrades one bad value at a time', () {
      final config = WorkspacesConfig.fromMap({
        'show_app_icons': false,
        // A TOML float where an int is wanted, the config_reader contract.
        'icon_size': 20.0,
        'max_icons': 'lots',
      });
      expect(config.showAppIcons, isFalse);
      expect(config.iconSize, 20);
      expect(config.maxIcons, const WorkspacesConfig().maxIcons);
    });

    test('clamps a value a painter could not use', () {
      expect(WorkspacesConfig.fromMap({'icon_size': 900}).iconSize, 64);
      expect(WorkspacesConfig.fromMap({'max_icons': 0}).maxIcons, 1);
    });

    test('flashes urgent workspaces by default, slowly', () {
      const config = WorkspacesConfig();
      expect(config.flashUrgent, isTrue);
      expect(WorkspacesConfig.fromMap({}).flashUrgent, isTrue);
      // The whole point of the feature: a breath, not a blink.
      expect(config.urgentFlashSeconds, greaterThanOrEqualTo(3.0));
      expect(WorkspacesConfig.fromMap({}).urgentFlashSeconds,
          config.urgentFlashSeconds);
    });

    test('reads and clamps the flash keys', () {
      expect(
          WorkspacesConfig.fromMap({'flash_urgent': false}).flashUrgent, isFalse);
      expect(
          WorkspacesConfig.fromMap({'urgent_flash_seconds': 8}).urgentFlashSeconds,
          8.0);
      // A period near zero is a strobe in the corner of the eye, and one past
      // half a minute never visibly moves.
      expect(
          WorkspacesConfig.fromMap({'urgent_flash_seconds': 0})
              .urgentFlashSeconds,
          1.0);
      expect(
          WorkspacesConfig.fromMap({'urgent_flash_seconds': 600})
              .urgentFlashSeconds,
          30.0);
      expect(
          WorkspacesConfig.fromMap({'urgent_flash_seconds': 'slowly'})
              .urgentFlashSeconds,
          const WorkspacesConfig().urgentFlashSeconds);
    });
  });
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

int _nextId = 1;

WorkspaceResult _result({required int num, String? name, required String output}) =>
    WorkspaceResult.fromJson({
      'num': num,
      'name': name,
      'visible': true,
      'focused': true,
      // Always false, and deliberately so: miracle.dart documents
      // `GET_WORKSPACES`'s `urgent` as legacy and never set, which is why the
      // flash reads the tree instead.
      'urgent': false,
      'output': output,
      'rect': _rect(),
    });

Event _workspaceEvent() => Event.fromJson(IpcType.ipcEventWorkspace, {
      'change': 'focus',
      'old': null,
      'current': _workspace(1, '1', 'DP-1'),
    });

Event _windowEvent(WindowChange change) =>
    Event.fromJson(IpcType.ipcEventWindow, {
      'change': change.wireName,
      'container': _window('firefox'),
    });

Event _outputEvent() =>
    Event.fromJson(IpcType.ipcEventOutput, {'change': 'unspecified'});

Event _tickEvent() => Event.fromJson(
    IpcType.ipcEventTick, {'first': false, 'payload': ''});

Map<String, dynamic> _rect() =>
    {'x': 0, 'y': 0, 'width': 1920, 'height': 1080};

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
  List<Map<String, dynamic>> nodes = const [],
  List<Map<String, dynamic>> floating = const [],
  bool urgent = false,
}) =>
    {
      'id': _nextId++,
      'name': name,
      'type': 'workspace',
      'rect': _rect(),
      'num': num,
      'visible': true,
      'focused': false,
      'urgent': urgent,
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

/// A container holding other containers — no `app_id` of its own.
Map<String, dynamic> _split(List<Map<String, dynamic>> children) =>
    _window(null, nodes: children);

Map<String, dynamic> _window(
  String? appId, {
  Map<String, dynamic>? properties,
  List<Map<String, dynamic>> nodes = const [],
  List<Map<String, dynamic>> floating = const [],
  bool urgent = false,
}) =>
    {
      'id': _nextId++,
      'name': appId ?? '',
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
      'urgent': urgent,
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
