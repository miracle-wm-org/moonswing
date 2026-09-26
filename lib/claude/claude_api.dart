// The web half of the Claude module: checking an API key, and one streamed
// turn of the Messages API.
//
// Raw HTTP over `package:http` rather than an SDK, because Anthropic publishes
// none for Dart and the request is one endpoint: `POST /v1/messages` with
// `stream: true`, read back as server-sent events. Flutter-free and behind an
// interface for the reasons `github_api.dart` is — the store drives it and a
// test driving that store must not reach the network — and every event is
// parsed by a pure function over a decoded map, so a shape change at the API
// costs the event rather than the answer.
//
// **Why an API key and not a claude.ai sign-in.** A Claude Pro or Max
// subscription signs in to Anthropic's own apps; Anthropic does not let a third
// party offer that login or spend a subscription's limits from its own product.
// What a program may use is the Claude API, which authenticates with a key from
// the Claude Console and is billed to that Console account. So the account the
// shell links is a Console key, pasted once under Settings › Accounts.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// The API root. Overridable only by tests.
const String kClaudeApiBase = 'https://api.anthropic.com';

/// Where a key is made: the Claude Console's API keys page.
const String kClaudeConsoleKeysUrl =
    'https://console.anthropic.com/settings/keys';

/// Where the key's usage and bill are seen.
const String kClaudeConsoleUsageUrl = 'https://console.anthropic.com/usage';

/// The model a question goes to unless `[modules.claude] model` says otherwise.
const String kClaudeDefaultModel = 'claude-opus-5';

/// How hard the model thinks before it answers, unless `[modules.claude]
/// effort` says otherwise. `medium` rather than the API's default `high`:
/// this is a question typed into a bar popup, where the wait is the cost the
/// user feels, and the popup is where a longer answer can be asked for.
const String kClaudeDefaultEffort = 'medium';

/// The effort levels the API accepts.
const List<String> kClaudeEfforts = ['low', 'medium', 'high', 'xhigh', 'max'];

/// The output cap for one answer. Generous because the request is streamed —
/// the cap exists to end a runaway, not to shape an answer, and hitting it cuts
/// a generated UI off mid-JSON.
const int kClaudeMaxTokens = 64000;

/// The models that accept `fallbacks: "default"`. A safety classifier on these
/// can decline a benign request (a question about a firewall rule, say); with
/// the parameter the API re-runs it on the model Anthropic recommends for that
/// category inside the same call, rather than handing back a refusal. Any other
/// model is sent without it, since the parameter is validated per model.
const Set<String> kClaudeFallbackModels = {
  'claude-opus-5',
  'claude-opus-5-5',
  'claude-fable-5',
  'claude-fable-5-1',
};

/// The beta header the `fallbacks: "default"` form is gated on. Exactly this
/// value: the array form uses a different date and each 400s with the other.
const String kClaudeFallbackBeta = 'server-side-fallback-2026-07-01';

/// Thrown when a request fails in a way the user should be told about.
class ClaudeException implements Exception {
  const ClaudeException(this.message, {this.retryable = false});

  final String message;

  /// Whether trying the same thing again could work: overloaded, rate-limited,
  /// a dropped connection. The popup offers a retry either way; this decides
  /// what it says.
  final bool retryable;

  @override
  String toString() => message;
}

/// The key is not valid — never was, or has been deleted in the Console.
///
/// Its own type because it is the one failure with a *state* change behind it:
/// the store forgets the key and goes back to signed out, rather than leaving a
/// retry that can only fail.
class ClaudeAuthException extends ClaudeException {
  const ClaudeAuthException([
    super.message = 'The Claude API key was rejected',
  ]);
}

/// One turn of the conversation as the API is sent it.
class ClaudeTurn {
  const ClaudeTurn.user(this.text) : role = 'user';
  const ClaudeTurn.assistant(this.text) : role = 'assistant';

  final String role;
  final String text;

  Map<String, dynamic> toJson() => {'role': role, 'content': text};

  @override
  bool operator ==(Object other) =>
      other is ClaudeTurn && other.role == role && other.text == text;

  @override
  int get hashCode => Object.hash(role, text);
}

/// What a streamed turn yields.
sealed class ClaudeEvent {
  const ClaudeEvent();
}

/// A piece of the answer's text, in order.
class ClaudeTextDelta extends ClaudeEvent {
  const ClaudeTextDelta(this.text);

  final String text;
}

/// The model the turn is being served by, from `message_start` — which, after
/// a pre-output fallback, is the fallback model rather than the one asked for.
class ClaudeModelServed extends ClaudeEvent {
  const ClaudeModelServed(this.model);

  final String model;
}

/// The turn is over. [stopReason] is the API's own word for why: `end_turn`,
/// `max_tokens`, `refusal`, …
class ClaudeStopped extends ClaudeEvent {
  const ClaudeStopped(this.stopReason, {this.refusalCategory});

  final String stopReason;

  /// `stop_details.category` on a refusal, informational only; null otherwise
  /// and sometimes null on a refusal too.
  final String? refusalCategory;
}

/// The request body for one streamed turn. Pure, so the shape is pinned by
/// `test/claude_api_test.dart`.
Map<String, dynamic> claudeRequestBody({
  required String model,
  required String system,
  required List<ClaudeTurn> messages,
  String effort = kClaudeDefaultEffort,
  int maxTokens = kClaudeMaxTokens,
}) => {
  'model': model,
  'max_tokens': maxTokens,
  'stream': true,
  // Automatic prompt caching. The system prompt carries genui's schemas and
  // the catalogue — several thousand tokens that are identical on every turn —
  // and the history only ever grows at the end, so each turn re-reads the
  // last one's prefix from the cache rather than paying for it again.
  'cache_control': {'type': 'ephemeral'},
  'system': system,
  'messages': [for (final m in messages) m.toJson()],
  // No `thinking` key: the default models think adaptively when it is
  // omitted, and effort is the one dial worth exposing.
  'output_config': {'effort': effort},
  if (kClaudeFallbackModels.contains(model)) 'fallbacks': 'default',
};

/// The headers for [claudeRequestBody]'s request.
Map<String, String> claudeHeaders(String key, {String? model}) => {
  'content-type': 'application/json',
  'x-api-key': key,
  'anthropic-version': '2023-06-01',
  if (model != null && kClaudeFallbackModels.contains(model))
    'anthropic-beta': kClaudeFallbackBeta,
};

/// The events in one SSE `data:` payload. Pure; unknown event types — and the
/// API adds them — yield nothing rather than failing the answer.
///
/// Only text is surfaced. Thinking arrives as its own blocks, empty by default
/// on these models, and a server-side fallback's audit marker is a `fallback`
/// block; neither is part of what the user reads.
List<ClaudeEvent> claudeEventsFromData(Map<String, dynamic> data) {
  switch (data['type']) {
    case 'message_start':
      final message = data['message'];
      if (message is Map && message['model'] is String) {
        return [ClaudeModelServed(message['model'] as String)];
      }
      return const [];
    case 'content_block_delta':
      final delta = data['delta'];
      if (delta is Map &&
          delta['type'] == 'text_delta' &&
          delta['text'] is String) {
        return [ClaudeTextDelta(delta['text'] as String)];
      }
      return const [];
    case 'message_delta':
      final delta = data['delta'];
      if (delta is! Map) return const [];
      final reason = delta['stop_reason'];
      if (reason is! String) return const [];
      final details = delta['stop_details'];
      final category = details is Map && details['category'] is String
          ? details['category'] as String
          : null;
      return [ClaudeStopped(reason, refusalCategory: category)];
    case 'error':
      throw claudeErrorFrom(data, status: null);
    default:
      return const [];
  }
}

/// Turns SSE lines into events. `event:` lines are ignored — every `data:`
/// payload carries its own `type` — and so are comments and pings.
Stream<ClaudeEvent> claudeEventsFromSse(Stream<String> lines) async* {
  await for (final line in lines) {
    if (!line.startsWith('data:')) continue;
    final payload = line.substring(5).trim();
    if (payload.isEmpty) continue;
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      continue;
    }
    if (decoded is! Map<String, dynamic>) continue;
    yield* Stream.fromIterable(claudeEventsFromData(decoded));
  }
}

/// The exception an error body describes. [status] is the HTTP status when
/// there is one; a mid-stream `error` event has none.
ClaudeException claudeErrorFrom(Map<String, dynamic>? body, {int? status}) {
  final error = body?['error'];
  final type = error is Map ? error['type'] : null;
  final raw = error is Map && error['message'] is String
      ? error['message'] as String
      : '';
  if (status == 401 || type == 'authentication_error') {
    return const ClaudeAuthException();
  }
  if (status == 403 || type == 'permission_error') {
    return ClaudeException(
      raw.isEmpty ? 'This API key may not use that model' : raw,
    );
  }
  if (status == 429 || type == 'rate_limit_error') {
    return const ClaudeException(
      'Rate limited by the Claude API. Wait a moment and try again.',
      retryable: true,
    );
  }
  if (status == 529 || type == 'overloaded_error') {
    return const ClaudeException(
      'Claude is overloaded right now. Try again shortly.',
      retryable: true,
    );
  }
  if (type == 'invalid_request_error' || status == 400 || status == 404) {
    // Said verbatim: the API's own sentence names the field, and "bad request"
    // on its own names nothing. A low credit balance arrives this way too.
    return ClaudeException(raw.isEmpty ? 'The request was refused' : raw);
  }
  if (status != null && status >= 500) {
    return const ClaudeException(
      'The Claude API had a problem. Try again.',
      retryable: true,
    );
  }
  return ClaudeException(
    raw.isEmpty ? 'The Claude API answered with an error' : raw,
    retryable: true,
  );
}

/// What the store talks to.
abstract interface class ClaudeClient {
  /// Checks [key] without spending a token: a read of the model list. Throws
  /// [ClaudeAuthException] for a key the API will not take.
  Future<void> verifyKey(String key);

  /// One streamed turn.
  Stream<ClaudeEvent> stream({
    required String key,
    required String model,
    required String system,
    required List<ClaudeTurn> messages,
    required String effort,
  });
}

class HttpClaudeClient implements ClaudeClient {
  HttpClaudeClient({http.Client? httpClient, this.base = kClaudeApiBase})
    : _client = httpClient;

  final http.Client? _client;
  final String base;

  http.Client get _c => _client ?? (_shared ??= http.Client());
  static http.Client? _shared;

  @override
  Future<void> verifyKey(String key) async {
    final http.Response response;
    try {
      response = await _c.get(
        Uri.parse('$base/v1/models?limit=1'),
        headers: claudeHeaders(key),
      );
    } catch (_) {
      throw const ClaudeException('Could not reach the Claude API');
    }
    if (response.statusCode == 200) return;
    throw claudeErrorFrom(_decode(response.body), status: response.statusCode);
  }

  @override
  Stream<ClaudeEvent> stream({
    required String key,
    required String model,
    required String system,
    required List<ClaudeTurn> messages,
    required String effort,
  }) async* {
    final request = http.Request('POST', Uri.parse('$base/v1/messages'))
      ..headers.addAll(claudeHeaders(key, model: model))
      ..body = jsonEncode(
        claudeRequestBody(
          model: model,
          system: system,
          messages: messages,
          effort: effort,
        ),
      );
    final http.StreamedResponse response;
    try {
      response = await _c.send(request);
    } catch (_) {
      throw const ClaudeException(
        'Could not reach the Claude API',
        retryable: true,
      );
    }
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw claudeErrorFrom(_decode(body), status: response.statusCode);
    }
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    try {
      yield* claudeEventsFromSse(lines);
    } on ClaudeException {
      rethrow;
    } catch (_) {
      throw const ClaudeException(
        'The connection to Claude dropped mid-answer',
        retryable: true,
      );
    }
  }

  static Map<String, dynamic>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
