// The compositor's IPC, as `moonswing-mcp` uses it to lay out windows.
//
// miracle's socket is the target — it is what `miraclemsg` talks to, and every
// command here is a string `miraclemsg` would accept. The protocol is i3's, so
// the same client also drives sway or i3 when that is what the session runs;
// unlike the shell, which turns its Miracle-only features *off* on another
// compositor, an agent laying out windows is just as well served by sway's
// answer to `[con_id=12] move to workspace 3`. Which one it reached is reported
// (`flavour`), settled the way `MiracleManager` settles it: the environment
// first, and for a bare `SWAYSOCK`/`I3SOCK`, whether `GET_KEYBINDS` — miracle's
// own message — is answered.
library;

import 'dart:async';
import 'dart:io';

import 'package:miracle/miracle.dart';

import 'package:moonswing/mcp/mcp_protocol.dart';
import 'package:moonswing/miracle_session.dart';

enum CompositorFlavour {
  miracle('miracle-wm'),
  i3Compatible('i3-compatible (sway or i3)');

  const CompositorFlavour(this.label);

  final String label;
}

/// Finds the IPC socket: the environment's, else the newest one in the
/// runtime directory — an MCP server launched by a desktop client's service
/// manager rather than from the session's own shell may not have inherited
/// `MIRACLESOCK`.
String? findCompositorSocket(Map<String, String> environment) {
  final named = MiracleConnection.resolveSocketPath(environment);
  if (named != null && named.isNotEmpty) return named;
  final runtime = environment['XDG_RUNTIME_DIR'];
  if (runtime == null || runtime.isEmpty) return null;
  final dir = Directory(runtime);
  if (!dir.existsSync()) return null;
  File? best;
  DateTime? bestTime;
  try {
    for (final entity in dir.listSync()) {
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.sock')) continue;
      if (!name.startsWith('miracle-ipc') && !name.startsWith('sway-ipc')) {
        continue;
      }
      final stat = entity.statSync();
      if (stat.type != FileSystemEntityType.unixDomainSock) continue;
      // miracle before sway when both are lying about, then the newest.
      final preferred = name.startsWith('miracle');
      final bestPreferred =
          best?.uri.pathSegments.last.startsWith('miracle') ?? false;
      if (best == null ||
          (preferred && !bestPreferred) ||
          (preferred == bestPreferred && stat.modified.isAfter(bestTime!))) {
        best = File(entity.path);
        bestTime = stat.modified;
      }
    }
  } on FileSystemException {
    return null;
  }
  return best?.path;
}

/// One lazily opened connection, re-opened after it dies.
class CompositorClient {
  CompositorClient({
    Map<String, String>? environment,
    this.socketPath,
    this.requestTimeout = const Duration(seconds: 10),
    this.probeTimeout = const Duration(seconds: 2),
  }) : _environment = environment ?? Platform.environment;

  final Map<String, String> _environment;

  /// Overrides the search (`--wm-socket`).
  final String? socketPath;

  /// No request waits longer than this — the shell's rule, since a request the
  /// compositor ignores is otherwise a call that never returns.
  final Duration requestTimeout;
  final Duration probeTimeout;

  MiracleConnection? _connection;
  Future<MiracleConnection>? _connecting;
  CompositorFlavour? _flavour;
  String? _path;

  /// What the last successful connection reached, or null before one.
  CompositorFlavour? get flavour => _flavour;

  /// The socket it reached.
  String? get path => _path;

  Future<MiracleConnection> _open() async {
    final existing = _connection;
    if (existing != null) return existing;
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<MiracleConnection> _connect() async {
    final path = socketPath ?? findCompositorSocket(_environment);
    if (path == null) {
      throw const McpToolException(
          'No window manager IPC socket was found. Set MIRACLESOCK (or '
          'SWAYSOCK) in the environment the MCP server is started with, or '
          'pass --wm-socket.');
    }
    final name = path.split('/').last;
    final session = socketPath == null
        ? detectMiracleSession(_environment)
        : MiracleSession.undetermined;
    var flavour = switch (session) {
      MiracleSession.miracle => CompositorFlavour.miracle,
      _ when name.startsWith('miracle') => CompositorFlavour.miracle,
      MiracleSession.other => CompositorFlavour.i3Compatible,
      MiracleSession.undetermined => null,
    };

    var connection = await _dial(path);
    if (flavour == null) {
      try {
        await connection.getKeybinds().timeout(probeTimeout);
        flavour = CompositorFlavour.miracle;
      } on TimeoutException {
        flavour = CompositorFlavour.i3Compatible;
        // The unanswered probe stays pending on that socket; start clean.
        await _discard(connection);
        connection = await _dial(path);
      } on MiracleConnectionException {
        flavour = CompositorFlavour.i3Compatible;
        await _discard(connection);
        connection = await _dial(path);
      }
    }
    _flavour = flavour;
    _path = path;
    _connection = connection;
    return connection;
  }

  Future<MiracleConnection> _dial(String path) async {
    final connection = MiracleConnection();
    try {
      await connection.connect(
        socketPath: path,
        requestTimeout: requestTimeout,
        onSocketError: (_, _) => _lost(connection),
        onSocketDone: () => _lost(connection),
      );
    } on SocketException catch (e) {
      throw McpToolException('Could not reach the window manager at $path: '
          '${e.osError?.message ?? e.message}.');
    } on MiracleConnectionException catch (e) {
      throw McpToolException(e.message);
    }
    return connection;
  }

  void _lost(MiracleConnection connection) {
    if (identical(_connection, connection)) _connection = null;
  }

  static Future<void> _discard(MiracleConnection connection) async {
    try {
      await connection.disconnect();
    } catch (_) {}
  }

  /// Runs [request] on the connection; a dead socket is dropped so the next
  /// call reconnects, and every failure is a sentence.
  Future<T> _request<T>(Future<T> Function(MiracleConnection c) request) async {
    final connection = await _open();
    try {
      return await request(connection);
    } on TimeoutException {
      _lost(connection);
      unawaited(_discard(connection));
      throw const McpToolException(
          'The window manager did not answer in time.');
    } on MiracleConnectionException catch (e) {
      _lost(connection);
      throw McpToolException('The window manager connection failed: '
          '${e.message}');
    } on SocketException catch (e) {
      _lost(connection);
      throw McpToolException('The window manager connection failed: '
          '${e.osError?.message ?? e.message}');
    }
  }

  /// Runs [command] exactly as `miraclemsg <command>` would — criteria,
  /// `;`-separated lists and all.
  Future<List<CommandResult>> command(String command) =>
      _request((c) => c.command(command));

  Future<BaseNode> tree() => _request((c) => c.getTree());

  Future<List<WorkspaceResult>> workspaces() =>
      _request((c) => c.getWorkspaces());

  Future<List<OutputResult>> outputs() => _request((c) => c.getOutputs());

  Future<VersionResult> version() => _request((c) => c.getVersion());

  Future<void> close() async {
    final connection = _connection;
    _connection = null;
    if (connection != null) await _discard(connection);
  }
}

/// The app id a window is known by: `app_id`, or an XWayland window's class —
/// `containerAppId`'s rule (`lib/modules/workspace_apps.dart`), which the
/// shell's own workspace row uses, restated here without Flutter.
String? windowAppId(ContainerNode node) {
  String? nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;
  return nonEmpty(node.appId) ??
      nonEmpty(node.windowProperties.className) ??
      nonEmpty(node.windowProperties.instance);
}

/// Every window in [tree], with where it is — the shape `wm_list_windows`
/// answers with.
///
/// A window is a container with an app id and no children of its own; split
/// containers, which only group windows, are left out. Not `isWindow`, which is
/// the X11 id and null for nearly every Wayland window.
List<Map<String, Object?>> describeWindows(BaseNode tree) {
  final windows = <Map<String, Object?>>[];
  for (final output in tree.outputs) {
    for (final workspace in output.workspaces) {
      for (final node in workspace.descendants.whereType<ContainerNode>()) {
        if (node.nodes.isNotEmpty) continue;
        final appId = windowAppId(node);
        if (appId == null && node.pid == null) continue;
        windows.add({
          'id': node.id,
          'app_id': appId,
          'title': node.name,
          if (node.pid != null) 'pid': node.pid,
          'workspace': workspace.name,
          if (workspace.hasNumber) 'workspace_number': workspace.num,
          'output': output.name,
          'focused': node.focused,
          'visible': workspace.visible,
          'floating': node.isFloating,
          'fullscreen': node.isFullscreen,
          if (node.sticky) 'sticky': true,
          if (node.urgent) 'urgent': true,
          'rect': describeRect(node.rect),
        });
      }
    }
  }
  return windows;
}

Map<String, int> describeRect(Rect rect) => {
      'x': rect.x,
      'y': rect.y,
      'width': rect.width,
      'height': rect.height,
    };

/// The workspaces with their layout and the windows on each, by id.
List<Map<String, Object?>> describeWorkspaces(BaseNode tree) => [
      for (final output in tree.outputs)
        for (final workspace in output.workspaces)
          {
            'name': workspace.name,
            if (workspace.hasNumber) 'number': workspace.num,
            'output': output.name,
            'focused': workspace.focused,
            'visible': workspace.visible,
            'layout': workspace.layout.name,
            'windows': [
              for (final node
                  in workspace.descendants.whereType<ContainerNode>())
                if (node.nodes.isEmpty &&
                    (windowAppId(node) != null || node.pid != null))
                  node.id,
            ],
          },
    ];

/// `[con_id=N]`, the criteria every per-window tool scopes its command by.
String windowCriteria(int id) => '[con_id=$id]';

/// [value] as a command argument, quoted when it has to be.
String commandArgument(String value) => quoteArgument(value);
