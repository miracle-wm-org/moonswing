// Ranking for the launcher's search field.
//
// Pure — no Flutter, no FFI — so the ordering is unit tested directly. The
// lowercasing happens once, when the index is built.

import 'package:graceful_shell/app_info.dart';

/// An [AppEntry] with its searchable text pre-folded to lower case.
class SearchableApp {
  SearchableApp(this.entry)
      : name = entry.name.toLowerCase(),
        genericName = entry.genericName.toLowerCase(),
        id = entry.id.toLowerCase(),
        keywords = [
          for (final keyword in entry.keywords) keyword.toLowerCase(),
        ];

  final AppEntry entry;
  final String name;
  final String genericName;
  final String id;
  final List<String> keywords;
}

/// How well a field matched, low is better. Also the field weights: a hit in
/// the display name always outranks the same hit in a keyword.
const int _kNoMatch = 1 << 30;

/// Score of [query] against one field, or [_kNoMatch].
int _scoreField(String field, String query) {
  if (field.isEmpty) return _kNoMatch;
  if (field == query) return 0;
  if (field.startsWith(query)) return 1;
  // A match at a word boundary ("code" in "Visual Studio Code") beats one in
  // the middle of a word ("ode" in "Inkscape Node Editor").
  if (field.contains(' $query')) return 2;
  if (field.contains(query)) return 3;
  return _kNoMatch;
}

/// Best score across an app's fields, or [_kNoMatch] when nothing matched.
int _scoreApp(SearchableApp app, String query) {
  var best = _scoreField(app.name, query);
  // Each later field is offset so it can never beat an earlier one: a
  // substring hit in the name still ranks above an exact keyword hit.
  const step = 4;
  final generic = _scoreField(app.genericName, query);
  if (generic != _kNoMatch) {
    best = best < generic + step ? best : generic + step;
  }
  for (final keyword in app.keywords) {
    final score = _scoreField(keyword, query);
    if (score != _kNoMatch && score + step * 2 < best) {
      best = score + step * 2;
    }
  }
  final id = _scoreField(app.id, query);
  if (id != _kNoMatch) {
    best = best < id + step * 3 ? best : id + step * 3;
  }
  return best;
}

/// The apps matching [query], best first.
///
/// An empty query lists everything in the index's own order (which [AppIndex]
/// keeps sorted by name), so the launcher has something to show before the user
/// types. Ties break by name, so the order never depends on how the index
/// happened to be built.
List<AppEntry> rankApps(
  List<SearchableApp> apps,
  String query, {
  int limit = 200,
}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return [for (final app in apps.take(limit)) app.entry];
  }

  final scored = <(int, SearchableApp)>[];
  for (final app in apps) {
    final score = _scoreApp(app, normalized);
    if (score != _kNoMatch) scored.add((score, app));
  }

  scored.sort((a, b) {
    final byScore = a.$1.compareTo(b.$1);
    if (byScore != 0) return byScore;
    return a.$2.name.compareTo(b.$2.name);
  });

  return [for (final (_, app) in scored.take(limit)) app.entry];
}
