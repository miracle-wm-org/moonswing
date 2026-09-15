// The web half of the GitHub module: the sign-in handshake, the notification
// list, and the two writes that mark a thread read.
//
// Flutter-free and behind an interface, for the reasons `weather_api.dart` is:
// the store polls through it and a test driving that store must not reach the
// network, and the parsing is where a shape change at GitHub would otherwise
// turn into a crash — so every response is a pure function over a decoded map,
// and a row that will not parse costs that row rather than the list.
//
// Authentication is the **device flow**, which is what `gh auth login` uses and
// for the same reason: a desktop application cannot keep a client secret, and a
// shell has nowhere to redirect an OAuth callback to. The shell asks GitHub for
// a short user code, the user types it into github.com/login/device in a
// browser, and the shell polls until GitHub hands back a token. Nothing here
// ever sees a password.

import 'dart:convert';

import 'package:http/http.dart' as http;

/// The OAuth app the sign-in runs against by default: the GitHub CLI's own
/// public client id, the one `gh auth login` uses.
///
/// A client id is public by construction — the device flow exists precisely
/// because the *secret* cannot be shipped — and this one is in `gh`'s source.
/// Borrowing it is what makes the module work out of the box, at the cost of a
/// consent screen that says **GitHub CLI** rather than Graceful Shell, so
/// `[modules.github] client_id` lets anyone who minds register an OAuth app of
/// their own (Developer settings › OAuth Apps, with device flow enabled) and
/// point the module at it.
const String kGithubDefaultClientId = '178c6fc778ccc68e1d6a';

/// What the sign-in asks for.
///
/// `notifications` is read access to the notification list and the two writes
/// that mark a thread read, and nothing else — not the contents of a single
/// repository. It is deliberately the smallest scope that answers the question
/// this module asks. Notifications from *private* repositories need `repo`,
/// which is full read/write access to them; `[modules.github] scopes` is where
/// someone who wants those opts into that trade.
const String kGithubDefaultScopes = 'notifications';

/// GitHub's floor for how often the notification endpoint may be polled. The
/// API also says so per response, in `X-Poll-Interval`.
const int kGithubMinPollSeconds = 60;

/// Thrown when a request fails in a way the user should be told about. The
/// store turns it into the one line the popup shows in place of a list.
class GithubException implements Exception {
  const GithubException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The token is gone: revoked from github.com, expired, or never valid.
///
/// Its own type because it is the one failure with a *state* change behind it —
/// the store drops the stored token and goes back to signed out, rather than
/// leaving a retry button that can only fail.
class GithubAuthException extends GithubException {
  const GithubAuthException([super.message = 'GitHub sign-in expired']);
}

/// The user's half of the device flow: the code they type, and where.
class GithubDeviceCode {
  const GithubDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.interval,
    required this.expiresIn,
  });

  /// The shell's half — polled with, never shown.
  final String deviceCode;

  /// The eight characters the user types into [verificationUri].
  final String userCode;

  /// Where they type it: `https://github.com/login/device`.
  final String verificationUri;

  /// How long to wait between polls, in seconds, as GitHub asks.
  final int interval;

  /// How long the code is good for, in seconds.
  final int expiresIn;

  /// Parses the device-code response. Throws when it carries no code, because
  /// there is no sign-in to continue without one.
  static GithubDeviceCode fromJson(Map<String, dynamic> json) {
    final deviceCode = _asString(json['device_code']);
    final userCode = _asString(json['user_code']);
    if (deviceCode.isEmpty || userCode.isEmpty) {
      throw GithubException(_errorMessage(json, 'GitHub declined the sign-in'));
    }
    final uri = _asString(json['verification_uri']);
    return GithubDeviceCode(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri:
          uri.isEmpty ? 'https://github.com/login/device' : uri,
      // The defaults are the documented ones, used when GitHub omits the
      // field: a missing interval must not become a zero-second poll loop.
      interval: _asInt(json['interval']) ?? 5,
      expiresIn: _asInt(json['expires_in']) ?? 900,
    );
  }
}

/// One turn of the token poll.
sealed class GithubTokenResult {
  const GithubTokenResult();
}

/// The user has not finished authorising yet. [slowDown] is GitHub asking for
/// a longer gap — the spec's answer to polling too fast, and ignoring it is how
/// a client gets rate-limited out of its own sign-in.
class GithubTokenPending extends GithubTokenResult {
  const GithubTokenPending({this.slowDown = false});

  final bool slowDown;
}

/// The user authorised the app; this is the access token.
class GithubTokenGranted extends GithubTokenResult {
  const GithubTokenGranted(this.token);

  final String token;
}

/// Parses a token-poll response.
///
/// The three terminal failures — the code expired, the user said no, the app is
/// unknown — are a [GithubException], because each one ends the sign-in and the
/// user has to be told which happened. Everything else is [GithubTokenPending].
GithubTokenResult parseTokenResponse(Map<String, dynamic> json) {
  final token = _asString(json['access_token']);
  if (token.isNotEmpty) return GithubTokenGranted(token);

  return switch (_asString(json['error'])) {
    'authorization_pending' => const GithubTokenPending(),
    'slow_down' => const GithubTokenPending(slowDown: true),
    'expired_token' => throw const GithubException(
        'The sign-in code expired. Start again.',
      ),
    'access_denied' => throw const GithubException('Sign-in was cancelled.'),
    'incorrect_client_credentials' ||
    'unsupported_grant_type' =>
      throw GithubException(
        _errorMessage(json, 'That OAuth app cannot use the device flow.'),
      ),
    '' => throw const GithubException('GitHub sent no token'),
    _ => throw GithubException(
        _errorMessage(json, 'GitHub declined the sign-in'),
      ),
  };
}

/// What a notification is about. GitHub sends a handful more of these than
/// anyone has icons for; [other] is where they land, which costs the row its
/// glyph and nothing else.
enum GithubSubjectType {
  pullRequest,
  issue,
  commit,
  release,
  discussion,
  checkSuite,
  other;

  static GithubSubjectType parse(String raw) => switch (raw) {
        'PullRequest' => pullRequest,
        'Issue' => issue,
        'Commit' => commit,
        'Release' => release,
        'Discussion' => discussion,
        'CheckSuite' => checkSuite,
        _ => other,
      };
}

/// One notification thread.
class GithubNotification {
  const GithubNotification({
    required this.id,
    required this.title,
    required this.repository,
    required this.repositoryUrl,
    required this.type,
    required this.reason,
    required this.unread,
    required this.updatedAt,
    required this.url,
  });

  /// The thread id, which is what the two "mark read" endpoints take.
  final String id;

  final String title;

  /// `owner/name`.
  final String repository;

  /// The repository's page on the web — the fallback target for a subject
  /// whose own URL cannot be turned into one.
  final String repositoryUrl;

  final GithubSubjectType type;

  /// Why this arrived: `mention`, `review_requested`, `assign`, … See
  /// [githubReasonLabel] for the readable form.
  final String reason;

  final bool unread;

  final DateTime? updatedAt;

  /// Where a click goes — already a web URL, not an API one.
  final String url;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GithubNotification &&
          other.id == id &&
          other.title == title &&
          other.repository == repository &&
          other.type == type &&
          other.reason == reason &&
          other.unread == unread &&
          other.updatedAt == updatedAt &&
          other.url == url;

  @override
  int get hashCode =>
      Object.hash(id, title, repository, type, reason, unread, updatedAt, url);

  @override
  String toString() => 'GithubNotification($repository: $title)';
}

/// What one fetch produced.
class GithubNotificationPage {
  const GithubNotificationPage({
    required this.items,
    this.notModified = false,
    this.lastModified,
    this.pollInterval,
  });

  /// The threads, newest first. Empty when [notModified].
  final List<GithubNotification> items;

  /// GitHub answered 304: nothing has changed since [lastModified], the fetch
  /// cost no rate-limit quota, and the list on screen is still current.
  final bool notModified;

  /// The response's `Last-Modified`, to be echoed back as `If-Modified-Since`
  /// on the next fetch. Null when the response carried none.
  final String? lastModified;

  /// The response's `X-Poll-Interval`, in seconds: how long GitHub wants the
  /// client to wait. Null when the response carried none.
  final int? pollInterval;
}

/// The seam the store polls through. [HttpGithubClient] is the one
/// implementation; a test supplies its own and never opens a socket.
abstract class GithubClient {
  /// Starts the device flow: asks GitHub for the code the user will type.
  Future<GithubDeviceCode> requestDeviceCode({
    required String clientId,
    required String scopes,
  });

  /// One turn of the token poll. Pending is a normal answer, not a failure.
  Future<GithubTokenResult> pollAccessToken({
    required String clientId,
    required String deviceCode,
  });

  /// The signed-in user's login, for the popup's header.
  Future<String> fetchLogin(String token);

  /// The notification list.
  ///
  /// [lastModified] is the previous page's, echoed back so an unchanged list
  /// comes back as a 304 that costs no rate-limit quota — which is what lets
  /// this poll at GitHub's own cadence rather than a conservative one.
  Future<GithubNotificationPage> fetchNotifications({
    required String token,
    String? lastModified,
    bool participating = false,
    bool includeRead = false,
  });

  /// Marks one thread read.
  Future<void> markThreadRead({required String token, required String id});

  /// Marks everything read, up to and including [lastReadAt].
  Future<void> markAllRead({required String token, DateTime? lastReadAt});
}

/// The REST API, over `github.com` for the sign-in and `api.github.com` for
/// everything else — the same split `gh` uses, because the device flow lives on
/// the website and the data does not.
class HttpGithubClient implements GithubClient {
  const HttpGithubClient({http.Client? httpClient}) : _client = httpClient;

  final http.Client? _client;

  http.Client? get _c => _client;

  /// Sent on every request. The API version pin is GitHub's own advice: it is
  /// what stops a future default breaking the parse below.
  static const Map<String, String> _apiHeaders = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'graceful-shell',
  };

  Future<http.Response> _post(
    Uri url,
    Map<String, String> body, {
    String? token,
  }) async {
    final headers = {
      ..._apiHeaders,
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final client = _c;
    try {
      return client == null
          ? await http.post(url, headers: headers, body: body)
          : await client.post(url, headers: headers, body: body);
    } catch (e) {
      throw GithubException('Could not reach ${url.host}');
    }
  }

  Future<http.Response> _send(
    String method,
    Uri url, {
    required String token,
    Map<String, String> headers = const {},
    Object? body,
  }) async {
    final request = http.Request(method, url)
      ..headers.addAll({
        ..._apiHeaders,
        'Authorization': 'Bearer $token',
        ...headers,
      });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final client = _c;
    try {
      final streamed = client == null
          ? await request.send()
          : await client.send(request);
      return await http.Response.fromStream(streamed);
    } on GithubException {
      rethrow;
    } catch (e) {
      throw GithubException('Could not reach ${url.host}');
    }
  }

  /// The one place a status code becomes a message. 401 and 403-with-a-bad-token
  /// are [GithubAuthException] so the store knows to drop what it is holding.
  Never _fail(Uri url, http.Response response) {
    final code = response.statusCode;
    if (code == 401) {
      throw const GithubAuthException('GitHub rejected the saved sign-in');
    }
    if (code == 403 && _isRateLimited(response)) {
      throw const GithubException('GitHub rate limit reached');
    }
    if (code == 403) {
      throw const GithubAuthException(
        'That sign-in is not allowed to read notifications',
      );
    }
    throw GithubException('${url.host} answered $code');
  }

  static bool _isRateLimited(http.Response response) =>
      response.headers['x-ratelimit-remaining'] == '0';

  Map<String, dynamic> _decodeObject(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<GithubDeviceCode> requestDeviceCode({
    required String clientId,
    required String scopes,
  }) async {
    final url = Uri.https('github.com', '/login/device/code');
    final response = await _post(url, {
      'client_id': clientId,
      'scope': scopes,
    });
    if (response.statusCode != 200) _fail(url, response);
    return GithubDeviceCode.fromJson(_decodeObject(response));
  }

  @override
  Future<GithubTokenResult> pollAccessToken({
    required String clientId,
    required String deviceCode,
  }) async {
    final url = Uri.https('github.com', '/login/oauth/access_token');
    final response = await _post(url, {
      'client_id': clientId,
      'device_code': deviceCode,
      'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
    });
    // The device flow answers 200 with an `error` field for the states that are
    // not failures at all — pending, slow down — so the body decides, not the
    // status. A 4xx with a body GitHub still filled in is handled the same way.
    if (response.statusCode >= 500) _fail(url, response);
    return parseTokenResponse(_decodeObject(response));
  }

  @override
  Future<String> fetchLogin(String token) async {
    final url = Uri.https('api.github.com', '/user');
    final response = await _send('GET', url, token: token);
    if (response.statusCode != 200) _fail(url, response);
    return _asString(_decodeObject(response)['login']);
  }

  @override
  Future<GithubNotificationPage> fetchNotifications({
    required String token,
    String? lastModified,
    bool participating = false,
    bool includeRead = false,
  }) async {
    final url = Uri.https('api.github.com', '/notifications', {
      'all': '$includeRead',
      'participating': '$participating',
      'per_page': '50',
    });
    final response = await _send(
      'GET',
      url,
      token: token,
      headers: {'If-Modified-Since': ?lastModified},
    );
    final poll = _asInt(response.headers['x-poll-interval']);
    if (response.statusCode == 304) {
      return GithubNotificationPage(
        items: const [],
        notModified: true,
        // The 304 carries no Last-Modified of its own: the caller keeps the one
        // it sent, which is what the next If-Modified-Since must be.
        lastModified: lastModified,
        pollInterval: poll,
      );
    }
    if (response.statusCode != 200) _fail(url, response);
    return GithubNotificationPage(
      items: parseNotifications(jsonDecode(utf8.decode(response.bodyBytes))),
      lastModified: response.headers['last-modified'],
      pollInterval: poll,
    );
  }

  @override
  Future<void> markThreadRead({
    required String token,
    required String id,
  }) async {
    final url = Uri.https('api.github.com', '/notifications/threads/$id');
    final response = await _send('PATCH', url, token: token);
    // 205 is the documented success; 200 and 202 are accepted for the same
    // reason the parsers are lenient, and 404 means the thread is already gone,
    // which is the state the caller asked for.
    final code = response.statusCode;
    if (code == 404 || (code >= 200 && code < 300)) return;
    _fail(url, response);
  }

  @override
  Future<void> markAllRead({
    required String token,
    DateTime? lastReadAt,
  }) async {
    final url = Uri.https('api.github.com', '/notifications');
    final response = await _send(
      'PUT',
      url,
      token: token,
      body: {
        'read': true,
        if (lastReadAt != null)
          'last_read_at': lastReadAt.toUtc().toIso8601String(),
      },
    );
    final code = response.statusCode;
    if (code >= 200 && code < 300) return;
    _fail(url, response);
  }
}

/// The notification list's answer, as a list of rows.
///
/// A row missing an id, or one that is not a table at all, is dropped rather
/// than thrown over: the degrade-per-field rule the config layer runs on
/// applies to data from outside too, and one malformed thread must not cost the
/// user the other twenty.
List<GithubNotification> parseNotifications(Object? json) {
  if (json is! List) return const [];
  final items = <GithubNotification>[];
  for (final entry in json) {
    if (entry is! Map<String, dynamic>) continue;
    final parsed = parseNotification(entry);
    if (parsed != null) items.add(parsed);
  }
  return items;
}

/// One row of it, or null when it carries no id — which is the one field
/// nothing downstream can work without.
GithubNotification? parseNotification(Map<String, dynamic> json) {
  final id = _asString(json['id']);
  if (id.isEmpty) return null;

  final subject = json['subject'];
  final subjectMap = subject is Map<String, dynamic> ? subject : const {};
  final repository = json['repository'];
  final repoMap = repository is Map<String, dynamic> ? repository : const {};

  final repoName = _asString(repoMap['full_name']);
  final repoUrl = _asString(repoMap['html_url']).isNotEmpty
      ? _asString(repoMap['html_url'])
      : (repoName.isEmpty ? '' : 'https://github.com/$repoName');
  final type = GithubSubjectType.parse(_asString(subjectMap['type']));

  return GithubNotification(
    id: id,
    // A thread with no title still renders: the repository and the reason are
    // what most rows are read by anyway.
    title: _asString(subjectMap['title']),
    repository: repoName,
    repositoryUrl: repoUrl,
    type: type,
    reason: _asString(json['reason']),
    // Absent means unread: this endpoint returns unread threads by default, so
    // the safe reading of a missing field is the one that shows the row.
    unread: json['unread'] is bool ? json['unread'] as bool : true,
    updatedAt: DateTime.tryParse(_asString(json['updated_at']))?.toLocal(),
    url: githubWebUrl(
      subjectUrl: _asString(subjectMap['url']),
      type: type,
      repositoryUrl: repoUrl,
    ),
  );
}

/// The page a click should open, from the API URL the notification carries.
///
/// The notifications endpoint reports subjects by their *API* URL
/// (`https://api.github.com/repos/o/r/pulls/12`), which is JSON in a browser.
/// The web URL is a rewrite of it, and a pure function so
/// `test/github_api_test.dart` can pin every shape:
///
///   * `pulls/12`   → `/pull/12`   (the API and the website disagree here)
///   * `issues/12`  → `/issues/12`
///   * `commits/ab` → `/commit/ab`
///   * releases, check suites and anything else → the repository's own page,
///     because their API ids are not the website's and a wrong link is worse
///     than a general one.
///
/// A subject with no URL — which is what a Discussion sends — falls back the
/// same way, and an unparseable one costs the row its link, not its render.
String githubWebUrl({
  required String subjectUrl,
  required GithubSubjectType type,
  required String repositoryUrl,
}) {
  if (subjectUrl.isEmpty) return repositoryUrl;
  final uri = Uri.tryParse(subjectUrl);
  if (uri == null || !uri.hasScheme) return repositoryUrl;

  final segments = uri.pathSegments;
  // `/repos/<owner>/<repo>/<kind>/<id>` — anything shorter is not a subject
  // URL this knows how to rewrite.
  final repoIndex = segments.indexOf('repos');
  if (repoIndex < 0 || segments.length < repoIndex + 5) return repositoryUrl;
  final owner = segments[repoIndex + 1];
  final repo = segments[repoIndex + 2];
  final kind = segments[repoIndex + 3];
  final id = segments[repoIndex + 4];
  if (owner.isEmpty || repo.isEmpty || id.isEmpty) return repositoryUrl;

  final path = switch (kind) {
    'pulls' => 'pull/$id',
    'issues' => 'issues/$id',
    'commits' => 'commit/$id',
    'discussions' => 'discussions/$id',
    _ => '',
  };
  if (path.isEmpty) return repositoryUrl;

  // The website host beside the API one: `api.github.com` is `github.com`, and
  // GitHub Enterprise serves its API under `<host>/api/v3`, which is the same
  // host. Neither is guessed at beyond that.
  final host = uri.host.startsWith('api.') ? uri.host.substring(4) : uri.host;
  return Uri.https(host, '/$owner/$repo/$path').toString();
}

/// Why a thread arrived, in words. GitHub's reasons are snake_case identifiers;
/// an unknown one is un-snaked rather than dropped, so a reason added after
/// this was written still reads as English.
String githubReasonLabel(String reason) => switch (reason) {
      'assign' => 'Assigned to you',
      'author' => 'You opened this',
      'comment' => 'New comment',
      'ci_activity' => 'Workflow run',
      'invitation' => 'Invitation',
      'manual' => 'Subscribed',
      'mention' => 'Mentioned you',
      'push' => 'New commits',
      'review_requested' => 'Review requested',
      'security_alert' => 'Security alert',
      'state_change' => 'Closed or reopened',
      'subscribed' => 'Watching',
      'team_mention' => 'Mentioned your team',
      'approval_requested' => 'Approval requested',
      'member_feature_requested' => 'Feature requested',
      '' => '',
      _ => _unsnake(reason),
    };

String _unsnake(String raw) {
  final words = raw.split('_').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return raw;
  final first = words.first;
  return [
    first[0].toUpperCase() + first.substring(1),
    ...words.skip(1),
  ].join(' ');
}

/// The error GitHub described, or [fallback] when it described none.
String _errorMessage(Map<String, dynamic> json, String fallback) {
  final description = _asString(json['error_description']);
  if (description.isNotEmpty) return description;
  final message = _asString(json['message']);
  if (message.isNotEmpty) return message;
  return fallback;
}

String _asString(Object? value) => value is String ? value.trim() : '';

int? _asInt(Object? value) {
  if (value is num && value.isFinite) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
