import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

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
List<TextSpan> highlightMatches(
  String text,
  List<String> terms, {
  required TextStyle hit,
}) {
  if (terms.isEmpty || text.isEmpty) return [TextSpan(text: text)];
  final lower = text.toLowerCase();
  // Only when lower-casing kept every offset in place: a few characters (the
  // Turkish dotted İ) grow when lowered, and ranges found in the lowered copy
  // would then land on the wrong letters of the original.
  if (lower.length != text.length) return [TextSpan(text: text)];
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
  if (ranges.isEmpty) return [TextSpan(text: text)];
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
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final (start, end) in merged) {
    if (start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, start)));
    }
    spans.add(TextSpan(text: text.substring(start, end), style: hit));
    cursor = end;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  return spans;
}
