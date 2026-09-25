// Today's meetings on the todo board.
//
// While `[google] todo_sync` is on and the account is signed in, this holds a
// calendar lease on *today* and hands the day's timed events to
// `TodoStore.applyCalendarSync`, which does the arithmetic
// (`todo_calendar_sync.dart`). It re-applies when the calendar answers, when
// the board finishes loading, and at the next moment some card changes column
// — a one-shot timer to the nearest start or end, or to midnight, when the
// lease moves on to the new day. It never polls the clock. With the feature
// off it holds no lease and no timer, and the shell does no work for it.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/google/google_account_store.dart';
import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/google/google_calendar_store.dart';
import 'package:moonswing/google/google_config.dart';
import 'package:moonswing/todo/todo_calendar_sync.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_store.dart';

/// Keeps the board's calendar cards in step with the calendar.
class GoogleTodoSync {
  GoogleTodoSync({
    GoogleAccountStore? account,
    GoogleCalendarStore? calendar,
    TodoStore? todo,
    DateTime Function()? now,
    bool autoTimers = true,
  }) : _account = account ?? GoogleAccountStore.instance,
       _calendar = calendar ?? GoogleCalendarStore.instance,
       _todo = todo ?? TodoStore.instance,
       _now = now ?? DateTime.now,
       _autoTimers = autoTimers;

  static final GoogleTodoSync instance = GoogleTodoSync();

  final GoogleAccountStore _account;
  final GoogleCalendarStore _calendar;
  final TodoStore _todo;
  final DateTime Function() _now;
  final bool _autoTimers;

  bool _enabled = false;
  bool _listening = false;
  GoogleCalendarLease? _lease;
  Timer? _timer;
  bool _todoWasEditable = false;

  @visibleForTesting
  bool get active => _lease != null;

  /// Applies `[google] todo_sync`.
  void configure(GoogleConfig config) {
    _enabled = config.todoSync;
    if (!_listening) {
      _listening = true;
      _account.addListener(_update);
    }
    _update();
  }

  void _update() {
    final wanted = _enabled && _account.signedIn;
    if (wanted && _lease == null) {
      final day = dateOnly(_now());
      _lease = _calendar.acquire(day, addDays(day, 1));
      _calendar.addListener(_apply);
      _todo.addListener(_onTodo);
      _todoWasEditable = _todo.editable;
      _apply();
    } else if (!wanted && _lease != null) {
      _lease!.release();
      _lease = null;
      _calendar.removeListener(_apply);
      _todo.removeListener(_onTodo);
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Re-applies once the board has loaded; every other board change is the
  /// user's own and needs no sync.
  void _onTodo() {
    final editable = _todo.editable;
    if (editable == _todoWasEditable) return;
    _todoWasEditable = editable;
    if (editable) _apply();
  }

  static CalendarCardSource _source(GoogleEvent e) => CalendarCardSource(
    key: e.key,
    title: e.summary,
    start: e.start,
    end: e.end,
    link: e.meetingLink,
    url: e.htmlLink,
  );

  void _apply() {
    final lease = _lease;
    if (lease == null) return;
    final now = _now();
    final day = dateOnly(now);
    final tomorrow = addDays(day, 1);
    // The day turned over while nothing was watching: move the window, and
    // come back when the calendar has answered for the new day.
    if (lease.from != day) {
      lease.update(day, tomorrow);
    }
    final sources = [
      for (final e in _calendar.eventsOn(day))
        if (!e.allDay) _source(e),
    ];
    // Only a whole answer for today may abandon a card whose event is missing.
    if (_calendar.covers(day, tomorrow)) {
      _todo.applyCalendarSync(sources, day: day);
    }
    _arm(sources, now, tomorrow);
  }

  void _arm(List<CalendarCardSource> sources, DateTime now, DateTime tomorrow) {
    _timer?.cancel();
    _timer = null;
    if (!_autoTimers) return;
    final next = nextCalendarBoundary(sources, now) ?? tomorrow;
    final wake = next.isAfter(tomorrow) ? tomorrow : next;
    // A second past the boundary, so the comparison on waking lands after it.
    _timer = Timer(wake.difference(now) + const Duration(seconds: 1), () {
      _timer = null;
      _apply();
    });
  }

  @visibleForTesting
  void dispose() {
    _enabled = false;
    _update();
    if (_listening) _account.removeListener(_update);
    _listening = false;
  }
}
