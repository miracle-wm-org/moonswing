import 'package:flutter_test/flutter_test.dart';
import 'package:miracle/miracle.dart';

import 'package:graceful_shell/capture/capture_targets.dart';
import 'package:graceful_shell/capture/window_targets.dart';

/// The half of the window picker that comes from miracle: where every window
/// the user can point at is, and which output it is on.
///
/// A plain unit test over a hand-built `GET_TREE` reply — the walk is the one
/// part of the feature that can be wrong in a way nothing on screen would
/// obviously show, since a highlight in the wrong place still looks like a
/// highlight.
Map<String, dynamic> _rect(int x, int y, int w, int h) =>
    {'x': x, 'y': y, 'width': w, 'height': h};

Map<String, dynamic> _window(
  int id,
  String name,
  Map<String, dynamic> rect, {
  String? appId = 'org.example.app',
  bool visible = true,
  String type = 'con',
  Map<String, dynamic>? windowProperties,
}) =>
    {
      'type': type,
      'id': id,
      'name': name,
      'rect': rect,
      'visible': visible,
      'app_id': ?appId,
      'window_properties': ?windowProperties,
      'nodes': <dynamic>[],
      'floating_nodes': <dynamic>[],
    };

Map<String, dynamic> _workspace(
  int id,
  String output, {
  required bool visible,
  List<Map<String, dynamic>> nodes = const [],
  List<Map<String, dynamic>> floating = const [],
}) =>
    {
      'type': 'workspace',
      'id': id,
      'name': '$id',
      'num': id,
      'output': output,
      'visible': visible,
      'rect': _rect(0, 0, 1920, 1080),
      'nodes': nodes,
      'floating_nodes': floating,
    };

Map<String, dynamic> _output(
  String name,
  Map<String, dynamic> rect, {
  bool active = true,
  List<Map<String, dynamic>> workspaces = const [],
}) =>
    {
      'type': 'output',
      'id': name.hashCode,
      'name': name,
      'rect': rect,
      'active': active,
      'nodes': workspaces,
    };

BaseNode _tree(List<Map<String, dynamic>> outputs) => BaseNode.fromJson({
      'type': 'root',
      'id': 1,
      'name': 'root',
      'rect': _rect(0, 0, 3840, 1080),
      'nodes': outputs,
    });

void main() {
  group('collectOutputs', () {
    test('returns each active output in global coordinates', () {
      final tree = _tree([
        _output('DP-1', _rect(0, 0, 1920, 1080)),
        _output('HDMI-1', _rect(1920, 0, 1920, 1080)),
      ]);
      final outputs = collectOutputs(tree);
      expect(outputs.map((o) => o.name), ['DP-1', 'HDMI-1']);
      expect(outputs[1].rect.x, 1920);
      expect(outputs[1].size.width, 1920);
    });

    test('drops an inactive or zero-sized output', () {
      final tree = _tree([
        _output('DP-1', _rect(0, 0, 1920, 1080), active: false),
        _output('DP-2', _rect(0, 0, 0, 0)),
        _output('DP-3', _rect(0, 0, 800, 600)),
      ]);
      expect(collectOutputs(tree).map((o) => o.name), ['DP-3']);
    });

    test('outputNamed finds one and answers null for a stranger', () {
      final outputs =
          collectOutputs(_tree([_output('DP-1', _rect(0, 0, 800, 600))]));
      expect(outputNamed(outputs, 'DP-1')?.name, 'DP-1');
      expect(outputNamed(outputs, 'DP-9'), isNull);
    });

    group('resolveScreenOutput', () {
      // The surfaces are handed GDK's connector, and GDK has none to give on a
      // compositor with no `xdg-output` manager. An empty string matches none
      // of miracle's names, so without a second pass a window selection there
      // is a surface with nothing on it to point at.
      final outputs = collectOutputs(_tree([
        _output('DP-1', _rect(0, 0, 1920, 1080)),
        _output('HDMI-1', _rect(1920, 0, 1920, 1080)),
      ]));

      test('a name answers first', () {
        expect(resolveScreenOutput(outputs, 'HDMI-1')?.name, 'HDMI-1');
      });

      test('a name that matches nothing is not guessed past', () {
        expect(
          resolveScreenOutput(outputs, 'DP-9',
              origin: const CapturePoint(0, 0)),
          isNull,
        );
      });

      test('an unnamed surface is resolved by its corner', () {
        expect(
          resolveScreenOutput(outputs, '',
              origin: const CapturePoint(1920, 0))?.name,
          'HDMI-1',
        );
      });

      test('an unnamed surface on a lone output needs no corner', () {
        final one =
            collectOutputs(_tree([_output('DP-1', _rect(0, 0, 800, 600))]));
        expect(resolveScreenOutput(one, '')?.name, 'DP-1');
      });

      test('an unnamed surface among several, with no corner, answers null',
          () {
        expect(resolveScreenOutput(outputs, ''), isNull);
      });
    });
  });

  group('collectWindows', () {
    test('takes windows from visible workspaces and attributes the output', () {
      final tree = _tree([
        _output('DP-1', _rect(0, 0, 1920, 1080), workspaces: [
          _workspace(1, 'DP-1', visible: true, nodes: [
            _window(10, 'Editor', _rect(0, 0, 960, 1080)),
          ]),
          _workspace(2, 'DP-1', visible: false, nodes: [
            _window(11, 'Hidden', _rect(0, 0, 960, 1080)),
          ]),
        ]),
        _output('HDMI-1', _rect(1920, 0, 1920, 1080), workspaces: [
          _workspace(3, 'HDMI-1', visible: true, nodes: [
            _window(12, 'Browser', _rect(1920, 0, 1920, 1080)),
          ]),
        ]),
      ]);

      final windows = collectWindows(tree);
      expect(windows.map((w) => w.id), [10, 12],
          reason: 'a window on a workspace nobody can see cannot be pointed at');
      expect(windows.first.output, 'DP-1');
      expect(windows.last.output, 'HDMI-1');
      expect(windows.last.rect.x, 1920, reason: 'global, not output-local');
      expect(windows.first.title, 'Editor');
    });

    test('skips split containers, which have no app id', () {
      final tree = _tree([
        _output('DP-1', _rect(0, 0, 1920, 1080), workspaces: [
          _workspace(1, 'DP-1', visible: true, nodes: [
            {
              ..._window(20, 'split', _rect(0, 0, 1920, 1080), appId: null),
              'nodes': [
                _window(21, 'Left', _rect(0, 0, 960, 1080)),
                _window(22, 'Right', _rect(960, 0, 960, 1080)),
              ],
            },
          ]),
        ]),
      ]);
      expect(collectWindows(tree).map((w) => w.id), [21, 22]);
    });

    test('an XWayland window is found by its WM class', () {
      final tree = _tree([
        _output('DP-1', _rect(0, 0, 1920, 1080), workspaces: [
          _workspace(1, 'DP-1', visible: true, nodes: [
            _window(30, 'Legacy', _rect(0, 0, 800, 600),
                appId: null,
                windowProperties: const {'class': 'Xterm', 'instance': 'xterm'}),
          ]),
        ]),
      ]);
      final windows = collectWindows(tree);
      expect(windows.single.appId, 'Xterm');
    });

    test('drops a window that reports no area', () {
      final tree = _tree([
        _output('DP-1', _rect(0, 0, 1920, 1080), workspaces: [
          _workspace(1, 'DP-1', visible: true, nodes: [
            _window(40, 'Mapping', _rect(0, 0, 0, 0)),
            _window(41, 'Mapped', _rect(0, 0, 100, 100)),
          ]),
        ]),
      ]);
      expect(collectWindows(tree).map((w) => w.id), [41]);
    });
  });

  group('windowAt', () {
    late List<SelectableWindow> windows;

    setUp(() {
      windows = collectWindows(_tree([
        _output('DP-1', _rect(0, 0, 1920, 1080), workspaces: [
          _workspace(1, 'DP-1', visible: true, nodes: [
            _window(10, 'Tiled', _rect(0, 0, 1920, 1080)),
          ], floating: [
            _window(11, 'Floating', _rect(400, 300, 600, 400),
                type: 'floating_con'),
          ]),
        ]),
      ]));
    });

    test('answers the frontmost window, which is the floating one', () {
      expect(windowAt(windows, 500, 400)?.id, 11);
      expect(windowAt(windows, 50, 50)?.id, 10,
          reason: 'outside the floating window the tiled one is on top');
    });

    test('answers null off every window', () {
      expect(windowAt(windows, 5000, 5000), isNull);
    });
  });

  group('CaptureScene', () {
    test('splits its windows by output and finds an output by connector', () {
      final scene = CaptureScene.fromTree(_tree([
        _output('DP-1', _rect(0, 0, 1920, 1080), workspaces: [
          _workspace(1, 'DP-1', visible: true, nodes: [
            _window(10, 'Left', _rect(0, 0, 960, 1080)),
          ]),
        ]),
        _output('HDMI-1', _rect(1920, 0, 1920, 1080), workspaces: [
          _workspace(2, 'HDMI-1', visible: true, nodes: [
            _window(11, 'Right', _rect(1920, 0, 960, 1080)),
          ]),
        ]),
      ]));

      expect(scene.windowsOn('DP-1').map((w) => w.id), [10]);
      expect(scene.windowsOn('HDMI-1').map((w) => w.id), [11]);
      expect(scene.outputFor('HDMI-1')?.rect.x, 1920);
      expect(scene.isEmpty, isFalse);
    });

    test('the empty scene is what a shell with no IPC connection shows', () {
      expect(CaptureScene.empty.isEmpty, isTrue);
      expect(CaptureScene.empty.outputFor('DP-1'), isNull);
      expect(CaptureScene.empty.windowsOn('DP-1'), isEmpty);
    });
  });
}
