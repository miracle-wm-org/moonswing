// `[modules.github]`, beside the feature it configures rather than in
// `config.dart`, the shape `weather_config.dart` and `capture_config.dart` have:
// the store reads it and the bar module re-exports it.

import 'package:moonswing/config_reader.dart';
import 'package:moonswing/github/github_api.dart';

/// The GitHub module's options.
class GithubConfig {
  const GithubConfig({
    this.refreshSeconds = kGithubMinPollSeconds,
    this.showCount = true,
    this.participatingOnly = false,
    this.includeRead = false,
    this.markReadOnOpen = true,
    this.clientId = kGithubDefaultClientId,
    this.scopes = kGithubDefaultScopes,
  });

  /// How long between polls, in seconds.
  ///
  /// Floored at GitHub's own minimum, and only ever a floor: the API reports
  /// what it wants per response in `X-Poll-Interval`, and when that is longer
  /// than this the *server* wins. A client that polls faster than it is asked to
  /// gets rate-limited off the endpoint, which is a dead module rather than a
  /// fast one.
  final int refreshSeconds;

  /// Whether the bar shows the unread count beside the icon.
  final bool showCount;

  /// Only threads the user is directly involved in — mentioned, assigned,
  /// review requested — rather than everything they watch.
  final bool participatingOnly;

  /// Also list threads already marked read.
  final bool includeRead;

  /// Whether opening a notification marks its thread read, which is what
  /// clicking one on github.com does.
  final bool markReadOnOpen;

  /// The OAuth app the device flow runs against. See [kGithubDefaultClientId]
  /// for why there is a default at all.
  final String clientId;

  /// The scopes the sign-in asks for, space-separated. See
  /// [kGithubDefaultScopes]: `notifications` is the least that answers the
  /// question, and private repositories need `repo` on top of it.
  final String scopes;

  static GithubConfig fromMap(Map<String, dynamic>? map) {
    if (map == null) return const GithubConfig();
    const defaults = GithubConfig();
    return GithubConfig(
      // Clamped rather than dropped: a user asking for 10 seconds wants "as
      // often as possible", and the nearest thing GitHub allows is the floor.
      refreshSeconds: map.intOr(
        'refresh_seconds',
        defaults.refreshSeconds,
        min: kGithubMinPollSeconds,
        max: 3600,
      ),
      showCount: map.boolOr('show_count', defaults.showCount),
      participatingOnly:
          map.boolOr('participating_only', defaults.participatingOnly),
      includeRead: map.boolOr('include_read', defaults.includeRead),
      markReadOnOpen: map.boolOr('mark_read_on_open', defaults.markReadOnOpen),
      // An empty string is an absent value here, not a client id of none: a
      // sign-in against `client_id = ""` can only fail.
      clientId: map.stringOrNull('client_id') ?? defaults.clientId,
      scopes: map.stringOrNull('scopes') ?? defaults.scopes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GithubConfig &&
          other.refreshSeconds == refreshSeconds &&
          other.showCount == showCount &&
          other.participatingOnly == participatingOnly &&
          other.includeRead == includeRead &&
          other.markReadOnOpen == markReadOnOpen &&
          other.clientId == clientId &&
          other.scopes == scopes;

  @override
  int get hashCode => Object.hash(
        refreshSeconds,
        showCount,
        participatingOnly,
        includeRead,
        markReadOnOpen,
        clientId,
        scopes,
      );
}
