// The `[google]` section: what the shell does with the Google account signed
// in under Settings › Accounts.
//
// The account itself (the client and the grant) is not here. It lives in the
// XDG state directory (`google_account_file.dart`), because `config.toml` is
// the file people paste into bug reports.

import 'package:moonswing/config_reader.dart';

/// The `[google]` section.
class GoogleConfig {
  const GoogleConfig({
    this.calendars = const ['primary'],
    this.showInCalendar = true,
    this.todoSync = false,
    this.refreshMinutes = 5,
  });

  /// The calendar ids read, as the calendar list spells them. `primary` is
  /// Google's own alias for an account's main calendar, and here means every
  /// signed-in account's. Calendar ids are unique across accounts (a primary
  /// calendar's id is the account's address), so one list serves them all.
  final List<String> calendars;

  /// Whether the Calendar tab shows the account's events.
  final bool showInCalendar;

  /// Whether today's timed events become cards on the todo board.
  final bool todoSync;

  /// How often events are re-read while something is showing them.
  final int refreshMinutes;

  static const int minRefreshMinutes = 1;
  static const int maxRefreshMinutes = 60;

  factory GoogleConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const GoogleConfig();
    final calendars = map
        .stringListOr('calendars', const ['primary'])
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    return GoogleConfig(
      calendars: calendars,
      showInCalendar: map.boolOr('show_in_calendar', true),
      todoSync: map.boolOr('todo_sync', false),
      refreshMinutes: map.intOr(
        'refresh_minutes',
        5,
        min: minRefreshMinutes,
        max: maxRefreshMinutes,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoogleConfig &&
          _listEquals(other.calendars, calendars) &&
          other.showInCalendar == showInCalendar &&
          other.todoSync == todoSync &&
          other.refreshMinutes == refreshMinutes;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(calendars),
    showInCalendar,
    todoSync,
    refreshMinutes,
  );
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Whether the calendar [id] is read under [selected]; [primary] says it is
/// its account's own calendar, which `primary` selects too.
bool isCalendarSelected(
  List<String> selected, {
  required String id,
  required bool primary,
}) => selected.contains(id) || (primary && selected.contains('primary'));

/// [selected] with the calendar [id] switched [on] or off.
///
/// [primaries] are the ids of every signed-in account's own calendar. Turning
/// one of them off while `primary` stands for all of them spells the others
/// out; turning the last of them back on folds them into `primary` again, so a
/// config written with one account keeps reading as it did.
List<String> toggleCalendar(
  List<String> selected, {
  required String id,
  required bool primary,
  required bool on,
  required List<String> primaries,
}) {
  var next = [...selected];
  if (primary && !on && next.contains('primary')) {
    final at = next.indexOf('primary');
    next
      ..removeAt(at)
      ..insertAll(at, [
        for (final p in primaries)
          if (p != id && !next.contains(p)) p,
      ]);
  }
  next.remove(id);
  if (on && !isCalendarSelected(next, id: id, primary: primary)) {
    next.add(id);
  }
  if (primary &&
      primaries.isNotEmpty &&
      !next.contains('primary') &&
      primaries.every(next.contains)) {
    final folded = <String>[];
    for (final c in next) {
      if (!primaries.contains(c)) {
        folded.add(c);
      } else if (!folded.contains('primary')) {
        folded.add('primary');
      }
    }
    next = folded;
  }
  return next;
}
