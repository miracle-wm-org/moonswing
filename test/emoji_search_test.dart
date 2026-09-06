import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/emoji/emoji_data.dart';
import 'package:graceful_shell/emoji/emoji_search.dart';

Emoji _e(
  String char,
  String name, {
  EmojiCategory category = EmojiCategory.objects,
  List<String> keywords = const [],
}) => Emoji(char, name, category, keywords);

List<SearchableEmoji> _fold(List<Emoji> emoji) => [
  for (final e in emoji) SearchableEmoji(e),
];

List<String> _names(List<Emoji> results) => [for (final e in results) e.name];

void main() {
  group('scoreEmojiField', () {
    test('exact beats prefix beats word-start beats substring beats fuzzy', () {
      final exact = scoreEmojiField('cat', 'cat');
      final prefix = scoreEmojiField('catalogue', 'cat');
      final wordStart = scoreEmojiField('black cat', 'cat');
      final substring = scoreEmojiField('scatter', 'cat');
      final fuzzy = scoreEmojiField('cart', 'cat');

      expect(exact, lessThan(prefix));
      expect(prefix, lessThan(wordStart));
      expect(wordStart, lessThan(substring));
      expect(substring, lessThan(fuzzy));
      expect(fuzzy, lessThan(kEmojiNoMatch));
    });

    test('letters out of order are not a match', () {
      expect(scoreEmojiField('cat', 'tac'), kEmojiNoMatch);
    });

    test('a letter the field lacks is not a match', () {
      expect(scoreEmojiField('cat', 'cats'), kEmojiNoMatch);
    });

    test('an empty field or query never matches', () {
      expect(scoreEmojiField('', 'cat'), kEmojiNoMatch);
      expect(scoreEmojiField('cat', ''), kEmojiNoMatch);
    });

    test('a compact subsequence beats a scattered one', () {
      expect(
        scoreEmojiField('thumbs up', 'thmbs'),
        lessThan(scoreEmojiField('trumpet sound about', 'thmbs')),
      );
    });
  });

  group('rankEmoji dimensions', () {
    test('an empty query lists the table in its own order', () {
      final table = _fold([_e('b', 'beta'), _e('a', 'alpha')]);
      expect(_names(rankEmoji(table, '')), ['beta', 'alpha']);
      expect(_names(rankEmoji(table, '   ')), ['beta', 'alpha']);
    });

    test('the name is searched', () {
      final table = _fold([_e('🍕', 'pizza'), _e('🥗', 'green salad')]);
      expect(_names(rankEmoji(table, 'pizza')), ['pizza']);
    });

    test('keywords are searched', () {
      final table = _fold([
        _e('🍕', 'pizza', keywords: ['italian', 'slice']),
        _e('🥗', 'green salad', keywords: ['healthy']),
      ]);
      expect(_names(rankEmoji(table, 'italian')), ['pizza']);
    });

    test('the category is searched, by label and by its extra terms', () {
      final table = _fold([
        _e('🍕', 'pizza', category: EmojiCategory.food),
        _e('🔧', 'wrench', category: EmojiCategory.objects),
      ]);
      // "food" is in the label; "eat" is only in the category's terms.
      expect(_names(rankEmoji(table, 'food')), ['pizza']);
      expect(_names(rankEmoji(table, 'eat')), ['pizza']);
    });

    test('the character itself is searched, and only exactly', () {
      final table = _fold([_e('🍕', 'pizza'), _e('🥗', 'green salad')]);
      expect(_names(rankEmoji(table, '🍕')), ['pizza']);
    });

    test('the name outranks a keyword, which outranks the category', () {
      final table = _fold([
        _e('c', 'a cool category', category: EmojiCategory.food),
        _e('b', 'by keyword', keywords: ['pizza']),
        _e('a', 'pizza'),
        // Reachable only through its category's label.
        _e('d', 'unrelated', category: EmojiCategory.food),
      ]);
      // Every one of the four matches "pizza" or "food"; only the ordering of
      // the first three is under test here.
      expect(_names(rankEmoji(table, 'pizza')), ['pizza', 'by keyword']);
    });

    test('a literal hit always beats a fuzzy one in a better dimension', () {
      final table = _fold([
        // Fuzzy in the name: c-a-t scattered through "chart increasing".
        _e('📈', 'chart increasing'),
        // Substring in the name.
        _e('🐱', 'cat face'),
      ]);
      expect(_names(rankEmoji(table, 'cat')).first, 'cat face');
    });

    test('ties break by table order, which is written by likelihood', () {
      final table = _fold([_e('b', 'zebra face'), _e('a', 'ant face')]);
      expect(_names(rankEmoji(table, 'face')), ['zebra face', 'ant face']);
    });

    test('an exact keyword hit beats a fuzzy hit in the name', () {
      final table = _fold([
        // "l-o…l" is a subsequence of "loudly crying face".
        _e('😭', 'loudly crying face', keywords: ['sob']),
        _e('😂', 'face with tears of joy', keywords: ['lol']),
      ]);
      expect(_names(rankEmoji(table, 'lol')).first, 'face with tears of joy');
    });

    test('nothing matching answers an empty list', () {
      final table = _fold([_e('🍕', 'pizza')]);
      expect(rankEmoji(table, 'qqqq'), isEmpty);
    });
  });

  group('the shipped table', () {
    test('every entry has a character, a name and a keyword', () {
      for (final emoji in kEmoji) {
        expect(emoji.char, isNotEmpty, reason: emoji.name);
        expect(emoji.name, isNotEmpty, reason: emoji.char);
        expect(emoji.keywords, isNotEmpty, reason: emoji.name);
        for (final keyword in emoji.keywords) {
          expect(keyword, isNotEmpty, reason: emoji.name);
          expect(keyword, keyword.toLowerCase(), reason: emoji.name);
        }
      }
    });

    test('no character is listed twice', () {
      final seen = <String>{};
      for (final emoji in kEmoji) {
        expect(seen.add(emoji.char), isTrue, reason: '${emoji.name} repeats');
      }
    });

    test('every category is represented', () {
      final present = {for (final emoji in kEmoji) emoji.category};
      expect(present, containsAll(EmojiCategory.values));
    });

    test('the words a person actually types find something', () {
      // A spot check that the *keyword* dimension is carrying its weight:
      // none of these is the leading emoji's name.
      const wanted = {
        'lol': '😂',
        'shrug': '🤷',
        'thanks': '🙏',
        'party': '🥳',
        'lgtm': '👍',
        'idea': '💡',
        'settings': '⚙️',
        'linux': '🐧',
        'ship it': '🚀',
        'wfh': '🧑‍💻',
      };
      wanted.forEach((query, char) {
        final results = rankEmoji(searchableEmoji, query);
        expect(
          results.isNotEmpty ? results.first.char : '',
          char,
          reason: '"$query" should lead with $char',
        );
      });
    });

    test('a multi-word name is reachable without typing its spaces', () {
      final results = rankEmoji(searchableEmoji, 'grinningfacewithsweat');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.name, 'grinning face with sweat');
    });

    test('a multi-word query matches its words in order', () {
      // Enter is the copy key, so Space reaches the field and a query may
      // carry one; the subsequence match is what lets the words be a long way
      // apart in the name.
      final results = rankEmoji(searchableEmoji, 'face joy');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.name, 'face with tears of joy');
    });

    test('a trailing space does not empty the results', () {
      // Every two-word query passes through this state and no field is folded
      // with a trailing space, so without the trim the grid would empty on
      // the keystroke between the words.
      expect(
        rankEmoji(searchableEmoji, 'face ').first.name,
        rankEmoji(searchableEmoji, 'face').first.name,
      );
    });

    test('initials find a multi-word name', () {
      final results = rankEmoji(searchableEmoji, 'gfws');
      expect(_names(results).take(5), contains('grinning face with sweat'));
    });
  });

  group('the folded index', () {
    test('every emoji in a group shares one category term list', () {
      // [rankEmoji] scores the category **once per group** rather than once per
      // row, which is most of the work of a keystroke — and it is only correct
      // because the terms are the one shared list. Folding them per emoji would
      // also make that memo a lie.
      final seen = <EmojiCategory, List<String>>{};
      for (final emoji in searchableEmoji) {
        final terms = seen[emoji.category];
        if (terms == null) {
          seen[emoji.category] = emoji.categoryTerms;
          continue;
        }
        expect(
          identical(emoji.categoryTerms, terms),
          isTrue,
          reason:
              'the category tier is memoised per group, so every emoji in '
              'one must be scored against the same terms',
        );
      }
      expect(seen.length, EmojiCategory.values.length);
    });

    test('the shared terms are not writable through one emoji', () {
      expect(
        () => searchableEmoji.first.categoryTerms.add('mine'),
        throwsUnsupportedError,
      );
    });
  });

  group('narrowing', () {
    // A longer query can only ever match fewer rows: a field matches iff the query
    // is a subsequence of it (every literal tier implies a substring, and a
    // substring is a subsequence), and a prefix of a subsequence is a subsequence.
    // So rescoring only the previous survivors must answer *exactly* what a full
    // scan answers — not nearly. These walk the shipped table to say so.

    List<String> chars(List<Emoji> results) => [
      for (final e in results) e.char,
    ];

    test('typing a query one character at a time answers a full scan', () {
      const queries = [
        'smile',
        'face',
        'lol',
        'heart',
        'thumbs up',
        'face joy',
        'gfws',
        'food',
        'zzzz',
        'a',
        'party',
        'ship it',
        'linux',
        'settings',
        'wfh',
      ];
      for (final query in queries) {
        EmojiRanking? previous;
        for (var i = 1; i <= query.length; i++) {
          final typed = query.substring(0, i);
          previous = rankEmojiFrom(
            searchableEmoji,
            typed,
            previous: previous,
          );
          expect(
            chars(previous.results),
            chars(rankEmoji(searchableEmoji, typed)),
            reason: 'narrowing to "$typed" must answer what a scan answers',
          );
        }
      }
    });

    test('deleting a character widens again', () {
      // Not an extension, so it falls through to a full scan — which is what
      // widening has to cost. The bug this pins is a narrowing that kept the
      // old survivors and so could never grow the list back.
      var ranking = rankEmojiFrom(searchableEmoji, 'smile');
      ranking = rankEmojiFrom(searchableEmoji, 'smil', previous: ranking);
      expect(
        ranking.results.length,
        rankEmoji(searchableEmoji, 'smil').length,
      );
      expect(
        ranking.results.length,
        greaterThan(rankEmoji(searchableEmoji, 'smile').length),
      );
    });

    test('a pasted character is found even though no prefix of it was', () {
      // The one branch of the scorer that is not a field test, and so the one
      // the narrowing cannot reach on its own: 🧑 matched rows that 🧑‍💻 does
      // not, and 🧑‍💻 is not among them.
      final person = rankEmojiFrom(searchableEmoji, '🧑');
      final worker = rankEmojiFrom(
        searchableEmoji,
        '🧑‍💻',
        previous: person,
      );
      expect(worker.results.first.char, '🧑‍💻');
      expect(chars(worker.results), chars(rankEmoji(searchableEmoji, '🧑‍💻')));
    });

    test('a trailing space is not a new query', () {
      // "face " is a state every two-word query passes through, and the
      // comparison is between *normalized* queries — so this narrows rather
      // than rescans, and either way answers the same thing.
      final typed = rankEmojiFrom(searchableEmoji, 'face');
      final spaced = rankEmojiFrom(searchableEmoji, 'face ', previous: typed);
      expect(chars(spaced.results), chars(typed.results));
    });

    test('survivors carry their place in the table, not in the results', () {
      // The sort's tie-break is the table index; a candidate's place in a narrowed
      // list is not the place the ordering means. If the index were re-derived
      // from the narrowed list, ties would reorder on the second keystroke.
      final ranking = rankEmojiFrom(searchableEmoji, 'fa');
      for (final (index, candidate) in ranking.survivors) {
        expect(identical(searchableEmoji[index], candidate), isTrue);
      }
    });
  });
}
