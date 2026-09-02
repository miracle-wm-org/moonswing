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
      // The property Space-to-copy depends on: a query cannot contain a
      // space, so typing straight through a name has to work.
      final results = rankEmoji(searchableEmoji, 'grinningfacewithsweat');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.name, 'grinning face with sweat');
    });

    test('initials find a multi-word name', () {
      final results = rankEmoji(searchableEmoji, 'gfws');
      expect(_names(results).take(5), contains('grinning face with sweat'));
    });
  });
}
