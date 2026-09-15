import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/github/github_api.dart';
import 'package:graceful_shell/modules/github.dart' show githubAge;

/// The pure half of the GitHub module: what a response means, and where a click
/// goes. Nothing here opens a socket.
void main() {
  group('the notification list', () {
    test('parses a thread', () {
      final items = parseNotifications([
        {
          'id': '4711',
          'unread': true,
          'reason': 'review_requested',
          'updated_at': '2026-09-15T12:00:00Z',
          'subject': {
            'title': 'Add a GitHub module',
            'type': 'PullRequest',
            'url': 'https://api.github.com/repos/octo/shell/pulls/12',
          },
          'repository': {
            'full_name': 'octo/shell',
            'html_url': 'https://github.com/octo/shell',
          },
        },
      ]);

      expect(items, hasLength(1));
      final item = items.single;
      expect(item.id, '4711');
      expect(item.title, 'Add a GitHub module');
      expect(item.repository, 'octo/shell');
      expect(item.type, GithubSubjectType.pullRequest);
      expect(item.unread, isTrue);
      expect(item.url, 'https://github.com/octo/shell/pull/12');
      expect(item.updatedAt, DateTime.utc(2026, 9, 15, 12).toLocal());
    });

    test('a malformed row costs that row, never the list', () {
      final items = parseNotifications([
        'not a thread',
        {'id': ''},
        {'subject': 'not a table'},
        {
          'id': '2',
          'subject': {'title': 'Survivor', 'type': 'Issue'},
          'repository': {'full_name': 'octo/shell'},
        },
      ]);

      expect(items.map((i) => i.id), ['2']);
      expect(items.single.title, 'Survivor');
      // No subject URL: the click still has somewhere to go.
      expect(items.single.url, 'https://github.com/octo/shell');
    });

    test('a body that is not a list at all is an empty one', () {
      expect(parseNotifications({'message': 'Bad credentials'}), isEmpty);
      expect(parseNotifications(null), isEmpty);
    });

    test('a thread with no unread field is treated as unread', () {
      final item = parseNotification({
        'id': '3',
        'subject': {'title': 'Hello', 'type': 'Issue'},
        'repository': {'full_name': 'octo/shell'},
      });

      expect(item!.unread, isTrue);
    });
  });

  group('the web URL', () {
    const repo = 'https://github.com/octo/shell';

    test('rewrites the API paths a click can follow', () {
      expect(
        githubWebUrl(
          subjectUrl: 'https://api.github.com/repos/octo/shell/pulls/12',
          type: GithubSubjectType.pullRequest,
          repositoryUrl: repo,
        ),
        // `pulls` in the API, `pull` on the website: the one rewrite that is
        // not a copy.
        'https://github.com/octo/shell/pull/12',
      );
      expect(
        githubWebUrl(
          subjectUrl: 'https://api.github.com/repos/octo/shell/issues/9',
          type: GithubSubjectType.issue,
          repositoryUrl: repo,
        ),
        'https://github.com/octo/shell/issues/9',
      );
      expect(
        githubWebUrl(
          subjectUrl: 'https://api.github.com/repos/octo/shell/commits/abc123',
          type: GithubSubjectType.commit,
          repositoryUrl: repo,
        ),
        'https://github.com/octo/shell/commit/abc123',
      );
    });

    test('falls back to the repository for a subject it cannot rewrite', () {
      // A release: its API id is not the tag the website's URL is built from,
      // and a wrong link is worse than a general one.
      expect(
        githubWebUrl(
          subjectUrl: 'https://api.github.com/repos/octo/shell/releases/77',
          type: GithubSubjectType.release,
          repositoryUrl: repo,
        ),
        repo,
      );
      // A Discussion, which arrives with no subject URL at all.
      expect(
        githubWebUrl(
          subjectUrl: '',
          type: GithubSubjectType.discussion,
          repositoryUrl: repo,
        ),
        repo,
      );
      expect(
        githubWebUrl(
          subjectUrl: 'nonsense',
          type: GithubSubjectType.other,
          repositoryUrl: repo,
        ),
        repo,
      );
    });

    test('keeps an Enterprise host, minus the api prefix', () {
      expect(
        githubWebUrl(
          subjectUrl: 'https://github.example.com/api/v3/repos/o/r/issues/4',
          type: GithubSubjectType.issue,
          repositoryUrl: 'https://github.example.com/o/r',
        ),
        'https://github.example.com/o/r/issues/4',
      );
    });
  });

  group('the device flow', () {
    test('parses the code GitHub hands back', () {
      final code = GithubDeviceCode.fromJson(const {
        'device_code': 'dc',
        'user_code': 'ABCD-1234',
        'verification_uri': 'https://github.com/login/device',
        'interval': 5,
        'expires_in': 899,
      });

      expect(code.userCode, 'ABCD-1234');
      expect(code.interval, 5);
      expect(code.expiresIn, 899);
    });

    test('a response with no code is a failure, not an empty sign-in', () {
      expect(
        () => GithubDeviceCode.fromJson(const {
          'error': 'unauthorized_client',
          'error_description': 'Device flow is not enabled for this app',
        }),
        throwsA(isA<GithubException>().having(
          (e) => e.message,
          'message',
          'Device flow is not enabled for this app',
        )),
      );
    });

    test('a missing interval does not become a zero-second poll', () {
      final code = GithubDeviceCode.fromJson(const {
        'device_code': 'dc',
        'user_code': 'ABCD-1234',
      });

      expect(code.interval, 5);
      expect(code.verificationUri, 'https://github.com/login/device');
    });

    test('pending, slow down, and granted are the three normal answers', () {
      expect(
        parseTokenResponse(const {'error': 'authorization_pending'}),
        isA<GithubTokenPending>()
            .having((r) => r.slowDown, 'slowDown', isFalse),
      );
      expect(
        parseTokenResponse(const {'error': 'slow_down'}),
        isA<GithubTokenPending>().having((r) => r.slowDown, 'slowDown', isTrue),
      );
      expect(
        parseTokenResponse(const {'access_token': 'gho_abc'}),
        isA<GithubTokenGranted>().having((r) => r.token, 'token', 'gho_abc'),
      );
    });

    test('the terminal failures end the sign-in with a reason', () {
      expect(
        () => parseTokenResponse(const {'error': 'expired_token'}),
        throwsA(isA<GithubException>()),
      );
      expect(
        () => parseTokenResponse(const {'error': 'access_denied'}),
        throwsA(isA<GithubException>()),
      );
    });
  });

  group('labels', () {
    test('names the reasons a thread arrives for', () {
      expect(githubReasonLabel('review_requested'), 'Review requested');
      expect(githubReasonLabel('mention'), 'Mentioned you');
      expect(githubReasonLabel(''), '');
      // A reason invented after this was written still reads as English.
      expect(githubReasonLabel('some_new_reason'), 'Some new reason');
    });

    test('an age fits the two characters the row has for it', () {
      final now = DateTime(2026, 9, 15, 12);
      expect(githubAge(null), '');
      expect(githubAge(now.subtract(const Duration(seconds: 20)), now: now),
          'now');
      expect(githubAge(now.subtract(const Duration(minutes: 5)), now: now), '5m');
      expect(githubAge(now.subtract(const Duration(hours: 3)), now: now), '3h');
      expect(githubAge(now.subtract(const Duration(days: 4)), now: now), '4d');
      expect(githubAge(now.subtract(const Duration(days: 15)), now: now), '2w');
      // A clock that stepped backwards is "now", never a negative.
      expect(githubAge(now.add(const Duration(minutes: 5)), now: now), 'now');
    });
  });
}
