import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/code/code_config.dart';
import 'package:moonswing/code/code_dashboard.dart';
import 'package:moonswing/code/code_github.dart';
import 'package:moonswing/code/code_model.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/gitlab/gitlab_api.dart';
import 'package:moonswing/icons/shell_glyph.dart';

import 'code_fakes.dart';

/// The Code tab's pure half: staleness, the board's grouping and order, both
/// forges' parsers, and `[code]`.
void main() {
  final now = DateTime(2026, 11, 13, 12);
  DateTime ago(Duration d) => now.subtract(d);

  group('stalenessOf', () {
    const week = Duration(days: 7);

    test('fresh, then aging at half the threshold, then stale', () {
      expect(
        stalenessOf(ago(const Duration(days: 1)), threshold: week, now: now),
        CodeStaleness.fresh,
      );
      expect(
        stalenessOf(ago(const Duration(hours: 84)), threshold: week, now: now),
        CodeStaleness.aging,
      );
      expect(
        stalenessOf(ago(week), threshold: week, now: now),
        CodeStaleness.stale,
      );
    });

    test('no date, a future date and no threshold are all fresh', () {
      expect(stalenessOf(null, threshold: week, now: now), CodeStaleness.fresh);
      expect(
        stalenessOf(
          now.add(const Duration(days: 30)),
          threshold: week,
          now: now,
        ),
        CodeStaleness.fresh,
      );
      expect(
        stalenessOf(ago(week * 10), threshold: Duration.zero, now: now),
        CodeStaleness.fresh,
      );
    });
  });

  test('ages read the way the GitHub popup reads them', () {
    expect(codeAge(null, now: now), '');
    expect(codeAge(now, now: now), 'now');
    expect(codeAge(now.add(const Duration(hours: 1)), now: now), 'now');
    expect(codeAge(ago(const Duration(minutes: 4)), now: now), '4m');
    expect(codeAge(ago(const Duration(hours: 3)), now: now), '3h');
    expect(codeAge(ago(const Duration(days: 6)), now: now), '6d');
    expect(codeAge(ago(const Duration(days: 15)), now: now), '2w');
    expect(codeAgeWords(ago(const Duration(hours: 1)), now: now), 'an hour');
    expect(codeAgeWords(ago(const Duration(days: 1)), now: now), 'a day');
    expect(codeAgeWords(ago(const Duration(days: 9)), now: now), '9 days');
    expect(codeAgeWords(ago(const Duration(days: 21)), now: now), '3 weeks');
  });

  group('buildCodeBoard', () {
    const thresholds = CodeThresholds();

    test('reviews are a queue: longest waiting first', () {
      final board = buildCodeBoard(
        {
          CodeProvider.github: CodeSnapshot(
            reviews: [
              testItem(id: 'new', updatedAt: ago(const Duration(hours: 2))),
              testItem(id: 'old', updatedAt: ago(const Duration(days: 5))),
              testItem(id: 'undated'),
            ],
          ),
        },
        thresholds: thresholds,
        now: now,
      );
      expect(
        [for (final e in board.reviews.entries) e.item.id],
        ['old', 'new', 'undated'],
      );
      expect(board.reviews.entries.first.staleness, CodeStaleness.stale);
      expect(board.reviews.staleCount, 1);
    });

    test('your changes: what needs you, then what is stale, then recent', () {
      final board = buildCodeBoard(
        {
          CodeProvider.github: CodeSnapshot(
            authored: [
              testItem(id: 'fresh', updatedAt: ago(const Duration(hours: 1))),
              testItem(id: 'stale', updatedAt: ago(const Duration(days: 9))),
              testItem(
                id: 'failing',
                checks: CodeChecks.failing,
                updatedAt: ago(const Duration(hours: 5)),
              ),
            ],
          ),
        },
        thresholds: thresholds,
        now: now,
      );
      expect(
        [for (final e in board.authored.entries) e.item.id],
        ['failing', 'stale', 'fresh'],
      );
      expect(board.needsActionCount, 1);
    });

    test('both forges fold into one list, and can be narrowed to one', () {
      final snapshots = {
        CodeProvider.github: CodeSnapshot(
          assigned: [
            testItem(id: 'gh', kind: CodeItemKind.issue, updatedAt: now),
          ],
          assignedTotal: 12,
        ),
        CodeProvider.gitlab: CodeSnapshot(
          assigned: [
            testItem(
              id: 'gl',
              provider: CodeProvider.gitlab,
              kind: CodeItemKind.issue,
              updatedAt: ago(const Duration(days: 20)),
            ),
          ],
        ),
      };
      final both = buildCodeBoard(snapshots, thresholds: thresholds, now: now);
      expect([for (final e in both.assigned.entries) e.item.id], ['gl', 'gh']);
      // GitHub counted twelve; GitLab sent no count, so its list is its count.
      expect(both.assigned.total, 13);

      final gitlab = buildCodeBoard(
        snapshots,
        thresholds: thresholds,
        now: now,
        providers: {CodeProvider.gitlab},
      );
      expect([for (final e in gitlab.assigned.entries) e.item.id], ['gl']);
      expect(gitlab.assigned.total, 1);
    });

    test('the stale focus keeps only what has gone quiet, in every group', () {
      final board = buildCodeBoard(
        {
          CodeProvider.github: CodeSnapshot(
            reviews: [
              testItem(id: 'r1', updatedAt: ago(const Duration(days: 3))),
              testItem(id: 'r2', updatedAt: now),
            ],
            authored: [testItem(id: 'a1', updatedAt: now)],
          ),
        },
        thresholds: thresholds,
        now: now,
      );
      expect(board.staleCount, 1);
      final stale = board.visible(CodeFocus.stale);
      expect(stale, hasLength(3));
      expect([for (final e in stale[0].entries) e.item.id], ['r1']);
      expect(stale[1].entries, isEmpty);
      expect(board.visible(CodeFocus.reviews).single.group, CodeGroup.reviews);
      expect(board.visible(CodeFocus.all), hasLength(3));
    });

    test('shipped is newest merge first', () {
      final board = buildCodeBoard(
        {
          CodeProvider.github: CodeSnapshot(
            merged: [
              testItem(id: 'a', mergedAt: ago(const Duration(days: 3))),
              testItem(id: 'b', mergedAt: ago(const Duration(hours: 3))),
            ],
          ),
        },
        thresholds: thresholds,
        now: now,
      );
      expect([for (final m in board.merged) m.id], ['b', 'a']);
    });
  });

  test('the inbox puts unread first, newest first within each', () {
    final inbox = mergeCodeInbox([
      testTodo(id: 'read', unread: false, updatedAt: now),
      testTodo(id: 'old', updatedAt: ago(const Duration(days: 2))),
      testTodo(id: 'new', updatedAt: ago(const Duration(hours: 1))),
    ]);
    expect([for (final n in inbox) n.id], ['new', 'old', 'read']);
    expect(mergeCodeInbox(inbox, providers: {CodeProvider.github}), isEmpty);
  });

  group('status chips', () {
    test('what needs the author comes before good news', () {
      final chips = codeChipsFor(
        testItem(
          conflicts: true,
          checks: CodeChecks.failing,
          review: CodeReview.changesRequested,
        ),
      );
      expect(
        [for (final c in chips) c.label],
        ['Conflicts', 'Changes requested', 'Checks failing'],
      );
      expect(chips.every((c) => c.tone == CodeChipTone.action), isTrue);
    });

    test('approved and passing is ready to merge; issues have none', () {
      final ready = testItem(
        review: CodeReview.approved,
        checks: CodeChecks.passing,
      );
      expect(ready.readyToMerge, isTrue);
      expect(codeChipsFor(ready).single.label, 'Ready to merge');
      expect(
        codeChipsFor(
          testItem(review: CodeReview.approved, draft: true),
        ).map((c) => c.label),
        ['Approved', 'Draft'],
      );
      expect(codeChipsFor(testItem(kind: CodeItemKind.issue)), isEmpty);
    });
  });

  group('GitHub', () {
    test('the searches name the user, or @me before the login lands', () {
      final queries = codeGithubQueries(
        login: 'octocat',
        since: DateTime.utc(2026, 11, 6, 23),
      );
      expect(queries['reviews'], contains('review-requested:octocat'));
      expect(queries['authored'], contains('author:octocat'));
      expect(queries['assigned'], contains('assignee:octocat'));
      expect(queries['merged'], contains('merged:>=2026-11-06'));
      expect(
        codeGithubQueries(login: '', since: now)['reviews'],
        contains('review-requested:@me'),
      );
      final document = codeGithubDocument(login: 'octocat', since: now);
      expect(document, contains('reviews: search(type: ISSUE'));
      expect(document, contains('statusCheckRollup'));
    });

    test('a node becomes a pull request with its checks and review', () {
      final snapshot = parseCodeGithubResponse({
        'data': {
          'authored': {
            'issueCount': 41,
            'nodes': [
              {
                'id': 'PR_1',
                'number': 12,
                'title': 'Float the bar',
                'url': 'https://github.com/o/r/pull/12',
                'isDraft': false,
                'updatedAt': '2026-11-10T10:00:00Z',
                'mergeable': 'CONFLICTING',
                'reviewDecision': 'CHANGES_REQUESTED',
                'repository': {'nameWithOwner': 'o/r'},
                'author': {'login': 'octocat'},
                'comments': {'totalCount': 3},
                'commits': {
                  'nodes': [
                    {
                      'commit': {
                        'statusCheckRollup': {'state': 'FAILURE'},
                      },
                    },
                  ],
                },
              },
              // A result the fragment did not match, and a broken row.
              <String, dynamic>{},
              'nonsense',
            ],
          },
        },
      });
      final pr = snapshot.authored.single;
      expect(pr.reference, '#12');
      expect(pr.repository, 'o/r');
      expect(pr.checks, CodeChecks.failing);
      expect(pr.review, CodeReview.changesRequested);
      expect(pr.conflicts, isTrue);
      expect(pr.comments, 3);
      expect(pr.updatedAt, DateTime.utc(2026, 11, 10, 10).toLocal());
      expect(snapshot.authoredTotal, 41);
      expect(snapshot.reviews, isEmpty);
    });

    test('a partial answer is the data; no data at all is the error', () {
      expect(
        parseCodeGithubResponse({
          'data': {
            'reviews': {'issueCount': 0, 'nodes': []},
          },
          'errors': [
            {'message': 'one search refused'},
          ],
        }).reviews,
        isEmpty,
      );
      expect(
        () => parseCodeGithubResponse({
          'errors': [
            {'message': 'Bad credentials'},
          ],
        }),
        throwsA(
          isA<GithubException>().having(
            (e) => e.message,
            'message',
            'Bad credentials',
          ),
        ),
      );
    });

    test('a notification becomes an inbox thread', () {
      final notice = codeNoticeFromGithub(
        GithubNotification(
          id: '9',
          title: 'Review this',
          repository: 'o/r',
          repositoryUrl: 'https://github.com/o/r',
          type: GithubSubjectType.pullRequest,
          reason: 'review_requested',
          unread: true,
          updatedAt: now,
          url: 'https://github.com/o/r/pull/1',
        ),
      );
      expect(notice.provider, CodeProvider.github);
      expect(notice.subject, CodeNoticeSubject.pullRequest);
      expect(notice.reason, 'Review requested');
    });
  });

  group('GitLab', () {
    test('an instance is named the way an address bar would take it', () {
      expect(gitlabInstanceUri('gitlab.com').toString(), 'https://gitlab.com');
      expect(
        gitlabInstanceUri(' https://Git.Example.org/group/project ').toString(),
        'https://git.example.org',
      );
      expect(
        gitlabInstanceUri('http://localhost:8080').toString(),
        'http://localhost:8080',
      );
      expect(gitlabIsInsecure('http://git.lan.example'), isTrue);
      expect(gitlabInstanceUri(''), isNull);
      expect(gitlabInstanceUri('gitlab'), isNull);
      expect(gitlabInstanceUri('ftp://gitlab.com'), isNull);
    });

    test('the token page has the name and read_api filled in', () {
      final page = gitlabTokenPage(gitlabInstanceUri('gitlab.com')!);
      expect(page.path, '/-/user_settings/personal_access_tokens');
      expect(page.queryParameters, {'name': 'Moonswing', 'scopes': 'read_api'});
    });

    test('a merge request reads its status into checks, review, conflicts', () {
      CodeItem mr(String status, {bool draft = false}) =>
          parseGitlabMergeRequest({
            'id': 1,
            'iid': 4,
            'title': 'Tidy',
            'web_url': 'https://gitlab.com/g/p/-/merge_requests/4',
            'references': {'full': 'g/sub/p!4'},
            'detailed_merge_status': status,
            'draft': draft,
            'user_notes_count': 2,
            'author': {'username': 'tanuki'},
          })!;
      final failing = mr('ci_must_pass');
      expect(failing.repository, 'g/sub/p');
      expect(failing.reference, '!4');
      expect(failing.checks, CodeChecks.failing);
      expect(failing.comments, 2);
      expect(mr('ci_still_running').checks, CodeChecks.pending);
      expect(mr('not_approved').review, CodeReview.required);
      expect(mr('requested_changes').review, CodeReview.changesRequested);
      expect(mr('conflict').conflicts, isTrue);
      expect(mr('need_rebase').conflicts, isTrue);
      expect(mr('mergeable').readyToMerge, isTrue);
      expect(mr('draft_status').draft, isTrue);
      expect(mr('unchecked', draft: true).draft, isTrue);
    });

    test('a row that will not parse costs that row', () {
      expect(
        parseGitlabMergeRequests([
          {'id': 'x'},
          'nonsense',
          {'id': 2, 'web_url': 'https://gitlab.com/g/p/-/merge_requests/1'},
        ]),
        hasLength(1),
      );
      expect(parseGitlabIssues('not a list'), isEmpty);
      final issue = parseGitlabIssue({
        'id': 5,
        'iid': 9,
        'web_url': 'https://gitlab.com/g/p/-/issues/9',
        'references': {'full': 'g/p#9'},
      })!;
      expect(issue.kind, CodeItemKind.issue);
      expect(issue.reference, '#9');
    });

    test('a to-do reads as an inbox thread', () {
      final todo = parseGitlabTodo({
        'id': 77,
        'action_name': 'review_requested',
        'target_type': 'MergeRequest',
        'target': {'title': 'Tidy the tanuki'},
        'target_url': 'https://gitlab.com/g/p/-/merge_requests/1',
        'project': {'path_with_namespace': 'g/p'},
        'author': {'username': 'alice'},
        'state': 'pending',
        'updated_at': '2026-11-12T09:00:00Z',
      })!;
      expect(todo.id, '77');
      expect(todo.reason, 'Review requested');
      expect(todo.subject, CodeNoticeSubject.pullRequest);
      expect(todo.unread, isTrue);
      expect(gitlabTodoReason('some_new_thing'), 'Some new thing');
    });

    test('a user needs an id and a name, or it is not GitLab', () {
      expect(
        parseGitlabUser({'id': 3, 'username': 'tanuki'})?.username,
        'tanuki',
      );
      expect(parseGitlabUser({'message': '404 Not Found'}), isNull);
      expect(parseGitlabUser('<html>'), isNull);
    });
  });

  group('[code]', () {
    test('defaults, clamps, and a wrong type costing only its key', () {
      expect(CodeConfig.fromMap(null), const CodeConfig());
      final config = CodeConfig.fromMap({
        'refresh_minutes': 0,
        'review_stale_days': 3.0,
        'stale_days': 'soon',
        'issue_stale_days': 9999,
        'shipped_days': 14,
      });
      expect(config.refreshMinutes, CodeConfig.minRefreshMinutes);
      expect(config.reviewStaleDays, 3);
      expect(config.staleDays, CodeConfig.defaultStaleDays);
      expect(config.issueStaleDays, CodeConfig.maxStaleDays);
      expect(config.shippedDays, 14);
      expect(config.thresholds.review, const Duration(days: 3));
    });
  });

  test('the brand glyphs exist for both forges', () {
    expect(ShellGlyph.gitlab.isBrand, isTrue);
    expect(ShellGlyph.code.isBrand, isFalse);
  });
}
