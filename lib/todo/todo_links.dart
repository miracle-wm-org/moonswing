import 'package:flutter/foundation.dart';

/// A web address found in a card's title or body.
@immutable
class TodoLink {
  const TodoLink(this.start, this.end, this.url);

  /// Where it sits in the text, as a half-open range of UTF-16 offsets.
  final int start;
  final int end;

  /// What opening it opens: the text itself, with `https://` put in front of a
  /// bare `www.` address.
  final String url;

  @override
  bool operator ==(Object other) =>
      other is TodoLink &&
      other.start == start &&
      other.end == end &&
      other.url == url;

  @override
  int get hashCode => Object.hash(start, end, url);

  @override
  String toString() => 'TodoLink($start, $end, $url)';
}

/// A scheme a card may link to, or a bare `www.`; then everything up to the
/// next space or character that cannot sit in an address as typed.
final RegExp _candidate = RegExp(
  r'''(?:\b(?:https?|ftp)://|\bwww\.)[^\s<>"'`]+''',
  caseSensitive: false,
);

/// Punctuation that ends a sentence around an address far more often than it
/// ends an address.
const String _trailing = '.,;:!?*_~';

/// Every web address in [text], in order.
///
/// What is found is what a person reading the card would call a link: an
/// `http://`, `https://` or `ftp://` address, or one starting `www.`. Trailing
/// sentence punctuation is left out, and so is a closing bracket that has no
/// opening one inside the address — `(see https://example.com)` links the
/// address, not the parenthesis, while a Wikipedia page's `_(film)` keeps its
/// own. Anything that does not then parse as an absolute URL with a host is
/// dropped rather than handed to a browser.
List<TodoLink> findLinks(String text) {
  if (text.isEmpty) return const [];
  final links = <TodoLink>[];
  for (final match in _candidate.allMatches(text)) {
    final start = match.start;
    var end = match.end;
    while (end > start) {
      final last = text[end - 1];
      if (_trailing.contains(last)) {
        end--;
      } else if (_unbalancedCloser(text.substring(start, end), last)) {
        end--;
      } else {
        break;
      }
    }
    final raw = text.substring(start, end);
    final url = raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw;
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) continue;
    // A host with no dot in it is a typo or a word, not somewhere to go.
    if (!parsed.host.contains('.') && parsed.host != 'localhost') continue;
    links.add(TodoLink(start, end, url));
  }
  return links;
}

/// Whether [last], the final character of [candidate], is a closing bracket
/// with more closers than openers of its kind in [candidate].
bool _unbalancedCloser(String candidate, String last) {
  final String open;
  switch (last) {
    case ')':
      open = '(';
    case ']':
      open = '[';
    case '}':
      open = '{';
    default:
      return false;
  }
  var depth = 0;
  for (var i = 0; i < candidate.length; i++) {
    final c = candidate[i];
    if (c == open) depth++;
    if (c == last) depth--;
  }
  return depth < 0;
}
