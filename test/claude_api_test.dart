import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:moonswing/claude/claude_account_store.dart';
import 'package:moonswing/claude/claude_api.dart';
import 'package:moonswing/claude/claude_config.dart';

void main() {
  group('the request', () {
    test('streams, caches, and opts the default model into fallbacks', () {
      final body = claudeRequestBody(
        model: 'claude-opus-5',
        system: 'sys',
        messages: const [ClaudeTurn.user('hi')],
      );
      expect(body['stream'], true);
      expect(body['model'], 'claude-opus-5');
      expect(body['max_tokens'], kClaudeMaxTokens);
      expect(body['cache_control'], {'type': 'ephemeral'});
      expect(body['system'], 'sys');
      expect(body['messages'], [
        {'role': 'user', 'content': 'hi'},
      ]);
      expect(body['output_config'], {'effort': kClaudeDefaultEffort});
      expect(body['fallbacks'], 'default');
      // Adaptive thinking is the default when the key is omitted.
      expect(body.containsKey('thinking'), isFalse);
      expect(
        claudeHeaders('k', model: 'claude-opus-5')['anthropic-beta'],
        kClaudeFallbackBeta,
      );
    });

    test('a model without server-side fallbacks is sent without them', () {
      final body = claudeRequestBody(
        model: 'claude-haiku-4-5',
        system: '',
        messages: const [],
      );
      expect(body.containsKey('fallbacks'), isFalse);
      expect(
        claudeHeaders('k', model: 'claude-haiku-4-5'),
        isNot(contains('anthropic-beta')),
      );
      expect(claudeHeaders('k')['x-api-key'], 'k');
      expect(claudeHeaders('k')['anthropic-version'], '2023-06-01');
    });
  });

  group('the stream', () {
    Stream<String> sse(List<Map<String, dynamic>> events) =>
        Stream.fromIterable([
          for (final e in events) ...[
            'event: ${e['type']}',
            'data: ${jsonEncode(e)}',
            '',
          ],
        ]);

    test('yields the text, the serving model and the stop reason', () async {
      final events = await claudeEventsFromSse(
        sse([
          {
            'type': 'message_start',
            'message': {'model': 'claude-opus-4-8'},
          },
          {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {'type': 'text', 'text': ''},
          },
          {'type': 'ping'},
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': 'Hel'},
          },
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'thinking_delta', 'thinking': 'hmm'},
          },
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': 'lo'},
          },
          {'type': 'some_future_event'},
          {
            'type': 'message_delta',
            'delta': {
              'stop_reason': 'refusal',
              'stop_details': {'type': 'refusal', 'category': 'cyber'},
            },
          },
          {'type': 'message_stop'},
        ]),
      ).toList();

      expect(
        events.whereType<ClaudeModelServed>().single.model,
        'claude-opus-4-8',
      );
      expect(
        events.whereType<ClaudeTextDelta>().map((e) => e.text).join(),
        'Hello',
      );
      final stop = events.whereType<ClaudeStopped>().single;
      expect(stop.stopReason, 'refusal');
      expect(stop.refusalCategory, 'cyber');
    });

    test('a malformed line costs that line', () async {
      final events = await claudeEventsFromSse(
        Stream.fromIterable([
          'data: {not json',
          'data: ${jsonEncode({
            'type': 'content_block_delta',
            'delta': {'type': 'text_delta', 'text': 'x'},
          })}',
        ]),
      ).toList();
      expect(events, hasLength(1));
    });

    test('an error event ends the stream with its reason', () {
      expect(
        claudeEventsFromSse(
          Stream.value(
            'data: ${jsonEncode({
              'type': 'error',
              'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
            })}',
          ),
        ).toList(),
        throwsA(
          isA<ClaudeException>().having((e) => e.retryable, 'retryable', true),
        ),
      );
    });
  });

  group('errors', () {
    test('map to what the user can do about them', () {
      expect(claudeErrorFrom(null, status: 401), isA<ClaudeAuthException>());
      expect(claudeErrorFrom(null, status: 429).retryable, isTrue);
      expect(claudeErrorFrom(null, status: 529).retryable, isTrue);
      expect(claudeErrorFrom(null, status: 503).retryable, isTrue);
      final bad = claudeErrorFrom({
        'type': 'error',
        'error': {
          'type': 'invalid_request_error',
          'message': 'Your credit balance is too low',
        },
      }, status: 400);
      expect(bad.message, 'Your credit balance is too low');
      expect(bad.retryable, isFalse);
    });
  });

  group('HttpClaudeClient', () {
    test('verifies a key with a model list read', () async {
      final seen = <http.Request>[];
      final client = HttpClaudeClient(
        httpClient: MockClient((request) async {
          seen.add(request);
          return request.headers['x-api-key'] == 'good'
              ? http.Response('{"data":[]}', 200)
              : http.Response(
                  '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}',
                  401,
                );
        }),
      );
      await client.verifyKey('good');
      expect(seen.single.url.path, '/v1/models');
      expect(seen.single.method, 'GET');
      expect(client.verifyKey('bad'), throwsA(isA<ClaudeAuthException>()));
    });

    test('streams an answer', () async {
      late http.BaseRequest sent;
      final client = HttpClaudeClient(
        httpClient: MockClient.streaming((request, body) async {
          sent = request;
          final lines = [
            'event: content_block_delta',
            'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}',
            '',
            'event: message_delta',
            'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}',
            '',
          ].join('\n');
          return http.StreamedResponse(Stream.value(utf8.encode(lines)), 200);
        }),
      );
      final events = await client
          .stream(
            key: 'k',
            model: 'claude-opus-5',
            system: 's',
            messages: const [ClaudeTurn.user('q')],
            effort: 'low',
          )
          .toList();
      expect(sent.url.path, '/v1/messages');
      expect(sent.headers['anthropic-beta'], kClaudeFallbackBeta);
      expect((events.first as ClaudeTextDelta).text, 'Hi');
      expect((events.last as ClaudeStopped).stopReason, 'end_turn');
    });

    test('a non-200 answer is its error', () {
      final client = HttpClaudeClient(
        httpClient: MockClient(
          (_) async => http.Response(
            '{"type":"error","error":{"type":"rate_limit_error","message":"slow"}}',
            429,
          ),
        ),
      );
      expect(
        client
            .stream(
              key: 'k',
              model: 'm',
              system: '',
              messages: const [],
              effort: 'low',
            )
            .toList(),
        throwsA(
          isA<ClaudeException>().having((e) => e.retryable, 'retryable', true),
        ),
      );
    });
  });

  test('a key is shown as its prefix and last four characters', () {
    expect(claudeKeyHint(null), '');
    expect(
      claudeKeyHint('sk-ant-api03-abcdefghijklmnop-WXYZ'),
      'sk-ant-api03-…WXYZ',
    );
    expect(claudeKeyHint('short'), '…');
  });

  group('ClaudeConfig', () {
    test('reads its table, and a bad value costs that key', () {
      expect(ClaudeConfig.fromMap(null), const ClaudeConfig());
      final config = ClaudeConfig.fromMap({
        'model': 'claude-sonnet-5',
        'effort': 'ludicrous',
        'generate_ui': 'yes',
      });
      expect(config.model, 'claude-sonnet-5');
      expect(config.effort, kClaudeDefaultEffort);
      expect(config.generateUi, isTrue);
      expect(
        ClaudeConfig.fromMap({'effort': 'high', 'generate_ui': false}),
        const ClaudeConfig(effort: 'high', generateUi: false),
      );
    });
  });
}
