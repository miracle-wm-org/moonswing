// The Code tab's GitHub read: review requests, the user's own pull requests,
// the issues assigned to them and what they merged lately, in one GraphQL
// request.
//
// GraphQL rather than the REST search the rest of `lib/github/` uses, because
// the REST search answers with *issues* — a pull request there has no review
// decision, no checks and no mergeability, which are the three things that say
// whether a change needs its author. One query asks for all four lists with
// those fields, which is one request per poll where REST would be four
// searches plus a request per pull request.
//
// The sign-in, the token and a rejected token's sign-out are
// `GithubAccountStore`'s, as they are for every GitHub consumer; this file is
// handed a token and nothing else. Flutter-free behind an interface, for the
// reason `github_api.dart` is: the store polls through it, a test of that store
// must not reach the network, and the parse is a pure function over the decoded
// body where one malformed node costs that node and never the list.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:moonswing/code/code_model.dart';
import 'package:moonswing/github/github_api.dart';

/// How many of each list one read asks for. A search past this still reports
/// its full count, which the section heading shows.
const int kCodeGithubPageSize = 30;

/// The seam the store reads GitHub through.
abstract class CodeGithubClient {
  /// Everything the Code tab shows from GitHub, as [login] (or `@me`, while
  /// the account's name has not been read yet). [since] bounds the shipped
  /// list.
  Future<CodeSnapshot> fetch({
    required String token,
    required String login,
    required DateTime since,
  });
}

/// The search queries the read is made of, as a pure function so the test can
/// pin them.
///
/// `archived:false` because a review request on an archived repository can
/// never be answered and would sit at the top of the queue for ever.
Map<String, String> codeGithubQueries({
  required String login,
  required DateTime since,
}) {
  final who = login.isEmpty ? '@me' : login;
  final day = since.toUtc().toIso8601String().split('T').first;
  return {
    'reviews':
        'is:pr is:open archived:false review-requested:$who '
        'sort:updated-asc',
    'authored': 'is:pr is:open archived:false author:$who sort:updated-desc',
    'assigned':
        'is:issue is:open archived:false assignee:$who '
        'sort:updated-desc',
    'merged': 'is:pr is:merged author:$who merged:>=$day sort:updated-desc',
  };
}

/// The GraphQL document for [codeGithubQueries].
String codeGithubDocument({required String login, required DateTime since}) {
  final queries = codeGithubQueries(login: login, since: since);
  String search(String alias, String fragment, int first) =>
      '$alias: search(type: ISSUE, first: $first, '
      'query: ${jsonEncode(queries[alias])}) '
      '{ issueCount nodes { ...$fragment } }';
  return '''
fragment pr on PullRequest {
  id number title url isDraft createdAt updatedAt mergedAt mergeable
  reviewDecision
  repository { nameWithOwner }
  author { login }
  comments { totalCount }
  commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
}
fragment issue on Issue {
  id number title url createdAt updatedAt
  repository { nameWithOwner }
  author { login }
  comments { totalCount }
}
query {
  ${search('reviews', 'pr', kCodeGithubPageSize)}
  ${search('authored', 'pr', kCodeGithubPageSize)}
  ${search('assigned', 'issue', kCodeGithubPageSize)}
  ${search('merged', 'pr', 20)}
}''';
}

/// `api.github.com/graphql`.
class HttpCodeGithubClient implements CodeGithubClient {
  const HttpCodeGithubClient({http.Client? httpClient}) : _client = httpClient;

  final http.Client? _client;

  @override
  Future<CodeSnapshot> fetch({
    required String token,
    required String login,
    required DateTime since,
  }) async {
    final url = Uri.https('api.github.com', '/graphql');
    final headers = {
      'Accept': 'application/vnd.github+json',
      'Content-Type': 'application/json',
      'User-Agent': 'moonswing',
      'Authorization': 'Bearer $token',
    };
    final body = jsonEncode({
      'query': codeGithubDocument(login: login, since: since),
    });
    final http.Response response;
    try {
      final client = _client;
      response = client == null
          ? await http.post(url, headers: headers, body: body)
          : await client.post(url, headers: headers, body: body);
    } catch (_) {
      throw const GithubException('Could not reach api.github.com');
    }
    final code = response.statusCode;
    if (code == 401) {
      throw const GithubAuthException('GitHub rejected the saved sign-in');
    }
    if (code == 403 || code == 429) {
      throw const GithubException('GitHub rate limit reached — try later');
    }
    if (code != 200) throw GithubException('api.github.com answered $code');
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const GithubException('GitHub sent an answer that would not parse');
    }
    return parseCodeGithubResponse(decoded);
  }
}

/// The GraphQL answer, as a snapshot.
///
/// GraphQL reports a partial failure *beside* the data — one search refused, a
/// node from a repository behind SSO — so an `errors` list with data next to it
/// is the data, and only an answer with no data at all is a failure, worded from
/// the first error GitHub gave.
CodeSnapshot parseCodeGithubResponse(Object? json) {
  if (json is! Map<String, dynamic>) {
    throw const GithubException('GitHub sent no data');
  }
  final data = json['data'];
  if (data is! Map<String, dynamic>) {
    throw GithubException(_firstError(json) ?? 'GitHub sent no data');
  }

  (List<CodeItem>, int?) search(String alias, CodeItemKind kind) {
    final result = data[alias];
    if (result is! Map<String, dynamic>) return (const [], null);
    final nodes = result['nodes'];
    final items = <CodeItem>[];
    if (nodes is List) {
      for (final node in nodes) {
        if (node is! Map<String, dynamic>) continue;
        final item = parseCodeGithubNode(node, kind);
        if (item != null) items.add(item);
      }
    }
    final count = result['issueCount'];
    return (items, count is int ? count : null);
  }

  final (reviews, reviewsTotal) = search('reviews', CodeItemKind.pullRequest);
  final (authored, authoredTotal) = search(
    'authored',
    CodeItemKind.pullRequest,
  );
  final (assigned, assignedTotal) = search('assigned', CodeItemKind.issue);
  final (merged, _) = search('merged', CodeItemKind.pullRequest);
  return CodeSnapshot(
    reviews: reviews,
    authored: authored,
    assigned: assigned,
    merged: merged,
    reviewsTotal: reviewsTotal,
    authoredTotal: authoredTotal,
    assignedTotal: assignedTotal,
  );
}

/// One search node, or null when it carries no id or URL — the two fields a
/// row cannot do without. An empty node (`{}`) is what GraphQL sends for a
/// result the fragment's type did not match, and lands here too.
CodeItem? parseCodeGithubNode(Map<String, dynamic> node, CodeItemKind kind) {
  final id = _string(node['id']);
  final url = _string(node['url']);
  if (id.isEmpty || url.isEmpty) return null;
  final number = node['number'];
  final repo = node['repository'];
  final author = node['author'];
  final comments = node['comments'];

  var checks = CodeChecks.none;
  final commits = node['commits'];
  if (commits is Map && commits['nodes'] is List) {
    final list = commits['nodes'] as List;
    if (list.isNotEmpty && list.last is Map) {
      final commit = (list.last as Map)['commit'];
      if (commit is Map && commit['statusCheckRollup'] is Map) {
        checks = switch (_string(
          (commit['statusCheckRollup'] as Map)['state'],
        )) {
          'SUCCESS' => CodeChecks.passing,
          'FAILURE' || 'ERROR' => CodeChecks.failing,
          'PENDING' || 'EXPECTED' => CodeChecks.pending,
          _ => CodeChecks.none,
        };
      }
    }
  }

  return CodeItem(
    provider: CodeProvider.github,
    kind: kind,
    id: id,
    title: _string(node['title']),
    repository: repo is Map ? _string(repo['nameWithOwner']) : '',
    reference: number is int ? '#$number' : '',
    url: url,
    author: author is Map ? _string(author['login']) : '',
    createdAt: _date(node['createdAt']),
    updatedAt: _date(node['updatedAt']),
    mergedAt: _date(node['mergedAt']),
    draft: node['isDraft'] == true,
    checks: checks,
    review: switch (_string(node['reviewDecision'])) {
      'APPROVED' => CodeReview.approved,
      'CHANGES_REQUESTED' => CodeReview.changesRequested,
      'REVIEW_REQUIRED' => CodeReview.required,
      _ => CodeReview.none,
    },
    conflicts: _string(node['mergeable']) == 'CONFLICTING',
    comments: comments is Map && comments['totalCount'] is int
        ? comments['totalCount'] as int
        : 0,
  );
}

/// A GitHub notification as an inbox thread.
CodeNotice codeNoticeFromGithub(GithubNotification n) => CodeNotice(
  provider: CodeProvider.github,
  id: n.id,
  title: n.title,
  repository: n.repository,
  subject: switch (n.type) {
    GithubSubjectType.pullRequest => CodeNoticeSubject.pullRequest,
    GithubSubjectType.issue => CodeNoticeSubject.issue,
    GithubSubjectType.commit => CodeNoticeSubject.commit,
    GithubSubjectType.release => CodeNoticeSubject.release,
    GithubSubjectType.discussion => CodeNoticeSubject.discussion,
    GithubSubjectType.checkSuite => CodeNoticeSubject.pipeline,
    GithubSubjectType.other => CodeNoticeSubject.other,
  },
  reason: githubReasonLabel(n.reason),
  url: n.url,
  unread: n.unread,
  updatedAt: n.updatedAt,
);

String? _firstError(Map<String, dynamic> json) {
  final errors = json['errors'];
  if (errors is! List || errors.isEmpty) {
    final message = _string(json['message']);
    return message.isEmpty ? null : message;
  }
  final first = errors.first;
  if (first is Map) {
    final message = _string(first['message']);
    if (message.isNotEmpty) return message;
  }
  return null;
}

String _string(Object? value) => value is String ? value.trim() : '';

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;
