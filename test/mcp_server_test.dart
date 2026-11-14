import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/mcp/compositor_client.dart';
import 'package:moonswing/mcp/mcp_protocol.dart';
import 'package:moonswing/mcp/mcp_transport.dart';
import 'package:moonswing/mcp/moonswing_tools.dart';
import 'package:moonswing/mcp/shell_client.dart';

/// `moonswing-mcp` from the outside: the JSON-RPC a client sends, and what it
/// gets back — the protocol, both transports, and the window-manager tools
/// against a stand-in for miracle's IPC socket. Everything the binary does but
/// talk to a real compositor and a real shell.

/// A stand-in for miracle's IPC socket: i3's framing, answering each request
/// type with whatever [replies] holds, and recording every command it was sent.
class _FakeCompositor {
  _FakeCompositor._(this._server, this.path, this._dir);

  final ServerSocket _server;
  final String path;
  final Directory _dir;
  final List<String> commands = [];
  final Map<int, Object? Function(String payload)> replies = {};

  static Future<_FakeCompositor> start({String name = 'miracle-ipc.sock'}) async {
    final dir = await Directory.systemTemp.createTemp('mcp_wm');
    final path = '${dir.path}/$name';
    final server = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix), 0);
    final fake = _FakeCompositor._(server, path, dir);
    server.listen(fake._client);
    return fake;
  }

  void _client(Socket socket) {
    var buffer = Uint8List(0);
    socket.listen((data) {
      buffer = Uint8List.fromList([...buffer, ...data]);
      while (buffer.length >= 14) {
        final view = ByteData.sublistView(buffer);
        final length = view.getUint32(6, Endian.host);
        final type = view.getUint32(10, Endian.host);
        if (buffer.length < 14 + length) break;
        final payload = utf8.decode(buffer.sublist(14, 14 + length));
        buffer = Uint8List.fromList(buffer.sublist(14 + length));
        if (type == 0) commands.add(payload);
        final reply = replies[type];
        if (reply == null) continue;
        final bytes = utf8.encode(jsonEncode(reply(payload)));
        final frame = Uint8List(14 + bytes.length);
        frame.setRange(0, 6, utf8.encode('i3-ipc'));
        ByteData.sublistView(frame)
          ..setUint32(6, bytes.length, Endian.host)
          ..setUint32(10, type, Endian.host);
        frame.setRange(14, frame.length, bytes);
        socket.add(frame);
      }
    }, onError: (Object _) {});
  }

  Future<void> stop() async {
    await _server.close();
    await _dir.delete(recursive: true);
  }
}

Map<String, Object?> _rect(int x, int y, int w, int h) =>
    {'x': x, 'y': y, 'width': w, 'height': h};

Map<String, Object?> _window(int id, String appId, String title,
        {bool focused = false}) =>
    {
      'type': 'con',
      'id': id,
      'name': title,
      'app_id': appId,
      'pid': 1000 + id,
      'focused': focused,
      'rect': _rect(0, 0, 960, 1080),
      'nodes': <Object?>[],
      'floating_nodes': <Object?>[],
    };

final Map<String, Object?> _tree = {
  'type': 'root',
  'id': 1,
  'name': 'root',
  'rect': _rect(0, 0, 1920, 1080),
  'nodes': [
    {
      'type': 'output',
      'id': 2,
      'name': 'DP-1',
      'active': true,
      'rect': _rect(0, 0, 1920, 1080),
      'nodes': [
        {
          'type': 'workspace',
          'id': 3,
          'name': '1',
          'num': 1,
          'output': 'DP-1',
          'visible': true,
          'focused': true,
          'rect': _rect(0, 0, 1920, 1080),
          'nodes': [
            // A split container holding two windows: it is not a window.
            {
              'type': 'con',
              'id': 4,
              'name': '',
              'rect': _rect(0, 0, 1920, 1080),
              'nodes': [
                _window(10, 'firefox', 'Mozilla Firefox', focused: true),
                _window(11, 'foot', 'foot'),
              ],
              'floating_nodes': <Object?>[],
            },
          ],
          'floating_nodes': <Object?>[],
        },
      ],
    },
  ],
};

void main() {
  group('the protocol', () {
    McpServer server() => McpServer(
          info: const McpServerInfo(
              name: 'test', title: 'Test', version: '0', instructions: 'Hi.'),
          tools: [
            McpTool(
              name: 'echo',
              title: 'Echo',
              description: 'Says it back.',
              properties: {'text': Schema.string('What to say.')},
              required: ['text'],
              readOnly: true,
              handler: (args) async => McpToolResult.text(args.string('text')),
            ),
            McpTool(
              name: 'fail',
              title: 'Fail',
              description: 'Refuses.',
              handler: (args) async =>
                  throw const McpToolException('No, and here is why.'),
            ),
          ],
        );

    Future<Map<String, Object?>> call(McpServer s, String method,
            [Map<String, Object?>? params]) async =>
        (await s.handle({
          'jsonrpc': '2.0',
          'id': 7,
          'method': method,
          'params': ?params,
        }))! as Map<String, Object?>;

    test('initialize echoes a version it speaks, and names the server',
        () async {
      final answer = await call(server(), 'initialize', {
        'protocolVersion': '2025-03-26',
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'c', 'version': '1'},
      });
      final result = answer['result']! as Map<String, Object?>;
      expect(answer['id'], 7);
      expect(result['protocolVersion'], '2025-03-26');
      expect((result['serverInfo']! as Map)['name'], 'test');
      expect(result['instructions'], 'Hi.');
      expect((result['capabilities']! as Map).containsKey('tools'), isTrue);
    });

    test('a version it does not speak is answered with its newest', () async {
      final answer = await call(
          server(), 'initialize', {'protocolVersion': '1999-01-01'});
      expect((answer['result']! as Map)['protocolVersion'],
          kMcpProtocolVersions.first);
    });

    test('tools/list carries the schema and the hints', () async {
      final answer = await call(server(), 'tools/list');
      final tools = (answer['result']! as Map)['tools']! as List;
      final echo = tools.first as Map<String, Object?>;
      expect(echo['name'], 'echo');
      final schema = echo['inputSchema']! as Map;
      expect(schema['type'], 'object');
      expect(schema['required'], ['text']);
      expect((echo['annotations']! as Map)['readOnlyHint'], isTrue);
    });

    test('tools/call answers content, and a refusal is a tool error',
        () async {
      final s = server();
      final ok = await call(s, 'tools/call', {
        'name': 'echo',
        'arguments': {'text': 'hello'},
      });
      expect((ok['result']! as Map)['isError'], isFalse);
      expect(((ok['result']! as Map)['content']! as List).single,
          {'type': 'text', 'text': 'hello'});

      final refused = await call(s, 'tools/call', {'name': 'fail'});
      final result = refused['result']! as Map;
      expect(result['isError'], isTrue);
      expect((result['content']! as List).single['text'],
          'No, and here is why.');

      final missing = await call(s, 'tools/call', {
        'name': 'echo',
        'arguments': <String, Object?>{},
      });
      expect((missing['result']! as Map)['isError'], isTrue);
    });

    test('an unknown tool or method is a JSON-RPC error', () async {
      final s = server();
      final tool = await call(s, 'tools/call', {'name': 'nope'});
      expect((tool['error']! as Map)['code'], JsonRpcError.invalidParams);
      final method = await call(s, 'sampling/createMessage');
      expect((method['error']! as Map)['code'], JsonRpcError.methodNotFound);
    });

    test('notifications get no answer; bad JSON gets a parse error', () async {
      final s = server();
      expect(
          await s.handle({
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
          }),
          isNull);
      final parse = jsonDecode((await s.handleText('{nope'))!) as Map;
      expect((parse['error'] as Map)['code'], JsonRpcError.parseError);
    });

    test('a batch is answered as a batch, without its notifications',
        () async {
      final answers = await server().handle([
        {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
        {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        {'jsonrpc': '2.0', 'id': 2, 'method': 'ping'},
      ]);
      expect(answers, hasLength(2));
    });

    test('stdio answers one line per request', () async {
      final input = StreamController<List<int>>();
      final sink = _LineSink();
      final served = serveStdio(server(), input: input.stream, output: sink);
      input.add(utf8.encode('{"jsonrpc":"2.0","id":1,"method":"ping"}\n'
          '{"jsonrpc":"2.0","method":"notifications/initialized"}\n'));
      await input.close();
      await served;
      expect(sink.lines, ['{"jsonrpc":"2.0","id":1,"result":{}}']);
    });
  });

  group('the HTTP transport', () {
    late McpHttpTransport transport;
    late HttpClient client;

    setUp(() async {
      transport = await McpHttpTransport.bind(
        McpServer(
          info: const McpServerInfo(name: 't', title: 'T', version: '0'),
          tools: const [],
        ),
        port: 0,
        token: 'sesame',
      );
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await transport.close();
    });

    Future<HttpClientResponse> post(Object body,
        {String? token = 'sesame', String? origin}) async {
      final request = await client.postUrl(transport.url);
      request.headers.contentType = ContentType.json;
      request.headers.set('accept', 'application/json, text/event-stream');
      if (token != null) request.headers.set('authorization', 'Bearer $token');
      if (origin != null) request.headers.set('origin', origin);
      request.write(jsonEncode(body));
      return request.close();
    }

    test('answers a POST with the JSON-RPC response and a session id',
        () async {
      final response = await post({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': '2025-06-18'},
      });
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.value('mcp-session-id'), isNotNull);
      final body =
          jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      expect((body['result'] as Map)['protocolVersion'], '2025-06-18');
    });

    test('a notification is 202 with no body', () async {
      final response = await post(
          {'jsonrpc': '2.0', 'method': 'notifications/initialized'});
      expect(response.statusCode, HttpStatus.accepted);
      await response.drain<void>();
    });

    test('refuses a missing token and a cross-site origin', () async {
      final unauthorised =
          await post({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'}, token: null);
      expect(unauthorised.statusCode, HttpStatus.unauthorized);
      await unauthorised.drain<void>();

      final foreign = await post({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
          origin: 'https://example.com');
      expect(foreign.statusCode, HttpStatus.forbidden);
      await foreign.drain<void>();

      final local = await post({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
          origin: 'http://localhost:3000');
      expect(local.statusCode, HttpStatus.ok);
      await local.drain<void>();
    });

    test('will not listen beyond loopback without a token', () async {
      final server = McpServer(
          info: const McpServerInfo(name: 't', title: 'T', version: '0'),
          tools: const []);
      expect(
        () => McpHttpTransport.bind(server, host: '0.0.0.0', port: 0),
        throwsArgumentError,
      );
    });
  });

  group('the window manager tools', () {
    late _FakeCompositor fake;
    late CompositorClient wm;
    late Map<String, McpTool> tools;

    setUp(() async {
      fake = await _FakeCompositor.start();
      fake.replies[4] = (_) => _tree;
      fake.replies[0] = (payload) => [
            for (final _ in payload.split(';')) {'success': true},
          ];
      wm = CompositorClient(
        environment: {'MIRACLESOCK': fake.path},
        requestTimeout: const Duration(seconds: 2),
      );
      tools = {
        for (final tool in buildMoonswingTools(wm: wm, shell: ShellBusClient()))
          tool.name: tool,
      };
    });

    tearDown(() async {
      await wm.close();
      await fake.stop();
    });

    Future<McpToolResult> run(String name, Map<String, Object?> args) =>
        tools[name]!.handler(McpArgs(args));

    String text(McpToolResult result) =>
        (result.content.single as McpText).text;

    test('lists windows, not the split containers holding them', () async {
      final result = await run('wm_list_windows', {});
      final windows = jsonDecode(text(result)) as List;
      expect(windows.map((w) => w['id']), [10, 11]);
      expect(windows.first['app_id'], 'firefox');
      expect(windows.first['workspace'], '1');
      expect(windows.first['output'], 'DP-1');
      expect(windows.first['focused'], isTrue);
      expect(wm.flavour, CompositorFlavour.miracle);
    });

    test('filters by app id', () async {
      final windows =
          jsonDecode(text(await run('wm_list_windows', {'app_id': 'FOO'})))
              as List;
      expect(windows.map((w) => w['id']), [11]);
    });

    test('the helpers speak miraclemsg\'s commands, scoped by con_id',
        () async {
      await run('wm_move_window',
          {'window_id': 11, 'workspace': '3', 'follow': true});
      await run('wm_set_layout', {'window_id': 10, 'layout': 'splith'});
      await run('wm_resize_window', {'window_id': 10, 'width': 60});
      await run('wm_focus_window', {'app_id': 'foot'});
      await run('wm_set_window_state', {'floating': 'toggle'});
      await run('wm_switch_workspace', {'workspace': 'mail'});
      await run('wm_close_window', {'window_id': 11});
      expect(fake.commands, [
        '[con_id=11] move container to workspace number 3',
        'workspace number 3',
        '[con_id=10] layout splith',
        '[con_id=10] resize set width 60 ppt',
        '[app_id="foot"] focus',
        'floating toggle',
        'workspace mail',
        '[con_id=11] kill',
      ]);
    });

    test('a command the compositor refuses is a tool error with its reason',
        () async {
      fake.replies[0] = (_) => [
            {'success': false, 'parse_error': true, 'error': 'Unknown command'},
          ];
      final result = await run('wm_run_command', {'command': 'frobnicate'});
      expect(result.isError, isTrue);
      expect(text(result), contains('Unknown command'));
    });

    test('exec is refused unless allowed', () async {
      expect(commandRunsExec('exec foot'), isTrue);
      expect(commandRunsExec('[con_id=1] focus; exec_always rm -rf ~'), isTrue);
      expect(commandRunsExec('workspace 2'), isFalse);
      expect(commandRunsExec('rename workspace to exec'), isFalse);
      await expectLater(
        run('wm_run_command', {'command': 'workspace 2; exec foot'}),
        throwsA(isA<McpToolException>()),
      );
      expect(fake.commands, isEmpty);
      expect(tools.containsKey('wm_exec'), isFalse);
    });

    test('read-only leaves out everything that changes something', () {
      final names = {
        for (final tool in buildMoonswingTools(
          wm: wm,
          shell: ShellBusClient(),
          options: const MoonswingToolOptions(readOnly: true),
        ))
          tool.name,
      };
      expect(names, containsAll(['wm_list_windows', 'shell_status']));
      expect(names, isNot(contains('wm_close_window')));
      expect(names, isNot(contains('todo_add')));
    });

    test('--only keeps the named groups', () {
      final names = {
        for (final tool in buildMoonswingTools(
          wm: wm,
          shell: ShellBusClient(),
          options: const MoonswingToolOptions(groups: {'wm', 'todo'}),
        ))
          tool.name.split('_').first,
      };
      expect(names, {'wm', 'todo'});
    });

    test('an unanswered GET_KEYBINDS means an i3-compatible compositor',
        () async {
      final swayFake = await _FakeCompositor.start(name: 'sway-ipc.sock');
      swayFake.replies[4] = (_) => _tree;
      final sway = CompositorClient(
        environment: {'SWAYSOCK': swayFake.path},
        probeTimeout: const Duration(milliseconds: 100),
      );
      addTearDown(swayFake.stop);
      addTearDown(sway.close);
      await sway.tree();
      expect(sway.flavour, CompositorFlavour.i3Compatible);
    });

    test('no socket is a sentence, not a crash', () async {
      final none = CompositorClient(environment: const {});
      await expectLater(none.tree(), throwsA(isA<McpToolException>()));
    });
  });

  test('the binary reaches no Flutter, so `dart build cli` can compile it',
      () {
    final files = _reachable('bin/moonswing_mcp.dart');
    expect(files, contains('lib/mcp/moonswing_tools.dart'));
    for (final file in files) {
      expect(File(file).readAsStringSync(),
          isNot(contains("import 'package:flutter")), reason: file);
    }
  });

  test('every tool name is one every client accepts', () {
    final tools = buildMoonswingTools(
      wm: CompositorClient(environment: const {}),
      shell: ShellBusClient(),
      options: const MoonswingToolOptions(allowExec: true),
    );
    final names = tools.map((t) => t.name).toList();
    expect(names.toSet(), hasLength(names.length));
    for (final name in names) {
      expect(name, matches(RegExp(r'^[a-z][a-z0-9_]{0,63}$')));
    }
  });
}

class _LineSink implements IOSink {
  final List<String> lines = [];

  @override
  void writeln([Object? object = '']) => lines.add('$object');

  @override
  Future<void> flush() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Every `package:moonswing` file the binary reaches, transitively, from
/// `bin/moonswing_mcp.dart`.
Set<String> _reachable(String entry) {
  final seen = <String>{};
  final pending = [entry];
  final import = RegExp(r"^(?:import|export)\s+'([^']+)'", multiLine: true);
  while (pending.isNotEmpty) {
    final path = pending.removeLast();
    if (!seen.add(path)) continue;
    final dir = File(path).parent.path;
    for (final match in import.allMatches(File(path).readAsStringSync())) {
      final uri = match.group(1)!;
      if (uri.startsWith('package:moonswing/')) {
        pending.add('lib/${uri.substring('package:moonswing/'.length)}');
      } else if (!uri.contains(':')) {
        pending.add(File('$dir/$uri').absolute.path);
      }
    }
  }
  return seen;
}
