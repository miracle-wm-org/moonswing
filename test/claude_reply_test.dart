import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/claude/claude_reply.dart';

/// Feeds [chunks] and returns every piece, adjacent text merged.
List<ReplyPiece> split(List<String> chunks) {
  final splitter = ClaudeReplySplitter();
  final out = <ReplyPiece>[
    for (final c in chunks) ...splitter.add(c),
    ...splitter.close(),
  ];
  final merged = <ReplyPiece>[];
  for (final p in out) {
    if (p is ReplyText && merged.isNotEmpty && merged.last is ReplyText) {
      merged[merged.length - 1] = ReplyText(
        (merged.last as ReplyText).text + p.text,
      );
    } else {
      merged.add(p);
    }
  }
  return merged;
}

const _create =
    '{"version":"v0.9","createSurface":{"surfaceId":"s1","catalogId":"c"}}';

void main() {
  test('plain text streams straight through', () {
    final splitter = ClaudeReplySplitter();
    expect(splitter.add('Hello, '), [const ReplyText('Hello, ')]);
    expect(splitter.add('world {with braces}'), [
      const ReplyText('world {with braces}'),
    ]);
    expect(splitter.close(), isEmpty);
  });

  test('an A2UI fence becomes UI, wherever the chunks split it', () {
    final text = 'Here you go:\n```json\n$_create\n```\nDone.';
    for (var i = 1; i < text.length; i++) {
      final pieces = split([text.substring(0, i), text.substring(i)]);
      expect(pieces, hasLength(3), reason: 'split at $i');
      expect(pieces[0], const ReplyText('Here you go:\n'));
      expect((pieces[1] as ReplyUi).createdSurfaces, ['s1']);
      expect(pieces[2], const ReplyText('\nDone.'));
    }
  });

  test('a list of messages is one UI block', () {
    final pieces = split([
      '```json\n[$_create, {"version":"v0.9","updateComponents":{"surfaceId":"s1","components":[]}}]\n```',
    ]);
    expect(pieces.single, isA<ReplyUi>());
  });

  test('JSON that is not A2UI stays text the user can read', () {
    const block = '```json\n{"name": "example"}\n```';
    expect(split([block]), [const ReplyText(block)]);
  });

  test('code in another language streams as text, fence and all', () {
    final splitter = ClaudeReplySplitter();
    expect(splitter.add('Run:\n```sh\nls {a,b}'), [
      const ReplyText('Run:\n```sh\nls {a,b}'),
    ]);
    expect(splitter.add('\n```\nafter'), [const ReplyText('\n```\nafter')]);
  });

  test('an unclosed fence is text when the answer ends', () {
    expect(split(['```json\n{"createSurface":']), [
      const ReplyText('```json\n{"createSurface":'),
    ]);
  });

  test('looksLikeA2ui', () {
    expect(looksLikeA2ui({'deleteSurface': {}}), isTrue);
    expect(looksLikeA2ui([]), isFalse);
    expect(looksLikeA2ui({'a': 1}), isFalse);
    expect(looksLikeA2ui('createSurface'), isFalse);
  });
}
