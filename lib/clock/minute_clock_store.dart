// The wall clock to the minute, for the whole shell: one timer however many
// surfaces are showing the time.
//
// `TuxStore`'s singleton-`ChangeNotifier`-with-leases shape, for its reasons.
// The desktop surface is one FlutterView per monitor, so a `Timer` owned by a
// widget `State` is owned once per monitor — the anti-pattern the stores exist
// to prevent — and an idle shell with no clock on it must wake for this exactly
// never.
//
// Four things a change here has to keep true:
//
// - **The minute is derived, never accumulated.** [now] reads the wall clock
//   every time and the next wake-up is recomputed from it on every tick, so a
//   wake-up that lands late costs a late repaint rather than a clock that walks
//   away from the truth, and a suspend costs nothing at all.
// - **It ticks once a minute, not once a second.** The surfaces on it print
//   nothing finer, and a second-resolution store would be a repaint a second on
//   every monitor whether or not anything on screen had changed.
// - **A tick that finds the same minute does not notify.** Timers fire at or
//   after their deadline but the boundary is computed in milliseconds, so a
//   wake-up landing a hair inside the previous minute is ordinary; it re-arms
//   and says nothing.
// - **`acquire` notifies nothing.** It runs inside the acquiring widget's
//   `initState`, and a synchronous `notifyListeners` from there is a `setState`
//   on every other surface already holding a lease, during a build.
//
// Flutter-free apart from `ChangeNotifier`, like the other stores.

import 'dart:async';

import 'package:flutter/foundation.dart';

/// How long until the wall clock's next whole minute.
///
/// Pure, and public because it is the whole of the store's timing: the boundary
/// is read off [now]'s own seconds and milliseconds rather than added to the
/// last one, which is what stops a drift of however late each wake-up was from
/// accumulating over the days a desktop widget stays on screen. The result is
/// always between one millisecond and a whole minute, so it can neither be zero
/// nor spin.
Duration untilNextMinute(DateTime now) => Duration(
      milliseconds: Duration.millisecondsPerMinute -
          (now.second * Duration.millisecondsPerSecond + now.millisecond),
    );

/// [time] with its seconds and everything under them dropped.
///
/// What the store compares and what its consumers draw: two instants in the
/// same minute are the same reading, and a store that published the raw
/// `DateTime` would notify on a difference no surface can render.
DateTime minuteOf(DateTime time) =>
    DateTime(time.year, time.month, time.day, time.hour, time.minute);

class MinuteClockStore extends ChangeNotifier {
  MinuteClockStore._({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static final MinuteClockStore instance = MinuteClockStore._();

  /// A detached store on a clock the test moves by hand, so a widget test can
  /// take a real lease, name the minute it is pretending to be, and never arm a
  /// timer that outlives the test.
  @visibleForTesting
  factory MinuteClockStore.forTesting({required DateTime Function() clock}) =>
      MinuteClockStore._(clock: clock);

  final DateTime Function() _clock;

  /// The current local time, to the minute.
  ///
  /// Read through rather than cached: a consumer with no lease still gets a
  /// correct answer, it just does not get told when it changes. Deliberately
  /// not a stored field — a clock is the one value where a stale cache is the
  /// bug the whole widget would be reporting.
  DateTime get now => minuteOf(_clock());

  // --- leasing -------------------------------------------------------------

  int _leases = 0;
  Timer? _tick;

  /// The minute the last notification was for, so a wake-up that finds nothing
  /// new stays silent.
  DateTime? _published;

  /// Take a lease. The first one arms the tick; nothing here notifies.
  void acquire() {
    _leases++;
    if (_leases == 1) {
      _published = now;
      _arm();
    }
  }

  void release() {
    if (_leases > 0) _leases--;
    if (_leases == 0) {
      _tick?.cancel();
      _tick = null;
      _published = null;
    }
  }

  @visibleForTesting
  int get leaseCount => _leases;

  @visibleForTesting
  bool get ticking => _tick != null;

  // --- the tick ------------------------------------------------------------

  void _arm() {
    _tick?.cancel();
    // A one-shot rather than a `Timer.periodic`: a period would be measured
    // from whenever the last one happened to fire and would walk off the
    // minute boundary over a day of late wake-ups.
    _tick = Timer(untilNextMinute(_clock()), _onTick);
  }

  void _onTick() {
    _arm();
    _publish();
  }

  /// Notify only when the minute a surface would draw has actually moved.
  ///
  /// Every desktop surface on every monitor listens, and the whole point of a
  /// clock with no second hand is that most wake-ups of the machine are not
  /// this one.
  void _publish() {
    final minute = now;
    if (minute == _published) return;
    _published = minute;
    notifyListeners();
  }

  /// Fires the tick now, as though the minute had turned over. Tests only — the
  /// alternative is a test that waits a minute.
  @visibleForTesting
  void tickNow() => _onTick();

  @override
  void dispose() {
    _tick?.cancel();
    _tick = null;
    super.dispose();
  }
}
