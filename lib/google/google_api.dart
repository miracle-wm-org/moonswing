// The web half of the Google account: the token endpoint and the two Calendar
// reads the shell makes.
//
// Flutter-free and behind an interface, for `github_api.dart`'s reasons: the
// stores above poll through it and a test driving them must not reach the
// network, and parsing is where a shape change at Google would otherwise become
// a crash — so every response is a pure function over a decoded map, and an
// event that will not parse costs that event rather than the day.
//
// The client ID and secret are the *user's* own ("Desktop app" in Google Cloud
// Console). For an installed application Google documents the secret as not
// confidential — it identifies the client, it does not authenticate it; PKCE is
// what binds a code to the process that asked for it — so it is sent in the
// clear to the token endpoint exactly as Google's own libraries do.

import 'dart:convert';

import 'package:http/http.dart' as http;

/// What the sign-in asks for: read-only access to calendars and their events.
///
/// Deliberately the smallest scope that answers the questions asked of it. The
/// account's address is the primary calendar's id, so no `openid`/`email`
/// scope is needed to say who is signed in.
const String kGoogleCalendarScope =
    'https://www.googleapis.com/auth/calendar.readonly';

/// Thrown when a request fails in a way the user should be told about.
class GoogleException implements Exception {
  const GoogleException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The grant is gone: revoked at myaccount.google.com, expired (a consent
/// screen left in *Testing* expires refresh tokens after seven days), or issued
/// to a different client.
///
/// Its own type because it is the one failure with a state change behind it:
/// the account store drops the refresh token and goes back to signed out.
class GoogleAuthException extends GoogleException {
  const GoogleAuthException([super.message = 'Google sign-in expired']);
}

/// What the token endpoint hands back.
class GoogleTokens {
  const GoogleTokens({
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
  });

  final String accessToken;
  final DateTime expiresAt;

  /// Present on the first exchange (the sign-in asks for `access_type=offline`
  /// and `prompt=consent` so it always is) and usually absent on a refresh.
  final String? refreshToken;

  /// Parses a token response, measured from [now]. Null when it carries no
  /// access token.
  static GoogleTokens? fromJson(Map<String, dynamic> json, DateTime now) {
    final access = json['access_token'];
    if (access is! String || access.isEmpty) return null;
    final expires = json['expires_in'];
    final seconds = expires is num && expires.isFinite ? expires.toInt() : 3600;
    final refresh = json['refresh_token'];
    return GoogleTokens(
      accessToken: access,
      expiresAt: now.add(Duration(seconds: seconds)),
      refreshToken: refresh is String && refresh.isNotEmpty ? refresh : null,
    );
  }
}

/// One entry of the user's calendar list.
class GoogleCalendar {
  const GoogleCalendar({
    required this.id,
    required this.summary,
    this.primary = false,
    this.color,
  });

  final String id;
  final String summary;
  final bool primary;

  /// `#rrggbb`, as the calendar list spells it; null when it gives none.
  final String? color;

  static GoogleCalendar? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final override = json['summaryOverride'];
    final summary = json['summary'];
    final color = json['backgroundColor'];
    return GoogleCalendar(
      id: id,
      summary: override is String && override.isNotEmpty
          ? override
          : (summary is String && summary.isNotEmpty ? summary : id),
      primary: json['primary'] == true,
      color: color is String && color.startsWith('#') ? color : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GoogleCalendar &&
      other.id == id &&
      other.summary == summary &&
      other.primary == primary &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, summary, primary, color);
}

/// One occurrence of an event. `singleEvents=true` expands a recurring event
/// into instances, each with an id of its own.
class GoogleEvent {
  const GoogleEvent({
    required this.id,
    required this.calendarId,
    required this.summary,
    required this.start,
    required this.end,
    this.allDay = false,
    this.cancelled = false,
    this.htmlLink,
    this.meetingLink,
  });

  final String id;
  final String calendarId;
  final String summary;

  /// Local wall-clock time. For an all-day event, midnight of its first day.
  final DateTime start;

  /// Exclusive. For an all-day event, midnight of the day after its last.
  final DateTime end;

  final bool allDay;
  final bool cancelled;

  /// The event's page on calendar.google.com.
  final String? htmlLink;

  /// Where to join it: Meet, or a video link from conference data or the
  /// location. Null for an event that is not a call.
  final String? meetingLink;

  /// Unique across every calendar the shell reads.
  String get key => '$calendarId/$id';

  /// Whether any of it falls on the local day starting at [day] (midnight).
  bool overlapsDay(DateTime day) {
    final next = DateTime(day.year, day.month, day.day + 1);
    return start.isBefore(next) && end.isAfter(day) ||
        // A zero-length event at the day's midnight still belongs to it.
        (start == end && !start.isBefore(day) && start.isBefore(next));
  }

  /// Parses one `events.list` item. Null for a row that cannot be an event: no
  /// id, or no start the shell can place.
  static GoogleEvent? fromJson(Object? json, String calendarId) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final start = _parseWhen(json['start']);
    if (start == null) return null;
    final end = _parseWhen(json['end']);
    final summary = json['summary'];
    final html = json['htmlLink'];
    return GoogleEvent(
      id: id,
      calendarId: calendarId,
      summary: summary is String && summary.trim().isNotEmpty
          ? summary.trim()
          : '(No title)',
      start: start.at,
      // A missing or backwards end costs the duration, not the event.
      end: end == null || end.at.isBefore(start.at) ? start.at : end.at,
      allDay: start.allDay,
      cancelled: json['status'] == 'cancelled',
      htmlLink: html is String && _isWebUrl(html) ? html : null,
      meetingLink: meetingLinkOf(json),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GoogleEvent &&
      other.id == id &&
      other.calendarId == calendarId &&
      other.summary == summary &&
      other.start == start &&
      other.end == end &&
      other.allDay == allDay &&
      other.cancelled == cancelled &&
      other.htmlLink == htmlLink &&
      other.meetingLink == meetingLink;

  @override
  int get hashCode => Object.hash(
    id,
    calendarId,
    summary,
    start,
    end,
    allDay,
    cancelled,
    htmlLink,
    meetingLink,
  );
}

/// Where to join an event, in the order Google's own UI prefers: the Meet link,
/// then a video entry point from conference data (Zoom, Teams and the rest put
/// theirs there through add-ons), then the first web link in the location —
/// which is where a pasted Zoom link usually ends up.
String? meetingLinkOf(Map<dynamic, dynamic> json) {
  final hangout = json['hangoutLink'];
  if (hangout is String && _isWebUrl(hangout)) return hangout;
  final conference = json['conferenceData'];
  if (conference is Map) {
    final points = conference['entryPoints'];
    if (points is List) {
      for (final point in points) {
        if (point is! Map || point['entryPointType'] != 'video') continue;
        final uri = point['uri'];
        if (uri is String && _isWebUrl(uri)) return uri;
      }
    }
  }
  final location = json['location'];
  if (location is String) {
    final match = RegExp(r'https?://[^\s<>"]+').firstMatch(location);
    if (match != null) return match.group(0);
  }
  return null;
}

bool _isWebUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty;
}

/// `{"dateTime": "2026-09-25T10:00:00+02:00"}` or `{"date": "2026-09-25"}`.
({DateTime at, bool allDay})? _parseWhen(Object? json) {
  if (json is! Map) return null;
  final dateTime = json['dateTime'];
  if (dateTime is String) {
    final parsed = DateTime.tryParse(dateTime);
    if (parsed != null) return (at: parsed.toLocal(), allDay: false);
  }
  final date = json['date'];
  if (date is String) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
    if (match != null) {
      return (
        at: DateTime(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
        ),
        allDay: true,
      );
    }
  }
  return null;
}

/// The seam the stores talk through. One implementation talks to Google;
/// tests supply their own.
abstract class GoogleClient {
  /// Trades an authorization code for tokens.
  Future<GoogleTokens> exchangeCode({
    required String clientId,
    required String clientSecret,
    required String code,
    required String codeVerifier,
    required String redirectUri,
  });

  /// A fresh access token for [refreshToken].
  Future<GoogleTokens> refreshAccessToken({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  });

  /// Revokes [token] — a refresh token revokes the whole grant.
  Future<void> revoke(String token);

  /// The user's calendar list.
  Future<List<GoogleCalendar>> listCalendars(String accessToken);

  /// Every occurrence overlapping [from]–[to] on [calendarId], cancelled ones
  /// included, in start order.
  Future<List<GoogleEvent>> listEvents({
    required String accessToken,
    required String calendarId,
    required DateTime from,
    required DateTime to,
  });
}

/// [GoogleClient] over HTTPS.
class HttpGoogleClient implements GoogleClient {
  const HttpGoogleClient({http.Client? httpClient}) : _client = httpClient;

  final http.Client? _client;

  /// A bound on paging, so a calendar with an enormous month cannot keep the
  /// shell fetching forever. 250 per page, so 2500 events.
  static const int _maxPages = 10;

  static final Uri _tokenUrl = Uri.https('oauth2.googleapis.com', '/token');

  Future<http.Response> _post(Uri url, Map<String, String> body) async {
    final client = _client;
    try {
      return client == null
          ? await http.post(url, body: body)
          : await client.post(url, body: body);
    } catch (_) {
      throw GoogleException('Could not reach ${url.host}');
    }
  }

  Future<http.Response> _get(Uri url, String accessToken) async {
    final headers = {'Authorization': 'Bearer $accessToken'};
    final client = _client;
    try {
      return client == null
          ? await http.get(url, headers: headers)
          : await client.get(url, headers: headers);
    } catch (_) {
      throw GoogleException('Could not reach ${url.host}');
    }
  }

  static Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  /// The token endpoint's failures. `invalid_grant` is the dead refresh token;
  /// `invalid_client` is a client ID or secret typed wrong, which no retry
  /// fixes either.
  static Never _failToken(http.Response response) {
    final json = _decode(response);
    final error = json['error'];
    final description = json['error_description'];
    if (error == 'invalid_grant') {
      throw const GoogleAuthException(
        'Google sign-in expired or was revoked — sign in again',
      );
    }
    if (error == 'invalid_client' || error == 'unauthorized_client') {
      throw const GoogleAuthException(
        'Google rejected the client ID or secret',
      );
    }
    throw GoogleException(
      description is String && description.isNotEmpty
          ? 'Google: $description'
          : 'oauth2.googleapis.com answered ${response.statusCode}',
    );
  }

  /// The Calendar API's failures. Its error body carries a sentence worth
  /// showing — "Google Calendar API has not been used in project … before or
  /// it is disabled" is the one a new client hits first.
  static Never _failApi(Uri url, http.Response response) {
    if (response.statusCode == 401) {
      throw const GoogleAuthException('Google rejected the sign-in');
    }
    final error = _decode(response)['error'];
    if (error is Map && error['message'] is String) {
      throw GoogleException('Google Calendar: ${error['message']}');
    }
    throw GoogleException('${url.host} answered ${response.statusCode}');
  }

  @override
  Future<GoogleTokens> exchangeCode({
    required String clientId,
    required String clientSecret,
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final response = await _post(_tokenUrl, {
      'grant_type': 'authorization_code',
      'client_id': clientId,
      'client_secret': clientSecret,
      'code': code,
      'code_verifier': codeVerifier,
      'redirect_uri': redirectUri,
    });
    if (response.statusCode != 200) _failToken(response);
    final tokens = GoogleTokens.fromJson(_decode(response), DateTime.now());
    if (tokens == null) {
      throw const GoogleException('Google sent no access token');
    }
    return tokens;
  }

  @override
  Future<GoogleTokens> refreshAccessToken({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) async {
    final response = await _post(_tokenUrl, {
      'grant_type': 'refresh_token',
      'client_id': clientId,
      'client_secret': clientSecret,
      'refresh_token': refreshToken,
    });
    if (response.statusCode != 200) _failToken(response);
    final tokens = GoogleTokens.fromJson(_decode(response), DateTime.now());
    if (tokens == null) {
      throw const GoogleException('Google sent no access token');
    }
    return tokens;
  }

  @override
  Future<void> revoke(String token) async {
    // Best-effort: a grant already revoked answers 400, which is the outcome
    // asked for.
    await _post(Uri.https('oauth2.googleapis.com', '/revoke'), {
      'token': token,
    });
  }

  @override
  Future<List<GoogleCalendar>> listCalendars(String accessToken) async {
    final calendars = <GoogleCalendar>[];
    String? pageToken;
    for (var page = 0; page < _maxPages; page++) {
      final url = Uri.https(
        'www.googleapis.com',
        '/calendar/v3/users/me/calendarList',
        {'maxResults': '250', 'pageToken': ?pageToken},
      );
      final response = await _get(url, accessToken);
      if (response.statusCode != 200) _failApi(url, response);
      final json = _decode(response);
      calendars.addAll(parseCalendarList(json));
      final next = json['nextPageToken'];
      if (next is! String || next.isEmpty) break;
      pageToken = next;
    }
    return calendars;
  }

  @override
  Future<List<GoogleEvent>> listEvents({
    required String accessToken,
    required String calendarId,
    required DateTime from,
    required DateTime to,
  }) async {
    final events = <GoogleEvent>[];
    String? pageToken;
    for (var page = 0; page < _maxPages; page++) {
      final url = Uri.https(
        'www.googleapis.com',
        '/calendar/v3/calendars/${Uri.encodeComponent(calendarId)}/events',
        {
          'timeMin': from.toUtc().toIso8601String(),
          'timeMax': to.toUtc().toIso8601String(),
          'singleEvents': 'true',
          'orderBy': 'startTime',
          'showDeleted': 'true',
          'maxResults': '250',
          'pageToken': ?pageToken,
        },
      );
      final response = await _get(url, accessToken);
      if (response.statusCode != 200) _failApi(url, response);
      final json = _decode(response);
      events.addAll(parseEventList(json, calendarId));
      final next = json['nextPageToken'];
      if (next is! String || next.isEmpty) break;
      pageToken = next;
    }
    return events;
  }
}

/// The `items` of a calendar-list page; a bad row costs that row.
List<GoogleCalendar> parseCalendarList(Map<String, dynamic> json) => [
  if (json['items'] case final List<Object?> items)
    for (final item in items) ?GoogleCalendar.fromJson(item),
];

/// The `items` of an events page; a bad row costs that row.
List<GoogleEvent> parseEventList(
  Map<String, dynamic> json,
  String calendarId,
) => [
  if (json['items'] case final List<Object?> items)
    for (final item in items) ?GoogleEvent.fromJson(item, calendarId),
];
