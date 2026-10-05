// Which web addresses name one issue or pull request on github.com.
//
// Pure and Flutter-free, so `test/github_links_test.dart` can pin every shape a
// pasted link comes in: the tab a pull request was copied from, a comment
// anchor, a trailing slash, `www.`, and the addresses that only look like one.

/// One issue or pull request, by where it lives.
class GithubRef {
  const GithubRef({
    required this.owner,
    required this.repo,
    required this.number,
    required this.isPullRequest,
  });

  final String owner;
  final String repo;
  final int number;

  /// Whether the address said `pull` rather than `issues`. Only a hint for the
  /// icon shown before the answer arrives: the issues endpoint answers for
  /// both, and GitHub itself redirects one to the other.
  final bool isPullRequest;

  /// What the link is called while there is no title for it: `repo#12`.
  String get shortLabel => '$repo#$number';

  /// `owner/repo#12`, the way GitHub writes a reference across repositories.
  String get fullLabel => '$owner/$repo#$number';

  /// One key per issue, whichever way it was linked. GitHub's names are not
  /// case-sensitive, so neither is this.
  String get key => '${owner.toLowerCase()}/${repo.toLowerCase()}/$number';

  @override
  bool operator ==(Object other) =>
      other is GithubRef &&
      other.key == key &&
      other.isPullRequest == isPullRequest;

  @override
  int get hashCode => Object.hash(key, isPullRequest);

  @override
  String toString() => 'GithubRef($fullLabel)';
}

/// The first path segment of a github.com page that is GitHub's own rather
/// than an account's — none of them can own a repository.
const Set<String> _reserved = {
  'orgs',
  'settings',
  'notifications',
  'marketplace',
  'sponsors',
  'apps',
  'search',
  'login',
  'features',
};

/// The issue or pull request [url] links to, or null when it links anywhere
/// else.
///
/// `https://github.com/<owner>/<repo>/pull/<n>` and `…/issues/<n>`, with or
/// without `www.`, and whatever follows the number — `/files`, `/commits`, a
/// `#issuecomment-…` anchor, a query — since that is still the same issue.
/// GitHub Enterprise hosts are not guessed at: the account is github.com's.
GithubRef? parseGithubRef(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  final host = uri.host.toLowerCase();
  if (host != 'github.com' && host != 'www.github.com') return null;
  final segments = uri.pathSegments;
  if (segments.length < 4) return null;
  final owner = segments[0];
  final repo = segments[1];
  final kind = segments[2];
  if (owner.isEmpty || repo.isEmpty) return null;
  if (_reserved.contains(owner.toLowerCase())) return null;
  final bool isPull;
  switch (kind) {
    case 'pull':
      isPull = true;
    case 'issues':
      isPull = false;
    default:
      return null;
  }
  final raw = segments[3];
  // Digits only: `int.tryParse` would take a sign, and `issues/new` is a form.
  if (!RegExp(r'^[0-9]{1,9}$').hasMatch(raw)) return null;
  final number = int.parse(raw);
  if (number <= 0) return null;
  return GithubRef(
    owner: owner,
    repo: repo,
    number: number,
    isPullRequest: isPull,
  );
}
