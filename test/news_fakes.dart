import 'package:moonswing/news/news_client.dart';

/// A [NewsClient] answering from a table, with per-URL failures, that records
/// every URL it was asked for.
class FakeNewsClient implements NewsClient {
  FakeNewsClient(Map<Uri, String> documents) : documents = Map.of(documents);

  final Map<Uri, String> documents;
  final Map<Uri, NewsException> failures = {};
  final List<Uri> fetches = [];

  @override
  Future<String> fetch(Uri url) async {
    fetches.add(url);
    final failure = failures[url];
    if (failure != null) throw failure;
    final document = documents[url];
    if (document == null) throw NewsException('${url.host} answered 404');
    return document;
  }
}

/// An RSS 2.0 document of [items] — (title, link, pubDate) — each carrying
/// [itemSource] as its `<source>` when given, the way Google News does.
String rssDocument(List<(String, String, String)> items, {String? itemSource}) {
  final buffer = StringBuffer(
    '<?xml version="1.0"?><rss version="2.0"><channel><title>Feed</title>',
  );
  for (final (title, link, date) in items) {
    buffer
      ..write('<item><title>$title</title><link>$link</link>')
      ..write('<pubDate>$date</pubDate>');
    if (itemSource != null) buffer.write('<source>$itemSource</source>');
    buffer.write('</item>');
  }
  buffer.write('</channel></rss>');
  return buffer.toString();
}
