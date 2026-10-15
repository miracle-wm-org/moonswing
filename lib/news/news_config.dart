// `[news]`, as a typed object.
//
// A section of its own rather than `[modules.news]`: nothing in a panel reads
// it. The headlines are a desktop widget's, and the settings for them sit on
// the Desktop page beside the grid they are drawn on.

import 'package:flutter/foundation.dart';

import 'package:moonswing/config_reader.dart';
import 'package:moonswing/news/news_source.dart';

class NewsConfig {
  const NewsConfig({
    this.sources = kDefaultNewsSources,
    this.refreshMinutes = defaultRefreshMinutes,
  });

  static const int defaultRefreshMinutes = 15;

  /// Bounded below because this is a timer period against somebody else's
  /// free feed — and a headline list does not move faster than this anyway.
  static const int minRefreshMinutes = 5;
  static const int maxRefreshMinutes = 1440;

  /// The `sources` entries as written, minus any that name nothing, with
  /// duplicates dropped. A preset's short name or a feed URL — see
  /// [parseNewsSource].
  ///
  /// An absent key is [kDefaultNewsSources]; an empty list is an empty list,
  /// and the card says so, because a user who switched every source off meant
  /// it.
  final List<String> sources;

  /// How often every feed is read again while a news card is on screen.
  final int refreshMinutes;

  /// [sources], resolved.
  List<NewsSource> get feeds => [
    for (final id in sources) ?parseNewsSource(id),
  ];

  factory NewsConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const NewsConfig();
    final List<String> sources;
    if (map['sources'] is List) {
      // Normalized the way `StockConfig` normalizes its symbols: a preset is
      // spelled in lower case whatever the file says, so `AP` and `ap` are one
      // entry, and an entry naming nothing costs that entry.
      final seen = <String>{};
      sources = List.unmodifiable([
        for (final raw in map.stringListOr('sources'))
          if (parseNewsSource(raw) case final source?)
            if (seen.add(source.id)) source.id,
      ]);
    } else {
      sources = kDefaultNewsSources;
    }
    return NewsConfig(
      sources: sources,
      refreshMinutes: map.intOr(
        'refresh_minutes',
        defaultRefreshMinutes,
        min: minRefreshMinutes,
        max: maxRefreshMinutes,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NewsConfig &&
          listEquals(other.sources, sources) &&
          other.refreshMinutes == refreshMinutes;

  @override
  int get hashCode => Object.hash(Object.hashAll(sources), refreshMinutes);
}
