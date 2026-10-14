import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/news/news_feed.dart';
import 'package:moonswing/news/news_format.dart';
import 'package:moonswing/news/news_store.dart';

/// What Google News answers a `site:` search with, trimmed to two items.
const _googleNews = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
  <channel>
    <title>"site:reuters.com when:1d" - Google News</title>
    <link>https://news.google.com/search?q=site:reuters.com</link>
    <item>
      <title>Central bank holds rates steady - Reuters</title>
      <link>https://news.google.com/rss/articles/CBMiAAA?oc=5</link>
      <guid isPermaLink="false">CBMiAAA</guid>
      <pubDate>Tue, 14 Oct 2026 13:05:00 GMT</pubDate>
      <description>&lt;a href="https://news.google.com/rss/articles/CBMiAAA"&gt;Central bank&lt;/a&gt;</description>
      <source url="https://www.reuters.com">Reuters</source>
    </item>
    <item>
      <title>Storm makes landfall &amp;#8212; officials urge caution - Reuters</title>
      <link>https://news.google.com/rss/articles/CBMiBBB?oc=5</link>
      <pubDate>Tue, 14 Oct 2026 09:30:00 -0400</pubDate>
      <source url="https://www.reuters.com">Reuters</source>
    </item>
  </channel>
</rss>''';

const _atom = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Example Wire</title>
  <entry>
    <title type="html">Election results &lt;b&gt;certified&lt;/b&gt;</title>
    <link rel="self" href="https://example.com/api/1"/>
    <link href="https://example.com/story/1"/>
    <published>2026-10-14T08:00:00Z</published>
    <updated>2026-10-14T09:00:00Z</updated>
  </entry>
  <entry>
    <title>Only updated</title>
    <link rel="alternate" href="https://example.com/story/2"/>
    <updated>2026-10-13T22:15:00+02:00</updated>
  </entry>
  <entry>
    <title>No link at all</title>
  </entry>
</feed>''';

const _rdf = '''<?xml version="1.0"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns="http://purl.org/rss/1.0/"
         xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel rdf:about="https://example.org/">
    <title>RDF Daily</title>
  </channel>
  <item rdf:about="https://example.org/a">
    <title>Parliament passes budget</title>
    <link>https://example.org/a</link>
    <dc:date>2026-10-14T06:45:00Z</dc:date>
  </item>
</rdf:RDF>''';

NewsHeadline _h(
  String title, {
  String? link,
  DateTime? at,
  String src = 'AP',
}) => NewsHeadline(
  title: title,
  link: link ?? 'https://example.com/${title.hashCode}',
  source: src,
  published: at,
);

void main() {
  group('parseNewsFeed', () {
    test('Google News: the outlet comes off the title, the date to UTC', () {
      final feed = parseNewsFeed(_googleNews, sourceName: 'Reuters');
      expect(feed.headlines, hasLength(2));
      final first = feed.headlines.first;
      expect(first.title, 'Central bank holds rates steady');
      expect(first.link, 'https://news.google.com/rss/articles/CBMiAAA?oc=5');
      expect(first.source, 'Reuters');
      expect(first.published, DateTime.utc(2026, 10, 14, 13, 5));

      final second = feed.headlines.last;
      expect(
        second.title,
        'Storm makes landfall — officials urge caution',
        reason: 'an entity escaped twice is decoded',
      );
      expect(second.published, DateTime.utc(2026, 10, 14, 13, 30));
    });

    test('a preset is labelled by its own name, never the channel title', () {
      final feed = parseNewsFeed(_googleNews, sourceName: 'Reuters');
      expect(feed.headlines.map((h) => h.source).toSet(), {'Reuters'});
    });

    test(
      'Atom: the alternate link, published over updated, markup stripped',
      () {
        final feed = parseNewsFeed(
          _atom,
          sourceName: 'example.com',
          preferItemSource: true,
        );
        expect(feed.title, 'Example Wire');
        expect(feed.headlines, hasLength(2), reason: 'the linkless entry goes');
        expect(feed.headlines[0].title, 'Election results certified');
        expect(feed.headlines[0].link, 'https://example.com/story/1');
        expect(feed.headlines[0].published, DateTime.utc(2026, 10, 14, 8));
        expect(
          feed.headlines[0].source,
          'Example Wire',
          reason: 'a feed of the user\'s own is named by its title',
        );
        expect(feed.headlines[1].published, DateTime.utc(2026, 10, 13, 20, 15));
      },
    );

    test('RSS 1.0: items beside the channel, in its namespace', () {
      final feed = parseNewsFeed(
        _rdf,
        sourceName: 'example.org',
        preferItemSource: true,
      );
      expect(feed.headlines.single.title, 'Parliament passes budget');
      expect(feed.headlines.single.source, 'RDF Daily');
      expect(
        feed.headlines.single.published,
        DateTime.utc(2026, 10, 14, 6, 45),
      );
    });

    test('a bad item costs the item, a bad date costs the date', () {
      const doc = '''<rss version="2.0"><channel><title>T</title>
        <item><title>Kept</title><link>https://a.example/1</link>
          <pubDate>yesterday-ish</pubDate></item>
        <item><title></title><link>https://a.example/2</link></item>
        <item><title>Relative link</title><link>/story/3</link></item>
        <item><title>Script link</title><link>javascript:alert(1)</link></item>
        <item><title>Guid link</title>
          <guid>https://a.example/4</guid></item>
      </channel></rss>''';
      final feed = parseNewsFeed(doc, sourceName: 'A');
      expect(feed.headlines.map((h) => h.title), ['Kept', 'Guid link']);
      expect(feed.headlines.first.published, isNull);
    });

    test('a document that is not a feed is refused whole', () {
      expect(
        () =>
            parseNewsFeed('<html><body>Consent</body></html>', sourceName: 'A'),
        throwsA(isA<NewsFeedFormatException>()),
      );
      expect(
        () => parseNewsFeed('not xml at all <', sourceName: 'A'),
        throwsA(isA<NewsFeedFormatException>()),
      );
    });
  });

  group('parseNewsDate', () {
    test('RFC 822 with names, offsets and no seconds', () {
      expect(
        parseNewsDate('Tue, 14 Oct 2026 13:05:00 GMT'),
        DateTime.utc(2026, 10, 14, 13, 5),
      );
      expect(
        parseNewsDate('14 Oct 2026 08:05 EDT'),
        DateTime.utc(2026, 10, 14, 12, 5),
      );
      expect(
        parseNewsDate('Tue, 14 Oct 26 13:05:00 +0530'),
        DateTime.utc(2026, 10, 14, 7, 35),
      );
      expect(
        parseNewsDate('Wed, 1 Jan 2025 00:30:00 -01:00'),
        DateTime.utc(2025, 1, 1, 1, 30),
      );
    });

    test('ISO 8601, with and without a zone', () {
      expect(
        parseNewsDate('2026-10-14T13:05:00Z'),
        DateTime.utc(2026, 10, 14, 13, 5),
      );
      expect(
        parseNewsDate('2026-10-14T13:05:00'),
        DateTime.utc(2026, 10, 14, 13, 5),
        reason: 'a zoneless date is the server\'s, read as UTC',
      );
    });

    test('anything else is no date', () {
      expect(parseNewsDate(''), isNull);
      expect(parseNewsDate('soon'), isNull);
      expect(parseNewsDate('Tue, 14 Foo 2026 13:05:00 GMT'), isNull);
      expect(parseNewsDate('Tue, 40 Oct 2026 13:05:00 GMT'), isNull);
    });
  });

  group('mergeNewsHeadlines', () {
    test('newest first across feeds, undated last in feed order', () {
      final merged = mergeNewsHeadlines([
        [_h('a1', at: DateTime.utc(2026, 10, 14, 9)), _h('a-undated')],
        [
          _h('b1', at: DateTime.utc(2026, 10, 14, 11), src: 'Reuters'),
          _h('b-undated', src: 'Reuters'),
        ],
      ]);
      expect(merged.map((h) => h.title), [
        'b1',
        'a1',
        'a-undated',
        'b-undated',
      ]);
    });

    test('one story under two feeds is one row', () {
      final merged = mergeNewsHeadlines([
        [_h('Quake hits coast', at: DateTime.utc(2026, 10, 14, 10))],
        [
          _h('Quake Hits Coast!', at: DateTime.utc(2026, 10, 14, 9), src: 'R'),
          _h(
            'Other',
            link: 'https://example.com/${'Quake hits coast'.hashCode}',
          ),
        ],
      ]);
      expect(merged.map((h) => h.title), ['Quake hits coast']);
    });

    test('capped', () {
      final merged = mergeNewsHeadlines([
        [for (var i = 0; i < 10; i++) _h('story $i')],
      ], limit: 3);
      expect(merged, hasLength(3));
    });
  });

  group('formatNewsTime', () {
    final now = DateTime(2026, 10, 14, 15, 0);

    test('a clock time today, then yesterday, a weekday, a date', () {
      expect(formatNewsTime(DateTime(2026, 10, 14, 9, 5), now), '09:05');
      expect(formatNewsTime(DateTime(2026, 10, 14, 0, 0), now), '00:00');
      expect(formatNewsTime(DateTime(2026, 10, 13, 23, 59), now), 'Yesterday');
      expect(formatNewsTime(DateTime(2026, 10, 10, 12), now), 'Sat');
      expect(formatNewsTime(DateTime(2026, 10, 7, 12), now), '7 Oct');
    });

    test('a story stamped ahead of this clock is today\'s', () {
      expect(formatNewsTime(DateTime(2026, 10, 15, 1), now), '01:00');
    });
  });
}
