import 'dart:async';

import 'package:moonswing/claude/claude_api.dart';

/// A [ClaudeClient] that answers from a script rather than the network.
class FakeClaudeClient implements ClaudeClient {
  FakeClaudeClient({this.verifyError, List<List<ClaudeEvent>>? answers})
    : answers = answers ?? [];

  /// Thrown by [verifyKey] when set.
  Object? verifyError;

  /// One list of events per [stream] call, in order. An exhausted script
  /// answers "ok".
  final List<List<ClaudeEvent>> answers;

  /// Thrown after an answer's events, when set, and then cleared.
  Object? streamError;

  /// What each [stream] call was sent.
  final List<
    ({
      String key,
      String model,
      String system,
      List<ClaudeTurn> messages,
      String effort,
    })
  >
  requests = [];

  /// When set, [stream] waits for this before emitting, so a test can stop an
  /// answer mid-flight.
  Completer<void>? gate;

  final List<String> verified = [];

  @override
  Future<void> verifyKey(String key) async {
    verified.add(key);
    final error = verifyError;
    if (error != null) throw error;
  }

  @override
  Stream<ClaudeEvent> stream({
    required String key,
    required String model,
    required String system,
    required List<ClaudeTurn> messages,
    required String effort,
  }) async* {
    requests.add((
      key: key,
      model: model,
      system: system,
      messages: List.of(messages),
      effort: effort,
    ));
    final gate = this.gate;
    if (gate != null) await gate.future;
    final events = answers.isEmpty
        ? const <ClaudeEvent>[ClaudeTextDelta('ok'), ClaudeStopped('end_turn')]
        : answers.removeAt(0);
    for (final e in events) {
      yield e;
    }
    final error = streamError;
    if (error != null) {
      streamError = null;
      throw error;
    }
  }
}
