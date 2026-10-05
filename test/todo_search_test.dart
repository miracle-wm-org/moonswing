import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/todo/todo_links.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_search.dart';
import 'package:moonswing/todo/todo_store.dart';

const TextStyle _hit = TextStyle(fontWeight: FontWeight.bold);

List<(String, bool)> _runs(List<TextSpan> spans) => [
  for (final span in spans) (span.text!, span.style == _hit),
];

TodoItem _item(String id, String title) => TodoItem(
  id: id,
  title: title,
  body: '',
  column: TodoColumn.inbox,
  created: DateTime(2026, 9, 20),
);

void main() {
  group('highlightMatchesWithChips', () {
    const chip = TextSpan(text: '[chip]');
    const text =
        'See https://github.com/o/r/pull/1 and https://example.com now';

    test('draws a chosen link as its chip and the rest as text', () {
      final links = findLinks(text);
      final told = <(String, bool)>[];
      final recognizer = TapGestureRecognizer();
      addTearDown(recognizer.dispose);
      final seen = <TodoLink>[];
      final spans = highlightMatchesWithChips(
        text,
        ['exam', 'pull'],
        hit: _hit,
        links: links,
        link: const TextStyle(decoration: TextDecoration.underline),
        recognizerFor: (link) {
          seen.add(link);
          return recognizer;
        },
        chipFor: (link, matched) {
          told.add((link.url, matched));
          return link.url.contains('github') ? chip : null;
        },
      );
      expect(told, [
        ('https://github.com/o/r/pull/1', true),
        ('https://example.com', true),
      ]);
      expect(spans.first, isA<TextSpan>());
      expect((spans.first as TextSpan).text, 'See ');
      expect(spans[1], same(chip));
      expect(
        [
          for (final s in spans.skip(2))
            (
              (s as TextSpan).text,
              s.style?.fontWeight == FontWeight.bold,
              s.recognizer != null,
            ),
        ],
        [
          (' and ', false, false),
          ('https://', false, true),
          ('exam', true, true),
          ('ple.com', false, true),
          (' now', false, false),
        ],
      );
      // The text link's recognizer is asked for with its place in the whole
      // text, not in the stretch after the chip.
      expect(seen.toSet(), {links.last});
    });

    test('says a link was not matched when no term falls inside it', () {
      final told = <bool>[];
      highlightMatchesWithChips(
        text,
        ['see'],
        hit: _hit,
        links: findLinks(text),
        chipFor: (link, matched) {
          told.add(matched);
          return chip;
        },
      );
      expect(told, [false, false]);
    });
  });

  group('highlightMatches', () {
    test('marks every occurrence, in any case', () {
      expect(_runs(highlightMatches('Bug in bugfix', ['BUG'], hit: _hit)), [
        ('Bug', true),
        (' in ', false),
        ('bug', true),
        ('fix', false),
      ]);
    });

    test('merges overlapping and touching terms into one run', () {
      expect(
        _runs(
          highlightMatches('bluetooth', ['blue', 'uet', 'tooth'], hit: _hit),
        ),
        [('bluetooth', true)],
      );
    });

    test('with nothing to mark, is the text alone', () {
      expect(_runs(highlightMatches('plain', const [], hit: _hit)), [
        ('plain', false),
      ]);
      expect(_runs(highlightMatches('plain', ['zzz'], hit: _hit)), [
        ('plain', false),
      ]);
    });

    test('draws a link, highlighted or not, with its recognizer', () {
      const link = TextStyle(decoration: TextDecoration.underline);
      final recognizer = TapGestureRecognizer();
      addTearDown(recognizer.dispose);
      const text = 'Open https://example.com today';
      final spans = highlightMatches(
        text,
        ['example'],
        hit: _hit,
        links: findLinks(text),
        link: link,
        recognizerFor: (_) => recognizer,
      );
      expect(
        [
          for (final span in spans)
            (
              span.text,
              span.style?.fontWeight == FontWeight.bold,
              span.style?.decoration == TextDecoration.underline,
              span.recognizer != null,
            ),
        ],
        [
          ('Open ', false, false, false),
          ('https://', false, true, true),
          ('example', true, true, true),
          ('.com', false, true, true),
          (' today', false, false, false),
        ],
      );
    });
  });

  group('TodoBoardSearch', () {
    late TodoStore store;
    late TodoBoardSearch search;
    late int notified;

    setUp(() {
      store = TodoStore.forTesting(
        items: [_item('a', 'Dentist'), _item('b', 'Groceries')],
        inMemory: true,
      );
      search = TodoBoardSearch(store);
      notified = 0;
      search.addListener(() => notified++);
    });

    tearDown(() {
      search.dispose();
      store.dispose();
    });

    test('no query shows every card', () {
      expect(search.active, isFalse);
      expect(search.matches, isNull);
      expect(search.shows('a'), isTrue);
    });

    test('a query narrows the board, and clearing it restores it', () {
      search.query = 'dent';
      expect(search.matches, {'a'});
      expect(search.shows('b'), isFalse);
      search.clear();
      expect(search.matches, isNull);
      expect(search.shows('b'), isTrue);
    });

    test('notifies when the matches or the highlight move, and only then', () {
      search.query = 'dent';
      expect(notified, 1);
      // Same match, different highlight.
      search.query = 'denti';
      expect(notified, 2);
      // Trailing space: same terms, same matches.
      search.query = 'denti ';
      expect(notified, 2);
      // An unrelated edit to the board leaves the matches where they were.
      store.update(
        'b',
        title: 'Groceries and more',
        body: '',
        column: TodoColumn.inbox,
        due: null,
        recurrence: null,
      );
      expect(notified, 2);
    });

    test('follows an edit that changes what matches', () {
      search.query = 'milk';
      expect(search.matches, isEmpty);
      store.update(
        'b',
        title: 'Groceries',
        body: 'milk',
        column: TodoColumn.inbox,
        due: null,
        recurrence: null,
      );
      expect(search.matches, {'b'});
    });
  });
}
