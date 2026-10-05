import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';

import 'package:moonswing/todo/todo_links.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_store.dart';

/// The board's search: what has been typed, and which cards it leaves showing.
///
/// Owned by the overlay, for its lifetime. It listens to the store as well as
/// to the query, because a card edited while the board is filtered has to join
/// or leave the filter as it changes — and it notifies only when the set of
/// matching cards actually moves, since every card on the board rebuilds when
/// it does.
class TodoBoardSearch extends ChangeNotifier {
  TodoBoardSearch(this._store) {
    _store.addListener(_refresh);
  }

  final TodoStore _store;

  String _query = '';
  List<String> _terms = const [];
  Set<String>? _matches;

  /// What was typed, verbatim.
  String get query => _query;

  /// The words the cards are matched on, for the highlight.
  List<String> get terms => _terms;

  /// Whether the board is filtered at all.
  bool get active => _terms.isNotEmpty;

  /// The ids of the cards the query matches, or null when there is no query
  /// and every card shows.
  Set<String>? get matches => _matches;

  /// Whether [id] is shown.
  bool shows(String id) => _matches?.contains(id) ?? true;

  set query(String value) {
    if (value == _query) return;
    _query = value;
    final terms = searchTerms(value);
    final termsMoved = !listEquals(terms, _terms);
    _terms = terms;
    if (!_update() && termsMoved) notifyListeners();
  }

  void clear() => query = '';

  void _refresh() {
    if (active) _update();
  }

  /// Re-runs the query; notifies, and answers true, when the matches moved.
  bool _update() {
    final Set<String>? next = _terms.isEmpty
        ? null
        : {
            for (final hit in _store.search(_query, kind: EntryKind.todo))
              hit.id,
          };
    if (setEquals(next, _matches)) return false;
    _matches = next;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _store.removeListener(_refresh);
    super.dispose();
  }
}

/// [text] as spans, with every occurrence of any of [terms] — in any case —
/// drawn in [hit]. Overlapping and touching occurrences merge into one run.
///
/// Substring matching, the same rule as the search itself (see [entryMatches]),
/// so what lights up on a card is exactly why it is showing.
///
/// Each of [links] is drawn in [link] as well, and carries the recognizer
/// [recognizerFor] answers for it, so a highlighted part of an address is
/// still part of the address and still opens it.
List<TextSpan> highlightMatches(
  String text,
  List<String> terms, {
  required TextStyle hit,
  List<TodoLink> links = const [],
  TextStyle? link,
  GestureRecognizer? Function(TodoLink link)? recognizerFor,
}) {
  final ranges = _matchRanges(text, terms);
  if (ranges.isEmpty && links.isEmpty) return [TextSpan(text: text)];
  // Every place the style can change, then one span per stretch between two.
  final cuts = <int>{0, text.length};
  for (final (start, end) in ranges) {
    cuts
      ..add(start)
      ..add(end);
  }
  for (final l in links) {
    cuts
      ..add(l.start)
      ..add(l.end);
  }
  final sorted = cuts.toList()..sort();
  final spans = <TextSpan>[];
  for (var i = 0; i + 1 < sorted.length; i++) {
    final start = sorted[i];
    final end = sorted[i + 1];
    if (start >= end) continue;
    final lit = ranges.any((r) => r.$1 <= start && end <= r.$2);
    TodoLink? inside;
    for (final l in links) {
      if (l.start <= start && end <= l.end) {
        inside = l;
        break;
      }
    }
    TextStyle? style = lit ? hit : null;
    if (inside != null && link != null) {
      style = style == null ? link : style.merge(link);
    }
    spans.add(
      TextSpan(
        text: text.substring(start, end),
        style: style,
        recognizer: inside == null ? null : recognizerFor?.call(inside),
      ),
    );
  }
  return spans;
}

/// [highlightMatches], except that a link [chipFor] answers a span for is
/// drawn as that span in place of its address.
///
/// [chipFor] is told whether any of [terms] falls inside the address, so a
/// card a search found by its link still says why it is showing once the
/// address is no longer drawn. A link it answers null for is the underlined
/// text [highlightMatches] draws.
List<InlineSpan> highlightMatchesWithChips(
  String text,
  List<String> terms, {
  required TextStyle hit,
  required InlineSpan? Function(TodoLink link, bool matched) chipFor,
  List<TodoLink> links = const [],
  TextStyle? link,
  GestureRecognizer? Function(TodoLink link)? recognizerFor,
}) {
  final ranges = _matchRanges(text, terms);
  final spans = <InlineSpan>[];
  var from = 0;
  final pending = <TodoLink>[];
  void flush(int to) {
    final base = from;
    if (to <= base) return;
    spans.addAll(
      highlightMatches(
        text.substring(base, to),
        terms,
        hit: hit,
        links: [
          for (final l in pending)
            TodoLink(l.start - base, l.end - base, l.url),
        ],
        link: link,
        recognizerFor: recognizerFor == null
            ? null
            : (shifted) => recognizerFor(
                TodoLink(shifted.start + base, shifted.end + base, shifted.url),
              ),
      ),
    );
    pending.clear();
  }

  for (final l in links) {
    final matched = ranges.any((r) => r.$1 < l.end && l.start < r.$2);
    final chip = chipFor(l, matched);
    if (chip == null) {
      pending.add(l);
      continue;
    }
    flush(l.start);
    spans.add(chip);
    from = l.end;
  }
  flush(text.length);
  return spans;
}

/// Where [terms] occur in [text], ignoring case, merged into disjoint runs in
/// order.
List<(int, int)> _matchRanges(String text, List<String> terms) {
  if (terms.isEmpty || text.isEmpty) return const [];
  final lower = text.toLowerCase();
  // Only when lower-casing kept every offset in place: a few characters (the
  // Turkish dotted İ) grow when lowered, and ranges found in the lowered copy
  // would then land on the wrong letters of the original.
  if (lower.length != text.length) return const [];
  final ranges = <(int, int)>[];
  for (final term in terms) {
    final needle = term.toLowerCase();
    if (needle.isEmpty) continue;
    var from = 0;
    while (true) {
      final at = lower.indexOf(needle, from);
      if (at < 0) break;
      ranges.add((at, at + needle.length));
      from = at + 1;
    }
  }
  if (ranges.isEmpty) return const [];
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[];
  for (final range in ranges) {
    if (merged.isNotEmpty && range.$1 <= merged.last.$2) {
      final last = merged.removeLast();
      merged.add((last.$1, range.$2 > last.$2 ? range.$2 : last.$2));
    } else {
      merged.add(range);
    }
  }
  return merged;
}
