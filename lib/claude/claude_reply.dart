// Splits a streamed answer into what the user reads and what genui builds.
//
// Claude answers in prose, and — when a UI would serve better than a paragraph
// — writes A2UI messages into ```json fences, the way genui's prompt asks it
// to. genui's own `A2uiParserTransformer` expects to own the whole stream and
// treats *any* balanced `{…}` as a candidate message, which in a chat answer is
// wrong in two ways: prose about code is full of braces, so text is held back
// waiting for a brace that closes three paragraphs later; and a JSON example
// the user asked for would be swallowed as a malformed UI. So this splitter
// sits in front of it and hands genui exactly the fences that are A2UI, and
// streams everything else as text, the moment it arrives.
//
// Pure and Flutter-free, so `test/claude_reply_test.dart` pins it chunk by
// chunk — every split point is one a real stream produces.

import 'dart:convert';

/// A piece of an answer.
sealed class ReplyPiece {
  const ReplyPiece();
}

/// Text for the user to read.
class ReplyText extends ReplyPiece {
  const ReplyText(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is ReplyText && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'ReplyText(${jsonEncode(text)})';
}

/// One fenced block that is A2UI: a message object, or a list of them.
class ReplyUi extends ReplyPiece {
  const ReplyUi(this.json, this.source);

  /// The decoded message(s).
  final Object json;

  /// The block's text, exactly as written — what genui's parser is fed.
  final String source;

  /// The `surfaceId` of every `createSurface` in the block, in order.
  List<String> get createdSurfaces => [
    for (final m in json is List ? json as List : [json])
      if (m is Map &&
          m['createSurface'] is Map &&
          (m['createSurface'] as Map)['surfaceId'] is String)
        (m['createSurface'] as Map)['surfaceId'] as String,
  ];

  @override
  String toString() => 'ReplyUi($source)';
}

const Set<String> _a2uiKeys = {
  'createSurface',
  'updateComponents',
  'updateDataModel',
  'deleteSurface',
};

/// Whether [json] is an A2UI message or a list of them.
bool looksLikeA2ui(Object? json) {
  bool one(Object? m) => m is Map && m.keys.any(_a2uiKeys.contains);
  if (json is List) return json.isNotEmpty && json.every(one);
  return one(json);
}

enum _State { text, codeFence, heldFence }

/// The incremental splitter.
class ClaudeReplySplitter {
  String _buffer = '';
  _State _state = _State.text;
  String _fenceHeader = '';

  /// Feeds [chunk]; returns whatever can be decided now.
  List<ReplyPiece> add(String chunk) {
    _buffer += chunk;
    final out = <ReplyPiece>[];
    void text(String t) {
      if (t.isEmpty) return;
      if (out.isNotEmpty && out.last is ReplyText) {
        out[out.length - 1] = ReplyText((out.last as ReplyText).text + t);
      } else {
        out.add(ReplyText(t));
      }
    }

    while (_buffer.isNotEmpty) {
      final fence = _buffer.indexOf('```');
      switch (_state) {
        case _State.text:
          if (fence < 0) {
            // Up to two trailing backticks may be the start of a fence.
            final keep = _trailingBackticks(_buffer);
            text(_buffer.substring(0, _buffer.length - keep));
            _buffer = _buffer.substring(_buffer.length - keep);
            return out;
          }
          final newline = _buffer.indexOf('\n', fence);
          if (newline < 0) {
            // The fence's language is not known yet.
            text(_buffer.substring(0, fence));
            _buffer = _buffer.substring(fence);
            return out;
          }
          final lang = _buffer.substring(fence + 3, newline).trim();
          if (lang == 'json' || lang.isEmpty) {
            text(_buffer.substring(0, fence));
            _fenceHeader = _buffer.substring(fence, newline + 1);
            _buffer = _buffer.substring(newline + 1);
            _state = _State.heldFence;
          } else {
            // Code the user is to read: streamed as it comes, fence and all.
            text(_buffer.substring(0, newline + 1));
            _buffer = _buffer.substring(newline + 1);
            _state = _State.codeFence;
          }
        case _State.codeFence:
          if (fence < 0) {
            final keep = _trailingBackticks(_buffer);
            text(_buffer.substring(0, _buffer.length - keep));
            _buffer = _buffer.substring(_buffer.length - keep);
            return out;
          }
          text(_buffer.substring(0, fence + 3));
          _buffer = _buffer.substring(fence + 3);
          _state = _State.text;
        case _State.heldFence:
          if (fence < 0) return out;
          final body = _buffer.substring(0, fence);
          _buffer = _buffer.substring(fence + 3);
          _state = _State.text;
          final piece = _decide(body);
          if (piece is ReplyText) {
            text(piece.text);
          } else {
            out.add(piece);
          }
      }
    }
    return out;
  }

  /// Ends the answer: whatever is still held is text after all.
  List<ReplyPiece> close() {
    final rest = _state == _State.heldFence ? '$_fenceHeader$_buffer' : _buffer;
    _buffer = '';
    _state = _State.text;
    return rest.isEmpty ? const [] : [ReplyText(rest)];
  }

  ReplyPiece _decide(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
    if (decoded != null && looksLikeA2ui(decoded)) {
      return ReplyUi(decoded, body.trim());
    }
    return ReplyText('$_fenceHeader$body```');
  }

  static int _trailingBackticks(String s) {
    var n = 0;
    while (n < 2 && n < s.length && s[s.length - 1 - n] == '`') {
      n++;
    }
    return n;
  }
}
