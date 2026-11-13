// GitLab's REST API (v4), as much of it as the shell reads: who a token belongs
// to, the merge requests and issues the Code tab shows, and the to-do list —
// GitLab's inbox — with the two writes that mark to-dos done.
//
// Any GitLab, not only gitlab.com: the host is part of the account, because a
// great deal of GitLab is self-managed and the API is the same on all of it.
//
// The sign-in is a **personal access token**, not an OAuth flow. GitLab's
// device flow needs an OAuth application registered on *each* instance, which
// a shell that does not know the user's instance cannot ship — while a token is
// something every instance issues the same way, from a page the card links to
// with the name and scope already filled in. `read_api` is the scope asked for:
// everything here but the two to-do writes, which need `api` and say so when
// refused rather than signing the account out.
//
// Flutter-free and behind an interface, for `github_api.dart`'s reasons: the
// stores read through it and their tests never open a socket, and every parse
// is a pure function over decoded JSON in which one malformed row costs that
// row.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:moonswing/code/code_model.dart';

/// The instance a new account is on unless the user names another.
const String kGitlabDefaultHost = 'gitlab.com';

/// What the token page is asked to tick: read access to the API, nothing more.
const String kGitlabTokenScopes = 'read_api';

/// Thrown when a request fails in a way the user should be told about.
class GitlabException implements Exception {
  const GitlabException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The token is gone: revoked, expired — personal access tokens do — or never
/// valid. The account signs out on it, with the reason.
class GitlabAuthException extends GitlabException {
  const GitlabAuthException([
    super.message = 'GitLab rejected the saved token',
  ]);
}

/// Who a token belongs to.
class GitlabUser {
  const GitlabUser({
    required this.id,
    required this.username,
    this.name = '',
    this.webUrl = '',
  });

  final int id;
  final String username;
  final String name;
  final String webUrl;
}

/// The instance [raw] names, as the base every request is made against —
/// `https://host[:port]` with no path — or null when it names none.
///
/// Forgiving the way an address bar is: `gitlab.com`, `https://gitlab.com/`,
/// and a URL copied from a project page (`https://git.example.org/group/x`) all
/// name an instance. `http://` is kept when written, for an instance on a
/// network the user trusts, and the card warns about it.
Uri? gitlabInstanceUri(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  // A host with no dot is not a typo of "gitlab.com" this can rescue — but
  // `localhost` is a real instance on a development machine.
  if (!uri.host.contains('.') && uri.host != 'localhost') return null;
  return Uri(
    scheme: uri.scheme,
    host: uri.host.toLowerCase(),
    port: uri.hasPort ? uri.port : null,
  );
}

/// Whether [raw] names an instance over plain http.
bool gitlabIsInsecure(String raw) => gitlabInstanceUri(raw)?.scheme == 'http';

/// The page that makes a token, with its name and scope filled in — GitLab
/// reads both off the query string.
Uri gitlabTokenPage(Uri instance) => instance.replace(
  path: '/-/user_settings/personal_access_tokens',
  queryParameters: {'name': 'Moonswing', 'scopes': kGitlabTokenScopes},
);

/// What the Code tab asks GitLab for.
abstract class GitlabClient {
  /// The token's owner — the sign-in's one check that the token works.
  Future<GitlabUser> fetchUser({required Uri instance, required String token});

  /// Everything the Code tab shows from this instance, as [username].
  Future<CodeSnapshot> fetchDashboard({
    required Uri instance,
    required String token,
    required String username,
    required DateTime since,
  });

  /// Marks one to-do done.
  Future<void> markTodoDone({
    required Uri instance,
    required String token,
    required String id,
  });

  /// Marks every pending to-do done.
  Future<void> markAllTodosDone({required Uri instance, required String token});
}

/// The REST API, at `<instance>/api/v4`.
class HttpGitlabClient implements GitlabClient {
  const HttpGitlabClient({http.Client? httpClient}) : _client = httpClient;

  final http.Client? _client;

  static const Duration _timeout = Duration(seconds: 20);

  Uri _url(Uri instance, String path, [Map<String, String>? query]) =>
      instance.replace(path: '/api/v4$path', queryParameters: query);

  Future<http.Response> _send(
    String method,
    Uri url, {
    required String token,
  }) async {
    final request = http.Request(method, url)
      ..headers.addAll({
        'Accept': 'application/json',
        'User-Agent': 'moonswing',
        'PRIVATE-TOKEN': token,
      });
    try {
      final client = _client;
      final streamed =
          await (client == null ? request.send() : client.send(request))
              .timeout(_timeout);
      return await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw GitlabException('${url.host} did not answer');
    } catch (_) {
      throw GitlabException('Could not reach ${url.host}');
    }
  }

  /// The one place a status code becomes a message.
  Never _fail(Uri url, http.Response response, {bool write = false}) {
    final code = response.statusCode;
    if (code == 401) {
      throw const GitlabAuthException(
        'GitLab rejected the saved token — it may have expired',
      );
    }
    if (code == 403 && write) {
      throw const GitlabException(
        'Marking to-dos done needs a token with the api scope',
      );
    }
    if (code == 403) throw const GitlabException('GitLab refused the request');
    if (code == 429) throw const GitlabException('GitLab rate limit reached');
    throw GitlabException('${url.host} answered $code');
  }

  Future<Object?> _get(
    Uri instance,
    String token,
    String path, [
    Map<String, String>? query,
  ]) async {
    final url = _url(instance, path, query);
    final response = await _send('GET', url, token: token);
    if (response.statusCode != 200) _fail(url, response);
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw GitlabException('${url.host} sent an answer that would not parse');
    }
  }

  @override
  Future<GitlabUser> fetchUser({
    required Uri instance,
    required String token,
  }) async {
    final user = parseGitlabUser(await _get(instance, token, '/user'));
    if (user == null) {
      throw const GitlabException('That does not look like a GitLab instance');
    }
    return user;
  }

  @override
  Future<CodeSnapshot> fetchDashboard({
    required Uri instance,
    required String token,
    required String username,
    required DateTime since,
  }) async {
    const page = {'per_page': '30', 'order_by': 'updated_at'};
    final results = await Future.wait([
      _get(instance, token, '/merge_requests', {
        ...page,
        'scope': 'all',
        'state': 'opened',
        'reviewer_username': username,
      }),
      _get(instance, token, '/merge_requests', {
        ...page,
        'scope': 'created_by_me',
        'state': 'opened',
      }),
      _get(instance, token, '/issues', {
        ...page,
        'scope': 'assigned_to_me',
        'state': 'opened',
      }),
      _get(instance, token, '/merge_requests', {
        ...page,
        'scope': 'created_by_me',
        'state': 'merged',
        'updated_after': since.toUtc().toIso8601String(),
      }),
      _get(instance, token, '/todos', {'state': 'pending', 'per_page': '50'}),
    ]);
    return CodeSnapshot(
      reviews: parseGitlabMergeRequests(results[0]),
      authored: parseGitlabMergeRequests(results[1]),
      assigned: parseGitlabIssues(results[2]),
      merged: [
        // `updated_after` is the closest the endpoint has to "merged after";
        // a change merged long ago and commented on since is not shipped now.
        for (final mr in parseGitlabMergeRequests(results[3]))
          if (mr.mergedAt == null || !mr.mergedAt!.isBefore(since)) mr,
      ],
      inbox: parseGitlabTodos(results[4]),
    );
  }

  @override
  Future<void> markTodoDone({
    required Uri instance,
    required String token,
    required String id,
  }) async {
    final url = _url(instance, '/todos/$id/mark_as_done');
    final response = await _send('POST', url, token: token);
    final code = response.statusCode;
    // 404 is a to-do already gone, which is the state asked for.
    if (code == 404 || (code >= 200 && code < 300)) return;
    _fail(url, response, write: true);
  }

  @override
  Future<void> markAllTodosDone({
    required Uri instance,
    required String token,
  }) async {
    final url = _url(instance, '/todos/mark_as_done');
    final response = await _send('POST', url, token: token);
    final code = response.statusCode;
    if (code >= 200 && code < 300) return;
    _fail(url, response, write: true);
  }
}

/// `/user`, or null when the answer is not a user — which is what a host
/// that is not GitLab at all sends back.
GitlabUser? parseGitlabUser(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final id = json['id'];
  final username = _string(json['username']);
  if (id is! int || username.isEmpty) return null;
  return GitlabUser(
    id: id,
    username: username,
    name: _string(json['name']),
    webUrl: _string(json['web_url']),
  );
}

/// A merge request list.
List<CodeItem> parseGitlabMergeRequests(Object? json) => [
  if (json is List)
    for (final row in json)
      if (row is Map<String, dynamic>) ?parseGitlabMergeRequest(row),
];

/// An issue list.
List<CodeItem> parseGitlabIssues(Object? json) => [
  if (json is List)
    for (final row in json)
      if (row is Map<String, dynamic>) ?parseGitlabIssue(row),
];

/// The to-do list.
List<CodeNotice> parseGitlabTodos(Object? json) => [
  if (json is List)
    for (final row in json)
      if (row is Map<String, dynamic>) ?parseGitlabTodo(row),
];

/// One merge request, or null without an id or a page to open.
///
/// GitLab says what stands between a merge request and the merge button in one
/// field, `detailed_merge_status`; it is read into the same checks/review/
/// conflicts triple a GitHub pull request is, so the row draws both alike. An
/// instance older than that field (15.6) falls back on `merge_status` and
/// `has_conflicts`, which say less.
CodeItem? parseGitlabMergeRequest(Map<String, dynamic> json) {
  final id = json['id'];
  final url = _string(json['web_url']);
  if (id is! int || url.isEmpty) return null;
  final status = _string(json['detailed_merge_status']);
  final draft =
      json['draft'] == true ||
      json['work_in_progress'] == true ||
      status == 'draft_status';
  final reference = _reference(json, '!');
  return CodeItem(
    provider: CodeProvider.gitlab,
    kind: CodeItemKind.pullRequest,
    id: 'gitlab-mr-$id',
    title: _string(json['title']),
    repository: reference.$1,
    reference: reference.$2,
    url: url,
    author: _author(json),
    createdAt: _date(json['created_at']),
    updatedAt: _date(json['updated_at']),
    mergedAt: _date(json['merged_at']),
    draft: draft,
    checks: switch (status) {
      'ci_must_pass' => CodeChecks.failing,
      'ci_still_running' => CodeChecks.pending,
      'mergeable' => CodeChecks.passing,
      _ => CodeChecks.none,
    },
    review: switch (status) {
      'not_approved' => CodeReview.required,
      'requested_changes' => CodeReview.changesRequested,
      'mergeable' => CodeReview.approved,
      _ => CodeReview.none,
    },
    conflicts:
        json['has_conflicts'] == true ||
        status == 'conflict' ||
        status == 'need_rebase',
    comments: _int(json['user_notes_count']),
  );
}

/// One issue, or null without an id or a page to open.
CodeItem? parseGitlabIssue(Map<String, dynamic> json) {
  final id = json['id'];
  final url = _string(json['web_url']);
  if (id is! int || url.isEmpty) return null;
  final reference = _reference(json, '#');
  return CodeItem(
    provider: CodeProvider.gitlab,
    kind: CodeItemKind.issue,
    id: 'gitlab-issue-$id',
    title: _string(json['title']),
    repository: reference.$1,
    reference: reference.$2,
    url: url,
    author: _author(json),
    createdAt: _date(json['created_at']),
    updatedAt: _date(json['updated_at']),
    comments: _int(json['user_notes_count']),
  );
}

/// One to-do, or null without an id.
CodeNotice? parseGitlabTodo(Map<String, dynamic> json) {
  final id = json['id'];
  if (id is! int) return null;
  final target = json['target'];
  final targetMap = target is Map<String, dynamic> ? target : const {};
  final project = json['project'];
  final author = json['author'];
  final targetUrl = _string(json['target_url']);
  return CodeNotice(
    provider: CodeProvider.gitlab,
    id: '$id',
    title: _string(targetMap['title']).isNotEmpty
        ? _string(targetMap['title'])
        : _string(json['body']),
    repository: project is Map ? _string(project['path_with_namespace']) : '',
    subject: switch (_string(json['target_type'])) {
      'MergeRequest' => CodeNoticeSubject.pullRequest,
      'Issue' || 'WorkItem' => CodeNoticeSubject.issue,
      'Commit' => CodeNoticeSubject.commit,
      'DiscussionNote' || 'Note' => CodeNoticeSubject.discussion,
      _ => CodeNoticeSubject.other,
    },
    reason: gitlabTodoReason(_string(json['action_name'])),
    url: targetUrl.isNotEmpty ? targetUrl : _string(targetMap['web_url']),
    // A pending to-do is GitLab's unread; the list asks for pending only.
    unread: _string(json['state']) != 'done',
    updatedAt: _date(json['updated_at']) ?? _date(json['created_at']),
    author: author is Map ? _string(author['username']) : '',
  );
}

/// Why a to-do arrived, in the words the GitHub inbox uses for the same
/// thing, so one inbox reads as one.
String gitlabTodoReason(String action) => switch (action) {
  'assigned' => 'Assigned to you',
  'mentioned' => 'Mentioned you',
  'directly_addressed' => 'Mentioned you',
  'build_failed' => 'Pipeline failed',
  'marked' => 'Added to your to-dos',
  'approval_required' => 'Approval requested',
  'unmergeable' => 'Can no longer merge',
  'review_requested' => 'Review requested',
  'review_submitted' => 'Review submitted',
  'member_access_requested' => 'Access requested',
  'merge_train_removed' => 'Removed from merge train',
  '' => '',
  _ => _unsnake(action),
};

/// `group/project` and `!12` out of `references.full` (`group/project!12`), or
/// the bare `iid` when an instance sends no references.
(String, String) _reference(Map<String, dynamic> json, String sigil) {
  final refs = json['references'];
  final full = refs is Map ? _string(refs['full']) : '';
  final at = full.lastIndexOf(sigil);
  if (at > 0) return (full.substring(0, at), full.substring(at));
  final iid = json['iid'];
  return ('', iid is int ? '$sigil$iid' : '');
}

String _author(Map<String, dynamic> json) {
  final author = json['author'];
  return author is Map ? _string(author['username']) : '';
}

String _unsnake(String raw) {
  final words = raw.split('_').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return raw;
  final first = words.first;
  return [
    first[0].toUpperCase() + first.substring(1),
    ...words.skip(1),
  ].join(' ');
}

String _string(Object? value) => value is String ? value.trim() : '';

int _int(Object? value) => value is int ? value : 0;

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;
