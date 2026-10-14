// A feed document into headlines: RSS 2.0, RSS 1.0 (RDF) and Atom.
//
// Pure and Flutter-free. Every element is matched by its *local* name, so a
// feed that puts its items in a namespace (RSS 1.0 does, by definition) or
// prefixes Atom reads the same as one that does not.
//
// Degrades per item, the way `TomlReader` degrades per key: an item with no
// title or no usable link costs that item, an unparseable date costs the
// date, and only a document that is not XML at all — or is XML but no feed —
// costs the source.

import 'package:xml/xml.dart';

/// One story.
class NewsHeadline {
  const NewsHeadline({
    required this.title,
    required this.link,
    required this.source,
    this.published,
  });

  final String title;

  /// The story's page — absolute `http` or `https`, or the item was dropped.
  final String link;

  /// The outlet, as the card names it.
  final String source;

  /// When the feed says the story went up, in UTC. Null when it did not say,
  /// or said it in a form nothing here reads.
  final DateTime? published;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NewsHeadline &&
          other.title == title &&
          other.link == link &&
          other.source == source &&
          other.published == published;

  @override
  int get hashCode => Object.hash(title, link, source, published);

  @override
  String toString() => 'NewsHeadline($source: $title)';
}

/// The document was not a feed.
class NewsFeedFormatException implements Exception {
  const NewsFeedFormatException(this.message);

  final String message;

  @override
  String toString() => 'NewsFeedFormatException: $message';
}

/// What [parseNewsFeed] read: the feed's own title, and its items in document
/// order.
class NewsFeed {
  const NewsFeed({required this.title, required this.headlines});

  final String title;
  final List<NewsHeadline> headlines;
}

/// Parses [document].
///
/// [sourceName] labels each headline. With [preferItemSource] — a URL the
/// user added, rather than a preset with a name of its own — an item's
/// `<source>` and then the channel's title win over it, because they are the
/// better name for a feed this side only knows the host of.
///
/// Throws [NewsFeedFormatException] when [document] is not a feed.
NewsFeed parseNewsFeed(
  String document, {
  required String sourceName,
  bool preferItemSource = false,
}) {
  final XmlDocument xml;
  try {
    xml = XmlDocument.parse(document);
  } on XmlException catch (e) {
    throw NewsFeedFormatException('not XML: ${e.message}');
  }
  final root = xml.rootElement;
  final rootName = root.name.local;
  final List<XmlElement> items;
  final String channelTitle;
  final bool atom;
  if (rootName == 'feed') {
    atom = true;
    channelTitle = _text(_child(root, 'title'));
    items = _children(root, 'entry').toList();
  } else if (rootName == 'rss' || rootName == 'RDF') {
    atom = false;
    final channel = _child(root, 'channel');
    channelTitle = _text(channel == null ? null : _child(channel, 'title'));
    // RSS 2.0 nests items in the channel; RSS 1.0 makes them its siblings.
    items = [
      if (channel != null) ..._children(channel, 'item'),
      ..._children(root, 'item'),
    ];
  } else {
    throw NewsFeedFormatException('a <$rootName> document is not a feed');
  }

  final headlines = <NewsHeadline>[];
  for (final item in items) {
    final headline = atom
        ? _atomEntry(
            item,
            sourceName: sourceName,
            channelTitle: channelTitle,
            preferItemSource: preferItemSource,
          )
        : _rssItem(
            item,
            sourceName: sourceName,
            channelTitle: channelTitle,
            preferItemSource: preferItemSource,
          );
    if (headline != null) headlines.add(headline);
  }
  return NewsFeed(title: channelTitle, headlines: headlines);
}

NewsHeadline? _rssItem(
  XmlElement item, {
  required String sourceName,
  required String channelTitle,
  required bool preferItemSource,
}) {
  final itemSource = _text(_child(item, 'source'));
  var title = _text(_child(item, 'title'));
  // Google News writes the outlet into the title as well as into `<source>`:
  // "Headline - Reuters". The card already says who it is from.
  if (itemSource.isNotEmpty && title.endsWith(' - $itemSource')) {
    title = title.substring(0, title.length - itemSource.length - 3).trim();
  }
  var link = _absoluteLink(_text(_child(item, 'link')));
  // A `<guid>` that is a permalink is the link, for a feed that left `<link>`
  // out — permitted by RSS 2.0, and done.
  if (link == null) {
    final guid = _child(item, 'guid');
    if (guid != null && guid.getAttribute('isPermaLink') != 'false') {
      link = _absoluteLink(_text(guid));
    }
  }
  if (title.isEmpty || link == null) return null;
  final date = _text(
    _child(item, 'pubDate'),
  ).ifEmpty(() => _text(_child(item, 'date')));
  return NewsHeadline(
    title: title,
    link: link,
    source: _label(
      sourceName: sourceName,
      itemSource: itemSource,
      channelTitle: channelTitle,
      preferItemSource: preferItemSource,
    ),
    published: parseNewsDate(date),
  );
}

NewsHeadline? _atomEntry(
  XmlElement entry, {
  required String sourceName,
  required String channelTitle,
  required bool preferItemSource,
}) {
  final title = _text(_child(entry, 'title'));
  // The `alternate` link is the story; a bare `<link href>` is `alternate` by
  // the spec's default. `self`, `edit`, `enclosure` and the rest are not.
  String? link;
  for (final candidate in _children(entry, 'link')) {
    final rel = candidate.getAttribute('rel') ?? 'alternate';
    if (rel != 'alternate') continue;
    link = _absoluteLink(candidate.getAttribute('href') ?? '');
    if (link != null) break;
  }
  if (title.isEmpty || link == null) return null;
  final sourceElement = _child(entry, 'source');
  final itemSource = sourceElement == null
      ? ''
      : _text(_child(sourceElement, 'title'));
  final date = _text(
    _child(entry, 'published'),
  ).ifEmpty(() => _text(_child(entry, 'updated')));
  return NewsHeadline(
    title: title,
    link: link,
    source: _label(
      sourceName: sourceName,
      itemSource: itemSource,
      channelTitle: channelTitle,
      preferItemSource: preferItemSource,
    ),
    published: parseNewsDate(date),
  );
}

String _label({
  required String sourceName,
  required String itemSource,
  required String channelTitle,
  required bool preferItemSource,
}) {
  if (!preferItemSource) return sourceName;
  if (itemSource.isNotEmpty) return itemSource;
  if (channelTitle.isNotEmpty) return channelTitle;
  return sourceName;
}

XmlElement? _child(XmlElement parent, String local) {
  for (final child in parent.childElements) {
    if (child.name.local == local) return child;
  }
  return null;
}

Iterable<XmlElement> _children(XmlElement parent, String local) =>
    parent.childElements.where((child) => child.name.local == local);

/// An element's text, as a line a person reads: HTML stripped, entities a
/// feed escaped twice decoded, whitespace collapsed.
String _text(XmlElement? element) {
  if (element == null) return '';
  return cleanNewsText(element.innerText);
}

/// [raw] as a single line of plain text.
///
/// A feed's title is supposed to be plain text and frequently is not: an
/// `&amp;#8217;` decodes once in the XML parser and arrives here as
/// `&#8217;`, and some feeds put markup inside CDATA.
String cleanNewsText(String raw) {
  var text = raw;
  if (text.contains('<')) text = text.replaceAll(_tag, ' ');
  if (text.contains('&')) text = _decodeEntities(text);
  return text.replaceAll(_whitespace, ' ').trim();
}

final RegExp _tag = RegExp(r'<[^>]*>');
final RegExp _whitespace = RegExp(r'\s+');
final RegExp _entity = RegExp(r'&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);');

const Map<String, String> _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
  'ndash': '–',
  'mdash': '—',
  'hellip': '…',
};

String _decodeEntities(String text) => text.replaceAllMapped(_entity, (match) {
  final body = match.group(1)!;
  if (body.startsWith('#')) {
    final hex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
    final code = int.tryParse(
      hex ? body.substring(2) : body.substring(1),
      radix: hex ? 16 : 10,
    );
    // A code point outside Unicode, or a lone surrogate, is left as
    // written rather than thrown on.
    if (code == null ||
        code <= 0 ||
        code > 0x10FFFF ||
        (code >= 0xD800 && code <= 0xDFFF)) {
      return match.group(0)!;
    }
    return String.fromCharCode(code);
  }
  return _namedEntities[body] ?? match.group(0)!;
});

/// [raw] when it is an absolute `http`/`https` URL — the only thing the card
/// hands a browser — otherwise null.
String? _absoluteLink(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !uri.isAbsolute ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  return text;
}

/// A feed's date, in UTC: RFC 822 as RSS writes it (`Tue, 14 Oct 2026
/// 13:05:00 GMT`, with a numeric or a North American zone), or ISO 8601 as
/// Atom and Dublin Core do. Null for anything else.
DateTime? parseNewsDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final match = _rfc822.firstMatch(text);
  if (match == null) {
    // ISO 8601. A date with no zone is read as UTC rather than as local time:
    // it came from a server, and the server's local time is not this one's.
    final iso = DateTime.tryParse(text);
    if (iso == null) return null;
    return iso.isUtc
        ? iso
        : DateTime.utc(
            iso.year,
            iso.month,
            iso.day,
            iso.hour,
            iso.minute,
            iso.second,
          );
  }
  final day = int.parse(match.group(1)!);
  final month = _months[match.group(2)!.toLowerCase()];
  var year = int.parse(match.group(3)!);
  if (month == null) return null;
  if (match.group(3)!.length == 2) year += year < 50 ? 2000 : 1900;
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.tryParse(match.group(6) ?? '') ?? 0;
  if (day < 1 || day > 31 || hour > 23 || minute > 59 || second > 60) {
    return null;
  }
  final offset = _zoneOffset(match.group(7) ?? '');
  return DateTime.utc(year, month, day, hour, minute, second).subtract(offset);
}

final RegExp _rfc822 = RegExp(
  r'^(?:[A-Za-z]{3,},?\s*)?(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\.?\s+(\d{2}|\d{4})'
  r'\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([A-Za-z]+|[+-]\d{4}|[+-]\d{2}:\d{2})?\s*$',
);

const Map<String, int> _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// The zones RFC 822 names, in hours east of UTC. An unknown name is read as
/// UTC: an hour or so out on one story beats dropping its date.
const Map<String, int> _zones = {
  'ut': 0,
  'utc': 0,
  'gmt': 0,
  'z': 0,
  'est': -5,
  'edt': -4,
  'cst': -6,
  'cdt': -5,
  'mst': -7,
  'mdt': -6,
  'pst': -8,
  'pdt': -7,
  'bst': 1,
  'cet': 1,
  'cest': 2,
};

Duration _zoneOffset(String zone) {
  if (zone.isEmpty) return Duration.zero;
  final sign = zone[0];
  if (sign == '+' || sign == '-') {
    final digits = zone.substring(1).replaceAll(':', '');
    final hours = int.parse(digits.substring(0, 2));
    final minutes = int.parse(digits.substring(2, 4));
    final offset = Duration(hours: hours, minutes: minutes);
    return sign == '-' ? -offset : offset;
  }
  return Duration(hours: _zones[zone.toLowerCase()] ?? 0);
}

extension on String {
  String ifEmpty(String Function() other) => isEmpty ? other() : this;
}
