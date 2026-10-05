import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_links.dart';

void main() {
  group('parseGithubRef', () {
    test('reads a pull request and an issue', () {
      final pull = parseGithubRef('https://github.com/o/r/pull/12')!;
      expect(
        (pull.owner, pull.repo, pull.number, pull.isPullRequest),
        ('o', 'r', 12, true),
      );
      final issue = parseGithubRef('https://github.com/o/r/issues/7')!;
      expect((issue.number, issue.isPullRequest), (7, false));
      expect(issue.shortLabel, 'r#7');
      expect(issue.fullLabel, 'o/r#7');
    });

    test('takes whatever follows the number as the same issue', () {
      for (final url in [
        'https://github.com/o/r/pull/12/files',
        'https://github.com/o/r/pull/12/',
        'https://github.com/o/r/pull/12#issuecomment-1',
        'https://github.com/o/r/pull/12?w=1',
        'https://www.github.com/o/r/pull/12',
        'http://GitHub.com/o/r/pull/12',
      ]) {
        expect(parseGithubRef(url)?.number, 12, reason: url);
      }
    });

    test('is one key per issue, whichever way and case it was linked', () {
      expect(
        parseGithubRef('https://github.com/O/R/pull/3')!.key,
        parseGithubRef('https://github.com/o/r/issues/3')!.key,
      );
    });

    test('leaves everything else alone', () {
      for (final url in [
        'https://github.com/o/r',
        'https://github.com/o/r/pulls',
        'https://github.com/o/r/issues/new',
        'https://github.com/o/r/issues/-1',
        'https://github.com/o/r/issues/0',
        'https://github.com/o/r/commit/abc123',
        'https://github.com/o/r/discussions/4',
        'https://github.com/orgs/o/projects/1',
        'https://gist.github.com/o/r/issues/1',
        'https://example.com/o/r/pull/1',
        'ftp://github.com/o/r/pull/1',
        'not a url',
      ]) {
        expect(parseGithubRef(url), isNull, reason: url);
      }
    });
  });

  group('parseIssue', () {
    GithubIssueState? stateOf(Map<String, dynamic> json) =>
        parseIssue({'number': 1, 'title': 't', ...json})?.state;

    test('tells the five states apart', () {
      expect(stateOf({'state': 'open'}), GithubIssueState.open);
      expect(
        stateOf({'state': 'closed', 'state_reason': 'completed'}),
        GithubIssueState.completed,
      );
      expect(stateOf({'state': 'closed'}), GithubIssueState.completed);
      expect(
        stateOf({'state': 'closed', 'state_reason': 'not_planned'}),
        GithubIssueState.closed,
      );
      final pull = {'pull_request': <String, dynamic>{}};
      expect(stateOf({...pull, 'state': 'open'}), GithubIssueState.open);
      expect(
        stateOf({...pull, 'state': 'open', 'draft': true}),
        GithubIssueState.draft,
      );
      expect(
        stateOf({
          'pull_request': {'merged_at': '2026-10-01T00:00:00Z'},
          'state': 'closed',
        }),
        GithubIssueState.merged,
      );
      expect(
        stateOf({
          'pull_request': {'merged_at': null},
          'state': 'closed',
        }),
        GithubIssueState.closed,
      );
    });

    test('knows a pull request by its pull_request table', () {
      expect(parseIssue({'number': 1})!.isPullRequest, isFalse);
      expect(
        parseIssue({
          'number': 1,
          'pull_request': <String, dynamic>{},
        })!.isPullRequest,
        isTrue,
      );
    });

    test('degrades: no number is nothing, an odd field is a default', () {
      expect(parseIssue({'title': 'x'}), isNull);
      expect(parseIssue('nope'), isNull);
      final odd = parseIssue({'number': '5', 'title': 3, 'state': 'weird'})!;
      expect(
        (odd.number, odd.title, odd.state),
        (5, '', GithubIssueState.open),
      );
    });
  });
}
