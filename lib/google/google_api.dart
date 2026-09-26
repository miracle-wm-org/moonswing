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

/// A titled link on an event: an attachment, or a web address found in its
/// description or location.
class GoogleLink {
  const GoogleLink({required this.label, required this.url});

  final String label;
  final String url;

  @override
  bool operator ==(Object other) =>
      other is GoogleLink && other.label == label && other.url == url;

  @override
  int get hashCode => Object.hash(label, url);
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
    this.account = '',
    this.allDay = false,
    this.cancelled = false,
    this.htmlLink,
    this.meetingLink,
    this.meetingName,
    this.description,
    this.location,
    this.color,
    this.iCalUid,
    this.attachments = const [],
    this.descriptionLinks = const [],
  });

  final String id;

  /// The calendar as it was asked for: `primary`, or the calendar's own id.
  final String calendarId;

  /// The signed-in account it was read through, or empty when unknown. Set by
  /// the store, since the API answers per calendar and not per account.
  final String account;

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

  /// What [meetingLink] is, as conference data names it ("Google Meet",
  /// "Zoom Meeting"), or null when it does not say.
  final String? meetingName;

  /// The description as plain text: Google stores what its own editor wrote,
  /// which is HTML.
  final String? description;

  final String? location;

  /// `#rrggbb` from the event's own colour, or null for the calendar's.
  final String? color;

  /// The same meeting's id in every calendar it was sent to, so an invitation
  /// read through two accounts can be recognised as one meeting.
  final String? iCalUid;

  /// Files attached in Google Calendar (usually Drive documents).
  final List<GoogleLink> attachments;

  /// The anchors' addresses in an HTML description, which its plain text
  /// loses: a link's text need not be its address.
  final List<String> descriptionLinks;

  /// Unique across every calendar of every account the shell reads.
  ///
  /// A primary calendar asked for as `primary` is keyed by the account, which
  /// is also the primary calendar's real id, so either spelling of the same
  /// calendar gives the same key.
  String get key => '${_calendarKey()}/$id';

  String _calendarKey() =>
      calendarId == 'primary' && account.isNotEmpty ? account : calendarId;

  /// The key a single-account build gave the same occurrence: a primary
  /// calendar was keyed as `primary`. Null when that is [key] already.
  String? get legacyKey {
    final legacy = '$calendarId/$id';
    return legacy == key ? null : legacy;
  }

  /// Every other link worth offering beside [meetingLink] and [htmlLink]:
  /// attachments, then web addresses in the location and the description.
  List<GoogleLink> get links {
    final seen = <String>{?meetingLink, ?htmlLink};
    final out = <GoogleLink>[];
    void add(GoogleLink link) {
      if (seen.add(link.url)) out.add(link);
    }

    attachments.forEach(add);
    for (final url in descriptionLinks) {
      add(GoogleLink(label: linkLabel(url), url: url));
    }
    for (final text in [?location, ?description]) {
      for (final url in findWebUrls(text)) {
        add(GoogleLink(label: linkLabel(url), url: url));
      }
    }
    return out;
  }

  /// Whether any of it falls on the local day starting at [day] (midnight).
  bool overlapsDay(DateTime day) {
    final next = DateTime(day.year, day.month, day.day + 1);
    return start.isBefore(next) && end.isAfter(day) ||
        // A zero-length event at the day's midnight still belongs to it.
        (start == end && !start.isBefore(day) && start.isBefore(next));
  }

  /// This occurrence read through [account].
  GoogleEvent withAccount(String account) => GoogleEvent(
    id: id,
    calendarId: calendarId,
    summary: summary,
    start: start,
    end: end,
    account: account,
    allDay: allDay,
    cancelled: cancelled,
    htmlLink: htmlLink,
    meetingLink: meetingLink,
    meetingName: meetingName,
    description: description,
    location: location,
    color: color,
    iCalUid: iCalUid,
    attachments: attachments,
    descriptionLinks: descriptionLinks,
  );

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
    final description = json['description'];
    final location = json['location'];
    final uid = json['iCalUID'];
    final plain = description is String ? plainTextOf(description) : '';
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
      meetingName: _meetingNameOf(json),
      // Links are read off the HTML, where an anchor's address can differ
      // from its text; the text shown is the plain version.
      description: plain.isEmpty ? null : plain,
      location: location is String && location.trim().isNotEmpty
          ? location.trim()
          : null,
      color: googleEventColors[json['colorId']],
      iCalUid: uid is String && uid.isNotEmpty ? uid : null,
      attachments: _attachmentsOf(json['attachments']),
      descriptionLinks: description is String
          ? _hrefsOf(description).toSet().toList()
          : const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GoogleEvent &&
      other.id == id &&
      other.calendarId == calendarId &&
      other.account == account &&
      other.summary == summary &&
      other.start == start &&
      other.end == end &&
      other.allDay == allDay &&
      other.cancelled == cancelled &&
      other.htmlLink == htmlLink &&
      other.meetingLink == meetingLink &&
      other.meetingName == meetingName &&
      other.description == description &&
      other.location == location &&
      other.color == color &&
      other.iCalUid == iCalUid &&
      _listEquals(other.attachments, attachments) &&
      _listEquals(other.descriptionLinks, descriptionLinks);

  @override
  int get hashCode => Object.hash(
    id,
    calendarId,
    account,
    summary,
    start,
    end,
    allDay,
    cancelled,
    htmlLink,
    meetingLink,
    meetingName,
    description,
    location,
    color,
    iCalUid,
    Object.hashAll(attachments),
    Object.hashAll(descriptionLinks),
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Google Calendar's event palette, by `colorId`. Fixed by Google (the
/// `colors` endpoint answers the same table to every account), so it is a
/// constant rather than a request.
const Map<Object?, String> googleEventColors = {
  '1': '#7986cb', // Lavender
  '2': '#33b679', // Sage
  '3': '#8e24aa', // Grape
  '4': '#e67c73', // Flamingo
  '5': '#f6bf26', // Banana
  '6': '#f4511e', // Tangerine
  '7': '#039be5', // Peacock
  '8': '#616161', // Graphite
  '9': '#3f51b5', // Blueberry
  '10': '#0b8043', // Basil
  '11': '#d50000', // Tomato
};

/// The attachments' titles and addresses; a bad row costs that row.
List<GoogleLink> _attachmentsOf(Object? json) => [
  if (json is List)
    for (final item in json)
      if (item is Map &&
          item['fileUrl'] is String &&
          _isWebUrl(item['fileUrl'] as String))
        GoogleLink(
          label: item['title'] is String && (item['title'] as String).isNotEmpty
              ? item['title'] as String
              : linkLabel(item['fileUrl'] as String),
          url: item['fileUrl'] as String,
        ),
];

/// The name conference data gives the call, e.g. "Google Meet".
String? _meetingNameOf(Map<dynamic, dynamic> json) {
  if (json['conferenceData'] case {
    'conferenceSolution': {'name': final String name},
  } when name.trim().isNotEmpty) {
    return name.trim();
  }
  final hangout = json['hangoutLink'];
  if (hangout is String && _isWebUrl(hangout)) return 'Google Meet';
  return null;
}

/// The `href`s of the anchors in an HTML description.
Iterable<String> _hrefsOf(String html) sync* {
  for (final m in RegExp(
    r"""<a\s[^>]*href\s*=\s*["']([^"']+)["']""",
    caseSensitive: false,
  ).allMatches(html)) {
    final url = _decodeEntities(m.group(1)!);
    if (_isWebUrl(url)) yield url;
  }
}

/// Web addresses in plain text, trailing punctuation left off.
Iterable<String> findWebUrls(String text) sync* {
  for (final m in RegExp(r'https?://[^\s<>"]+').allMatches(text)) {
    final url = m.group(0)!.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');
    if (_isWebUrl(url)) yield url;
  }
}

/// A short name for [url]'s button: what the address is, where the shell can
/// tell, else its host.
String linkLabel(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host.toLowerCase() ?? '';
  if (host == 'meet.google.com') return 'Google Meet';
  if (host.endsWith('zoom.us')) return 'Zoom';
  if (host == 'teams.microsoft.com' || host == 'teams.live.com') {
    return 'Microsoft Teams';
  }
  if (host == 'docs.google.com') {
    final kind = uri!.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    return switch (kind) {
      'document' => 'Google Doc',
      'spreadsheets' => 'Google Sheet',
      'presentation' => 'Google Slides',
      'forms' => 'Google Form',
      _ => 'Google Docs',
    };
  }
  if (host == 'drive.google.com') return 'Google Drive';
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// An event description as plain text. Google's editor writes HTML — `<br>`,
/// `<b>`, anchors, lists — while one created over the API or by another client
/// is usually plain text already; both come out as readable lines.
String plainTextOf(String html) {
  var text = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li|h\d)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  text = _decodeEntities(text)
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

String _decodeEntities(String text) => text
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code == null || code > 0x10FFFF
          ? m.group(0)!
          : String.fromCharCode(code);
    })
    // Last, so an escaped entity (`&amp;lt;`) decodes once.
    .replaceAll('&amp;', '&');

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

/// An `events.list` address for [calendarId].
///
/// Built from path *segments*, which are encoded once. `Uri.https` takes an
/// unencoded path and encodes it itself, so a calendar id encoded first went
/// out as `%2540` for its `@` — every calendar but `primary` then answered 404,
/// "Not Found", while `primary`, with nothing to encode, kept working.
Uri eventsUrl(String calendarId, Map<String, String> query) => Uri(
  scheme: 'https',
  host: 'www.googleapis.com',
  pathSegments: ['calendar', 'v3', 'calendars', calendarId, 'events'],
  queryParameters: query,
);

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
      final url = eventsUrl(calendarId, {
        'timeMin': from.toUtc().toIso8601String(),
        'timeMax': to.toUtc().toIso8601String(),
        'singleEvents': 'true',
        'orderBy': 'startTime',
        'showDeleted': 'true',
        'maxResults': '250',
        'pageToken': ?pageToken,
      });
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
