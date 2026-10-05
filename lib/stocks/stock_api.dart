// The web half of the stock market strip: quotes, and finding a symbol by name.
//
// **The source is `ticker`'s** (github.com/achannarasappa/ticker) — Yahoo
// Finance's `query1` API, reached the way `ticker`'s `unary` client reaches it,
// because the request is only half of it. Yahoo refuses an anonymous quote
// request, and what it wants first is a *session*: the `A3` cookie that
// `finance.yahoo.com` sets, then a "crumb" read with that cookie from
// `/v1/test/getcrumb`, both sent with every request after. In the EU the first
// request is redirected to a consent page instead, and the cookie is what
// agreeing to it sets. All three steps, the headers they are made with and the
// order they are made in are `ticker`'s, transcribed — and so is the policy of
// trying the request first and establishing a session only once it is refused,
// so a session that is still good costs nothing to keep using.
//
// Search is the same host's `/v1/finance/search`, which `ticker` has no use for
// (its watchlist is a file somebody edits) and which is the one endpoint Yahoo's
// own symbol box calls.
//
// Flutter-free and behind [StockClient] for the weather client's reasons: the
// store leases one poller for every surface, so a test driving it must not reach
// the network, and the parse is a pure function in `stock_quote.dart`.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:moonswing/stocks/stock_quote.dart';

/// The seam the store polls through. [YahooFinanceClient] is the one
/// implementation; a test supplies its own and never opens a socket.
abstract class StockClient {
  /// Quotes for [symbols], in whatever order the source answers. A symbol the
  /// source does not know is simply absent from the answer.
  Future<List<StockQuote>> quotes(List<String> symbols);

  /// Symbols matching [query], by symbol or by name. Empty for a blank query.
  Future<List<StockSearchResult>> search(String query);
}

/// Thrown when a request fails in a way the user should be told about. The
/// store turns it into the one line of text every surface shows.
class StockException implements Exception {
  const StockException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The fields `ticker`'s `GetAssetQuotes` asks for, plus the four the
/// transform reads that it gets anyway (`quoteType`, `currency`,
/// `marketState`, `exchangeDataDelayedBy`) — named rather than left to the
/// server's default, which has dropped fields before.
const List<String> kYahooQuoteFields = [
  'shortName',
  'regularMarketChange',
  'regularMarketChangePercent',
  'regularMarketPrice',
  'regularMarketPreviousClose',
  'regularMarketOpen',
  'regularMarketDayRange',
  'regularMarketDayHigh',
  'regularMarketDayLow',
  'regularMarketVolume',
  'postMarketChange',
  'postMarketChangePercent',
  'postMarketPrice',
  'preMarketChange',
  'preMarketChangePercent',
  'preMarketPrice',
  'fiftyTwoWeekHigh',
  'fiftyTwoWeekLow',
  'marketCap',
  'quoteType',
  'currency',
  'marketState',
  'exchangeDataDelayedBy',
];

// `ticker`'s header values. Yahoo answers a request that does not look like a
// browser with a 429 regardless of rate, so these are not decoration.
const String _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';
const String _acceptHtml =
    'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,'
    'image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7';
const String _acceptLanguage = 'en-US,en;q=0.9';

/// Yahoo Finance, as `ticker` reads it.
class YahooFinanceClient implements StockClient {
  YahooFinanceClient({
    http.Client? httpClient,
    this.baseUrl = 'https://query1.finance.yahoo.com',
    this.sessionRootUrl = 'https://finance.yahoo.com',
    this.sessionCrumbUrl = 'https://query2.finance.yahoo.com',
    this.sessionConsentUrl = 'https://consent.yahoo.com',
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient;

  final http.Client? _http;

  /// `ticker`'s `MonitorYahooBaseURL` and its three session URLs — separate
  /// hosts on purpose, and the crumb has to come from `query2` even though
  /// the quotes come from `query1`.
  final String baseUrl;
  final String sessionRootUrl;
  final String sessionCrumbUrl;
  final String sessionConsentUrl;

  /// How long one request may take. A quote poll that hangs would otherwise
  /// hold the store's in-flight flag, and with it every later poll, forever.
  final Duration timeout;

  /// The session — name/value pairs, never the attributes, which is all a
  /// request sends back — and the crumb read with it. Empty until the first
  /// refusal establishes them.
  Map<String, String> _cookies = const {};
  String _crumb = '';

  /// The handshake in flight, so a quote poll and a search refused at the
  /// same moment establish one session between them.
  Future<void>? _refreshing;

  /// The crumb the session is using, empty before the first handshake. Read
  /// by the tests; nothing else has a use for it.
  String get crumb => _crumb;

  http.Client get _client => _http ?? _shared;
  static final http.Client _shared = http.Client();

  @override
  Future<List<StockQuote>> quotes(List<String> symbols) async {
    if (symbols.isEmpty) return const [];
    final response = await _withSession(() => _getQuotes(symbols));
    try {
      return parseYahooQuotes(jsonDecode(response.body));
    } on FormatException {
      throw const StockException('Yahoo Finance sent a quote it could not read');
    }
  }

  @override
  Future<List<StockSearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final response = await _withSession(() => _getSearch(trimmed));
    try {
      return parseYahooSearch(jsonDecode(response.body));
    } on FormatException {
      throw const StockException('Yahoo Finance sent a search it could not read');
    }
  }

  /// [request], and — once it is refused — the session handshake and the
  /// request again. `ticker`'s `getQuotes`, except that it retries once
  /// rather than recursing: a session Yahoo refuses straight after issuing it
  /// will be refused the next time too, and the store's own poll is the
  /// retry.
  Future<http.Response> _withSession(
    Future<http.Response> Function() request,
  ) async {
    var response = await _guard(request);
    if (response.statusCode >= 400) {
      await (_refreshing ??= _refreshSession().whenComplete(() {
        _refreshing = null;
      }));
      response = await _guard(request);
    }
    if (response.statusCode == 429) {
      throw const StockException('Yahoo Finance is rate-limiting requests');
    }
    if (response.statusCode != 200) {
      throw StockException('Yahoo Finance answered ${response.statusCode}');
    }
    return response;
  }

  /// [request] with its transport failures turned into the store's one
  /// message, so the bar says "could not be reached" rather than a socket
  /// error's errno.
  Future<http.Response> _guard(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(timeout);
    } on StockException {
      rethrow;
    } on TimeoutException {
      throw const StockException('Yahoo Finance did not answer in time');
    } catch (_) {
      throw const StockException('Yahoo Finance could not be reached');
    }
  }

  Future<http.Response> _getQuotes(List<String> symbols) {
    final url = Uri.parse('$baseUrl/v7/finance/quote').replace(
      queryParameters: {
        'fields': kYahooQuoteFields.join(','),
        'symbols': symbols.join(','),
        'formatted': 'true',
        'lang': 'en-US',
        'region': 'US',
        'corsDomain': 'finance.yahoo.com',
        if (_crumb.isNotEmpty) 'crumb': _crumb,
      },
    );
    return _client.get(url, headers: _apiHeaders(url));
  }

  Future<http.Response> _getSearch(String query) {
    final url = Uri.parse('$baseUrl/v1/finance/search').replace(
      queryParameters: {
        'q': query,
        'quotesCount': '10',
        'newsCount': '0',
        'listsCount': '0',
        'enableFuzzyQuery': 'false',
        'lang': 'en-US',
        'region': 'US',
        if (_crumb.isNotEmpty) 'crumb': _crumb,
      },
    );
    return _client.get(url, headers: _apiHeaders(url));
  }

  Map<String, String> _apiHeaders(Uri url) => {
        'Authority': url.host,
        'Accept': '*/*',
        'Accept-Language': _acceptLanguage,
        'Origin': baseUrl,
        'User-Agent': _userAgent,
        if (_cookies.isNotEmpty) 'Cookie': _cookieHeader(_cookies),
      };

  // --- the session -----------------------------------------------------------

  /// `ticker`'s `refreshSession`: a cookie, then a crumb read with it.
  Future<void> _refreshSession() async {
    try {
      final cookies = await _getCookie();
      final crumb = await _getCrumb(cookies);
      _cookies = cookies;
      _crumb = crumb;
    } on StockException {
      rethrow;
    } on TimeoutException {
      throw const StockException('Yahoo Finance did not answer in time');
    } catch (_) {
      throw const StockException('Yahoo Finance could not be reached');
    }
  }

  Future<Map<String, String>> _getCookie() async {
    final response = await _send(
      'GET',
      Uri.parse(sessionRootUrl),
      headers: _pageHeaders,
    );
    final location = response.headers['location'] ?? '';
    if (_isRedirect(response.statusCode) && location.contains('/consent')) {
      return _getCookieEU();
    }
    final cookies = parseSetCookies(_setCookieValues(response));
    if (!cookies.containsKey('A3')) {
      throw const StockException('Yahoo Finance did not start a session');
    }
    return cookies;
  }

  /// The EU flow: follow the redirect to the consent page, read the session
  /// id and the CSRF token out of the URLs it passed through and the `GUCS`
  /// cookie out of the responses, and post the agreement `ticker` posts.
  ///
  /// Read off *every* hop rather than off the hop `ticker` indexes into by
  /// position: the redirect chain has been one hop longer and shorter in
  /// different countries, and the values are distinctive enough to find
  /// wherever they land.
  Future<Map<String, String>> _getCookieEU() async {
    final hops = await _follow(
      'GET',
      Uri.parse(sessionRootUrl),
      headers: _pageHeaders,
      maxRedirects: 3,
    );
    final last = hops.last;
    if (last.response.statusCode < 200 || last.response.statusCode >= 300) {
      throw StockException(
        'Yahoo Finance consent page answered ${last.response.statusCode}',
      );
    }

    String? find(RegExp pattern) {
      for (final hop in hops.reversed) {
        final match = pattern.firstMatch(hop.url.toString());
        if (match != null) return match.group(1);
        final location = hop.response.headers['location'];
        final viaLocation =
            location == null ? null : pattern.firstMatch(location);
        if (viaLocation != null) return viaLocation.group(1);
      }
      return null;
    }

    final sessionId = find(RegExp(r'sessionId=([A-Za-z0-9_-]*)'));
    final csrfToken = find(RegExp(r'gcrumb=([A-Za-z0-9_]*)'));
    if (sessionId == null || sessionId.isEmpty) {
      throw const StockException('Yahoo Finance consent page had no session');
    }
    if (csrfToken == null || csrfToken.isEmpty) {
      throw const StockException('Yahoo Finance consent page had no token');
    }
    final gucs = <String, String>{
      for (final hop in hops) ...parseSetCookies(_setCookieValues(hop.response)),
    };
    if (gucs.isEmpty) {
      throw const StockException('Yahoo Finance consent page set no cookie');
    }

    final consentUrl = Uri.parse(
      '$sessionConsentUrl/v2/collectConsent?sessionId=$sessionId',
    );
    final form = {
      'csrfToken': csrfToken,
      'sessionId': sessionId,
      'namespace': 'yahoo',
      'agree': 'agree',
    };
    final agreed = await _follow(
      'POST',
      consentUrl,
      headers: {
        'Origin': sessionConsentUrl,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': _acceptHtml,
        'Accept-Language': _acceptLanguage,
        'Referer': consentUrl.toString(),
        'User-Agent': _userAgent,
        'DNT': '1',
        'Cookie': _cookieHeader(gucs),
      },
      body: form,
      maxRedirects: 2,
    );
    final cookies = <String, String>{
      for (final hop in agreed) ...parseSetCookies(_setCookieValues(hop.response)),
    };
    if (!cookies.containsKey('A3')) {
      throw const StockException('Yahoo Finance did not accept the consent');
    }
    return cookies;
  }

  Future<String> _getCrumb(Map<String, String> cookies) async {
    final response = await _client.get(
      Uri.parse('$sessionCrumbUrl/v1/test/getcrumb'),
      headers: {
        'Authority': Uri.parse(sessionCrumbUrl).host,
        'Accept': '*/*',
        'Accept-Language': _acceptLanguage,
        'Content-Type': 'text/plain',
        'Origin': sessionRootUrl,
        'User-Agent': _userAgent,
        'Cookie': _cookieHeader(cookies),
      },
    ).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StockException(
        'Yahoo Finance refused a session (${response.statusCode})',
      );
    }
    final crumb = response.body.trim();
    // An HTML page in place of a crumb is the shape a block page takes, and
    // sending it back as a query parameter would only be refused again.
    if (crumb.isEmpty || crumb.contains('<') || crumb.length > 64) {
      throw const StockException('Yahoo Finance refused a session');
    }
    return crumb;
  }

  Map<String, String> get _pageHeaders => const {
        'Authority': 'finance.yahoo.com',
        'Accept': _acceptHtml,
        'Accept-Language': _acceptLanguage,
        'User-Agent': _userAgent,
      };

  /// One request with redirects left unfollowed: the session's cookies are on
  /// the redirect itself, and the default client would throw them away on the
  /// way to wherever it points.
  Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Map<String, String>? body,
  }) async {
    final request = http.Request(method, url)
      ..followRedirects = false
      ..headers.addAll(headers);
    if (body != null) request.bodyFields = body;
    final streamed = await _client.send(request).timeout(timeout);
    return http.Response.fromStream(streamed).timeout(timeout);
  }

  /// [url] and up to [maxRedirects] of the redirects after it, every hop
  /// kept. A redirect after a POST is a GET, as a browser makes it.
  Future<List<_Hop>> _follow(
    String method,
    Uri url, {
    required Map<String, String> headers,
    Map<String, String>? body,
    required int maxRedirects,
  }) async {
    final hops = <_Hop>[];
    var next = url;
    var verb = method;
    Map<String, String>? payload = body;
    for (var i = 0; i <= maxRedirects; i++) {
      final response = await _send(verb, next, headers: headers, body: payload);
      hops.add(_Hop(next, response));
      final location = response.headers['location'];
      if (!_isRedirect(response.statusCode) || location == null) break;
      next = next.resolve(location);
      verb = 'GET';
      payload = null;
    }
    return hops;
  }
}

class _Hop {
  const _Hop(this.url, this.response);
  final Uri url;
  final http.Response response;
}

bool _isRedirect(int status) => status >= 300 && status < 400;

/// Every `Set-Cookie` on [response], one per header.
///
/// `response.headers` folds repeated headers into one comma-joined string,
/// and a cookie's `Expires` has a comma in it — so the folded form cannot be
/// split back apart. The split view is what keeps one cookie one cookie.
List<String> _setCookieValues(http.BaseResponse response) =>
    response.headersSplitValues['set-cookie'] ?? const [];

/// The name/value pair of each `Set-Cookie` header in [headers], attributes
/// dropped — `ticker`'s `parseSetCookieHeaders`, keeping only the half a
/// request sends back. A later header for the same name wins, as it would in
/// a browser's jar.
Map<String, String> parseSetCookies(Iterable<String> headers) {
  final cookies = <String, String>{};
  for (final header in headers) {
    final pair = header.split(';').first;
    final eq = pair.indexOf('=');
    if (eq <= 0) continue;
    final name = pair.substring(0, eq).trim();
    final value = pair.substring(eq + 1).trim();
    if (name.isEmpty) continue;
    cookies[name] = value;
  }
  return cookies;
}

String _cookieHeader(Map<String, String> cookies) =>
    cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
