import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/github/github_api.dart';
import 'package:graceful_shell/github/github_config.dart';

/// `[modules.github]`, under the config layer's one rule: a wrongly-typed value
/// costs that key, never the table.
void main() {
  test('an absent table is the defaults', () {
    const defaults = GithubConfig();
    expect(GithubConfig.fromMap(null), defaults);
    expect(GithubConfig.fromMap(const {}), defaults);
    expect(defaults.refreshSeconds, kGithubMinPollSeconds);
    expect(defaults.clientId, kGithubDefaultClientId);
    expect(defaults.scopes, kGithubDefaultScopes);
    expect(defaults.showCount, isTrue);
    expect(defaults.markReadOnOpen, isTrue);
  });

  test('reads what the user wrote', () {
    final config = GithubConfig.fromMap(const {
      'refresh_seconds': 300,
      'show_count': false,
      'participating_only': true,
      'include_read': true,
      'mark_read_on_open': false,
      'client_id': 'Iv1.deadbeef',
      'scopes': 'notifications repo',
    });

    expect(config.refreshSeconds, 300);
    expect(config.showCount, isFalse);
    expect(config.participatingOnly, isTrue);
    expect(config.includeRead, isTrue);
    expect(config.markReadOnOpen, isFalse);
    expect(config.clientId, 'Iv1.deadbeef');
    expect(config.scopes, 'notifications repo');
  });

  test('a cadence below GitHub\'s floor is raised to it, not honoured', () {
    // Polling faster than the API allows is how a client gets rate-limited off
    // the endpoint: a dead module rather than a fast one.
    expect(
      GithubConfig.fromMap(const {'refresh_seconds': 5}).refreshSeconds,
      kGithubMinPollSeconds,
    );
    expect(
      GithubConfig.fromMap(const {'refresh_seconds': 99999}).refreshSeconds,
      3600,
    );
    // A TOML float is a number too.
    expect(
      GithubConfig.fromMap(const {'refresh_seconds': 120.0}).refreshSeconds,
      120,
    );
  });

  test('a wrongly-typed value costs that key alone', () {
    final config = GithubConfig.fromMap(const {
      'refresh_seconds': 'often',
      'show_count': 'yes',
      'client_id': 42,
      'scopes': '   ',
      'participating_only': true,
    });

    const defaults = GithubConfig();
    expect(config.refreshSeconds, defaults.refreshSeconds);
    expect(config.showCount, defaults.showCount);
    expect(config.clientId, defaults.clientId,
        reason: 'a sign-in against a client id of 42 could only fail');
    expect(config.scopes, defaults.scopes);
    expect(config.participatingOnly, isTrue, reason: 'the good key survives');
  });

  test('carries value equality, which is what lets a notifier refuse a rebuild',
      () {
    expect(const GithubConfig(), const GithubConfig());
    expect(const GithubConfig().hashCode, const GithubConfig().hashCode);
    expect(
      const GithubConfig(showCount: false) == const GithubConfig(),
      isFalse,
    );
  });
}
