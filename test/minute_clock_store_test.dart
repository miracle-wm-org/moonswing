// The minute clock: the lease, the one-shot tick behind it, and the promise
// that a wake-up finding the same minute says nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/clock/minute_clock_store.dart';

/// A store on a clock the test moves by hand.
({MinuteClockStore store, void Function(DateTime) setNow}) _store({
  DateTime? start,
}) {
  var now = start ?? DateTime(2026, 9, 7, 10, 20, 30);
  final store = MinuteClockStore.forTesting(clock: () => now);
  addTearDown(store.dispose);
  return (store: store, setNow: (value) => now = value);
}

void main() {
  group('the next boundary', () {
    test('is the rest of the current minute', () {
      expect(
        untilNextMinute(DateTime(2026, 9, 7, 10, 20, 30)),
        const Duration(seconds: 30),
      );
      expect(
        untilNextMinute(DateTime(2026, 9, 7, 10, 20, 59, 250)),
        const Duration(milliseconds: 750),
      );
    });

    test('is a whole minute exactly on the boundary', () {
      expect(
        untilNextMinute(DateTime(2026, 9, 7, 10, 20)),
        const Duration(minutes: 1),
      );
    });

    test('is never zero, so the tick cannot spin', () {
      // The one property that matters: a zero-length timer re-arming itself
      // from inside its own callback is a busy loop on the UI isolate.
      for (var second = 0; second < 60; second++) {
        for (final ms in const [0, 1, 499, 999]) {
          final wait = untilNextMinute(DateTime(2026, 9, 7, 10, 20, second, ms));
          expect(wait, greaterThan(Duration.zero),
              reason: 'at $second.${ms}s');
          expect(wait, lessThanOrEqualTo(const Duration(minutes: 1)));
        }
      }
    });

    test('is derived from the clock, never added to the last one', () {
      // A wake-up that lands late must cost a late repaint, not a clock that
      // walks away from the wall clock. Two seconds late still lands on the
      // boundary.
      expect(
        untilNextMinute(DateTime(2026, 9, 7, 10, 20, 2)),
        const Duration(seconds: 58),
      );
    });
  });

  group('the reading', () {
    test('drops the seconds', () {
      final s = _store(start: DateTime(2026, 9, 7, 10, 20, 59, 999));
      expect(s.store.now, DateTime(2026, 9, 7, 10, 20));
    });

    test('is read through to the clock, so it is never stale', () {
      // No lease, no tick, and still the right answer — a cached field is the
      // one bug a clock widget would be reporting.
      final s = _store();
      s.setNow(DateTime(2027, 1, 1, 0, 0, 5));
      expect(s.store.now, DateTime(2027, 1, 1));
    });
  });

  group('leasing', () {
    test('arms the tick on the first lease only', () {
      final s = _store();
      expect(s.store.ticking, isFalse);

      s.store.acquire();
      expect(s.store.leaseCount, 1);
      expect(s.store.ticking, isTrue);

      s.store.acquire();
      expect(s.store.leaseCount, 2);
      expect(s.store.ticking, isTrue);
    });

    test('cancels the tick when the last lease goes', () {
      // An idle shell with no clock on it must wake for this exactly never.
      final s = _store();
      s.store
        ..acquire()
        ..acquire()
        ..release();
      expect(s.store.ticking, isTrue);

      s.store.release();
      expect(s.store.leaseCount, 0);
      expect(s.store.ticking, isFalse);
    });

    test('re-arms when a lease is taken again', () {
      final s = _store();
      s.store
        ..acquire()
        ..release();
      s.store.acquire();
      expect(s.store.ticking, isTrue);
    });

    test('an unbalanced release does not go negative', () {
      final s = _store();
      s.store.release();
      expect(s.store.leaseCount, 0);

      s.store.acquire();
      expect(s.store.leaseCount, 1);
      expect(s.store.ticking, isTrue);
    });

    test('notifies nothing synchronously', () {
      // `acquire` runs inside the acquiring widget's `initState`, and a
      // synchronous notification from there is a `setState` on every other
      // surface already holding a lease, during a build.
      final s = _store();
      var notifications = 0;
      s.store.addListener(() => notifications++);

      s.store.acquire();
      expect(notifications, 0);
    });
  });

  group('the tick', () {
    test('notifies when the minute moves', () {
      final s = _store();
      var notifications = 0;
      s.store
        ..acquire()
        ..addListener(() => notifications++);

      s.setNow(DateTime(2026, 9, 7, 10, 21, 0, 3));
      s.store.tickNow();
      expect(notifications, 1);
    });

    test('says nothing when only the seconds moved', () {
      // Timers fire at or after their deadline, so a wake-up landing a hair
      // inside the minute it was arming out of is ordinary. Every desktop
      // surface on every monitor listens; a notification here is a repaint of
      // each of them for nothing.
      final s = _store();
      var notifications = 0;
      s.store
        ..acquire()
        ..addListener(() => notifications++);

      s.setNow(DateTime(2026, 9, 7, 10, 20, 59, 998));
      s.store.tickNow();
      expect(notifications, 0);
      expect(s.store.ticking, isTrue, reason: 're-armed rather than given up');
    });

    test('notifies once per minute, however often it is woken', () {
      final s = _store();
      var notifications = 0;
      s.store
        ..acquire()
        ..addListener(() => notifications++);

      s.setNow(DateTime(2026, 9, 7, 10, 21, 0));
      s.store.tickNow();
      s.store.tickNow();
      s.store.tickNow();
      expect(notifications, 1);

      s.setNow(DateTime(2026, 9, 7, 10, 22, 0));
      s.store.tickNow();
      expect(notifications, 2);
    });

    test('follows a clock stepped backwards', () {
      // Unlike an elapsed-time ticker, which drops a backwards step: this one
      // prints the wall clock, and the wall clock is what moved.
      final s = _store();
      var notifications = 0;
      s.store
        ..acquire()
        ..addListener(() => notifications++);

      s.setNow(DateTime(2026, 9, 7, 9, 20, 0));
      s.store.tickNow();
      expect(notifications, 1);
      expect(s.store.now, DateTime(2026, 9, 7, 9, 20));
    });
  });
}
