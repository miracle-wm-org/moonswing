import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:moonswing/stocks/stock_api.dart';

/// The Yahoo client against a scripted server: the session handshake `ticker`
/// performs, in its order, and what reaches the user when any of it fails.
void main() {
  /// A folded `Set-Cookie`, the way a client hands several back as one header
  /// — with the comma inside `Expires` that makes splitting it a trap.
  const setCookies =
      'B=abc; Expires=Wed, 21 Oct 2027 07:28:00 GMT; Path=/; Domain=.yahoo.com, '
      'A3=d=AQABBG&S=AQAAAt; Expires=Thu, 22 Oct 2027 07:28:00 GMT; '
      'Domain=.yahoo.com; Path=/; Secure; HttpOnly, '
      'A1S=d=xyz; Path=/';

  String quoteBody(List<String> symbols) => jsonEncode({
        'quoteResponse': {
          'result': [
            for (final s in symbols)
              {
                'symbol': s,
                'marketState': 'REGULAR',
                'regularMarketPrice': {'raw': 100.0, 'fmt': '100.00'},
                'regularMarketChange': {'raw': 1.0, 'fmt': '1.00'},
                'regularMarketChangePercent': {'raw': 1.0, 'fmt': '1.00%'},
              },
          ],
          'error': null,
        },
      });

  test('a refused request establishes a session, then retries with it',
      () async {
    final log = <String>[];
    late http.BaseRequest retried;
    final client = YahooFinanceClient(
      httpClient: MockClient((request) async {
        final url = request.url;
        log.add('${request.method} ${url.host}${url.path}');
        if (url.path == '/v7/finance/quote') {
          if (url.queryParameters['crumb'] != 'cr4mb') {
            return http.Response('Unauthorized', 401);
          }
          retried = request;
          final symbols = url.queryParameters['symbols']!.split(',');
          return http.Response(quoteBody(symbols), 200);
        }
        if (url.host == 'finance.yahoo.com') {
          // Redirects are not followed: the cookies are on this response.
          expect(request.followRedirects, isFalse);
          return http.Response('', 200, headers: {'set-cookie': setCookies});
        }
        if (url.path == '/v1/test/getcrumb') {
          expect(request.headers['Cookie'], contains('A3=d=AQABBG&S=AQAAAt'));
          return http.Response('cr4mb\n', 200);
        }
        return http.Response('?', 404);
      }),
    );

    final quotes = await client.quotes(['AAPL', 'MSFT']);

    expect(quotes.map((q) => q.symbol), ['AAPL', 'MSFT']);
    expect(log, [
      'GET query1.finance.yahoo.com/v7/finance/quote',
      'GET finance.yahoo.com',
      'GET query2.finance.yahoo.com/v1/test/getcrumb',
      'GET query1.finance.yahoo.com/v7/finance/quote',
    ]);
    expect(client.crumb, 'cr4mb');
    // Every cookie, attributes dropped, and the comma in Expires did not
    // split one cookie into two.
    expect(
      retried.headers['Cookie'],
      'B=abc; A3=d=AQABBG&S=AQAAAt; A1S=d=xyz',
    );
    expect(retried.url.queryParameters['formatted'], 'true');
    expect(
      retried.url.queryParameters['fields']!.split(','),
      containsAll(['regularMarketPrice', 'postMarketPrice', 'marketState']),
    );
    expect(retried.headers['User-Agent'], contains('Mozilla/5.0'));

    // The session is kept: the next poll is one request.
    log.clear();
    await client.quotes(['AAPL']);
    expect(log, ['GET query1.finance.yahoo.com/v7/finance/quote']);
  });

  test('no A3 cookie is a visible failure, not a crumbless retry', () async {
    final client = YahooFinanceClient(
      httpClient: MockClient((request) async {
        if (request.url.host == 'finance.yahoo.com') {
          return http.Response('', 200, headers: {'set-cookie': 'B=abc'});
        }
        return http.Response('Unauthorized', 401);
      }),
    );
    await expectLater(
      client.quotes(['AAPL']),
      throwsA(isA<StockException>().having(
        (e) => e.message,
        'message',
        'Yahoo Finance did not start a session',
      )),
    );
  });

  test('a refusal that survives a fresh session says what Yahoo answered',
      () async {
    final client = YahooFinanceClient(
      httpClient: MockClient((request) async {
        if (request.url.host == 'finance.yahoo.com') {
          return http.Response('', 200, headers: {'set-cookie': 'A3=x'});
        }
        if (request.url.path == '/v1/test/getcrumb') {
          return http.Response('crumb', 200);
        }
        return http.Response('Too many', 429);
      }),
    );
    await expectLater(
      client.quotes(['AAPL']),
      throwsA(isA<StockException>().having(
        (e) => e.message,
        'message',
        'Yahoo Finance is rate-limiting requests',
      )),
    );
  });

  test('a block page in place of a crumb is refused', () async {
    final client = YahooFinanceClient(
      httpClient: MockClient((request) async {
        if (request.url.host == 'finance.yahoo.com') {
          return http.Response('', 200, headers: {'set-cookie': 'A3=x'});
        }
        if (request.url.path == '/v1/test/getcrumb') {
          return http.Response('<html>blocked</html>', 200);
        }
        return http.Response('Unauthorized', 401);
      }),
    );
    await expectLater(client.quotes(['AAPL']), throwsA(isA<StockException>()));
  });

  test('a transport failure is one plain sentence', () async {
    final client = YahooFinanceClient(
      httpClient: MockClient((request) async {
        throw http.ClientException('Connection refused');
      }),
    );
    await expectLater(
      client.quotes(['AAPL']),
      throwsA(isA<StockException>().having(
        (e) => e.message,
        'message',
        'Yahoo Finance could not be reached',
      )),
    );
  });

  test('no symbols is no request', () async {
    var requests = 0;
    final client = YahooFinanceClient(
      httpClient: MockClient((request) async {
        requests++;
        return http.Response('', 500);
      }),
    );
    expect(await client.quotes(const []), isEmpty);
    expect(await client.search('  '), isEmpty);
    expect(requests, 0);
  });

  test('search reads the same host, by name', () async {
    late Uri asked;
    final client = YahooFinanceClient(
      httpClient: MockClient((request) async {
        asked = request.url;
        return http.Response(
          jsonEncode({
            'quotes': [
              {
                'symbol': 'AAPL',
                'shortname': 'Apple Inc.',
                'exchDisp': 'NASDAQ',
                'typeDisp': 'Equity',
              },
            ],
          }),
          200,
        );
      }),
    );
    final results = await client.search(' apple ');
    expect(asked.host, 'query1.finance.yahoo.com');
    expect(asked.path, '/v1/finance/search');
    expect(asked.queryParameters['q'], 'apple');
    expect(asked.queryParameters['newsCount'], '0');
    expect(results.single.symbol, 'AAPL');
    expect(results.single.name, 'Apple Inc.');
  });

  test('the EU consent flow agrees, and keeps the A3 cookie it is given',
      () async {
    final posts = <http.Request>[];
    final client = YahooFinanceClient(
      httpClient: MockClient((request) async {
        final url = request.url;
        if (url.path == '/v7/finance/quote') {
          if (url.queryParameters['crumb'] == null) {
            return http.Response('Unauthorized', 401);
          }
          return http.Response(quoteBody(['SAP.DE']), 200);
        }
        if (url.host == 'finance.yahoo.com') {
          return http.Response('', 302, headers: {
            'location': 'https://guce.yahoo.com/consent?gcrumb=GCR123&done=1',
          });
        }
        if (url.host == 'guce.yahoo.com') {
          return http.Response('', 302, headers: {
            'location':
                'https://consent.yahoo.com/v2/collectConsent?sessionId=3_cc-sess',
            'set-cookie': 'GUCS=gucs1; Path=/',
          });
        }
        if (url.host == 'consent.yahoo.com' && request.method == 'GET') {
          return http.Response('<form>...</form>', 200);
        }
        if (url.host == 'consent.yahoo.com' && request.method == 'POST') {
          posts.add(request);
          return http.Response('', 200, headers: {
            'set-cookie': 'A3=eu-session; Path=/; Domain=.yahoo.com',
          });
        }
        if (url.path == '/v1/test/getcrumb') {
          expect(request.headers['Cookie'], contains('A3=eu-session'));
          return http.Response('eucrumb', 200);
        }
        return http.Response('?', 404);
      }),
    );

    final quotes = await client.quotes(['SAP.DE']);

    expect(quotes.single.symbol, 'SAP.DE');
    expect(client.crumb, 'eucrumb');
    final post = posts.single;
    expect(post.url.queryParameters['sessionId'], '3_cc-sess');
    expect(post.bodyFields, {
      'csrfToken': 'GCR123',
      'sessionId': '3_cc-sess',
      'namespace': 'yahoo',
      'agree': 'agree',
    });
    expect(post.headers['Cookie'], contains('GUCS=gucs1'));
  });

  test('parseSetCookies keeps name and value, drops attributes', () {
    expect(
      parseSetCookies([
        'A3=x=y; Path=/; Secure',
        'junk',
        '=novalue',
        'B=1',
        'B=2',
      ]),
      {'A3': 'x=y', 'B': '2'},
    );
  });
}
