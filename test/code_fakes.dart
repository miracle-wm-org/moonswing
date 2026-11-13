// Shared fakes for the Code tab and GitLab tests: offline GitLab and GitHub
// dashboard clients, and builders for the items they answer with.
//
// Not a `_test.dart` file, so `flutter test` does not try to run it. Nothing
// here opens a socket.

import 'dart:async';

import 'package:moonswing/code/code_github.dart';
import 'package:moonswing/code/code_model.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/gitlab/gitlab_api.dart';

/// A GitLab that answers from what it was handed.
class FakeGitlabClient implements GitlabClient {
  FakeGitlabClient({
    this.user = const GitlabUser(id: 7, username: 'tanuki', name: 'Tanuki'),
    this.snapshot = const CodeSnapshot(),
  });

  GitlabUser user;
  CodeSnapshot snapshot;
  GitlabException? failUserWith;
  GitlabException? failFetchWith;
  GitlabException? failWriteWith;

  /// When set, [fetchUser] waits on it — a connect held in flight.
  Completer<void>? userGate;

  int userCalls = 0;
  int fetchCalls = 0;
  Uri? lastInstance;
  String? lastToken;
  String? lastUsername;
  final List<String> done = [];
  int allDoneCalls = 0;

  @override
  Future<GitlabUser> fetchUser({
    required Uri instance,
    required String token,
  }) async {
    userCalls++;
    lastInstance = instance;
    lastToken = token;
    final gate = userGate;
    if (gate != null) await gate.future;
    final failure = failUserWith;
    if (failure != null) throw failure;
    return user;
  }

  @override
  Future<CodeSnapshot> fetchDashboard({
    required Uri instance,
    required String token,
    required String username,
    required DateTime since,
  }) async {
    fetchCalls++;
    lastInstance = instance;
    lastToken = token;
    lastUsername = username;
    final failure = failFetchWith;
    if (failure != null) throw failure;
    return snapshot;
  }

  @override
  Future<void> markTodoDone({
    required Uri instance,
    required String token,
    required String id,
  }) async {
    final failure = failWriteWith;
    if (failure != null) throw failure;
    done.add(id);
  }

  @override
  Future<void> markAllTodosDone({
    required Uri instance,
    required String token,
  }) async {
    allDoneCalls++;
    final failure = failWriteWith;
    if (failure != null) throw failure;
  }
}

/// GitHub's half of the Code tab, answering from what it was handed.
class FakeCodeGithubClient implements CodeGithubClient {
  FakeCodeGithubClient({this.snapshot = const CodeSnapshot()});

  CodeSnapshot snapshot;
  GithubException? failWith;
  int calls = 0;
  String? lastLogin;
  DateTime? lastSince;

  @override
  Future<CodeSnapshot> fetch({
    required String token,
    required String login,
    required DateTime since,
  }) async {
    calls++;
    lastLogin = login;
    lastSince = since;
    final failure = failWith;
    if (failure != null) throw failure;
    return snapshot;
  }
}

/// An item with everything a test does not care about filled in.
CodeItem testItem({
  String id = '1',
  CodeProvider provider = CodeProvider.github,
  CodeItemKind kind = CodeItemKind.pullRequest,
  String title = 'Make the bar float',
  String repository = 'miracle-wm-org/moonswing',
  String reference = '#1',
  String author = 'octocat',
  DateTime? updatedAt,
  DateTime? mergedAt,
  bool draft = false,
  CodeChecks checks = CodeChecks.none,
  CodeReview review = CodeReview.none,
  bool conflicts = false,
  int comments = 0,
}) => CodeItem(
  provider: provider,
  kind: kind,
  id: id,
  title: title,
  repository: repository,
  reference: reference,
  url: 'https://github.com/$repository/pull/$id',
  author: author,
  updatedAt: updatedAt,
  mergedAt: mergedAt,
  draft: draft,
  checks: checks,
  review: review,
  conflicts: conflicts,
  comments: comments,
);

/// A GitLab to-do.
CodeNotice testTodo({
  String id = '100',
  String title = 'Tidy the tanuki',
  bool unread = true,
  DateTime? updatedAt,
}) => CodeNotice(
  provider: CodeProvider.gitlab,
  id: id,
  title: title,
  repository: 'group/project',
  subject: CodeNoticeSubject.pullRequest,
  reason: 'Review requested',
  url: 'https://gitlab.com/group/project/-/merge_requests/1',
  unread: unread,
  updatedAt: updatedAt,
);
