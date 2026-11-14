import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/control/control_api.dart';
import 'package:moonswing/control/control_config.dart';
import 'package:moonswing/control/shell_control_server.dart';
import 'package:moonswing/mcp/compositor_client.dart';
import 'package:moonswing/mcp/mcp_protocol.dart';
import 'package:moonswing/mcp/moonswing_tools.dart';
import 'package:moonswing/mcp/shell_client.dart';
import 'package:moonswing/overlay/settings_route.dart';
import 'package:moonswing/todo/todo_model.dart';

/// `org.moonswing.Shell1` end to end: the MCP tools a model calls, over a real
/// D-Bus connection (an in-process bus, so no session bus is needed), into the
/// shell's exported object, against a fake of what the shell does. The live
/// half — `LiveShellControl` — is only the stores every other test already
/// covers; what can go wrong *here* is a signature or a field order disagreeing
/// between the two ends, which is exactly what this round trip catches.
class _FakeShell implements ShellControl {
  final List<String> calls = [];
  final List<ControlTodo> board = [];
  String theme = 'glassy';
  bool dnd = false;
  double level = 0.5;

  @override
  Map<String, Object> status() =>
      {'api': kShellControlApiVersion, 'theme': theme, 'do_not_disturb': dnd};

  @override
  List<ControlAction> actions() => [
        for (final action in ShellAction.values)
          ControlAction(action,
              unavailable: action.needsMiracle ? 'Not miracle.' : null),
      ];

  @override
  void activate(ShellAction action) => calls.add('activate ${action.id}');

  @override
  void openOverview(String tab) => calls.add('overview $tab');

  @override
  void openSettings(String category, String module) =>
      calls.add('settings $category/$module');

  @override
  List<ControlTheme> themes() => const [
        ControlTheme(slug: 'glassy', name: 'Glassy', builtIn: true),
        ControlTheme(slug: 'dracula', name: 'Dracula', builtIn: true),
      ];

  @override
  void setTheme(String slug) {
    if (!themes().any((t) => t.slug == slug)) {
      throw ShellControlException.invalidArgs('There is no theme "$slug".');
    }
    theme = slug;
  }

  @override
  List<ControlTimer> timers() => const [
        ControlTimer(
          id: 3,
          stopwatch: false,
          label: 'Tea',
          running: true,
          finished: false,
          reading: Duration(minutes: 2, seconds: 5),
        ),
      ];

  @override
  int startTimer(Duration duration, String label) {
    calls.add('timer ${duration.inSeconds} $label');
    return 4;
  }

  @override
  int startStopwatch() => 5;

  @override
  void timerControl(int id, String operation) =>
      calls.add('timer $id $operation');

  @override
  List<ControlTodo> todos() => board;

  @override
  String addTodo(String title, String body, String column, DateTime? due) {
    final id = 'card-${board.length + 1}';
    board.add(ControlTodo(
        id: id, column: column, title: title, body: body, due: due));
    return id;
  }

  @override
  void moveTodo(String id, String column) => calls.add('move $id $column');

  @override
  void deleteTodo(String id) => calls.add('delete $id');

  @override
  String addNote(String title, String body) => 'note-1';

  @override
  List<ControlNotification> notifications() => [
        ControlNotification(
          id: 9,
          appName: 'Mail',
          summary: 'New message',
          body: 'Hi',
          arrivedAt: DateTime(2026, 11, 14, 9),
          read: false,
        ),
      ];

  @override
  void dismissNotification(int id) => calls.add('dismiss $id');

  @override
  void setDoNotDisturb(bool value) => dnd = value;

  @override
  List<ControlApp> searchApps(String query, int limit) => [
        const ControlApp(
            id: 'firefox', name: 'Firefox', description: 'Web Browser'),
      ].take(limit).toList();

  @override
  void launchApp(String id) => calls.add('launch $id');

  @override
  Future<({double volume, bool muted})> volume() async =>
      (volume: level, muted: false);

  @override
  Future<void> setVolume(double volume) async => level = volume;

  @override
  Future<void> setMuted(bool muted) async => calls.add('muted $muted');

  @override
  Future<Uint8List> screenshot(String output, int maxWidth) async {
    calls.add('screenshot "$output" $maxWidth');
    return Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);
  }
}

void main() {
  test('the interface\'s ids are the shell\'s', () {
    expect(kControlOverviewTabs, [
      OverviewTab.calendar,
      OverviewTab.system,
      OverviewTab.systemInfo,
      OverviewTab.settings,
      OverviewTab.todo,
      OverviewTab.code,
      OverviewTab.shortcuts,
    ]);
    expect(kControlTodoColumns, [for (final c in TodoColumn.values) c.wireName]);
    expect(ShellAction.values.map((a) => a.id).toSet(),
        hasLength(ShellAction.values.length));
  });

  test('[control] defaults on, and degrades per key', () {
    expect(ControlConfig.fromMap(null), const ControlConfig());
    expect(const ControlConfig().enabled, isTrue);
    expect(const ControlConfig().screenshots, isTrue);
    expect(
      ControlConfig.fromMap({'enabled': 'yes', 'screenshots': false}),
      const ControlConfig(screenshots: false),
    );
  });

  group('over the bus', () {
    late Directory dir;
    late DBusServer bus;
    late DBusClient shellSide;
    late ShellBusClient mcpSide;
    late _FakeShell fake;
    late Map<String, McpTool> tools;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('shell_control');
      bus = DBusServer();
      final address = await bus
          .listenAddress(DBusAddress.unix(path: '${dir.path}/bus'));
      fake = _FakeShell();
      shellSide = DBusClient(address);
      await shellSide.registerObject(ShellControlServer(fake));
      await shellSide.requestName(kShellControlBusName);
      mcpSide = ShellBusClient(connect: () => DBusClient(address));
      tools = {
        for (final tool in buildMoonswingTools(
          wm: CompositorClient(environment: const {}),
          shell: mcpSide,
        ))
          tool.name: tool,
      };
    });

    tearDown(() async {
      await mcpSide.close();
      await shellSide.close();
      await bus.close();
      await dir.delete(recursive: true);
    });

    Future<McpToolResult> run(String name, [Map<String, Object?>? args]) =>
        tools[name]!.handler(McpArgs(args ?? const {}));

    Object? json(McpToolResult result) {
      expect(result.isError, isFalse,
          reason: (result.content.first as McpText).text);
      return jsonDecode((result.content.single as McpText).text);
    }

    test('status, themes and a theme switch', () async {
      expect(json(await run('shell_status')),
          {'api': 1, 'theme': 'glassy', 'do_not_disturb': false});
      expect(json(await run('shell_list_themes')), [
        {'slug': 'glassy', 'name': 'Glassy', 'built_in': true},
        {'slug': 'dracula', 'name': 'Dracula', 'built_in': true},
      ]);
      await run('shell_set_theme', {'slug': 'dracula'});
      expect(fake.theme, 'dracula');
    });

    test('a refusal arrives as the shell\'s own sentence', () async {
      await expectLater(
        run('shell_set_theme', {'slug': 'nope'}),
        throwsA(isA<McpToolException>().having(
            (e) => e.message, 'message', 'There is no theme "nope".')),
      );
    });

    test('actions, the overview and settings', () async {
      await run('shell_run_action', {'action': 'open_launcher'});
      await run('shell_open_overview', {'tab': 'todo'});
      await run('shell_open_settings', {'category': 'display'});
      await run('shell_open_settings', {'module': 'clock'});
      expect(fake.calls, [
        'activate open_launcher',
        'overview todo',
        'settings display/',
        'settings /clock',
      ]);
    });

    test('an action the interface does not know is refused by the shell',
        () async {
      // Straight at the bus, past the MCP tool's own enum check.
      await expectLater(
        mcpSide.callShell('Activate', [const DBusString('make_coffee')], ''),
        throwsA(isA<McpToolException>().having(
            (e) => e.message, 'message', contains('ListActions'))),
      );
    });

    test('the todo board round trip', () async {
      final added = json(await run('todo_add', {
        'title': 'Write the docs',
        'body': '- [ ] Claude\n- [ ] OpenAI',
        'column': 'todo',
        'due': '2026-11-20',
      }));
      expect(added, {'id': 'card-1'});
      expect(json(await run('todo_list')), [
        {
          'id': 'card-1',
          'column': 'todo',
          'title': 'Write the docs',
          'body': '- [ ] Claude\n- [ ] OpenAI',
          'due': '2026-11-20',
        },
      ]);
      await run('todo_move', {'id': 'card-1', 'column': 'finished'});
      expect(fake.calls, ['move card-1 finished']);
      await expectLater(
        run('todo_add', {'title': 'x', 'due': 'next tuesday'}),
        throwsA(isA<McpToolException>()),
      );
    });

    test('timers', () async {
      expect(json(await run('shell_list_timers')), [
        {
          'id': 3,
          'kind': 'timer',
          'label': 'Tea',
          'running': true,
          'finished': false,
          'reading': '02:05',
        },
      ]);
      await run('shell_start_timer', {'minutes': 10, 'label': 'Pasta'});
      await run('shell_control_timer', {'id': 3, 'operation': 'pause'});
      expect(fake.calls, ['timer 600 Pasta', 'timer 3 pause']);
    });

    test('notifications and do-not-disturb', () async {
      final list = json(await run('shell_list_notifications')) as List;
      expect(list.single['summary'], 'New message');
      expect(list.single['read'], isFalse);
      await run('shell_dismiss_notification', {'all': true});
      await run('shell_set_do_not_disturb', {'enabled': true});
      expect(fake.calls, ['dismiss 0']);
      expect(fake.dnd, isTrue);
    });

    test('apps and volume', () async {
      expect(json(await run('shell_search_apps', {'query': 'fire'})), [
        {'id': 'firefox', 'name': 'Firefox', 'description': 'Web Browser'},
      ]);
      await run('shell_launch_app', {'app_id': 'firefox'});
      expect(json(await run('shell_get_volume')),
          {'volume': 50, 'muted': false});
      await run('shell_set_volume', {'volume': 30, 'muted': true});
      expect(fake.level, closeTo(0.3, 1e-9));
      expect(fake.calls, ['launch firefox', 'muted true']);
    });

    test('a screenshot comes back as an image', () async {
      final result = await run('shell_screenshot', {'output': 'DP-1'});
      final image = result.content.first as McpImage;
      expect(base64Decode(image.data), [0x89, 0x50, 0x4e, 0x47]);
      expect(image.mimeType, 'image/png');
      expect(fake.calls, ['screenshot "DP-1" 1600']);
    });
  });
}
