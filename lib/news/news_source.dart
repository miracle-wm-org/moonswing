// Where the headlines come from: the shipped presets, and how a `[news]
// sources` entry names one.
//
// Flutter-free and pure — no I/O — so `test/news_config_test.dart` can pin
// every preset's URL and the rule that turns a config string into a feed.

/// One feed the store reads.
class NewsSource {
  const NewsSource({
    required this.id,
    required this.name,
    required this.url,
    this.preset = false,
  });

  /// What `[news] sources` spells it as: a preset's short name, or the feed's
  /// own URL for anything else.
  final String id;

  /// What the card writes beside each of its headlines. For a URL the user
  /// added it is the host until the feed says what it calls itself.
  final String name;

  /// The RSS or Atom document.
  final Uri url;

  /// Whether this is one of [kNewsPresets]. A preset's [name] is the label,
  /// whatever its feed calls itself — two of them are Google News searches,
  /// whose channel title is the query.
  final bool preset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NewsSource &&
          other.id == id &&
          other.name == name &&
          other.url == url &&
          other.preset == preset;

  @override
  int get hashCode => Object.hash(id, name, url, preset);

  @override
  String toString() => 'NewsSource($id)';
}

/// The last day of one site's stories, as Google News indexes them.
///
/// The Associated Press and Reuters — the two wire services the rest of the
/// press reprints, and the two most often named when somebody asks for news
/// told straight — both stopped publishing RSS of their own (Reuters in 2020,
/// AP never had a supported one). Google News still answers a `site:` search
/// as a feed, item by item with the outlet named in `<source>`, so that is how
/// they are read. The links go through Google's redirect, which a browser
/// follows to the story.
Uri _googleNewsSite(String site) => Uri.https(
  'news.google.com',
  '/rss/search',
  {'q': 'site:$site when:1d', 'hl': 'en-US', 'gl': 'US', 'ceid': 'US:en'},
);

/// The feeds a config can name by a short id, in the order Settings offers
/// them.
///
/// Wire services and public broadcasters: the outlets whose house style is
/// the plain account, and whose headlines read as a list of what happened
/// rather than a list of arguments about it.
final List<NewsSource> kNewsPresets = List.unmodifiable([
  NewsSource(
    id: 'ap',
    name: 'AP',
    url: _googleNewsSite('apnews.com'),
    preset: true,
  ),
  NewsSource(
    id: 'reuters',
    name: 'Reuters',
    url: _googleNewsSite('reuters.com'),
    preset: true,
  ),
  NewsSource(
    id: 'npr',
    name: 'NPR',
    url: Uri.parse('https://feeds.npr.org/1001/rss.xml'),
    preset: true,
  ),
  NewsSource(
    id: 'bbc',
    name: 'BBC',
    url: Uri.parse('https://feeds.bbci.co.uk/news/world/rss.xml'),
    preset: true,
  ),
  NewsSource(
    id: 'pbs',
    name: 'PBS NewsHour',
    url: Uri.parse('https://www.pbs.org/newshour/feeds/rss/headlines'),
    preset: true,
  ),
]);

/// What a config with no `sources` key reads: the two wire services.
const List<String> kDefaultNewsSources = ['ap', 'reuters'];

/// The preset called [id], ignoring case, or null.
NewsSource? newsPreset(String id) {
  final key = id.trim().toLowerCase();
  for (final preset in kNewsPresets) {
    if (preset.id == key) return preset;
  }
  return null;
}

/// The source a `[news] sources` entry names, or null when it names nothing:
/// not a preset, and not an absolute `http`/`https` URL.
///
/// A bare word that is not a preset is dropped rather than guessed at — `ap`
/// misspelled as `apn` is not a host.
NewsSource? parseNewsSource(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final preset = newsPreset(text);
  if (preset != null) return preset;
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !uri.isAbsolute ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  return NewsSource(id: text, name: newsHostLabel(uri), url: uri);
}

/// [uri]'s host without a leading `www.` or `feeds.` — what a feed with no
/// title of its own is called.
String newsHostLabel(Uri uri) {
  var host = uri.host.toLowerCase();
  for (final prefix in const ['www.', 'feeds.', 'rss.']) {
    if (host.startsWith(prefix) && host.length > prefix.length) {
      host = host.substring(prefix.length);
      break;
    }
  }
  return host;
}
