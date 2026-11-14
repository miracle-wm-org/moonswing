// `moonswing-mcp`: the Model Context Protocol server for the Moonswing desktop.
//
// Point an MCP client at it — Claude Code, Claude Desktop, OpenAI's Codex CLI or
// Agents SDK, LM Studio, Goose, Open WebUI, anything that speaks MCP — and the
// model behind it can see and arrange the user's windows through miracle-wm's
// IPC and drive the shell through `org.moonswing.Shell`. How to wire up each
// client is `website/src/content/docs/start/agents.md`.
//
//   dart compile exe bin/moonswing_mcp.dart -o build/moonswing-mcp
//   moonswing-mcp                       # stdio, what clients launch
//   moonswing-mcp --http 8765           # http://127.0.0.1:8765/mcp
//
// Flutter-free, `tool/screencast_spike.dart`'s rule, so that compile works.

import 'dart:async';
import 'dart:io';

import 'package:moonswing/mcp/compositor_client.dart';
import 'package:moonswing/mcp/mcp_protocol.dart';
import 'package:moonswing/mcp/mcp_transport.dart';
import 'package:moonswing/mcp/moonswing_tools.dart';
import 'package:moonswing/mcp/shell_client.dart';

const String kVersion = '1.0.0';

const String kUsage = '''
moonswing-mcp — an MCP server for the Moonswing shell and miracle-wm.

Usage: moonswing-mcp [options]

With no options it speaks MCP over stdin/stdout, which is how MCP clients
start a local server.

  --http [HOST:]PORT  Serve Streamable HTTP at http://HOST:PORT/mcp instead
                      (HOST defaults to 127.0.0.1).
  --token TOKEN       Require "Authorization: Bearer TOKEN" over HTTP. Also
                      read from MOONSWING_MCP_TOKEN. Required to listen on
                      anything but loopback.
  --read-only         Offer only the tools that change nothing (listing
                      windows, reading status, screenshots).
  --only GROUPS       Offer only these tool groups, comma-separated: wm,
                      shell, todo, note, media. Small models choose better
                      among fewer tools.
  --allow-exec        Let the model run arbitrary command lines through the
                      window manager's exec. Off by default.
  --wm-socket PATH    The window manager's IPC socket, if MIRACLESOCK and
                      SWAYSOCK are not set in this environment.
  --list-tools        Print the tools this configuration offers, and exit.
  --version           Print the version, and exit.
  -h, --help          Print this, and exit.
''';

Future<void> main(List<String> arguments) async {
  String? http;
  String? token = Platform.environment['MOONSWING_MCP_TOKEN'];
  String? socket;
  var readOnly = false;
  var allowExec = false;
  var listTools = false;
  Set<String>? groups;

  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    String value() {
      if (i + 1 >= arguments.length) {
        stderr.writeln('moonswing-mcp: $arg needs a value.\n\n$kUsage');
        exit(64);
      }
      return arguments[++i];
    }

    switch (arg) {
      case '--http':
        http = value();
      case '--token':
        token = value();
      case '--wm-socket':
        socket = value();
      case '--only':
        groups = {
          for (final group in value().split(','))
            if (group.trim().isNotEmpty) group.trim(),
        };
        final unknown = groups.difference(kMoonswingToolGroups.toSet());
        if (unknown.isNotEmpty) {
          stderr.writeln('moonswing-mcp: unknown tool group '
              '${unknown.join(', ')}; the groups are '
              '${kMoonswingToolGroups.join(', ')}.');
          exit(64);
        }
      case '--read-only':
        readOnly = true;
      case '--allow-exec':
        allowExec = true;
      case '--list-tools':
        listTools = true;
      case '--version':
        stdout.writeln('moonswing-mcp $kVersion');
        return;
      case '-h' || '--help':
        stdout.write(kUsage);
        return;
      default:
        stderr.writeln('moonswing-mcp: unknown option $arg\n\n$kUsage');
        exit(64);
    }
  }

  final wm = CompositorClient(socketPath: socket);
  final shell = ShellBusClient();
  final server = McpServer(
    info: const McpServerInfo(
      name: 'moonswing',
      title: 'Moonswing desktop',
      version: kVersion,
      instructions: kMoonswingMcpInstructions,
    ),
    tools: buildMoonswingTools(
      wm: wm,
      shell: shell,
      options: MoonswingToolOptions(
        readOnly: readOnly,
        allowExec: allowExec,
        groups: groups,
      ),
    ),
  );

  if (listTools) {
    for (final tool in server.tools) {
      stdout.writeln('${tool.name.padRight(28)} ${tool.title}');
    }
    return;
  }

  Future<void> shutdown() async {
    await wm.close();
    await shell.close();
  }

  if (http == null) {
    await serveStdio(server);
    await shutdown();
    // A dbus connection or socket left open would otherwise keep the process
    // alive after the client has gone.
    exit(0);
  }

  final colon = http.lastIndexOf(':');
  final host = colon > 0 ? http.substring(0, colon) : '127.0.0.1';
  final port = int.tryParse(colon >= 0 ? http.substring(colon + 1) : http);
  if (port == null || port < 0 || port > 65535) {
    stderr.writeln('moonswing-mcp: --http wants [HOST:]PORT, got "$http".');
    exit(64);
  }
  final McpHttpTransport transport;
  try {
    transport = await McpHttpTransport.bind(server,
        host: host, port: port, token: token);
  } on ArgumentError catch (e) {
    stderr.writeln('moonswing-mcp: ${e.message}');
    exit(64);
  } on SocketException catch (e) {
    stderr.writeln('moonswing-mcp: cannot listen on $host:$port: '
        '${e.osError?.message ?? e.message}');
    exit(69);
  }
  stderr.writeln('moonswing-mcp: serving MCP at ${transport.url}'
      '${transport.token == null ? '' : ' (bearer token required)'}');
  final done = Completer<void>();
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) {
      if (!done.isCompleted) done.complete();
    });
  }
  await done.future;
  await transport.close();
  await shutdown();
  exit(0);
}
