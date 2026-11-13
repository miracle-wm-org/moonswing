// `[code]`, as a typed object.
//
// A section of its own rather than `[modules.*]`: nothing in a panel reads it.
// The Code tab is the overview's, and its settings sit on a Shell page of their
// own; the accounts it reads are not config at all (Settings › Accounts).

import 'package:moonswing/code/code_model.dart';
import 'package:moonswing/config_reader.dart';

class CodeConfig {
  const CodeConfig({
    this.refreshMinutes = defaultRefreshMinutes,
    this.reviewStaleDays = defaultReviewStaleDays,
    this.staleDays = defaultStaleDays,
    this.issueStaleDays = defaultIssueStaleDays,
    this.shippedDays = defaultShippedDays,
  });

  static const int defaultRefreshMinutes = 5;
  static const int minRefreshMinutes = 1;
  static const int maxRefreshMinutes = 120;

  static const int defaultReviewStaleDays = 2;
  static const int defaultStaleDays = 7;
  static const int defaultIssueStaleDays = 14;
  static const int minStaleDays = 1;
  static const int maxStaleDays = 365;

  static const int defaultShippedDays = 7;
  static const int minShippedDays = 1;
  static const int maxShippedDays = 90;

  /// How often the forges are read again while the Code tab is showing. Never
  /// while it is not: the tab holds the only lease.
  final int refreshMinutes;

  /// Days a review request may wait before it is stale. Short, because the
  /// wait is somebody else's.
  final int reviewStaleDays;

  /// Days one of the user's own open changes may go quiet.
  final int staleDays;

  /// Days an assigned issue may go quiet.
  final int issueStaleDays;

  /// How far back the shipped list reaches.
  final int shippedDays;

  CodeThresholds get thresholds => CodeThresholds(
    review: Duration(days: reviewStaleDays),
    change: Duration(days: staleDays),
    issue: Duration(days: issueStaleDays),
  );

  factory CodeConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const CodeConfig();
    int days(String key, int fallback) =>
        map.intOr(key, fallback, min: minStaleDays, max: maxStaleDays);
    return CodeConfig(
      refreshMinutes: map.intOr(
        'refresh_minutes',
        defaultRefreshMinutes,
        min: minRefreshMinutes,
        max: maxRefreshMinutes,
      ),
      reviewStaleDays: days('review_stale_days', defaultReviewStaleDays),
      staleDays: days('stale_days', defaultStaleDays),
      issueStaleDays: days('issue_stale_days', defaultIssueStaleDays),
      shippedDays: map.intOr(
        'shipped_days',
        defaultShippedDays,
        min: minShippedDays,
        max: maxShippedDays,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodeConfig &&
          other.refreshMinutes == refreshMinutes &&
          other.reviewStaleDays == reviewStaleDays &&
          other.staleDays == staleDays &&
          other.issueStaleDays == issueStaleDays &&
          other.shippedDays == shippedDays;

  @override
  int get hashCode => Object.hash(
    refreshMinutes,
    reviewStaleDays,
    staleDays,
    issueStaleDays,
    shippedDays,
  );
}
