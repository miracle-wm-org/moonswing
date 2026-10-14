// Fetching one feed.
//
// An interface with one HTTP implementation, so the store's tests drive it
// with canned documents and no network behind them. Flutter-free.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// A feed could not be read. [message] is what the card shows, so it says
/// what happened in the words of somebody looking at a desktop, not a stack.
class NewsException implements Exception {
  const NewsException(this.message);

  final String message;

  @override
  String toString() => 'NewsException: $message';
}

abstract class NewsClient {
  /// The document at [url], decoded. Throws [NewsException].
  Future<String> fetch(Uri url);
}

class HttpNewsClient implements NewsClient {
  HttpNewsClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _http = httpClient;

  final http.Client? _http;
  final Duration timeout;

  http.Client get _client => _http ?? _shared;
  static final http.Client _shared = http.Client();

  @override
  Future<String> fetch(Uri url) async {
    final http.Response response;
    try {
      response = await _client
          .get(
            url,
            headers: const {
              // A browser-shaped agent: several feed hosts answer a bare
              // library agent with a 403 or a consent page.
              'User-Agent':
                  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/124.0 Safari/537.36 moonswing',
              'Accept':
                  'application/rss+xml, application/atom+xml, '
                  'application/xml;q=0.9, text/xml;q=0.9, */*;q=0.5',
            },
          )
          .timeout(timeout);
    } on TimeoutException {
      throw NewsException('${url.host} took too long to answer');
    } on SocketException {
      throw NewsException('Couldn’t reach ${url.host}');
    } on http.ClientException {
      throw NewsException('Couldn’t reach ${url.host}');
    } on HandshakeException {
      throw NewsException('${url.host}’s certificate was refused');
    }
    final status = response.statusCode;
    if (status == 429) {
      throw NewsException('${url.host} is limiting requests');
    }
    if (status < 200 || status >= 300) {
      throw NewsException('${url.host} answered $status');
    }
    return _decode(response);
  }

  /// The body as text. UTF-8 unless the response names another charset:
  /// `http` defaults a `text/xml` with no charset to Latin-1, which is right
  /// by the letter of RFC 2616 and wrong for every feed that relies on the
  /// XML declaration's UTF-8 default — curly quotes come out as mojibake.
  static String _decode(http.Response response) {
    final type = response.headers['content-type'] ?? '';
    final charset = RegExp(
      r'charset="?([^";\s]+)',
      caseSensitive: false,
    ).firstMatch(type)?.group(1)?.toLowerCase();
    if (charset != null && charset != 'utf-8' && charset != 'utf8') {
      final encoding = Encoding.getByName(charset);
      if (encoding != null) return encoding.decode(response.bodyBytes);
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }
}
