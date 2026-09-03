// Ranking for the emoji picker's search field.
//
// Pure — no Flutter, no I/O — so the ordering is unit tested directly, the way
// `launcher/app_search.dart` is. It is that file's shape with two differences,
// and both are the point of this one:
//
//  * **Every dimension is searched**, not a preferred one with the rest as
//    tie-breakers: the name, the category, every keyword, and the character
//    itself. A person looking for 🍕 types "pizza" (name), "food" (category),
//    "italian" (keyword) or pastes the emoji back in, and only the first of
//    those four is anything the launcher's model would have found.
//  * **The match is fuzzy** — a subsequence, so "gfws" finds "grinning face
//    with sweat" and "thmbs" finds "thumbs up". That is worth more here than
//    it is over application names because an emoji's name is a *description*
//    rather than a word somebody knows: nobody types "backhand index pointing
//    right" in full, and a wall of six hundred glyphs is narrowed by typing
//    the few letters you are sure of. A query may contain spaces (Enter is
//    the copy key, not Space — see `emoji_picker_overlay.dart`), and because
//    the match is a subsequence the words in one need only appear *in order*:
//    "face joy" finds "face with tears of joy".
//
// The fuzziness is also what makes the *ordering* here differ from that file's:
// match quality dominates and the dimension is only the tie-break, where the
// launcher can weight the field first because every match it makes is literal.
// See [_kDimensions] for the query that settles it.
//
// The lowercasing happens once, when the index is built, rather than on every
// keystroke across the whole table.
library;

import 'package:graceful_shell/emoji/emoji_data.dart';

/// The strings that name each category, folded **once for the enum** rather
/// than once per emoji.
///
/// This list is nine entries long and every [SearchableEmoji] in a group
/// shares the one instance. Building it per emoji — which is what the
/// constructor below used to do — compiled [_wordSeparator] afresh for each of
/// the six hundred rows, lowercased the label twice for each, and threw away
/// six hundred copies of nine distinct lists, all inside the first frame of
/// the picker's window. Sharing is also what makes the per-query memo in
/// [rankEmoji] correct: two emoji in one group are scored against the *same*
/// terms, so the answer can be computed nine times instead of six hundred.
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
/// The category's several spellings are flattened into one list at
/// construction rather than assembled per keystroke: the scorer wants "the
/// strings that name this group" and does not care which of them was the
/// label and which an extra term. Assembling it in [scoreEmoji] instead is an
/// allocation per emoji per keystroke, which over the whole table is several
/// hundred lists thrown away for every character typed. That list comes from
/// [_categoryTerms] and is *shared* between every emoji in the group — see
/// there for why it may not be rebuilt here.
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

/// The multiplier that combines the two. Equal to the number of dimensions,
/// so every weight is strictly less than it and **the tier dominates**: an
/// exact hit in a keyword beats a fuzzy hit in the name, and the dimension
/// only ever separates two matches of the same quality.
///
/// That ordering is the one correction this makes to `app_search.dart`'s
/// model, and it is forced by the fuzziness rather than a matter of taste.
/// Weighting the dimension first — "the vaguest hit in the name outranks an
/// exact hit in a keyword", which is right when every match is a literal
/// one — answers "lol" with 😭 (`l-o…l` scattered through "loudly crying
/// face") ahead of 😂, whose keywords say `lol` outright.
const int _kDimensions = 3;

/// Score of [query] against one field, as a *tier*: a literal one, else
/// [_kFuzzy] plus the match's spread, else [kEmojiNoMatch].
///
/// Exposed for the unit tests, which pin the tier ordering directly rather
/// than inferring it from whole-table rankings. Everything ranking a whole
/// table goes through [_scoreField] instead, which takes the space-prefixed
/// query the word-start test needs as a parameter rather than building it
/// again for every field of every row.
int scoreEmojiField(String field, String query) =>
    _scoreField(field, query, ' $query');

/// [scoreEmojiField] with the word-start needle hoisted out.
///
/// `' $query'` is one allocation, and the naive spelling makes it once per
/// *field*: a row carries its name, its keywords and its category's terms, so
/// over six hundred rows that was several thousand throwaway strings for
/// every character typed.
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
/// null when [field] does not contain it as a subsequence at all.
///
/// Greedy-leftmost rather than optimal: finding the *tightest* packing is a
/// dynamic program over the whole table on every keystroke, and the leftmost
/// one already separates "thumbs up" from "trumpet sound" — the ordering this
/// number exists to make. The answer is bucketed into `0.._kFuzzySpreadMax`
/// so one extra character between hits cannot outweigh a better dimension.
///
/// It walks **code units** rather than `field.indexOf(query[i], at)`, which is
/// the same search spelled with an allocation per character per field: `[]` on
/// a `String` hands back a one-character `String`, and this is the innermost
/// loop of the one pass that runs over every field the literal tests have
/// already refused — which, for any query that narrows the grid at all, is
/// nearly all of them.
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
/// into the field should find pizza, but a query that merely happens to share
/// a code unit with one means nothing.
///
/// [categoryTier] is the answer [_bestTier] would give for this emoji's
/// [SearchableEmoji.categoryTerms], supplied by [rankEmoji], which computes it
/// once per *group* rather than once per row. Left null it is computed here,
/// which is what a lone caller wants.
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
/// An empty query answers the table in its own order, which is grouped by
/// category — so the picker has something to show before the user types, and
/// what it shows is browsable rather than arbitrary.
///
/// The **trim** is what makes a multi-word query typeable: with Space free to
/// reach the field, "face " is a state every two-word query passes through,
/// and a trailing space no field is folded with would empty the grid on the
/// keystroke between the words. Interior spaces are kept, because they are
/// the query.
///
/// **Ties break by table order**, which is the one place this departs from
/// `rankApps` — that sorts equal scores by name, on the grounds that the
/// ordering must not depend on how the index happened to be built. Here the
/// table is not "happened to be": it is written head-first by how likely a
/// row is to be the one wanted, `world_cities.dart`'s rule, and 😂 leads 😹
/// for "lol" only because of it. Sorting those two by name answers with the
/// cat. The index is carried explicitly because `List.sort` is not stable.
///
/// There is no limit: the table is a few hundred entries and the grid
/// scrolls, so cutting it off would only ever hide an answer.
///
/// **The category is scored once per group, not once per row.** Its terms are
/// shared (see [_categoryTerms]) and there are nine of them against six
/// hundred rows, so the memo in [rankEmojiFrom] is most of the work of a
/// keystroke: the category is the widest of the three dimensions, seven or
/// eight strings against a name and a handful of keywords.
///
/// This is the whole-table entry point, and it is what a caller with no
/// previous answer to narrow from wants. A picker typing a character at a
/// time goes through [rankEmojiFrom] instead, which answers the same thing
/// for a fraction of the work.
List<Emoji> rankEmoji(List<SearchableEmoji> emoji, String query) =>
    rankEmojiFrom(emoji, query).results;

/// A ranking, and the rows it came from.
///
/// The results are what the grid draws; [survivors] is what makes the *next*
/// keystroke cheap, and it is kept beside them rather than derived from them
/// because a result is an [Emoji] and the scorer wants the folded row and its
/// place in the table.
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
  /// The index travels because the sort's tie-break is on it: a candidate's
  /// place in a narrowed list is not the place the ordering means. Empty for
  /// the empty query, which narrows nothing — see [rankEmojiFrom].
  final List<(int, SearchableEmoji)> survivors;
}

/// [rankEmoji], with the previous answer available to narrow from.
///
/// **A longer query can only ever match fewer rows, and that is provable
/// rather than approximate.** [_scoreField] answers a match iff one of exact,
/// prefix, word-start, substring or subsequence holds; the first four all
/// imply the query is a *substring* of the field, and a substring is a
/// subsequence — so a field matches iff the query is a subsequence of it. A
/// prefix of a subsequence is itself a subsequence, so if `q2` matched a
/// field and `q1` is a prefix of `q2`, then `q1` matched it too. Extending a
/// query therefore cannot make a row *newly* match, and rescoring only the
/// previous survivors answers exactly what a full scan would: the scores are
/// computed fresh from the new query, so this is not an approximation and
/// `test/emoji_search_test.dart` walks the shipped table to say so.
///
/// **The character is the one branch that is not a field test**, and so the
/// one the narrowing cannot reach: `_scoreEmoji`'s `query == emoji.char`
/// makes a row match on something no prefix of it ever matched, which is a
/// real state — paste 🧑, then paste 🧑‍💻 over it. It is answered against the
/// whole table through [_charIndexOf], which is a hash lookup rather than the
/// six hundred string comparisons the scan was doing anyway.
///
/// Deleting a character is not an extension, so it falls through to a full
/// scan — which is what widening the results costs and has to.
///
/// [previous] must be an answer over this same [emoji] table: its survivors
/// are *indices* into one, so a ranking cannot be carried across a change of
/// table. The picker drops it in `didUpdateWidget` for that reason.
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
/// An [Expando] rather than a top-level map because the table is a parameter:
/// the shipped [searchableEmoji] and the small ones the widget tests inject
/// are different lists and must not share an index. Built lazily, and only on
/// the narrowing path, so a picker nobody pastes into never builds one.
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
