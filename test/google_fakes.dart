import 'dart:async';

import 'package:moonswing/google/google_api.dart';

/// A [GoogleClient] that answers from fields a test sets, and counts.
class FakeGoogleClient implements GoogleClient {
  FakeGoogleClient({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// How long each access token lives.
  Duration tokenLife = const Duration(hours: 1);

  /// Thrown by the next refresh, when set.
  GoogleException? refreshError;

  /// Thrown by every [listEvents] while set.
  GoogleException? eventsError;

  /// Thrown by [listEvents] for one calendar id.
  Map<String, GoogleException> eventsErrors = {};

  /// How many [listEvents] calls should answer 401 before the next succeeds.
  int unauthorizedEvents = 0;

  /// Held open until completed, when set, so a test can see a refresh in
  /// flight.
  Completer<void>? refreshGate;

  List<GoogleCalendar> calendars = const [
    GoogleCalendar(id: 'me@example.com', summary: 'Me', primary: true),
  ];

  /// Per calendar id.
  Map<String, List<GoogleEvent>> events = {};

  /// Per account, by the refresh token its access tokens were minted from.
  /// Answered instead of [calendars] and [events] for an account named here.
  Map<String, List<GoogleCalendar>> calendarsByRefresh = {};
  Map<String, Map<String, List<GoogleEvent>>> eventsByRefresh = {};

  /// Which refresh token each access token was minted from.
  final Map<String, String> _refreshOf = {};

  int exchanges = 0;
  int refreshes = 0;
  int eventCalls = 0;
  final List<String> revoked = [];
  final List<String> accessTokensSeen = [];
  String? lastRedirectUri;

  int _issued = 0;

  GoogleTokens _mint({String? refresh, String? from}) {
    final token = 'access-${++_issued}';
    if (from != null) _refreshOf[token] = from;
    return GoogleTokens(
      accessToken: token,
      expiresAt: _now().add(tokenLife),
      refreshToken: refresh,
    );
  }

  @override
  Future<GoogleTokens> exchangeCode({
    required String clientId,
    required String clientSecret,
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    exchanges++;
    lastRedirectUri = redirectUri;
    return _mint(refresh: 'refresh-for-$code', from: 'refresh-for-$code');
  }

  @override
  Future<GoogleTokens> refreshAccessToken({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) async {
    refreshes++;
    await refreshGate?.future;
    final error = refreshError;
    if (error != null) throw error;
    return _mint(from: refreshToken);
  }

  @override
  Future<void> revoke(String token) async => revoked.add(token);

  @override
  Future<List<GoogleCalendar>> listCalendars(String accessToken) async {
    accessTokensSeen.add(accessToken);
    return [...calendarsByRefresh[_refreshOf[accessToken]] ?? calendars];
  }

  @override
  Future<List<GoogleEvent>> listEvents({
    required String accessToken,
    required String calendarId,
    required DateTime from,
    required DateTime to,
  }) async {
    eventCalls++;
    accessTokensSeen.add(accessToken);
    if (unauthorizedEvents > 0) {
      unauthorizedEvents--;
      throw const GoogleAuthException('Google rejected the sign-in');
    }
    final error = eventsError ?? eventsErrors[calendarId];
    if (error != null) throw error;
    final source = eventsByRefresh[_refreshOf[accessToken]] ?? events;
    return [
      for (final e in source[calendarId] ?? const <GoogleEvent>[])
        if (e.start.isBefore(to) && e.end.isAfter(from)) e,
    ];
  }
}
