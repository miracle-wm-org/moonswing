// The Model Context Protocol, the part of it a tool server needs.
//
// MCP is JSON-RPC 2.0: a client sends `initialize`, lists the server's tools with
// `tools/list`, and calls one with `tools/call`. That is the whole of what
// `moonswing-mcp` serves — no resources, prompts or sampling — so this is a
// dispatcher over a table of [McpTool]s, with the transports (`mcp_transport.dart`)
// carrying messages to it and its answers back.
//
// Flutter-free: the server is a `dart compile exe` binary, and
// `test/mcp_protocol_test.dart` drives this file with plain maps.
library;

import 'dart:async';
import 'dart:convert';

/// The protocol revisions this server speaks, newest first. A client asking for
/// one of these gets it back; anything else is answered with the newest, which
/// the spec says the client then accepts or disconnects over.
const List<String> kMcpProtocolVersions = [
  '2025-11-25',
  '2025-06-18',
  '2025-03-26',
  '2024-11-05',
];

/// JSON-RPC's own error codes.
abstract final class JsonRpcError {
  static const int parseError = -32700;
  static const int invalidRequest = -32600;
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;
  static const int internalError = -32603;
}

/// One piece of a tool's answer.
sealed class McpContent {
  const McpContent();

  Map<String, Object?> toJson();
}

class McpText extends McpContent {
  const McpText(this.text);

  final String text;

  @override
  Map<String, Object?> toJson() => {'type': 'text', 'text': text};
}

class McpImage extends McpContent {
  const McpImage(this.data, {this.mimeType = 'image/png'});

  /// Base64.
  final String data;
  final String mimeType;

  @override
  Map<String, Object?> toJson() =>
      {'type': 'image', 'data': data, 'mimeType': mimeType};
}

/// What a tool answers.
///
/// [isError] is a *tool* failure — the window did not exist, the shell is not
/// running — which the model is shown and can act on. A malformed call is a
/// JSON-RPC error instead, and never reaches a handler.
class McpToolResult {
  const McpToolResult(this.content, {this.isError = false});

  McpToolResult.text(String text, {bool isError = false})
      : this([McpText(text)], isError: isError);

  /// [value] as indented JSON — what nearly every tool here answers with, since
  /// a model reads a JSON object as well as a sentence and a program reads it
  /// better.
  McpToolResult.json(Object? value)
      : this([McpText(const JsonEncoder.withIndent('  ').convert(value))]);

  McpToolResult.error(String message) : this([McpText(message)], isError: true);

  final List<McpContent> content;
  final bool isError;

  Map<String, Object?> toJson() => {
        'content': [for (final piece in content) piece.toJson()],
        'isError': isError,
      };
}

/// A refusal a handler throws to answer [McpToolResult.error] with [message].
class McpToolException implements Exception {
  const McpToolException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The arguments a tool was called with, read the way `TomlReader` reads
/// config: a missing or wrongly-typed value is an [McpToolException] naming the
/// argument, never a cast error the model cannot make sense of.
class McpArgs {
  const McpArgs(this.raw);

  final Map<String, Object?> raw;

  bool has(String key) => raw[key] != null;

  String string(String key) {
    final value = optionalString(key);
    if (value == null) throw McpToolException('"$key" is required.');
    return value;
  }

  String? optionalString(String key) {
    final value = raw[key];
    if (value == null) return null;
    if (value is String) return value;
    if (value is num || value is bool) return '$value';
    throw McpToolException('"$key" must be a string.');
  }

  int integer(String key, {int? min, int? max}) {
    final value = optionalInteger(key, min: min, max: max);
    if (value == null) throw McpToolException('"$key" is required.');
    return value;
  }

  int? optionalInteger(String key, {int? min, int? max}) {
    final value = raw[key];
    if (value == null) return null;
    final int number;
    if (value is int) {
      number = value;
    } else if (value is double && value.isFinite && value == value.truncate()) {
      number = value.toInt();
    } else if (value is String && int.tryParse(value.trim()) != null) {
      number = int.parse(value.trim());
    } else {
      throw McpToolException('"$key" must be a whole number.');
    }
    if (min != null && number < min) {
      throw McpToolException('"$key" must be at least $min.');
    }
    if (max != null && number > max) {
      throw McpToolException('"$key" must be at most $max.');
    }
    return number;
  }

  double? optionalNumber(String key, {double? min, double? max}) {
    final value = raw[key];
    if (value == null) return null;
    final double number;
    if (value is num) {
      number = value.toDouble();
    } else if (value is String && double.tryParse(value.trim()) != null) {
      number = double.parse(value.trim());
    } else {
      throw McpToolException('"$key" must be a number.');
    }
    if (!number.isFinite) throw McpToolException('"$key" must be finite.');
    if (min != null && number < min) {
      throw McpToolException('"$key" must be at least $min.');
    }
    if (max != null && number > max) {
      throw McpToolException('"$key" must be at most $max.');
    }
    return number;
  }

  bool? optionalBool(String key) {
    final value = raw[key];
    if (value == null) return null;
    if (value is bool) return value;
    if (value == 'true') return true;
    if (value == 'false') return false;
    throw McpToolException('"$key" must be true or false.');
  }

  List<String>? optionalStrings(String key) {
    final value = raw[key];
    if (value == null) return null;
    if (value is String) return [value];
    if (value is List && value.every((v) => v is String)) {
      return value.cast<String>();
    }
    throw McpToolException('"$key" must be a list of strings.');
  }

  /// One of [choices], or [fallback] when absent.
  String choice(String key, List<String> choices, {String? fallback}) {
    final value = optionalString(key) ?? fallback;
    if (value == null) throw McpToolException('"$key" is required.');
    if (!choices.contains(value)) {
      throw McpToolException(
          '"$key" must be one of ${choices.join(', ')}; got "$value".');
    }
    return value;
  }
}

typedef McpToolHandler = Future<McpToolResult> Function(McpArgs args);

/// One tool: what the model is told about it, and what it runs.
class McpTool {
  const McpTool({
    required this.name,
    required this.title,
    required this.description,
    required this.handler,
    this.properties = const {},
    this.required = const [],
    this.readOnly = false,
    this.destructive = false,
    this.idempotent = false,
  });

  /// `group_verb_object`, snake case — the shape every client accepts (OpenAI's
  /// function names allow `[a-zA-Z0-9_-]` and 64 characters).
  final String name;
  final String title;
  final String description;

  /// JSON Schema for each argument, by name.
  final Map<String, Map<String, Object?>> properties;
  final List<String> required;

  /// Whether it changes nothing. `--read-only` serves only these.
  final bool readOnly;

  /// Whether what it changes cannot be put back by another call (closing a
  /// window, deleting a card).
  final bool destructive;
  final bool idempotent;

  final McpToolHandler handler;

  Map<String, Object?> toJson() => {
        'name': name,
        'title': title,
        'description': description,
        'inputSchema': {
          'type': 'object',
          'properties': properties,
          if (required.isNotEmpty) 'required': required,
          'additionalProperties': false,
        },
        'annotations': {
          'title': title,
          'readOnlyHint': readOnly,
          'destructiveHint': destructive,
          'idempotentHint': idempotent,
          // Everything here acts on this machine's desktop, nowhere else.
          'openWorldHint': false,
        },
      };
}

/// JSON Schema shorthands for [McpTool.properties].
abstract final class Schema {
  static Map<String, Object?> string(String description, {List<String>? oneOf}) => {
        'type': 'string',
        'description': description,
        'enum': ?oneOf,
      };

  static Map<String, Object?> integer(String description, {int? min, int? max}) =>
      {
        'type': 'integer',
        'description': description,
        'minimum': ?min,
        'maximum': ?max,
      };

  static Map<String, Object?> number(String description,
          {num? min, num? max}) =>
      {
        'type': 'number',
        'description': description,
        'minimum': ?min,
        'maximum': ?max,
      };

  static Map<String, Object?> boolean(String description) =>
      {'type': 'boolean', 'description': description};

  static Map<String, Object?> strings(String description) => {
        'type': 'array',
        'description': description,
        'items': {'type': 'string'},
      };
}

/// Who this server says it is.
class McpServerInfo {
  const McpServerInfo({
    required this.name,
    required this.title,
    required this.version,
    this.instructions,
  });

  final String name;
  final String title;
  final String version;

  /// Sent in `initialize`'s answer, for the client to put in front of the model.
  final String? instructions;
}

/// The dispatcher. Transport-agnostic: [handle] takes one decoded JSON-RPC
/// message (or a batch) and answers what should be sent back, or null for a
/// notification.
class McpServer {
  McpServer({required this.info, required List<McpTool> tools})
      : _tools = {for (final tool in tools) tool.name: tool};

  final McpServerInfo info;
  final Map<String, McpTool> _tools;

  Iterable<McpTool> get tools => _tools.values;

  /// The revision agreed in `initialize`, or null before it.
  String? negotiatedVersion;

  /// Answers one message, or each of a batch.
  Future<Object?> handle(Object? message) async {
    if (message is List) {
      if (message.isEmpty) {
        return _error(null, JsonRpcError.invalidRequest, 'Empty batch.');
      }
      final answers = <Object?>[];
      for (final entry in message) {
        final answer = await _handleOne(entry);
        if (answer != null) answers.add(answer);
      }
      return answers.isEmpty ? null : answers;
    }
    return _handleOne(message);
  }

  /// [handle] for a line of text, parse errors included.
  Future<String?> handleText(String text) async {
    final Object? message;
    try {
      message = jsonDecode(text);
    } on FormatException catch (e) {
      return jsonEncode(
          _error(null, JsonRpcError.parseError, 'Parse error: ${e.message}'));
    }
    final answer = await handle(message);
    return answer == null ? null : jsonEncode(answer);
  }

  Future<Map<String, Object?>?> _handleOne(Object? message) async {
    if (message is! Map<String, Object?>) {
      return _error(null, JsonRpcError.invalidRequest,
          'A JSON-RPC message must be an object.');
    }
    final id = message['id'];
    final method = message['method'];
    // A response to something we sent: this server sends no requests, so
    // there is nothing to match it to.
    if (method == null) return null;
    if (method is! String || message['jsonrpc'] != '2.0') {
      return id == null
          ? null
          : _error(id, JsonRpcError.invalidRequest, 'Not a JSON-RPC 2.0 request.');
    }
    final paramsValue = message['params'];
    final params = paramsValue is Map<String, Object?>
        ? paramsValue
        : const <String, Object?>{};
    // A notification: `notifications/initialized`, `notifications/cancelled`.
    // None of them needs an answer, and none changes what this server does.
    if (id == null) return null;
    try {
      final result = await _dispatch(method, params);
      return {'jsonrpc': '2.0', 'id': id, 'result': result};
    } on _RpcFailure catch (e) {
      return _error(id, e.code, e.message);
    } catch (e) {
      return _error(id, JsonRpcError.internalError, '$e');
    }
  }

  Future<Map<String, Object?>> _dispatch(
      String method, Map<String, Object?> params) async {
    switch (method) {
      case 'initialize':
        final asked = params['protocolVersion'];
        final version = asked is String && kMcpProtocolVersions.contains(asked)
            ? asked
            : kMcpProtocolVersions.first;
        negotiatedVersion = version;
        return {
          'protocolVersion': version,
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {
            'name': info.name,
            'title': info.title,
            'version': info.version,
          },
          if (info.instructions != null) 'instructions': info.instructions,
        };
      case 'ping':
        return {};
      case 'tools/list':
        return {
          'tools': [for (final tool in _tools.values) tool.toJson()],
        };
      case 'tools/call':
        final name = params['name'];
        final tool = name is String ? _tools[name] : null;
        if (tool == null) {
          throw _RpcFailure(JsonRpcError.invalidParams, 'Unknown tool: $name');
        }
        final arguments = params['arguments'];
        if (arguments != null && arguments is! Map<String, Object?>) {
          throw _RpcFailure(
              JsonRpcError.invalidParams, 'Tool arguments must be an object.');
        }
        return (await _call(tool, McpArgs(
                (arguments as Map<String, Object?>?) ?? const {})))
            .toJson();
      // Asked by clients that probe every capability, whatever was declared.
      case 'resources/list':
        return {'resources': []};
      case 'resources/templates/list':
        return {'resourceTemplates': []};
      case 'prompts/list':
        return {'prompts': []};
      default:
        throw _RpcFailure(
            JsonRpcError.methodNotFound, 'Method not found: $method');
    }
  }

  Future<McpToolResult> _call(McpTool tool, McpArgs args) async {
    try {
      return await tool.handler(args);
    } on McpToolException catch (e) {
      return McpToolResult.error(e.message);
    } on TimeoutException {
      return McpToolResult.error('${tool.name} timed out.');
    } catch (e) {
      return McpToolResult.error('${tool.name} failed: $e');
    }
  }

  static Map<String, Object?> _error(Object? id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };
}

class _RpcFailure implements Exception {
  const _RpcFailure(this.code, this.message);

  final int code;
  final String message;
}
