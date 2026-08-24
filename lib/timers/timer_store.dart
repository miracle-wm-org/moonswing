import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/timers/timer_format.dart';

/// How often the store re-notifies while something is counting.
///
/// The readouts show whole seconds, so the *content* only changes once a
/// second — but the entries are not aligned to each other or to the wall clock,
/// and a one-second period would leave a countdown's own boundary up to a full
/// second late. Four times a second is close enough that no transition reads as
/// stuck, and it costs nothing when nothing is running: the ticker exists only
/// while at least one entry is, the [SystemStatsStore] lease discipline applied
/// to a store whose consumers cannot hold leases.
const Duration kTimerTickInterval = Duration(milliseconds: 250);

/// Which way an entry counts.
enum ShellTimerKind {
  /// Counts down from [ShellTimer.total] and announces itself at zero.
  timer,

  /// Counts up from zero, with no end.
  stopwatch,
}

/// One running (or paused, or finished) timer or stopwatch.
///
/// The elapsed time is *derived*, never accumulated by the ticker: an entry
/// holds the time banked by previous runs plus the instant the current run
/// began, and every readout is a subtraction against the wall clock. A ticker
/// that added its own period instead would drift by however much the frame it
/// woke on was late, and would lose the whole of a suspend.
@immutable
class ShellTimer {
  const ShellTimer({
    required this.id,
    required this.kind,
    required this.total,
    required this.accumulated,
    required this.startedAt,
    this.finished = false,
  });

  /// Stable within a session, and never reused — the popup and the calendar
  /// page address entries by it.
  final int id;

  final ShellTimerKind kind;

  /// What a countdown counts down from. [Duration.zero] for a stopwatch.
  final Duration total;

  /// Time banked by runs that have already been paused.
  final Duration accumulated;

  /// When the current run began, or null when the entry is not running.
  final DateTime? startedAt;

  /// Whether a countdown has reached zero. Never true for a stopwatch.
  final bool finished;

  bool get running => startedAt != null;

  /// How long this entry has been counting, at [now].
  ///
  /// A backwards clock step (NTP, a resume from suspend on a machine whose RTC
  /// disagreed) yields a negative difference; it is dropped rather than
  /// subtracted, so a readout can stall but can never run backwards.
  Duration elapsedAt(DateTime now) {
    final start = startedAt;
    if (start == null) return accumulated;
    final delta = now.difference(start);
    return delta.isNegative ? accumulated : accumulated + delta;
  }

  /// What the readout shows: time left for a countdown, time spent for a
  /// stopwatch. Never negative.
  Duration displayAt(DateTime now) {
    final elapsed = elapsedAt(now);
    if (kind == ShellTimerKind.stopwatch) {
      return elapsed.isNegative ? Duration.zero : elapsed;
    }
    final left = total - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// Sentinel for [copyWith], so `startedAt: null` can mean "not running"
  /// rather than "leave it alone".
  static const Object _keep = Object();

  ShellTimer copyWith({
    Duration? total,
    Duration? accumulated,
    Object? startedAt = _keep,
    bool? finished,
  }) {
    return ShellTimer(
      id: id,
      kind: kind,
      total: total ?? this.total,
      accumulated: accumulated ?? this.accumulated,
      startedAt: identical(startedAt, _keep)
          ? this.startedAt
          : startedAt as DateTime?,
      finished: finished ?? this.finished,
    );
  }
}

/// The shell's timers and stopwatches.
///
/// Same singleton-[ChangeNotifier] shape as [OsdStore] and `ThemeStore`: the
/// calendar page and the clock module's bar readout are separate widget trees
/// in separate FlutterViews, so a store is the only thing that can hold state
/// both of them see.
///
/// Four things a change here has to keep true:
///
///  * **Nothing is persisted.** A countdown restored across a shell restart is
///    either wrong (the shell was down for longer than it had left) or a
///    surprise, and a stopwatch that survived one measures nothing the user
///    asked it to. Timers are runtime state like the OSD's, so there is no
///    config schema, no start-up service, and nothing for `main()` to await.
///  * **Stopping removes.** "Stopped" is what makes an entry stop rendering in
///    the bar, so the verb has to be a removal rather than a third state —
///    otherwise the clock module would need its own rule for which non-running
///    entries still count, and a paused timer (which must stay visible, or the
///    user could not resume it) would be indistinguishable from a stopped one.
///  * **The ticker exists only while something runs.** It is started and
///    stopped by [_syncTicker] off every mutation, so an idle shell with no
///    timers wakes for this store exactly never.
///  * **Elapsed time is derived, not counted.** See [ShellTimer.elapsedAt] —
///    the ticker's only job is to ask for a repaint.
class TimersStore extends ChangeNotifier {
  TimersStore._({
    DateTime Function()? now,
    this.tickInterval = kTimerTickInterval,
    bool autoTick = true,
  }) : _now = now ?? DateTime.now,
       _autoTick = autoTick;

  static final TimersStore instance = TimersStore._()
    // The one wiring the singleton needs, and it is deliberately here rather
    // than in a start-up service: a finished countdown that announced itself
    // only in the bar is one the user misses the moment they look away, and
    // the shell is its own notification daemon, so this is a store write.
    ..onFinished = postTimerFinishedNotification;

  /// A store a test drives by hand.
  ///
  /// [autoTick] is false because a pending [Timer] fails the widget binding's
  /// end-of-test invariants, and because a test that wants to watch a countdown
  /// finish should step its own clock rather than wait out real seconds. Call
  /// [tick] to advance it.
  @visibleForTesting
  factory TimersStore.forTesting({
    DateTime Function()? now,
    Duration tickInterval = kTimerTickInterval,
    bool autoTick = false,
  }) {
    return TimersStore._(
      now: now,
      tickInterval: tickInterval,
      autoTick: autoTick,
    );
  }

  final DateTime Function() _now;
  final bool _autoTick;

  /// How often [tick] runs while something is counting.
  final Duration tickInterval;

  /// Called once, with the finished entry, when a countdown reaches zero.
  ///
  /// Injectable so a unit test of this store never posts into the notification
  /// daemon's store; the singleton wires [postTimerFinishedNotification].
  void Function(ShellTimer entry)? onFinished;

  final List<ShellTimer> _entries = [];
  Timer? _ticker;
  int _nextId = 1;

  /// Every entry, oldest first — running, paused and finished alike. All of
  /// them render; only a [stop] takes one out of this list.
  List<ShellTimer> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  int get length => _entries.length;

  /// The one entry, when there is exactly one — the case the bar renders as a
  /// readout rather than as an icon.
  ShellTimer? get onlyEntry => _entries.length == 1 ? _entries.single : null;

  /// The wall clock the readouts are measured against.
  DateTime get now => _now();

  ShellTimer? entry(int id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Starts a countdown of [duration], and returns its id.
  ///
  /// Durations past [kMaxTimerDuration] are clamped rather than refused: the
  /// parser already rejects them at the field, so anything arriving here is a
  /// caller's arithmetic and clamping keeps the readout's layout honest.
  int startTimer(Duration duration) {
    final total = duration > kMaxTimerDuration ? kMaxTimerDuration : duration;
    return _add(
      ShellTimer(
        id: _nextId++,
        kind: ShellTimerKind.timer,
        total: total.isNegative ? Duration.zero : total,
        accumulated: Duration.zero,
        startedAt: _now(),
      ),
    );
  }

  /// Starts a stopwatch, and returns its id.
  int startStopwatch() {
    return _add(
      ShellTimer(
        id: _nextId++,
        kind: ShellTimerKind.stopwatch,
        total: Duration.zero,
        accumulated: Duration.zero,
        startedAt: _now(),
      ),
    );
  }

  int _add(ShellTimer entry) {
    _entries.add(entry);
    _syncTicker();
    notifyListeners();
    return entry.id;
  }

  /// Banks the current run and stops counting. A no-op on an entry that is
  /// already paused or finished.
  void pause(int id) {
    _mutate(id, (e) {
      if (!e.running) return null;
      return e.copyWith(accumulated: e.elapsedAt(_now()), startedAt: null);
    });
  }

  /// Starts counting again from where [pause] left off.
  ///
  /// A finished countdown is not resumed but restarted — there is nothing left
  /// of it to resume, and the alternative (a resume that finishes on the next
  /// tick) is a button that visibly does nothing.
  void resume(int id) {
    _mutate(id, (e) {
      if (e.running) return null;
      if (e.finished) {
        return e.copyWith(
          accumulated: Duration.zero,
          startedAt: _now(),
          finished: false,
        );
      }
      return e.copyWith(startedAt: _now());
    });
  }

  void toggle(int id) {
    final e = entry(id);
    if (e == null) return;
    if (e.running) {
      pause(id);
    } else {
      resume(id);
    }
  }

  /// Back to the start, keeping whether it was running: a running stopwatch
  /// keeps running from zero, a paused one sits at zero. A finished countdown
  /// starts over, which is the only reading of "reset" that does anything.
  void reset(int id) {
    _mutate(id, (e) {
      final restart = e.running || e.finished;
      return e.copyWith(
        accumulated: Duration.zero,
        startedAt: restart ? _now() : null,
        finished: false,
      );
    });
  }

  /// Removes the entry — the "stop" the bar readout disappears on.
  void stop(int id) {
    final before = _entries.length;
    _entries.removeWhere((e) => e.id == id);
    if (_entries.length == before) return;
    _syncTicker();
    notifyListeners();
  }

  void stopAll() {
    if (_entries.isEmpty) return;
    _entries.clear();
    _syncTicker();
    notifyListeners();
  }

  /// Applies [change] to the entry with [id]; a null return means no change.
  void _mutate(int id, ShellTimer? Function(ShellTimer entry) change) {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) return;
    final next = change(_entries[index]);
    if (next == null) return;
    _entries[index] = next;
    _syncTicker();
    notifyListeners();
  }

  /// Retires any countdown that has run out, then asks every readout to
  /// repaint.
  ///
  /// Public for tests, which step [now] themselves rather than waiting out real
  /// seconds.
  @visibleForTesting
  void tick() {
    final now = _now();
    final finished = <ShellTimer>[];
    for (var i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      if (!e.running || e.kind != ShellTimerKind.timer) continue;
      if (e.elapsedAt(now) < e.total) continue;
      // Parked at exactly its total, so the readout reads 00:00 rather than
      // however far past zero the tick happened to land.
      _entries[i] = e.copyWith(
        accumulated: e.total,
        startedAt: null,
        finished: true,
      );
      finished.add(_entries[i]);
    }
    if (finished.isNotEmpty) _syncTicker();
    // Announced after the list is settled, so a handler that reads `entries`
    // sees the finished state rather than the one that is about to be replaced.
    for (final e in finished) {
      onFinished?.call(e);
    }
    notifyListeners();
  }

  void _syncTicker() {
    final wanted = _autoTick && _entries.any((e) => e.running);
    if (wanted) {
      _ticker ??= Timer.periodic(tickInterval, (_) => tick());
      return;
    }
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }
}

/// Posts a finished countdown to the shell's own notification store.
///
/// The bar readout is not enough on its own: a timer that runs out while the
/// user is looking at something else has to say so, and the shell already owns
/// `org.freedesktop.Notifications`, so this is one store write rather than a
/// D-Bus round trip to ourselves. No timeout — a fired timer stays in the list
/// until it is dismissed.
void postTimerFinishedNotification(ShellTimer entry) {
  final store = NotificationStore.instance;
  store.addOrReplace(
    NotificationItem(
      id: store.allocateId(),
      appName: 'Graceful Shell',
      summary: 'Timer finished',
      body: '${formatTimerDuration(entry.total)} is up.',
      actions: const [],
      expireTimeout: 0,
      arrivedAt: DateTime.now(),
    ),
  );
}
