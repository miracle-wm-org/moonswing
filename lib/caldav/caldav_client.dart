// CalDAV (RFC 4791), the part of it a task list needs: find the user's task
// lists, say whether one has changed, list and fetch its tasks, and write and
// delete them — every write conditional on the version this machine last saw,
// so another client's edit is never overwritten blind.
//
// The protocol is what the servers people already run for their calendars
// speak — Radicale, Baïkal, Nextcloud, ownCloud, Fastmail, iCloud, SOGo — and
// what the task apps on their phones (DAVx⁵ with jtx or Tasks.org) and desktops
// (Thunderbird, Evolution) read. Only `http.Client`, which follows redirects for
// GET alone, so this follows them itself: `/.well-known/caldav` is a redirect
// by design.
//
// Flutter-free, for `test/caldav_client_test.dart`.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// How long one request may take before the server counts as unreachable.
const Duration kCalDavTimeout = Duration(seconds: 30);

const String _dav = 'DAV:';
const String _caldav = 'urn:ietf:params:xml:ns:caldav';
const String _cs = 'http://calendarserver.org/ns/';
const String _apple = 'http://apple.com/ns/ical/';

/// Why a request failed, in words for the user.
class CalDavException implements Exception {
  const CalDavException(this.message, {this.statusCode});
  final String message;

  /// The HTTP status, when the server answered at all.
  final int? statusCode;

  @override
  String toString() => message;
}

/// A conditional write or delete found the server's copy changed since it was
/// read: somebody else edited it.
class CalDavConflict extends CalDavException {
  const CalDavConflict(super.message) : super(statusCode: 412);
}

/// Whether [url] would send a password unencrypted to another machine.
bool calDavIsInsecure(String url) {
  final parsed = Uri.tryParse(url.trim());
  if (parsed == null || parsed.scheme != 'http') return false;
  const local = {'localhost', '127.0.0.1', '::1', '[::1]'};
  return !local.contains(parsed.host);
}

/// [url] as a server address, or null when it is not an absolute `http(s)`
/// one.
Uri? calDavServerUri(String url) {
  final parsed = Uri.tryParse(url.trim());
  if (parsed == null ||
      !(parsed.scheme == 'https' || parsed.scheme == 'http') ||
      parsed.host.isEmpty) {
    return null;
  }
  return parsed;
}

/// A calendar collection that can hold tasks.
class CalDavCollection {
  const CalDavCollection({required this.url, required this.name, this.color});

  /// Absolute, ending in `/`.
  final Uri url;
  final String name;

  /// `#rrggbb`, when the server has one.
  final String? color;

  @override
  bool operator ==(Object other) =>
      other is CalDavCollection &&
      other.url == url &&
      other.name == name &&
      other.color == color;

  @override
  int get hashCode => Object.hash(url, name, color);
}

/// One task resource, as listed: where it is and which version.
typedef CalDavEntry = ({String href, String? etag});

/// One task resource, fetched.
typedef CalDavResource = ({String href, String? etag, String data});

/// The requests a CalDAV server is asked.
class CalDavClient {
  CalDavClient({
    required this.username,
    required this.password,
    http.Client? client,
    this.timeout = kCalDavTimeout,
  }) : _client = client;

  final String username;
  final String password;
  final Duration timeout;
  final http.Client? _client;

  /// The key a listed or stored [href] is compared by: its path, resolved
  /// against [base] and percent-decoded, since two servers — or one server
  /// twice — may spell the same path differently.
  static String hrefKey(Uri base, String href) =>
      Uri.decodeFull(base.resolve(href).path);

  Map<String, String> get _auth => {
    if (username.isNotEmpty || password.isNotEmpty)
      'Authorization':
          'Basic ${base64Encode(utf8.encode('$username:$password'))}',
  };

  Future<_Answered> _send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
    String contentType = 'application/xml; charset=utf-8',
  }) async {
    final client = _client ?? http.Client();
    try {
      var target = url;
      for (var hop = 0; ; hop++) {
        final request = http.Request(method, target)
          ..followRedirects = false
          ..headers.addAll(_auth)
          ..headers.addAll(headers);
        if (body != null) {
          request.headers['Content-Type'] = contentType;
          request.body = body;
        }
        final streamed = await client.send(request).timeout(timeout);
        final response = await http.Response.fromStream(
          streamed,
        ).timeout(timeout);
        final location = response.headers['location'];
        if (hop < 5 &&
            location != null &&
            const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
          target = target.resolve(location);
          continue;
        }
        return _Answered(response, target);
      }
    } on TimeoutException {
      throw CalDavException('${url.host} did not answer in time.');
    } on CalDavException {
      rethrow;
    } catch (e) {
      throw CalDavException('Could not reach ${url.host}: $e');
    } finally {
      if (_client == null) client.close();
    }
  }

  static CalDavException _refusal(Uri url, http.Response response) {
    final code = response.statusCode;
    return CalDavException(switch (code) {
      401 || 403 => '${url.host} refused the user name or password ($code).',
      404 => '${url.host} has nothing at ${url.path} (404).',
      507 => '${url.host} is out of space (507).',
      _ =>
        '${url.host} answered $code'
            '${response.reasonPhrase == null ? '' : ' ${response.reasonPhrase}'}.',
    }, statusCode: code);
  }

  static bool _ok(http.Response response) =>
      response.statusCode >= 200 && response.statusCode < 300;

  Future<List<_DavResponse>> _propfind(
    Uri url,
    String props, {
    int depth = 0,
    Map<String, String> extraNs = const {},
  }) async {
    final ns = extraNs.entries
        .map((e) => ' xmlns:${e.key}="${e.value}"')
        .join();
    final response = await _send(
      'PROPFIND',
      url,
      headers: {'Depth': '$depth'},
      body:
          '<?xml version="1.0" encoding="utf-8"?>'
          '<d:propfind xmlns:d="DAV:"$ns><d:prop>$props</d:prop></d:propfind>',
    );
    if (response.statusCode != 207) throw _refusal(url, response);
    return _parseMultistatus(response, response.url);
  }

  /// The task lists the account at [server] can see.
  ///
  /// [server] may be the server's root, a principal, a calendar home or one
  /// calendar: whatever the user copied from their server's settings page.
  /// Follows RFC 6764 (`/.well-known/caldav`) and RFC 5397
  /// (`current-user-principal`) from wherever it starts.
  Future<List<CalDavCollection>> discoverTaskLists(Uri server) async {
    const probe =
        '<d:resourcetype/><d:displayname/><d:current-user-principal/>'
        '<c:calendar-home-set/><c:supported-calendar-component-set/>'
        '<a:calendar-color/>';
    const ns = {'c': _caldav, 'a': _apple};

    // The address given, first: it may already be the calendar, or the home.
    List<_DavResponse> here;
    try {
      here = await _propfind(server, probe, extraNs: ns);
    } on CalDavException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) rethrow;
      here = const [];
    }
    final self = here.isEmpty ? null : here.first;
    if (self != null && self.isCalendar) {
      final list = self.asTaskList();
      if (list != null) return [list];
      throw CalDavException(
        '${server.toString()} is a calendar without tasks.',
      );
    }

    Uri? home = self?.hrefProp(_caldav, 'calendar-home-set');
    var principal = self?.hrefProp(_dav, 'current-user-principal');
    if (home == null && principal == null) {
      final known = server.resolve('/.well-known/caldav');
      try {
        final found = await _propfind(known, probe, extraNs: ns);
        if (found.isNotEmpty) {
          home = found.first.hrefProp(_caldav, 'calendar-home-set');
          principal = found.first.hrefProp(_dav, 'current-user-principal');
        }
      } on CalDavException catch (e) {
        if (e.statusCode == 401 || e.statusCode == 403) rethrow;
      }
    }
    if (home == null && principal != null) {
      final found = await _propfind(
        principal,
        '<c:calendar-home-set/>',
        extraNs: ns,
      );
      if (found.isNotEmpty) {
        home = found.first.hrefProp(_caldav, 'calendar-home-set');
      }
    }
    // A server with no discovery at all: treat the address as the home.
    home ??= server;

    final listed = await _propfind(home, probe, depth: 1, extraNs: ns);
    return [
      for (final r in listed)
        if (r.isCalendar) ?r.asTaskList(),
    ];
  }

  /// A token that changes whenever anything in [collection] does — the
  /// collection's `getctag` and `sync-token` together — or null when the server
  /// offers neither, in which case every sync lists the collection.
  Future<String?> changeToken(Uri collection) async {
    final found = await _propfind(
      collection,
      '<cs:getctag/><d:sync-token/>',
      extraNs: const {'cs': _cs},
    );
    if (found.isEmpty) return null;
    final ctag = found.first.text(_cs, 'getctag');
    final sync = found.first.text(_dav, 'sync-token');
    if (ctag == null && sync == null) return null;
    return '${ctag ?? ''}|${sync ?? ''}';
  }

  /// Every task in [collection] with its ETag. A `calendar-query` rather than
  /// a listing of the folder, because a calendar that holds tasks may hold
  /// events too — Nextcloud's do, by default.
  Future<List<CalDavEntry>> listTasks(Uri collection) async {
    final response = await _send(
      'REPORT',
      collection,
      headers: {'Depth': '1'},
      body:
          '<?xml version="1.0" encoding="utf-8"?>'
          '<c:calendar-query xmlns:d="DAV:" xmlns:c="$_caldav">'
          '<d:prop><d:getetag/></d:prop>'
          '<c:filter><c:comp-filter name="VCALENDAR">'
          '<c:comp-filter name="VTODO"/>'
          '</c:comp-filter></c:filter>'
          '</c:calendar-query>',
    );
    if (response.statusCode != 207) throw _refusal(collection, response);
    final self = hrefKey(collection, collection.path);
    return [
      for (final r in _parseMultistatus(response, collection))
        if (hrefKey(collection, r.href) != self)
          (href: r.href, etag: r.text(_dav, 'getetag')),
    ];
  }

  /// The tasks at [hrefs], fetched in one `calendar-multiget`. A resource the
  /// server no longer has is simply missing from the answer.
  Future<List<CalDavResource>> fetch(Uri collection, List<String> hrefs) async {
    if (hrefs.isEmpty) return const [];
    final body = StringBuffer(
      '<?xml version="1.0" encoding="utf-8"?>'
      '<c:calendar-multiget xmlns:d="DAV:" xmlns:c="$_caldav">'
      '<d:prop><d:getetag/><c:calendar-data/></d:prop>',
    );
    for (final href in hrefs) {
      body.write('<d:href>${_escapeXml(href)}</d:href>');
    }
    body.write('</c:calendar-multiget>');
    final response = await _send(
      'REPORT',
      collection,
      headers: {'Depth': '1'},
      body: body.toString(),
    );
    if (response.statusCode != 207) throw _refusal(collection, response);
    return [
      for (final r in _parseMultistatus(response, collection))
        if (r.text(_caldav, 'calendar-data') case final data?)
          (href: r.href, etag: r.text(_dav, 'getetag'), data: data),
    ];
  }

  /// Writes [ics] to [resource] and answers the new ETag, when the server says
  /// it. With [create], only where nothing is yet; with [etag], only over that
  /// version. Throws [CalDavConflict] when that condition fails.
  Future<String?> put(
    Uri resource,
    String ics, {
    String? etag,
    bool create = false,
  }) async {
    final response = await _send(
      'PUT',
      resource,
      headers: create ? const {'If-None-Match': '*'} : {'If-Match': ?etag},
      body: ics,
      contentType: 'text/calendar; charset=utf-8',
    );
    if (response.statusCode == 412) {
      throw CalDavConflict('${resource.path} changed on the server.');
    }
    if (!_ok(response)) throw _refusal(resource, response);
    return response.headers['etag'];
  }

  /// Deletes [resource], only if it is still [etag] when one is given. One
  /// that is already gone is deleted.
  Future<void> delete(Uri resource, {String? etag}) async {
    final response = await _send(
      'DELETE',
      resource,
      headers: {'If-Match': ?etag},
    );
    if (response.statusCode == 404 || response.statusCode == 410) return;
    if (response.statusCode == 412) {
      throw CalDavConflict('${resource.path} changed on the server.');
    }
    if (!_ok(response)) throw _refusal(resource, response);
  }
}

String _escapeXml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// A response that remembers the URL it finally came from, after redirects.
class _Answered extends http.Response {
  _Answered(http.Response r, this.url)
    : super.bytes(
        r.bodyBytes,
        r.statusCode,
        headers: r.headers,
        reasonPhrase: r.reasonPhrase,
        request: r.request,
      );

  final Uri url;
}

/// One `<d:response>` of a multistatus: its href and the properties that came
/// back 200.
class _DavResponse {
  _DavResponse(this.base, this.href, this.props);

  final Uri base;
  final String href;
  final List<XmlElement> props;

  XmlElement? prop(String ns, String name) {
    for (final p in props) {
      if (p.name.local == name && p.name.namespaceUri == ns) return p;
    }
    return null;
  }

  String? text(String ns, String name) {
    final p = prop(ns, name);
    if (p == null) return null;
    final value = p.innerText.trim();
    return value.isEmpty ? null : p.innerText;
  }

  /// A property holding one `<d:href>`, resolved.
  Uri? hrefProp(String ns, String name) {
    final p = prop(ns, name);
    if (p == null) return null;
    for (final h in p.findAllElements('href', namespace: _dav)) {
      final value = h.innerText.trim();
      if (value.isNotEmpty) return base.resolve(value);
    }
    return null;
  }

  bool get isCalendar =>
      prop(
        _dav,
        'resourcetype',
      )?.findElements('calendar', namespace: _caldav).isNotEmpty ??
      false;

  /// This calendar as a task list, or null when it holds no tasks. A calendar
  /// that does not say which components it holds may hold any.
  CalDavCollection? asTaskList() {
    final comps = prop(_caldav, 'supported-calendar-component-set');
    if (comps != null) {
      final names = [
        for (final c in comps.findElements('comp', namespace: _caldav))
          (c.getAttribute('name') ?? '').toUpperCase(),
      ];
      if (names.isNotEmpty && !names.contains('VTODO')) return null;
    }
    var url = base.resolve(href);
    if (!url.path.endsWith('/')) url = url.replace(path: '${url.path}/');
    final name = text(_dav, 'displayname')?.trim();
    return CalDavCollection(
      url: url,
      name: name == null || name.isEmpty ? _lastSegment(url) : name,
      color: _color(text(_apple, 'calendar-color')),
    );
  }

  static String _lastSegment(Uri url) {
    final parts = url.pathSegments.where((s) => s.isNotEmpty);
    return parts.isEmpty ? url.host : parts.last;
  }

  /// `#rrggbb` from Apple's `#rrggbbaa`, or null.
  static String? _color(String? value) {
    final match = RegExp(
      r'^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$',
    ).firstMatch(value?.trim() ?? '');
    return match == null ? null : '#${match[1]!.toLowerCase()}';
  }
}

List<_DavResponse> _parseMultistatus(http.Response response, Uri base) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
  } on XmlException catch (e) {
    throw CalDavException(
      '${base.host} answered with XML that does not parse: ${e.message}',
    );
  }
  final out = <_DavResponse>[];
  for (final r in document.findAllElements('response', namespace: _dav)) {
    final href = r.findElements('href', namespace: _dav).firstOrNull;
    if (href == null) continue;
    final props = <XmlElement>[];
    for (final stat in r.findElements('propstat', namespace: _dav)) {
      final status = stat.findElements('status', namespace: _dav).firstOrNull;
      if (status != null && !status.innerText.contains(' 200')) continue;
      for (final prop in stat.findElements('prop', namespace: _dav)) {
        props.addAll(prop.childElements);
      }
    }
    out.add(_DavResponse(base, href.innerText.trim(), props));
  }
  return out;
}
