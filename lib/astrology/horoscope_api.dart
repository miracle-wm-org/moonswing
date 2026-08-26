// The web half of the astrology widget: the horoscope text, and where it comes
// from.
//
// Flutter-free and behind an interface, for `weather_api.dart`'s two reasons:
// the store leases a poller a widget test must be able to drive without a
// network, and the parse is where a shape change at the far end turns into a
// crash, so it is a pure function over a decoded map.
//
// **Why this source.** The requirement was one that could be queried without an
// account, and whose *server* is free software rather than a free tier. The
// field is thin — most "free horoscope APIs" are a marketing page in front of a
// key — and the one that meets it is ashutoshkrris/Horoscope-API: a Flask app
// under the MIT licence with a public instance at
// [kDefaultHoroscopeApiBase]. Two consequences the shell has to live with, and
// they are why `[astrology] api_base` is a config key rather than a constant:
//
// - **The server scrapes horoscope.com.** The text is somebody's copy, and
//   neither the licence nor the endpoint is a promise about it. The card
//   attributes it rather than presenting it as the shell's own, and a broken
//   scrape reaches the user as an error rather than as silence.
// - **The public instance is one person's free deployment.** It can go away,
// and   the answer when it does is not to ship a different scraper — it is that
//   anybody can run the MIT server themselves and point `api_base` at it. That
//   makes the dependency a *default*, not a lock-in, which is the only sense in
//   which a hosted API is FOSS at all.
//
// Contract, from the server's own `core/routes.py`:
//
//     GET {base}/api/v1/get-horoscope/{daily,weekly,monthly}
//         ?sign=Aries[&day=TODAY|TOMORROW|YESTERDAY|YYYY-MM-DD]
//     -> {"success": true, "status": 200, "data": ...}
//
// `day` is the daily endpoint's alone and is required there. `data` is a bare
// string in the repository's revision and an object carrying `horoscope_data`
// and `date` in the deployed one, so [parseHoroscope] accepts both — see its
// own note.

import 'dart:convert';

import 'package:http/http.dart' as http;

/// The public instance of the MIT-licensed server. Overridable — see the note
/// above, and `[astrology] api_base`.
const String kDefaultHoroscopeApiBase = 'https://horoscope-app-api.vercel.app';

/// Where the text on the card comes from, for the line that says so.
const String kHoroscopeAttribution = 'horoscope.com via Horoscope-API';

/// Which horoscope to ask for.
enum HoroscopePeriod {
  daily('daily', 'Today'),
  weekly('weekly', 'This week'),
  monthly('monthly', 'This month');

  const HoroscopePeriod(this.path, this.label);

  /// The endpoint segment.
  final String path;

  /// What the card calls it.
  final String label;

  /// How long a reading of this period is worth keeping, as the floor under
  /// the configured refresh interval. A daily horoscope changes once a day; a
  /// monthly one changes twelve times a year, and polling it hourly is asking
  /// somebody's free deployment for the same paragraph seven hundred times a
  /// month.
  Duration get minimumInterval => switch (this) {
        daily => const Duration(hours: 1),
        weekly => const Duration(hours: 6),
        monthly => const Duration(hours: 12),
      };

  /// [name]'s period, defaulting to [daily] — a config value is a string the
  /// user typed and a misspelling must cost the setting, not the module.
  static HoroscopePeriod parse(String name) {
    final wanted = name.trim().toLowerCase();
    for (final period in HoroscopePeriod.values) {
      if (period.path == wanted) return period;
    }
    return daily;
  }
}

/// One horoscope, as it will be rendered.
class HoroscopeReading {
  const HoroscopeReading({
    required this.text,
    required this.period,
    this.date = '',
  });

  /// The paragraph itself.
  final String text;

  final HoroscopePeriod period;

  /// What the server called the day this is for, verbatim and unparsed —
  /// "August 26, 2026", or empty when the response carried none.
  ///
  /// Not a [DateTime]: it is a display string in whatever format the far end
  /// chose, and parsing it would be inventing a precision the field does not
  /// have. The card shows it beside the period label or not at all.
  final String date;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HoroscopeReading &&
          other.text == text &&
          other.period == period &&
          other.date == date;

  @override
  int get hashCode => Object.hash(text, period, date);
}

/// Thrown when a lookup fails in a way the user should be told about. The store
/// turns it into the one line the card shows in place of a reading —
/// `WeatherException`'s job, and the same contract.
class HoroscopeException implements Exception {
  const HoroscopeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The seam the store fetches through. [HoroscopeApiClient] is the one
/// implementation; a test supplies its own and never opens a socket.
abstract class HoroscopeClient {
  Future<HoroscopeReading> fetch({
    required String sign,
    required HoroscopePeriod period,
    required String apiBase,
  });
}

/// The MIT-licensed Horoscope-API, at whatever base the config names.
class HoroscopeApiClient implements HoroscopeClient {
  const HoroscopeApiClient({http.Client? httpClient}) : _client = httpClient;

  final http.Client? _client;

  @override
  Future<HoroscopeReading> fetch({
    required String sign,
    required HoroscopePeriod period,
    required String apiBase,
  }) async {
    final url = horoscopeUrl(sign: sign, period: period, apiBase: apiBase);
    final client = _client;
    final http.Response response;
    try {
      response = client == null ? await http.get(url) : await client.get(url);
    } catch (e) {
      // A socket error is the overwhelmingly likely failure here and its
      // `toString` is a sentence about a host name; the user's question is
      // whether the shell is broken or the network is.
      throw HoroscopeException('Could not reach ${url.host}');
    }
    if (response.statusCode != 200) {
      throw HoroscopeException('${url.host} answered ${response.statusCode}');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw HoroscopeException('${url.host} did not answer with JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const HoroscopeException(
        'Unexpected response from the horoscope API',
      );
    }
    return parseHoroscope(decoded, period);
  }
}

/// The request URL, exposed so a test can pin it without a client.
///
/// [apiBase] is whatever the user configured; a trailing slash is trimmed so
/// `https://host/` and `https://host` are the same setting rather than one that
/// silently produces a double slash.
Uri horoscopeUrl({
  required String sign,
  required HoroscopePeriod period,
  required String apiBase,
}) {
  final base = apiBase.trim().replaceAll(RegExp(r'/+$'), '');
  return Uri.parse('$base/api/v1/get-horoscope/${period.path}').replace(
    queryParameters: {
      'sign': sign,
      // Only the daily endpoint takes a day, and it *requires* one — its
      // `reqparse` argument is `required=True`, so omitting it is a 400 rather
      // than a default. The weekly and monthly endpoints reject unknown
      // arguments silently, but sending one anyway would be describing a
      // contract that is not there.
      if (period == HoroscopePeriod.daily) 'day': 'TODAY',
    },
  );
}

/// The response body, decoded.
///
/// Degrades per field the way `parseForecast` does: the paragraph is the
/// reading and its absence is fatal, while the date is an ornament and a
/// missing one costs only itself.
///
/// `data` is read two ways because the server has shipped it both. The
/// repository's own revision returns `data.p.text` — a bare string — while the
/// deployed instance wraps it as `{"date": …, "horoscope_data": …}`. Accepting
/// only one of those is a parse that breaks on a deployment nobody told us
/// about, and the two shapes are trivially distinguishable.
HoroscopeReading parseHoroscope(
  Map<String, dynamic> json,
  HoroscopePeriod period,
) {
  final data = json['data'];

  if (data is String) {
    final text = data.trim();
    if (text.isEmpty) {
      throw const HoroscopeException('The horoscope API returned nothing');
    }
    return HoroscopeReading(text: text, period: period);
  }

  if (data is Map) {
    final raw = data['horoscope_data'];
    final text = raw is String ? raw.trim() : '';
    if (text.isEmpty) {
      throw const HoroscopeException('The horoscope API returned nothing');
    }
    final date = data['date'];
    return HoroscopeReading(
      text: text,
      period: period,
      date: date is String ? date.trim() : '',
    );
  }

  // A `success: false` body, an error page that happened to be JSON, or a shape
  // this build predates. The server's own failures come back as a `message`.
  final message = json['message'];
  throw HoroscopeException(
    message is String && message.trim().isNotEmpty
        ? message.trim()
        : 'Unexpected response from the horoscope API',
  );
}
