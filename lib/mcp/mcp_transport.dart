// How MCP messages reach `McpServer`: the two transports the spec defines.
//
// **stdio** is what nearly every client launches a local server with — Claude
// Code and Claude Desktop, OpenAI's Codex CLI and Agents SDK, LM Studio, Goose —
// one JSON-RPC message per line on stdin, one answer per line on stdout, and
// anything for a person on stderr, since a stray byte on stdout is a parse error
// at the other end.
//
// **Streamable HTTP** is for clients that only speak to a URL (Open WebUI,
// LibreChat, a remote-MCP API reached through a tunnel). Only the half of it a
// tool server needs: a POST carrying a message is answered with the JSON
// response; this server never starts a conversation, so there is no event
// stream to GET. It binds loopback unless told otherwise, refuses a cross-site
// `Origin` (a web page the user visits could otherwise drive their desktop
// through it — the spec's DNS-rebinding warning), and takes a bearer token,
// which it insists on before binding anywhere but loopback.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:moonswing/mcp/mcp_protocol.dart';

/// Serves [server] over stdin/stdout until stdin closes.
///
/// Requests are answered as they finish rather than in order — JSON-RPC
/// matches answers by id — so a slow screenshot does not hold up a `ping`.
Future<void> serveStdio(
  McpServer server, {
  Stream<List<int>>? input,
  IOSink? output,
}) async {
  final out = output ?? stdout;
  final pending = <Future<void>>[];
  await for (final line in (input ?? stdin)
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    final work = server.handleText(line).then((answer) {
      if (answer != null) out.writeln(answer);
    });
    pending.add(work);
    unawaited(work.whenComplete(() => pending.remove(work)));
  }
  await Future.wait(pending);
  await out.flush();
}

/// Whether [host] names this machine only.
bool isLoopbackHost(String host) {
  final bare = host.startsWith('[') && host.endsWith(']')
      ? host.substring(1, host.length - 1)
      : host;
  if (bare == 'localhost') return true;
  final address = InternetAddress.tryParse(bare);
  return address != null && address.isLoopback;
}

/// Whether a browser's `Origin` header is one this server may answer: absent
/// (not a browser), or a page on this machine.
bool isAllowedOrigin(String? origin) {
  if (origin == null || origin.isEmpty) return true;
  final uri = Uri.tryParse(origin);
  if (uri == null || uri.host.isEmpty) return false;
  return isLoopbackHost(uri.host);
}

/// The MCP endpoint's path.
const String kMcpHttpPath = '/mcp';

/// A running HTTP transport.
class McpHttpTransport {
  McpHttpTransport._(this._server, this._http, this.token);

  final McpServer _server;
  final HttpServer _http;

  /// The bearer token clients must send, or null for none.
  final String? token;

  final Set<String> _sessions = {};

  InternetAddress get address => _http.address;
  int get port => _http.port;

  /// The endpoint, as a client is configured with it.
  Uri get url => Uri(
        scheme: 'http',
        host: _http.address.type == InternetAddressType.IPv6
            ? '[${_http.address.address}]'
            : _http.address.address,
        port: port,
        path: kMcpHttpPath,
      );

  /// Binds [host]:[port] and starts answering. Throws [ArgumentError] for a
  /// non-loopback [host] with no [token].
  static Future<McpHttpTransport> bind(
    McpServer server, {
    String host = '127.0.0.1',
    int port = 8765,
    String? token,
  }) async {
    if (!isLoopbackHost(host) && (token == null || token.isEmpty)) {
      throw ArgumentError(
          'Refusing to listen on $host without a token: anyone who can reach '
          'it could drive this desktop. Pass --token (or set '
          'MOONSWING_MCP_TOKEN), or listen on 127.0.0.1.');
    }
    final http = await HttpServer.bind(host, port);
    final transport =
        McpHttpTransport._(server, http, token == null || token.isEmpty ? null : token);
    http.listen((request) => unawaited(transport._serve(request)));
    return transport;
  }

  Future<void> close() => _http.close(force: true);

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.uri.path != kMcpHttpPath) {
        return await _status(response, HttpStatus.notFound, 'Not found; the MCP '
            'endpoint is $kMcpHttpPath.');
      }
      if (!isAllowedOrigin(request.headers.value('origin'))) {
        return await _status(response, HttpStatus.forbidden, 'Cross-origin '
            'requests are refused.');
      }
      final expected = token;
      if (expected != null &&
          request.headers.value(HttpHeaders.authorizationHeader) !=
              'Bearer $expected') {
        response.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Bearer');
        return await _status(response, HttpStatus.unauthorized,
            'A bearer token is required.');
      }
      switch (request.method) {
        case 'POST':
          return await _post(request);
        case 'DELETE':
          final session = request.headers.value('mcp-session-id');
          if (session != null) _sessions.remove(session);
          return await _status(response, HttpStatus.ok, '');
        default:
          // GET would open the server-to-client event stream, and this server
          // has nothing to say unasked.
          response.headers.set(HttpHeaders.allowHeader, 'POST, DELETE');
          return await _status(response, HttpStatus.methodNotAllowed,
              'This server only answers POSTs.');
      }
    } catch (e) {
      try {
        await _status(response, HttpStatus.internalServerError, '$e');
      } catch (_) {}
    }
  }

  Future<void> _post(HttpRequest request) async {
    final response = request.response;
    final text = await utf8.decoder.bind(request).join();
    Object? message;
    try {
      message = jsonDecode(text);
    } on FormatException catch (e) {
      return _json(response, HttpStatus.badRequest, {
        'jsonrpc': '2.0',
        'id': null,
        'error': {
          'code': JsonRpcError.parseError,
          'message': 'Parse error: ${e.message}',
        },
      });
    }
    final initializing = _isInitialize(message);
    final answer = await _server.handle(message);
    if (answer == null) {
      response.statusCode = HttpStatus.accepted;
      await response.close();
      return;
    }
    if (initializing) {
      final session = _newSessionId();
      _sessions.add(session);
      response.headers.set('Mcp-Session-Id', session);
    }
    return _json(response, HttpStatus.ok, answer);
  }

  static bool _isInitialize(Object? message) {
    if (message is Map) return message['method'] == 'initialize';
    if (message is List) return message.any(_isInitialize);
    return false;
  }

  static String _newSessionId() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  static Future<void> _json(HttpResponse response, int status, Object? body) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    return response.close();
  }

  static Future<void> _status(HttpResponse response, int status, String text) {
    response.statusCode = status;
    response.headers.contentType = ContentType.text;
    response.write(text);
    return response.close();
  }
}
