// What the Code tab shows, as plain data: the pull and merge requests, issues
// and inbox threads of every linked forge, folded into one shape, and the
// arithmetic that says which of them have been left too long.
//
// Flutter-free and pure — no I/O, no clock of its own — so
// `test/code_model_test.dart` pins staleness, ordering and the board's
// grouping with a `now` it chooses. The two forges' parsers
// (`code_github.dart`, `gitlab/gitlab_api.dart`) produce these types and
// nothing downstream of them knows which forge an item came from except by
// [CodeProvider], which is drawn as the forge's mark and nothing more.

import 'package:flutter/foundation.dart' show immutable, listEquals;

/// The forge an item lives on.
enum CodeProvider {
  github('GitHub'),
  gitlab('GitLab');

  const CodeProvider(this.label);

  /// The service's own name, spelled its own way.
  final String label;
}

/// A pull (or merge) request, or an issue.
enum CodeItemKind { pullRequest, issue }

/// What a change's checks or pipeline last said.
enum CodeChecks {
  /// No checks, or the forge did not say.
  none,
  pending,
  passing,
  failing,
}

/// Where a change's review stands.
enum CodeReview {
  /// No review policy, or the forge did not say.
  none,

  /// Waiting for an approving review.
  required,
  approved,
  changesRequested,
}

/// How long an item has gone without anything happening on it, in three
/// steps: [fresh], [aging] once half its threshold has gone by, [stale] past
/// the threshold — which is the point at which the Code tab says so out loud.
enum CodeStaleness {
  fresh,
  aging,
  stale;

  bool get isStale => this == stale;
}

/// [updated] against [threshold] at [now].
///
/// No timestamp is [CodeStaleness.fresh]: an item the forge would not date is
/// not one to nag about. A timestamp in the future — a clock that is behind the
/// forge's — is no time at all, never a negative one.
CodeStaleness stalenessOf(
  DateTime? updated, {
  required Duration threshold,
  required DateTime now,
}) {
  if (updated == null || threshold <= Duration.zero) {
    return CodeStaleness.fresh;
  }
  final idle = now.difference(updated);
  if (idle >= threshold) return CodeStaleness.stale;
  if (idle * 2 >= threshold) return CodeStaleness.aging;
  return CodeStaleness.fresh;
}

/// How long ago [time] was, as a list column has room for it: `now`, `4m`,
/// `3h`, `6d`, `5w`. Empty for no timestamp. The same steps as the GitHub
/// popup's ages, so a thread reads the same in both.
String codeAge(DateTime? time, {required DateTime now}) {
  if (time == null) return '';
  final elapsed = now.difference(time);
  if (elapsed.inMinutes < 1) return 'now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m';
  if (elapsed.inHours < 24) return '${elapsed.inHours}h';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d';
  return '${elapsed.inDays ~/ 7}w';
}

/// The same span in words, for a tooltip: "3 days", "an hour", "2 weeks".
String codeAgeWords(DateTime? time, {required DateTime now}) {
  if (time == null) return '';
  final elapsed = now.difference(time);
  String plural(int n, String unit) =>
      n == 1 ? (unit == 'hour' ? 'an hour' : 'a $unit') : '$n ${unit}s';
  if (elapsed.inMinutes < 1) return 'a moment';
  if (elapsed.inMinutes < 60) return plural(elapsed.inMinutes, 'minute');
  if (elapsed.inHours < 24) return plural(elapsed.inHours, 'hour');
  if (elapsed.inDays < 14) return plural(elapsed.inDays, 'day');
  return plural(elapsed.inDays ~/ 7, 'week');
}

/// One pull request, merge request or issue.
@immutable
class CodeItem {
  const CodeItem({
    required this.provider,
    required this.kind,
    required this.id,
    required this.title,
    required this.repository,
    required this.reference,
    required this.url,
    this.author = '',
    this.createdAt,
    this.updatedAt,
    this.mergedAt,
    this.draft = false,
    this.checks = CodeChecks.none,
    this.review = CodeReview.none,
    this.conflicts = false,
    this.comments = 0,
  });

  final CodeProvider provider;
  final CodeItemKind kind;

  /// Unique on its forge; the key a row is built under.
  final String id;

  final String title;

  /// `owner/name` on GitHub, `group/subgroup/project` on GitLab.
  final String repository;

  /// How the forge writes this item's number: `#12` for a GitHub pull request
  /// or any issue, `!12` for a GitLab merge request.
  final String reference;

  /// The item's page — a web URL, never an API one.
  final String url;

  /// Who opened it; empty when the forge did not say (a deleted account).
  final String author;

  final DateTime? createdAt;

  /// The last time anything happened on it — a push, a comment, a review. What
  /// staleness is measured from.
  final DateTime? updatedAt;

  /// When it was merged, for the shipped list.
  final DateTime? mergedAt;

  final bool draft;
  final CodeChecks checks;
  final CodeReview review;

  /// Whether it cannot be merged as it stands.
  final bool conflicts;

  final int comments;

  /// Whether the author has something to do: a reviewer asked for changes,
  /// checks failed, or it no longer merges. What floats a change of the user's
  /// own to the top of their list.
  bool get needsAction =>
      review == CodeReview.changesRequested ||
      checks == CodeChecks.failing ||
      conflicts;

  /// Approved, passing and mergeable: nothing between it and the merge button.
  bool get readyToMerge =>
      !draft &&
      !conflicts &&
      review == CodeReview.approved &&
      checks != CodeChecks.failing &&
      checks != CodeChecks.pending;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodeItem &&
          other.provider == provider &&
          other.kind == kind &&
          other.id == id &&
          other.title == title &&
          other.repository == repository &&
          other.reference == reference &&
          other.url == url &&
          other.author == author &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.mergedAt == mergedAt &&
          other.draft == draft &&
          other.checks == checks &&
          other.review == review &&
          other.conflicts == conflicts &&
          other.comments == comments;

  @override
  int get hashCode => Object.hash(
    provider,
    kind,
    id,
    title,
    repository,
    reference,
    url,
    author,
    createdAt,
    updatedAt,
    mergedAt,
    draft,
    checks,
    review,
    conflicts,
    comments,
  );

  @override
  String toString() => 'CodeItem(${provider.name} $repository$reference)';
}

/// What an inbox thread is about — the glyph its row is drawn with.
enum CodeNoticeSubject {
  pullRequest,
  issue,
  commit,
  release,
  discussion,
  pipeline,
  other,
}

/// One inbox thread: a GitHub notification or a GitLab to-do.
@immutable
class CodeNotice {
  const CodeNotice({
    required this.provider,
    required this.id,
    required this.title,
    required this.repository,
    required this.subject,
    required this.reason,
    required this.url,
    this.unread = true,
    this.updatedAt,
    this.author = '',
  });

  final CodeProvider provider;

  /// The thread or to-do id, which is what marking it read or done takes.
  final String id;

  final String title;
  final String repository;
  final CodeNoticeSubject subject;

  /// Why it arrived, in words: "Review requested", "Mentioned you".
  final String reason;

  final String url;
  final bool unread;
  final DateTime? updatedAt;

  /// Who caused it, where the forge says (a GitLab to-do does).
  final String author;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodeNotice &&
          other.provider == provider &&
          other.id == id &&
          other.title == title &&
          other.repository == repository &&
          other.subject == subject &&
          other.reason == reason &&
          other.url == url &&
          other.unread == unread &&
          other.updatedAt == updatedAt &&
          other.author == author;

  @override
  int get hashCode => Object.hash(
    provider,
    id,
    title,
    repository,
    subject,
    reason,
    url,
    unread,
    updatedAt,
    author,
  );
}

/// Everything one forge said in one read.
@immutable
class CodeSnapshot {
  const CodeSnapshot({
    this.reviews = const [],
    this.authored = const [],
    this.assigned = const [],
    this.merged = const [],
    this.inbox = const [],
    this.reviewsTotal,
    this.authoredTotal,
    this.assignedTotal,
  });

  /// Open changes somebody has asked the user to review.
  final List<CodeItem> reviews;

  /// The user's own open changes.
  final List<CodeItem> authored;

  /// Open issues assigned to the user.
  final List<CodeItem> assigned;

  /// The user's changes merged in the shipped window, newest first.
  final List<CodeItem> merged;

  /// The forge's own inbox, where it is read with the rest — GitLab's to-dos.
  /// GitHub's notifications are `GithubStore`'s, which the bar module shares.
  final List<CodeNotice> inbox;

  /// How many the forge counted, where it counts past the page it sent. Null
  /// when it did not say, which reads as the list's own length.
  final int? reviewsTotal;
  final int? authoredTotal;
  final int? assignedTotal;

  /// A spelling of everything a surface draws, for the store's "did anything
  /// change" test.
  String get signature {
    final buffer = StringBuffer()
      ..write(reviewsTotal)
      ..write('/')
      ..write(authoredTotal)
      ..write('/')
      ..write(assignedTotal);
    for (final list in [reviews, authored, assigned, merged]) {
      buffer.write('§');
      for (final item in list) {
        buffer
          ..write('|')
          ..write(item.hashCode);
      }
    }
    buffer.write('§');
    for (final notice in inbox) {
      buffer
        ..write('|')
        ..write(notice.hashCode);
    }
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodeSnapshot &&
          listEquals(other.reviews, reviews) &&
          listEquals(other.authored, authored) &&
          listEquals(other.assigned, assigned) &&
          listEquals(other.merged, merged) &&
          listEquals(other.inbox, inbox) &&
          other.reviewsTotal == reviewsTotal &&
          other.authoredTotal == authoredTotal &&
          other.assignedTotal == assignedTotal;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(reviews),
    Object.hashAll(authored),
    Object.hashAll(assigned),
    Object.hashAll(merged),
    Object.hashAll(inbox),
    reviewsTotal,
    authoredTotal,
    assignedTotal,
  );
}

/// How long each group may go quiet before it is stale — `[code]`'s three
/// thresholds, in the shape the board needs.
@immutable
class CodeThresholds {
  const CodeThresholds({
    this.review = const Duration(days: 2),
    this.change = const Duration(days: 7),
    this.issue = const Duration(days: 14),
  });

  /// A review somebody is waiting on. Short, because the wait is somebody
  /// else's.
  final Duration review;

  /// One of the user's own open changes.
  final Duration change;

  /// An issue assigned to the user, which moves slower than a change.
  final Duration issue;

  @override
  bool operator ==(Object other) =>
      other is CodeThresholds &&
      other.review == review &&
      other.change == change &&
      other.issue == issue;

  @override
  int get hashCode => Object.hash(review, change, issue);
}

/// The groups the board is drawn in.
enum CodeGroup {
  reviews('Review requests', 'Waiting on your review'),
  authored('Your changes', 'Pull and merge requests you opened'),
  assigned('Assigned issues', 'Open issues assigned to you');

  const CodeGroup(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

/// What the board narrows itself to: everything, one group, or only what has
/// gone stale across all three.
enum CodeFocus { all, reviews, authored, assigned, stale }

/// An item with its staleness worked out, as a row draws it.
@immutable
class CodeEntry {
  const CodeEntry(this.item, this.staleness);

  final CodeItem item;
  final CodeStaleness staleness;

  @override
  bool operator ==(Object other) =>
      other is CodeEntry && other.item == item && other.staleness == staleness;

  @override
  int get hashCode => Object.hash(item, staleness);
}

/// One group, ordered, and how many there are in all.
@immutable
class CodeSection {
  const CodeSection({
    required this.group,
    required this.entries,
    required this.total,
  });

  final CodeGroup group;
  final List<CodeEntry> entries;

  /// What the forges counted, which can be more than [entries] holds: a search
  /// returns a page, and the count beside the heading says how many there are.
  final int total;

  int get staleCount => entries.where((e) => e.staleness.isStale).length;
}

/// The board: three groups, plus the counts the summary tiles show.
@immutable
class CodeBoard {
  const CodeBoard({
    required this.reviews,
    required this.authored,
    required this.assigned,
    required this.merged,
  });

  final CodeSection reviews;
  final CodeSection authored;
  final CodeSection assigned;

  /// Shipped in the window, newest first.
  final List<CodeItem> merged;

  List<CodeSection> get sections => [reviews, authored, assigned];

  /// Everything gone stale, across the three groups.
  int get staleCount =>
      reviews.staleCount + authored.staleCount + assigned.staleCount;

  /// The user's own changes that want something of them.
  int get needsActionCount =>
      authored.entries.where((e) => e.item.needsAction).length;

  /// The user's own changes with nothing left but the merge.
  int get readyCount =>
      authored.entries.where((e) => e.item.readyToMerge).length;

  /// The sections [focus] leaves, each narrowed to what it keeps.
  List<CodeSection> visible(CodeFocus focus) => switch (focus) {
    CodeFocus.all => sections,
    CodeFocus.reviews => [reviews],
    CodeFocus.authored => [authored],
    CodeFocus.assigned => [assigned],
    CodeFocus.stale => [
      for (final section in sections)
        CodeSection(
          group: section.group,
          entries: [
            for (final e in section.entries)
              if (e.staleness.isStale) e,
          ],
          total: section.staleCount,
        ),
    ],
  };
}

/// Folds every forge's snapshot into the board.
///
/// [providers] narrows it to some forges (the tab's GitHub/GitLab switch);
/// null keeps them all. Each group is ordered for what the user does with it:
///
///  * **Reviews**, longest waiting first. Somebody is blocked on each, and the
///    one who has waited longest is the one to go to next — a queue, not a
///    feed.
///  * **The user's changes**, anything that needs them (changes requested,
///    checks failing, conflicts) first, then whatever has gone stale, then the
///    rest most recent first.
///  * **Issues**, stale first, then most recent first.
CodeBoard buildCodeBoard(
  Map<CodeProvider, CodeSnapshot> snapshots, {
  required CodeThresholds thresholds,
  required DateTime now,
  Set<CodeProvider>? providers,
}) {
  final kept = [
    for (final entry in snapshots.entries)
      if (providers == null || providers.contains(entry.key)) entry.value,
  ];

  List<CodeEntry> entries(
    List<CodeItem> Function(CodeSnapshot) pick,
    Duration threshold,
  ) => [
    for (final snapshot in kept)
      for (final item in pick(snapshot))
        CodeEntry(
          item,
          stalenessOf(item.updatedAt, threshold: threshold, now: now),
        ),
  ];

  int total(
    List<CodeItem> Function(CodeSnapshot) pick,
    int? Function(CodeSnapshot) count,
  ) => kept.fold(0, (sum, s) => sum + (count(s) ?? pick(s).length));

  // Oldest first; an undated item last, since nothing says it has waited.
  int oldestFirst(CodeEntry a, CodeEntry b) =>
      _compareDates(a.item.updatedAt, b.item.updatedAt, newestFirst: false);
  int newestFirst(CodeEntry a, CodeEntry b) =>
      _compareDates(a.item.updatedAt, b.item.updatedAt, newestFirst: true);

  final reviews = entries((s) => s.reviews, thresholds.review)
    ..sort(oldestFirst);

  final authored = entries((s) => s.authored, thresholds.change)
    ..sort((a, b) {
      final rank = _authoredRank(a).compareTo(_authoredRank(b));
      return rank != 0 ? rank : newestFirst(a, b);
    });

  final assigned = entries((s) => s.assigned, thresholds.issue)
    ..sort((a, b) {
      final rank = (a.staleness.isStale ? 0 : 1).compareTo(
        b.staleness.isStale ? 0 : 1,
      );
      return rank != 0 ? rank : newestFirst(a, b);
    });

  final merged = [for (final snapshot in kept) ...snapshot.merged]
    ..sort(
      (a, b) => _compareDates(
        a.mergedAt ?? a.updatedAt,
        b.mergedAt ?? b.updatedAt,
        newestFirst: true,
      ),
    );

  return CodeBoard(
    reviews: CodeSection(
      group: CodeGroup.reviews,
      entries: reviews,
      total: total((s) => s.reviews, (s) => s.reviewsTotal),
    ),
    authored: CodeSection(
      group: CodeGroup.authored,
      entries: authored,
      total: total((s) => s.authored, (s) => s.authoredTotal),
    ),
    assigned: CodeSection(
      group: CodeGroup.assigned,
      entries: assigned,
      total: total((s) => s.assigned, (s) => s.assignedTotal),
    ),
    merged: merged,
  );
}

int _authoredRank(CodeEntry e) {
  if (e.item.needsAction) return 0;
  if (e.staleness.isStale) return 1;
  return 2;
}

int _compareDates(DateTime? a, DateTime? b, {required bool newestFirst}) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return newestFirst ? b.compareTo(a) : a.compareTo(b);
}

/// The inbox: every forge's threads, newest first, unread before read.
List<CodeNotice> mergeCodeInbox(
  Iterable<CodeNotice> notices, {
  Set<CodeProvider>? providers,
}) {
  final kept = [
    for (final n in notices)
      if (providers == null || providers.contains(n.provider)) n,
  ];
  kept.sort((a, b) {
    if (a.unread != b.unread) return a.unread ? -1 : 1;
    return _compareDates(a.updatedAt, b.updatedAt, newestFirst: true);
  });
  return kept;
}
