import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:moonswing/google/google_api.dart';

/// The parsing a shape change at Google would otherwise turn into a crash, and
/// the status codes that decide whether the account signs out.
void main() {
  group('GoogleEvent.fromJson', () {
    test('a timed event is placed in local time', () {
      final event = GoogleEvent.fromJson({
        'id': 'abc',
        'summary': ' Standup ',
        'start': {'dateTime': '2026-09-25T10:00:00Z'},
        'end': {'dateTime': '2026-09-25T10:15:00Z'},
        'htmlLink': 'https://www.google.com/calendar/event?eid=abc',
      }, 'primary')!;
      expect(event.key, 'primary/abc');
      expect(event.summary, 'Standup');
      expect(event.start, DateTime.utc(2026, 9, 25, 10).toLocal());
      expect(event.end.difference(event.start), const Duration(minutes: 15));
      expect(event.allDay, isFalse);
      expect(event.cancelled, isFalse);
      expect(event.htmlLink, startsWith('https://www.google.com/'));
      expect(event.meetingLink, isNull);
    });

    test('an all-day event runs midnight to midnight, end exclusive', () {
      final event = GoogleEvent.fromJson({
        'id': 'holiday',
        'start': {'date': '2026-12-25'},
        'end': {'date': '2026-12-26'},
      }, 'primary')!;
      expect(event.allDay, isTrue);
      expect(event.start, DateTime(2026, 12, 25));
      expect(event.end, DateTime(2026, 12, 26));
      expect(event.summary, '(No title)');
      expect(event.overlapsDay(DateTime(2026, 12, 25)), isTrue);
      expect(event.overlapsDay(DateTime(2026, 12, 26)), isFalse);
      expect(event.overlapsDay(DateTime(2026, 12, 24)), isFalse);
    });

    test('a cancelled occurrence says so', () {
      final event = GoogleEvent.fromJson({
        'id': 'x',
        'status': 'cancelled',
        'start': {'dateTime': '2026-09-25T10:00:00Z'},
        'end': {'dateTime': '2026-09-25T11:00:00Z'},
      }, 'primary')!;
      expect(event.cancelled, isTrue);
    });

    test('a row with no id or no start costs that row alone', () {
      expect(GoogleEvent.fromJson({'start': {}}, 'c'), isNull);
      expect(GoogleEvent.fromJson({'id': 'a'}, 'c'), isNull);
      expect(GoogleEvent.fromJson('nope', 'c'), isNull);
      final events = parseEventList({
        'items': [
          7,
          {
            'id': 'good',
            'start': {'date': '2026-01-01'},
          },
          {
            'id': 'bad',
            'start': {'dateTime': 'yesterday'},
          },
        ],
      }, 'c');
      expect(events.map((e) => e.id), ['good']);
    });

    test('an end before the start costs the duration, not the event', () {
      final event = GoogleEvent.fromJson({
        'id': 'x',
        'start': {'dateTime': '2026-09-25T10:00:00Z'},
        'end': {'dateTime': '2026-09-25T09:00:00Z'},
      }, 'c')!;
      expect(event.end, event.start);
    });
  });

  group('event details', () {
    test('description, location, colour, attachments and links', () {
      final e = GoogleEvent.fromJson({
        'id': 'x',
        'iCalUID': 'uid@google.com',
        'start': {'dateTime': '2026-09-25T10:00:00Z'},
        'end': {'dateTime': '2026-09-25T10:30:00Z'},
        'colorId': '11',
        'location': ' Room 4 ',
        'hangoutLink': 'https://meet.google.com/abc-defg-hij',
        'conferenceData': {
          'conferenceSolution': {'name': 'Google Meet'},
        },
        'description':
            'Agenda:<br><ul><li>Plan &amp; review</li></ul>'
            '<a href="https://docs.google.com/document/d/1">the doc</a> '
            'and https://example.com/page.',
        'attachments': [
          {'fileUrl': 'https://drive.google.com/file/d/2', 'title': 'Slides'},
          {'fileUrl': 'not a url'},
        ],
      }, 'primary')!;
      expect(e.description, contains('• Plan & review'));
      expect(e.description, isNot(contains('<')));
      expect(e.location, 'Room 4');
      expect(e.color, '#d50000');
      expect(e.iCalUid, 'uid@google.com');
      expect(e.meetingName, 'Google Meet');
      expect(e.attachments, [
        const GoogleLink(
          label: 'Slides',
          url: 'https://drive.google.com/file/d/2',
        ),
      ]);
      expect(e.links.map((l) => (l.label, l.url)), [
        ('Slides', 'https://drive.google.com/file/d/2'),
        ('Google Doc', 'https://docs.google.com/document/d/1'),
        ('example.com', 'https://example.com/page'),
      ]);
    });

    test('a primary calendar is keyed by its account', () {
      final e = GoogleEvent.fromJson({
        'id': 'x',
        'start': {'date': '2026-09-25'},
      }, 'primary')!;
      expect(e.key, 'primary/x');
      expect(e.legacyKey, isNull);
      final read = e.withAccount('me@example.com');
      expect(read.key, 'me@example.com/x');
      expect(read.legacyKey, 'primary/x');
      final shared = GoogleEvent.fromJson({
        'id': 'y',
        'start': {'date': '2026-09-25'},
      }, 'team')!.withAccount('me@example.com');
      expect(shared.key, 'team/y');
      expect(shared.legacyKey, isNull);
    });
  });

  group('meetingLinkOf', () {
    test('prefers Meet, then a video entry point, then the location', () {
      expect(
        meetingLinkOf({
          'hangoutLink': 'https://meet.google.com/abc-defg-hij',
          'location': 'https://zoom.us/j/1',
        }),
        'https://meet.google.com/abc-defg-hij',
      );
      expect(
        meetingLinkOf({
          'conferenceData': {
            'entryPoints': [
              {'entryPointType': 'phone', 'uri': 'tel:+1-555'},
              {'entryPointType': 'video', 'uri': 'https://zoom.us/j/42'},
            ],
          },
        }),
        'https://zoom.us/j/42',
      );
      expect(
        meetingLinkOf({'location': 'Room 4 / https://teams.microsoft.com/l/x'}),
        'https://teams.microsoft.com/l/x',
      );
      expect(meetingLinkOf({'location': 'Room 4'}), isNull);
      expect(meetingLinkOf({'hangoutLink': 'javascript:alert(1)'}), isNull);
    });
  });

  group('GoogleCalendar.fromJson', () {
    test('the user\'s own name for a calendar wins', () {
      final calendar = GoogleCalendar.fromJson({
        'id': 'team@group.calendar.google.com',
        'summary': 'Team',
        'summaryOverride': 'Work',
        'backgroundColor': '#9fe1e7',
      })!;
      expect(calendar.summary, 'Work');
      expect(calendar.primary, isFalse);
      expect(calendar.color, '#9fe1e7');
      expect(
        parseCalendarList({
          'items': [
            {'id': 'me@example.com', 'summary': 'Me', 'primary': true},
            {'summary': 'no id'},
          ],
        }).single.primary,
        isTrue,
      );
    });
  });

  group('HttpGoogleClient', () {
    test('a dead refresh token is an auth failure', () async {
      final client = HttpGoogleClient(
        httpClient: MockClient(
          (request) async =>
              http.Response(jsonEncode({'error': 'invalid_grant'}), 400),
        ),
      );
      await expectLater(
        client.refreshAccessToken(
          clientId: 'id',
          clientSecret: 'secret',
          refreshToken: 'r',
        ),
        throwsA(isA<GoogleAuthException>()),
      );
    });

    test(
      'the code exchange sends the verifier and keeps the refresh token',
      () async {
        late Map<String, String> sent;
        final client = HttpGoogleClient(
          httpClient: MockClient((request) async {
            sent = Uri.splitQueryString(request.body);
            return http.Response(
              jsonEncode({
                'access_token': 'a',
                'expires_in': 3599,
                'refresh_token': 'r',
              }),
              200,
            );
          }),
        );
        final tokens = await client.exchangeCode(
          clientId: 'id',
          clientSecret: 'secret',
          code: 'c',
          codeVerifier: 'v',
          redirectUri: 'http://127.0.0.1:1234',
        );
        expect(sent['grant_type'], 'authorization_code');
        expect(sent['code_verifier'], 'v');
        expect(sent['redirect_uri'], 'http://127.0.0.1:1234');
        expect(tokens.accessToken, 'a');
        expect(tokens.refreshToken, 'r');
      },
    );

    test('events are paged, and the API\'s own message is kept', () async {
      var calls = 0;
      final client = HttpGoogleClient(
        httpClient: MockClient((request) async {
          calls++;
          expect(request.headers['Authorization'], 'Bearer t');
          expect(request.url.queryParameters['singleEvents'], 'true');
          if (request.url.queryParameters['pageToken'] == null) {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': 'one',
                    'start': {'date': '2026-09-25'},
                  },
                ],
                'nextPageToken': 'p2',
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'two',
                  'start': {'date': '2026-09-26'},
                },
              ],
            }),
            200,
          );
        }),
      );
      final events = await client.listEvents(
        accessToken: 't',
        calendarId: 'team@group.calendar.google.com',
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 10, 1),
      );
      expect(calls, 2);
      expect(events.map((e) => e.key), [
        'team@group.calendar.google.com/one',
        'team@group.calendar.google.com/two',
      ]);

      final disabled = HttpGoogleClient(
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'error': {'message': 'Google Calendar API has not been used'},
            }),
            403,
          ),
        ),
      );
      await expectLater(
        disabled.listCalendars('t'),
        throwsA(
          isA<GoogleException>()
              .having((e) => e is GoogleAuthException, 'auth', isFalse)
              .having((e) => e.message, 'message', contains('not been used')),
        ),
      );
    });

    test('a calendar id is encoded once, not twice', () async {
      const id = 'en.usa#holiday@group.v.calendar.google.com';
      late Uri seen;
      final client = HttpGoogleClient(
        httpClient: MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode({'items': []}), 200);
        }),
      );
      await client.listEvents(
        accessToken: 't',
        calendarId: id,
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 10, 1),
      );
      // Encoded twice, `@` went out as `%2540`, and Google answered 404 for
      // every calendar but `primary`.
      expect(seen.toString(), isNot(contains('%25')));
      expect(seen.pathSegments, ['calendar', 'v3', 'calendars', id, 'events']);
    });
  });
}
