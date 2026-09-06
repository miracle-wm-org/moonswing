// Ranking for the emoji picker's search field.
//
// Pure — no Flutter, no I/O — so the ordering is unit tested directly, the way
// `launcher/app_search.dart` is. It is that file's shape with two differences:
//
//  * **Every dimension is searched**, not a preferred one with the rest as
//    tie-breakers: the name, the category, every keyword, and the character
//    itself. Somebody looking for 🍕 types "pizza", "food", "italian", or
//    pastes the emoji back in.
//  * **The match is fuzzy** — a subsequence, so "gfws" finds "grinning face
//    with sweat". That is worth more here than over application names because
//    an emoji's name is a *description* rather than a word somebody knows. A
//    query may contain spaces (Enter is the copy key, not Space), and because
//    the match is a subsequence the words need only appear *in order*.
//
// The fuzziness is also why the ordering differs from that file's: match
// quality dominates and the dimension is only the tie-break, where the launcher
// can weight the field first because every match it makes is literal. See
// [_kDimensions].
//
// The lowercasing happens once, when the index is built.
library;

import 'package:graceful_shell/emoji/emoji_data.dart';

/// The strings that name each category, folded **once for the enum** rather than
/// once per emoji.
///
/// Nine entries, and every [SearchableEmoji] in a group shares the one instance.
/// Building it per emoji compiled [_wordSeparator] afresh for each of six
/// hundred rows and threw away six hundred copies of nine distinct lists, all
/// inside the first frame of the picker's window. Sharing is also what makes the
/// per-query memo in [rankEmoji] correct: two emoji in one group are scored
/// against the *same* terms.
final List<List<String>> _categoryTerms = [
  for (final category in EmojiCategory.values) _termsFor(category),
];

/// Compiled once, at the top level, rather than per row inside a
/// collection-for.
final RegExp _wordSeparator = RegExp(r'[^a-z0-9]+');

List<String> _termsFor(EmojiCategory category) {
  final label = category.label.toLowerCase();
  return List<String>.unmodifiable([
    label,
    for (final t in category.terms) t.toLowerCase(),
    // The label's own words too, so "emotion" reaches the smileys through
    // the category as well as "smileys & emotion" does.
    for (final word in label.split(_wordSeparator))
      if (word.isNotEmpty && word != 'and') word,
  ]);
}

/// An [Emoji] with every searchable dimension pre-folded to lower case.
///
/// The category's several spellings are flattened into one list at construction
/// rather than per keystroke: assembling it in [scoreEmoji] is an allocation per
/// emoji per keystroke. That list comes from [_categoryTerms] and is *shared*
/// between every emoji in the group.
class SearchableEmoji {
  SearchableEmoji(this.emoji)
    : name = emoji.name.toLowerCase(),
      keywords = [for (final k in emoji.keywords) k.toLowerCase()],
      categoryTerms = _categoryTerms[emoji.category.index];

  final Emoji emoji;
  final String name;
  final List<String> keywords;

  /// Every string that names this emoji's group: the label, its extra terms,
  /// and the label's own words. Shared with every other emoji in the group.
  final List<String> categoryTerms;

  /// The group itself, which is the key [rankEmoji] memoises the category
  /// tier under.
  EmojiCategory get category => emoji.category;

  /// The character, unfolded — an emoji has no case.
  String get char => emoji.char;
}

/// Folds [kEmoji] once, lazily. A shell whose user never opens the picker
/// builds none of it — `world_cities.dart`'s trick, which is
/// `SearchableApp`'s.
final List<SearchableEmoji> searchableEmoji = [
  for (final emoji in kEmoji) SearchableEmoji(emoji),
];

/// No match. Also the ceiling every real score stays under, so a caller can
/// compare against it rather than carrying a nullable.
const int kEmojiNoMatch = 1 << 30;

/// The quality tiers a single field can match at, best first. These are what
/// [scoreEmojiField] answers: a *tier*, not a final score.
const int _kExact = 0;
const int _kPrefix = 1;
const int _kWordStart = 2;
const int _kSubstring = 3;

/// Base tier of a subsequence (fuzzy) hit. Deliberately above every literal
/// tier: "sun" appearing *in* a field always beats its letters being found
/// scattered through one, so the fuzzy pass only ever supplies rows the
/// literal passes had none of.
const int _kFuzzy = 4;

/// The most a subsequence's own spread adds on top of [_kFuzzy]. A compact
/// fuzzy hit ("thmbs" in "thumbs up") ranks above a scattered one ("thmbs" in
/// "trumpet sound about"), and the cap is what bounds a tier: every real
/// match carries one in `0 .. _kFuzzy + _kFuzzySpreadMax`.
const int _kFuzzySpreadMax = 3;

/// The dimension weights, best first: the **name**, then the **keywords**
/// (which are what the table exists for — "lol" and "shrug" are nobody's name
/// for an emoji, but they are what gets typed), then the **category**, the
/// coarsest thing anybody can ask by.
const int _kNameWeight = 0;
const int _kKeywordWeight = 1;
const int _kCategoryWeight = 2;

/// The multiplier that combines the two. Equal to the number of dimensions, so
/// every weight is strictly less than it and **the tier dominates**: an exact hit
/// in a keyword beats a fuzzy hit in the name.
///
/// That is the one correction this makes to `app_search.dart`'s model, forced by
/// the fuzziness. Weighting the dimension first — right when every match is
/// literal — answers "lol" with 😭 (`l-o…l` scattered through "loudly crying
/// face") ahead of 😂, whose keywords say `lol` outright.
const int _kDimensions = 3;

/// Score of [query] against one field, as a *tier*: a literal one, else
/// [_kFuzzy] plus the match's spread, else [kEmojiNoMatch].
///
/// Exposed for the unit tests, which pin the tier ordering directly. Everything
/// ranking a whole table goes through [_scoreField], which takes the
/// space-prefixed query as a parameter rather than rebuilding it per field.
int scoreEmojiField(String field, String query) =>
    _scoreField(field, query, ' $query');

/// [scoreEmojiField] with the word-start needle hoisted out.
///
/// `' $query'` is one allocation, and the naive spelling makes it once per
/// *field* — several thousand throwaway strings for every character typed.
int _scoreField(String field, String query, String spacedQuery) {
  if (field.isEmpty || query.isEmpty) return kEmojiNoMatch;
  if (field == query) return _kExact;
  if (field.startsWith(query)) return _kPrefix;
  // A match at a word boundary ("face" in "grinning face") beats one inside a
  // word ("ace" in "palace").
  if (field.contains(spacedQuery)) return _kWordStart;
  if (field.contains(query)) return _kSubstring;
  final spread = _subsequenceSpread(field, query);
  if (spread == null) return kEmojiNoMatch;
  return _kFuzzy + spread;
}

/// How spread out the leftmost subsequence match of [query] in [field] is, or
/// null when [field] does not contain it as a subsequence.
///
/// Greedy-leftmost rather than optimal: the tightest packing is a dynamic program
/// over the whole table on every keystroke, and the leftmost already separates
/// "thumbs up" from "trumpet sound". Bucketed into `0.._kFuzzySpreadMax` so one
/// extra character between hits cannot outweigh a better dimension.
///
/// It walks **code units** rather than `field.indexOf(query[i], at)`, which is
/// the same search with an allocation per character per field: `[]` on a `String`
/// hands back a one-character `String`, and this is the innermost loop of the one
/// pass that runs over every field the literal tests have refused.
int? _subsequenceSpread(String field, String query) {
  final fieldLength = field.length;
  final queryLength = query.length;
  if (queryLength > fieldLength) return null;
  var at = 0;
  var first = -1;
  var gaps = 0;
  for (var i = 0; i < queryLength; i++) {
    final wanted = query.codeUnitAt(i);
    var found = -1;
    for (var j = at; j < fieldLength; j++) {
      if (field.codeUnitAt(j) == wanted) {
        found = j;
        break;
      }
    }
    if (found < 0) return null;
    if (first < 0) {
      first = found;
    } else {
      gaps += found - at;
    }
    at = found + 1;
  }
  // A hit that starts at the front of the field, or at a word boundary, is
  // the one the reader would have picked out themselves.
  final anchored = first == 0 || (first > 0 && field[first - 1] == ' ');
  final looseness = gaps + (anchored ? 0 : 1);
  return looseness > _kFuzzySpreadMax ? _kFuzzySpreadMax : looseness;
}

/// One dimension's contribution: its tier scaled so the tier dominates, plus
/// the dimension's own weight as the tie-break. [kEmojiNoMatch] passes
/// through untouched, so a caller can compare the answers directly.
int _combine(int tier, int weight) =>
    tier == kEmojiNoMatch ? kEmojiNoMatch : tier * _kDimensions + weight;

/// The best score any match can carry: an exact hit in the highest-weighted
/// dimension. Nothing can beat it, so a row that reaches it stops scoring.
const int _kBestPossible = _kExact * _kDimensions + _kNameWeight;

/// Best tier for [query] across [fields], or [kEmojiNoMatch].
int _bestTier(List<String> fields, String query, String spacedQuery) {
  var best = kEmojiNoMatch;
  for (var i = 0; i < fields.length; i++) {
    final tier = _scoreField(fields[i], query, spacedQuery);
    if (tier < best) best = tier;
    if (best == _kExact) break;
  }
  return best;
}

/// Best score for [emoji] against [query], across every dimension it has.
///
/// The **character** is checked separately and only ever exactly: pasting 🍕
/// should find pizza, but a query that merely shares a code unit means nothing.
///
/// [categoryTier] is what [_bestTier] would give for this emoji's
/// [SearchableEmoji.categoryTerms], supplied by [rankEmoji], which computes it
/// once per *group*. Left null it is computed here.
int scoreEmoji(SearchableEmoji emoji, String query, {int? categoryTier}) =>
    _scoreEmoji(emoji, query, ' $query', categoryTier);

int _scoreEmoji(
  SearchableEmoji emoji,
  String query,
  String spacedQuery,
  int? categoryTier,
) {
  if (query == emoji.char) return _kBestPossible;

  var best = _combine(
    _scoreField(emoji.name, query, spacedQuery),
    _kNameWeight,
  );
  if (best == _kBestPossible) return best;

  final keyword = _combine(
    _bestTier(emoji.keywords, query, spacedQuery),
    _kKeywordWeight,
  );
  if (keyword < best) best = keyword;

  final category = _combine(
    categoryTier ?? _bestTier(emoji.categoryTerms, query, spacedQuery),
    _kCategoryWeight,
  );
  if (category < best) best = category;

  return best;
}

/// The emoji matching [query], best first.
///
/// An empty query answers the table in its own order, grouped by category, so
/// what the picker shows before the user types is browsable rather than
/// arbitrary.
///
/// The **trim** is what makes a multi-word query typeable: with Space free to
/// reach the field, "face " is a state every two-word query passes through, and a
/// trailing space no field is folded with would empty the grid between the words.
/// Interior spaces are kept, because they are the query.
///
/// **Ties break by table order**, the one place this departs from `rankApps`.
/// Here the table is written head-first by how likely a row is to be wanted
/// (`world_cities.dart`'s rule), and 😂 leads 😹 for "lol" only because of it;
/// sorting by name answers with the cat. The index is carried explicitly because
/// `List.sort` is not stable.
///
/// There is no limit: the table is a few hundred entries and the grid scrolls.
///
/// **The category is scored once per group, not once per row** — its terms are
/// shared and there are nine of them against six hundred rows, and it is the
/// widest of the three dimensions.
///
/// This is the whole-table entry point. A picker typing a character at a time
/// goes through [rankEmojiFrom] instead.
List<Emoji> rankEmoji(List<SearchableEmoji> emoji, String query) =>
    rankEmojiFrom(emoji, query).results;

/// A ranking, and the rows it came from.
///
/// The results are what the grid draws; [survivors] is what makes the *next*
/// keystroke cheap, kept beside them because a result is an [Emoji] and the
/// scorer wants the folded row and its place in the table.
class EmojiRanking {
  const EmojiRanking._(this.query, this.results, this.survivors);

  /// The **normalized** query these results answer — trimmed and folded, so
  /// it is the string [rankEmojiFrom] compares the next one against. The raw
  /// text is not it: `"face "` and `"face"` are one query, and only the
  /// folded form says so.
  final String query;

  final List<Emoji> results;

  /// Every row that matched, each with its index in the table it was ranked
  /// against.
  ///
  /// The index travels because the sort's tie-break is on it: a candidate's place
  /// in a narrowed list is not the place the ordering means. Empty for the empty
  /// query, which narrows nothing.
  final List<(int, SearchableEmoji)> survivors;
}

/// [rankEmoji], with the previous answer available to narrow from.
///
/// **A longer query can only ever match fewer rows, and that is provable rather
/// than approximate.** [_scoreField] answers a match iff one of exact, prefix,
/// word-start, substring or subsequence holds; the first four all imply the query
/// is a *substring*, and a substring is a subsequence — so a field matches iff
/// the query is a subsequence of it, and a prefix of a subsequence is itself a
/// subsequence. Extending a query therefore cannot make a row *newly* match, so
/// rescoring only the previous survivors answers exactly what a full scan would.
/// `test/emoji_search_test.dart` walks the shipped table to say so.
///
/// **The character is the one branch that is not a field test**, and so the one
/// the narrowing cannot reach: `query == emoji.char` makes a row match on
/// something no prefix of it ever matched (paste 🧑, then 🧑‍💻 over it). It is
/// answered against the whole table through [_charIndexOf], a hash lookup rather
/// than the six hundred string comparisons the scan was doing.
///
/// Deleting a character is not an extension, so it falls through to a full scan.
///
/// [previous] must be an answer over this same [emoji] table: its survivors are
/// *indices* into one. The picker drops it in `didUpdateWidget` for that reason.
EmojiRanking rankEmojiFrom(
  List<SearchableEmoji> emoji,
  String query, {
  EmojiRanking? previous,
}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    // No survivors: from the whole table there is nothing to narrow, and the
    // guard below reads the empty query as "scan".
    return EmojiRanking._('', [for (final e in emoji) e.emoji], const []);
  }

  final narrowed =
      previous != null &&
          previous.query.isNotEmpty &&
          normalized.startsWith(previous.query)
      ? previous.survivors
      : null;

  final spaced = ' $normalized';
  // -1 is "not yet scored"; every real tier, [kEmojiNoMatch] included, is
  // non-negative.
  final categoryTiers = List<int>.filled(EmojiCategory.values.length, -1);

  final scored = <(int, int, SearchableEmoji)>[];
  void consider(int index, SearchableEmoji candidate) {
    final group = candidate.category.index;
    var tier = categoryTiers[group];
    if (tier < 0) {
      tier = _bestTier(candidate.categoryTerms, normalized, spaced);
      categoryTiers[group] = tier;
    }
    final score = _scoreEmoji(candidate, normalized, spaced, tier);
    if (score != kEmojiNoMatch) scored.add((score, index, candidate));
  }

  if (narrowed == null) {
    for (var i = 0; i < emoji.length; i++) {
      consider(i, emoji[i]);
    }
  } else {
    for (final (index, candidate) in narrowed) {
      consider(index, candidate);
    }
    final pasted = _charIndexOf(emoji)[normalized];
    if (pasted != null) {
      var held = false;
      for (final (index, _) in narrowed) {
        if (index == pasted) {
          held = true;
          break;
        }
      }
      if (!held) consider(pasted, emoji[pasted]);
    }
  }

  scored.sort((a, b) {
    final byScore = a.$1.compareTo(b.$1);
    if (byScore != 0) return byScore;
    return a.$2.compareTo(b.$2);
  });

  return EmojiRanking._(
    normalized,
    <Emoji>[for (final (_, _, candidate) in scored) candidate.emoji],
    <(int, SearchableEmoji)>[
      for (final (_, index, candidate) in scored) (index, candidate),
    ],
  );
}

/// Char to table index, built once per table and cached against it.
///
/// An [Expando] rather than a top-level map because the table is a parameter: the
/// shipped [searchableEmoji] and the small ones widget tests inject must not
/// share an index. Built lazily and only on the narrowing path, so a picker
/// nobody pastes into never builds one.
final Expando<Map<String, int>> _charIndexes = Expando<Map<String, int>>(
  'emoji char index',
);

Map<String, int> _charIndexOf(List<SearchableEmoji> table) {
  final cached = _charIndexes[table];
  if (cached != null) return cached;
  final index = <String, int>{
    for (var i = 0; i < table.length; i++) table[i].char: i,
  };
  _charIndexes[table] = index;
  return index;
}
