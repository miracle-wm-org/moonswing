import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:http/http.dart' as http;

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/calendar/event.dart';
import 'package:graceful_shell/overlay/calendar/google_oauth.dart';
import 'package:graceful_shell/overlay/calendar/provider.dart';
import 'package:graceful_shell/overlay/calendar/token_store.dart';

const String _kApiBase = 'https://www.googleapis.com/calendar/v3';

/// How long the calendar list is trusted before being re-fetched. Users add and
/// remove calendars rarely; their *events* are what change minute to minute.
const Duration _kCalendarListTtl = Duration(hours: 1);

/// Reads events from Google Calendar over the REST API.
class GoogleCalendarProvider implements CalendarProvider {
  GoogleCalendarProvider({
    required GoogleOAuthConfig config,
    required CalendarTokenStore tokenStore,
    http.Client? httpClient,
    DateTime Function()? now,
  })  : _config = config,
        _tokenStore = tokenStore,
        _http = httpClient ?? http.Client(),
        _now = now ?? DateTime.now;

  GoogleOAuthConfig _config;
  final CalendarTokenStore _tokenStore;
  final http.Client _http;
  final DateTime Function() _now;

  OAuthTokens? _tokens;
  GoogleOAuthFlow? _flow;

  List<_GoogleCalendar>? _calendars;
  DateTime? _calendarsFetchedAt;

  @override
  String get id => 'google';

  @override
  CalendarProviderKind get kind => CalendarProviderKind.google;

  @override
  bool get isConfigured => _config.isComplete;

  @override
  bool get isConnected => _tokens != null;

  @override
  CalendarAccount? get account {
    final tokens = _tokens;
    if (tokens == null) return null;
    return CalendarAccount(
      id: id,
      kind: kind,
      label: 'Google Calendar',
      email: tokens.email,
    );
  }

  /// Picks up credentials edited in the settings UI without a shell restart.
  void updateConfig(GoogleOAuthConfig config) => _config = config;

  @override
  Future<void> restore() async {
    _tokens = (await _tokenStore.loadAll())[id];
  }

  @override
  Future<void> connect({void Function(Uri url)? onUrl}) async {
    if (!isConfigured) {
      throw const CalendarAuthException(
          'Add a Google OAuth client ID and secret before connecting.');
    }

    final flow = GoogleOAuthFlow(
      clientId: _config.clientId,
      clientSecret: _config.clientSecret,
      httpClient: _http,
    );
    _flow = flow;

    try {
      final tokens = await flow.authorize(onUrl: onUrl);
      _tokens = tokens;
      await _tokenStore.save(id, tokens);
    } finally {
      _flow = null;
    }
  }

  /// Aborts an in-flight [connect].
  Future<void> cancelConnect() async => _flow?.cancel();

  @override
  Future<void> disconnect() async {
    final tokens = _tokens;
    if (tokens != null && _config.isComplete) {
      await GoogleOAuthFlow(
        clientId: _config.clientId,
        clientSecret: _config.clientSecret,
        httpClient: _http,
      ).revoke(tokens);
    }
    await _forget();
  }

  Future<void> _forget() async {
    _tokens = null;
    _calendars = null;
    _calendarsFetchedAt = null;
    await _tokenStore.clear(id);
  }

  /// A live access token, refreshing first if the current one is spent.
  ///
  /// A dead grant (revoked in the Google account UI, or expired after months
  /// idle) drops the account entirely, so the UI falls back to the connect pane
  /// rather than retrying a request that can never succeed.
  Future<String> _accessToken() async {
    final tokens = _tokens;
    if (tokens == null) {
      throw const CalendarAuthException('Google Calendar is not connected.');
    }
    if (!tokens.isExpired(now: _now())) return tokens.accessToken;

    final flow = GoogleOAuthFlow(
      clientId: _config.clientId,
      clientSecret: _config.clientSecret,
      httpClient: _http,
    );

    try {
      final refreshed = await flow.refresh(tokens);
      _tokens = refreshed;
      await _tokenStore.save(id, refreshed);
      return refreshed.accessToken;
    } on CalendarAuthException {
      await _forget();
      rethrow;
    }
  }

  @override
  Future<List<CalendarEvent>> fetchEvents(DateTime from, DateTime to) async {
    final calendars = await _fetchCalendars();

    final events = <CalendarEvent>[];
    for (final calendar in calendars) {
      events.addAll(await _fetchCalendarEvents(calendar, from, to));
    }
    return events;
  }

  Future<List<_GoogleCalendar>> _fetchCalendars() async {
    final cached = _calendars;
    final fetchedAt = _calendarsFetchedAt;
    if (cached != null &&
        fetchedAt != null &&
        _now().difference(fetchedAt) < _kCalendarListTtl) {
      return cached;
    }

    final body = await _get(Uri.parse('$_kApiBase/users/me/calendarList'));
    final items = body['items'] as List<dynamic>? ?? const [];

    final calendars = <_GoogleCalendar>[];
    for (final item in items.whereType<Map<String, dynamic>>()) {
      // 'selected' is the checkbox in Google's own UI: honouring it means the
      // calendars a user has hidden there stay hidden here too.
      if (item['selected'] != true) continue;
      final calendarId = item['id'] as String?;
      if (calendarId == null) continue;

      calendars.add(_GoogleCalendar(
        id: calendarId,
        color: _parseHexColor(item['backgroundColor'] as String?),
      ));
    }

    _calendars = calendars;
    _calendarsFetchedAt = _now();
    return calendars;
  }

  Future<List<CalendarEvent>> _fetchCalendarEvents(
    _GoogleCalendar calendar,
    DateTime from,
    DateTime to,
  ) async {
    final events = <CalendarEvent>[];
    String? pageToken;

    do {
      final uri = Uri.parse(
        '$_kApiBase/calendars/${Uri.encodeComponent(calendar.id)}/events',
      ).replace(queryParameters: {
        'timeMin': from.toUtc().toIso8601String(),
        'timeMax': to.toUtc().toIso8601String(),
        // Expand recurring events into concrete instances; without this a weekly
        // standup arrives as a single rule the shell would have to expand itself.
        'singleEvents': 'true',
        'orderBy': 'startTime',
        'maxResults': '250',
        if (pageToken != null) 'pageToken': pageToken,
      });

      final body = await _get(uri);
      final items = body['items'] as List<dynamic>? ?? const [];
      for (final item in items.whereType<Map<String, dynamic>>()) {
        final event = parseGoogleEvent(
          item,
          calendarId: calendar.id,
          color: calendar.color,
        );
        if (event != null) events.add(event);
      }

      pageToken = body['nextPageToken'] as String?;
    } while (pageToken != null);

    return events;
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final token = await _accessToken();

    http.Response response;
    try {
      response = await _http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
    } on SocketException catch (e) {
      throw CalendarFetchException('Could not reach Google Calendar: ${e.message}');
    } on http.ClientException catch (e) {
      throw CalendarFetchException('Could not reach Google Calendar: ${e.message}');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      // The token was accepted at refresh but rejected here: the grant is gone.
      await _forget();
      throw const CalendarAuthException(
          'Google rejected the saved sign-in. Please reconnect.');
    }
    if (response.statusCode != 200) {
      throw CalendarFetchException(
          'Google Calendar returned HTTP ${response.statusCode}.');
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const CalendarFetchException(
          'Google Calendar returned an unreadable response.');
    }
  }
}

/// Turns one Google event resource into a [CalendarEvent], or null if it is not
/// something the agenda can show (cancelled, or missing its start).
///
/// Public because this mapping is where the subtle bugs live — exclusive end
/// dates, timezone offsets — so it is tested directly.
CalendarEvent? parseGoogleEvent(
  Map<String, dynamic> json, {
  required String calendarId,
  Color? color,
}) {
  if (json['status'] == 'cancelled') return null;

  final id = json['id'] as String?;
  final start = json['start'] as Map<String, dynamic>?;
  final end = json['end'] as Map<String, dynamic>?;
  if (id == null || start == null || end == null) return null;

  final startDate = start['date'] as String?;
  if (startDate != null) {
    // All-day. Google's end.date is *exclusive* — a single-day event on the 13th
    // arrives as start 13th, end 14th — so step back a day for an inclusive end.
    final endDate = end['date'] as String? ?? startDate;
    final first = DateTime.parse(startDate);
    final exclusiveEnd = DateTime.parse(endDate);
    final last = exclusiveEnd.isAfter(first)
        ? DateTime(exclusiveEnd.year, exclusiveEnd.month, exclusiveEnd.day - 1)
        : first;

    return CalendarEvent(
      id: id,
      calendarId: calendarId,
      title: json['summary'] as String? ?? '(No title)',
      start: DateTime(first.year, first.month, first.day),
      end: DateTime(last.year, last.month, last.day),
      allDay: true,
      location: json['location'] as String?,
      color: color,
    );
  }

  final startTime = start['dateTime'] as String?;
  final endTime = end['dateTime'] as String?;
  if (startTime == null) return null;

  final startLocal = DateTime.parse(startTime).toLocal();
  final endLocal =
      endTime != null ? DateTime.parse(endTime).toLocal() : startLocal;

  return CalendarEvent(
    id: id,
    calendarId: calendarId,
    title: json['summary'] as String? ?? '(No title)',
    start: startLocal,
    end: endLocal,
    location: json['location'] as String?,
    color: color,
  );
}

/// Parses Google's `#rrggbb` calendar colours.
Color? _parseHexColor(String? hex) {
  if (hex == null) return null;
  final cleaned = hex.replaceFirst('#', '');
  if (cleaned.length != 6) return null;
  final value = int.tryParse(cleaned, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

class _GoogleCalendar {
  const _GoogleCalendar({required this.id, this.color});
  final String id;
  final Color? color;
}
