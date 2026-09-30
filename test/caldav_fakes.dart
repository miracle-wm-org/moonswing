// A CalDAV server in memory, behind `MockClient`: discovery, the collection's
// change token, `calendar-query`, `calendar-multiget`, and conditional `PUT`
// and `DELETE` — enough of Radicale for the client and the sync to be tested
// against something that refuses a stale write the way a real server does.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeTask {
  FakeTask(this.etag, this.data);
  String etag;
  String data;
}

class FakeCalDavServer {
  FakeCalDavServer({this.sendEtagOnPut = true});

  static const String host = 'https://dav.example.com';
  static const String principal = '/dav/principals/me/';
  static const String home = '/dav/calendars/me/';
  static const String tasksPath = '/dav/calendars/me/tasks/';
  static const String eventsPath = '/dav/calendars/me/events/';
  static Uri get tasksUrl => Uri.parse('$host$tasksPath');
  static Uri get eventsUrl => Uri.parse('$host$eventsPath');

  /// Whether a `PUT` answers with the new ETag. Some servers do not.
  bool sendEtagOnPut;

  /// Answered to every request instead, when set: a server that is down.
  int? failWith;

  final Map<String, FakeTask> tasks = {};

  /// The events calendar's resources, by path. Answered whole to every
  /// `calendar-query`: the time range is the client's to apply as well.
  final Map<String, String> events = {};

  /// The last `calendar-query` sent to the events calendar.
  String? lastEventQuery;
  final List<String> log = [];
  int _version = 0;
  int ctag = 0;

  String _nextEtag() => '"${++_version}"';

  /// Puts a task on the server as another client would.
  String add(String name, String data) {
    final path = '$tasksPath$name';
    tasks[path] = FakeTask(_nextEtag(), data);
    ctag++;
    return path;
  }

  /// Changes a task as another client would.
  void edit(String path, String data) {
    tasks[path]!
      ..data = data
      ..etag = _nextEtag();
    ctag++;
  }

  void remove(String path) {
    tasks.remove(path);
    ctag++;
  }

  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final path = Uri.decodeFull(request.url.path);
    log.add('${request.method} $path');
    if (failWith case final code?) return http.Response('', code);
    final auth = request.headers['Authorization'];
    if (auth != 'Basic ${base64Encode(utf8.encode('me:secret'))}') {
      return http.Response('', 401);
    }
    switch (request.method) {
      case 'PROPFIND':
        return _propfind(path, request);
      case 'REPORT':
        return _report(path, request.body);
      case 'PUT':
        return _put(path, request);
      case 'DELETE':
        return _delete(path, request);
    }
    return http.Response('', 405);
  }

  http.Response _multistatus(String body) => http.Response(
    '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" '
    'xmlns:c="urn:ietf:params:xml:ns:caldav" '
    'xmlns:cs="http://calendarserver.org/ns/" '
    'xmlns:a="http://apple.com/ns/ical/">$body</d:multistatus>',
    207,
    headers: {'content-type': 'application/xml; charset=utf-8'},
  );

  String _response(String href, String props) =>
      '<d:response><d:href>$href</d:href><d:propstat><d:prop>$props'
      '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
      '</d:response>';

  String _calendar(String href, String name, String comp, String color) =>
      _response(
        href,
        '<d:resourcetype><d:collection/><c:calendar/></d:resourcetype>'
        '<d:displayname>$name</d:displayname>'
        '<c:supported-calendar-component-set><c:comp name="$comp"/>'
        '</c:supported-calendar-component-set>'
        '<a:calendar-color>$color</a:calendar-color>',
      );

  http.Response _propfind(String path, http.Request request) {
    final depth = request.headers['Depth'];
    if (path == '/.well-known/caldav') {
      return http.Response('', 301, headers: {'location': '/dav/'});
    }
    if (path == '/' || path == '/dav/') {
      return _multistatus(
        _response(
          path,
          '<d:resourcetype><d:collection/></d:resourcetype>'
          '<d:current-user-principal><d:href>$principal</d:href>'
          '</d:current-user-principal>',
        ),
      );
    }
    if (path == principal) {
      return _multistatus(
        _response(
          principal,
          '<c:calendar-home-set><d:href>$home</d:href></c:calendar-home-set>',
        ),
      );
    }
    if (path == home) {
      final body = StringBuffer(
        _response(home, '<d:resourcetype><d:collection/></d:resourcetype>'),
      );
      if (depth == '1') {
        body
          ..write(_calendar(tasksPath, 'Home tasks', 'VTODO', '#FF8800FF'))
          ..write(_calendar(eventsPath, 'Home calendar', 'VEVENT', '#0000FF'));
      }
      return _multistatus(body.toString());
    }
    if (path == tasksPath) {
      if (request.body.contains('getctag')) {
        return _multistatus(
          _response(
            tasksPath,
            '<cs:getctag>c$ctag</cs:getctag>'
            '<d:sync-token>http://example.com/sync/$ctag</d:sync-token>',
          ),
        );
      }
      return _multistatus(
        _calendar(tasksPath, 'Home tasks', 'VTODO', '#FF8800FF'),
      );
    }
    return http.Response('', 404);
  }

  http.Response _report(String path, String body) {
    if (path == eventsPath && body.contains('calendar-query')) {
      lastEventQuery = body;
      return _multistatus(
        [
          for (final e in events.entries)
            _response(
              e.key,
              '<d:getetag>"e"</d:getetag>'
              '<c:calendar-data>${_escape(e.value)}</c:calendar-data>',
            ),
        ].join(),
      );
    }
    if (path != tasksPath) return http.Response('', 404);
    if (body.contains('calendar-query')) {
      return _multistatus(
        [
          for (final e in tasks.entries)
            if (e.value.data.contains('BEGIN:VTODO'))
              _response(e.key, '<d:getetag>${e.value.etag}</d:getetag>'),
        ].join(),
      );
    }
    final hrefs = RegExp(
      '<d:href>(.*?)</d:href>',
    ).allMatches(body).map((m) => Uri.decodeFull(m[1]!));
    return _multistatus(
      [
        for (final href in hrefs)
          if (tasks[href] case final t?)
            _response(
              href,
              '<d:getetag>${t.etag}</d:getetag>'
              '<c:calendar-data>${_escape(t.data)}</c:calendar-data>',
            ),
      ].join(),
    );
  }

  static String _escape(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;');

  http.Response _put(String path, http.Request request) {
    final existing = tasks[path];
    if (request.headers['If-None-Match'] == '*' && existing != null) {
      return http.Response('', 412);
    }
    final ifMatch = request.headers['If-Match'];
    if (ifMatch != null && existing?.etag != ifMatch) {
      return http.Response('', 412);
    }
    final etag = _nextEtag();
    tasks[path] = FakeTask(etag, request.body);
    ctag++;
    return http.Response(
      '',
      existing == null ? 201 : 204,
      headers: {if (sendEtagOnPut) 'etag': etag},
    );
  }

  http.Response _delete(String path, http.Request request) {
    final existing = tasks[path];
    if (existing == null) return http.Response('', 404);
    final ifMatch = request.headers['If-Match'];
    if (ifMatch != null && existing.etag != ifMatch) {
      return http.Response('', 412);
    }
    tasks.remove(path);
    ctag++;
    return http.Response('', 204);
  }
}

/// A task as another client would write it.
String otherAppTask(String uid, String props) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Other//EN\r\n'
    'BEGIN:VTODO\r\nUID:$uid\r\nDTSTAMP:20260901T000000Z\r\n'
    '$props'
    'END:VTODO\r\nEND:VCALENDAR\r\n';
