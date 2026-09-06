// The settings search index: what a searchable field *is*, and the ranking behind
// the search bar at the top of the settings pane.
//
// Pure — no Flutter widgets, no I/O — so the ordering is a plain unit test. The
// folding to lower case happens once, when the index is built.
library;

import 'package:flutter/foundation.dart' show immutable;

import 'package:graceful_shell/overlay/settings_route.dart';

/// One searchable setting: what it is called, what it does, and where it lives.
///
/// This is the **source of truth for a row's label**, not a description of one
/// written beside it: every row carrying an [id] is built with
/// `SettingsRow.field`, which takes its label from here — so a renamed setting
/// cannot go on answering to its old name, which is the one way a hand-maintained
/// catalogue rots.
///
/// [description] and [tags] are search-only. A description is a sentence the
/// result row shows under the label, so what the index matched on is what the
/// user reads; tags are the words somebody would *type* without knowing what the
/// shell calls the field — "wallpaper" for Background, "colour" for the palette.
@immutable
class SettingsField {
  const SettingsField({
    required this.id,
    required this.label,
    required this.section,
    required this.route,
    this.description = '',
    this.tags = const <String>[],
  });

  /// Stable identity, and the address the highlight is keyed on — the config path
  /// where there is one (`modules.clock.show_date`, `theme.font_size`).
  ///
  /// Empty for a *page-level* entry: the hardware panes are lists of whatever the
  /// machine happens to have rather than tables of named fields, so a result there
  /// jumps to the pane and highlights nothing.
  final String id;

  /// The row's label, verbatim.
  final String label;

  /// Where the field lives, for the result row's second line — "Shell ›
  /// Appearance".
  final String section;

  /// Where picking the result goes.
  final SettingsRoute route;

  /// One sentence saying what the setting does.
  final String description;

  /// Words somebody might search for that are in neither the label nor the
  /// description.
  final List<String> tags;

  /// Whether a result for this field can highlight a row when it lands.
  bool get highlights => id.isNotEmpty;
}

/// A field in the Shell pane's [section] category.
///
/// [section] is a `_ShellCategory.title` — `test/settings_search_test.dart`
/// asserts every one resolves, so a category renamed in `shell.dart` cannot leave
/// a result pointing nowhere.
SettingsField shellField(
  String id,
  String label, {
  required String section,
  String description = '',
  List<String> tags = const <String>[],
}) => SettingsField(
  id: id,
  label: label,
  section: 'Shell › $section',
  route: SettingsRoute(shellCategory: section),
  description: description,
  tags: tags,
);

/// A field in the Window Manager pane's [section] category.
///
/// [shellField]'s counterpart for the compositor's own configuration. [section]
/// is a `_MiracleCategory.title` — `test/settings_search_test.dart` asserts
/// every one resolves, the same way it does for the Shell pane.
///
/// The `Window Manager ›` prefix is what a result row shows on its second line,
/// and it is what tells the two panes' near-identical rows apart: both have a
/// "Font", both have colours, and "Keyboard" is a category in each.
SettingsField miracleField(
  String id,
  String label, {
  required String section,
  String description = '',
  List<String> tags = const <String>[],
}) => SettingsField(
  id: id,
  label: label,
  section: 'Window Manager › $section',
  route: SettingsRoute(category: 'miracle', miracleCategory: section),
  description: description,
  tags: tags,
);

/// A [SettingsField] with its searchable text pre-folded to lower case.
class SearchableSetting {
  SearchableSetting(this.field)
    : label = field.label.toLowerCase(),
      description = field.description.toLowerCase(),
      section = field.section.toLowerCase(),
      tags = [for (final tag in field.tags) tag.toLowerCase()];

  final SettingsField field;
  final String label;
  final String description;
  final String section;
  final List<String> tags;

  /// Everything, joined — what the all-words pass below scans.
  late final String haystack = [label, description, section, ...tags].join(' ');
}

/// Worse than any real match. Also the field weights' ceiling.
const int _kNoMatch = 1 << 30;

/// The gap between one field's tiers and the next field's, so a substring hit
/// in the label still outranks an exact hit in a tag.
const int _kStep = 4;

/// A query whose words are all present but not as one run. Above every literal
/// tier, so this pass only ever *adds* rows — "font panel" finds nothing
/// literally and should still reach "Panel gradient" by way of its description.
const int _kScattered = _kStep * 5;

/// Score of [query] against one field, low is better, or [_kNoMatch].
int _scoreField(String field, String query) {
  if (field.isEmpty) return _kNoMatch;
  if (field == query) return 0;
  if (field.startsWith(query)) return 1;
  // A hit at a word boundary ("size" in "Font size") beats one inside a word
  // ("ize" in "Resize"). Same rule as the launcher's app ranking.
  if (field.contains(' $query')) return 2;
  if (field.contains(query)) return 3;
  return _kNoMatch;
}

int _min(int a, int b) => a < b ? a : b;

/// Best score for one setting, across its four dimensions.
int scoreSetting(SearchableSetting setting, String query) {
  var best = _scoreField(setting.label, query);

  final description = _scoreField(setting.description, query);
  if (description != _kNoMatch) best = _min(best, description + _kStep);

  for (final tag in setting.tags) {
    final score = _scoreField(tag, query);
    if (score != _kNoMatch) best = _min(best, score + _kStep * 2);
  }

  final section = _scoreField(setting.section, query);
  if (section != _kNoMatch) best = _min(best, section + _kStep * 3);

  if (best != _kNoMatch) return best;

  // Nothing matched the query as one run. Every word of it appearing
  // *somewhere* is still a match — a user typing "clock date" is describing a
  // row whose label is "Show date" under a group called "Clock".
  final words = query.split(RegExp(r'\s+'))..removeWhere((w) => w.isEmpty);
  if (words.length < 2) return _kNoMatch;
  for (final word in words) {
    if (!setting.haystack.contains(word)) return _kNoMatch;
  }
  return _kScattered;
}

/// The settings matching [query], best first.
///
/// An empty query answers **nothing** rather than everything: the results card
/// floats over the pane the user is reading, so an unasked-for list of two
/// hundred rows would cover the page on the first click into the field.
List<SettingsField> rankSettings(
  List<SearchableSetting> settings,
  String query, {
  int limit = 30,
}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return const <SettingsField>[];

  final scored = <(int, SearchableSetting)>[];
  for (final setting in settings) {
    final score = scoreSetting(setting, normalized);
    if (score != _kNoMatch) scored.add((score, setting));
  }

  // Ties break by label and then by section, so the order never depends on how
  // the catalogue happened to be concatenated — several modules have an "Icon
  // size" and the shell must list them the same way every time.
  scored.sort((a, b) {
    final byScore = a.$1.compareTo(b.$1);
    if (byScore != 0) return byScore;
    final byLabel = a.$2.label.compareTo(b.$2.label);
    if (byLabel != 0) return byLabel;
    return a.$2.section.compareTo(b.$2.section);
  });

  return [for (final (_, setting) in scored.take(limit)) setting.field];
}
