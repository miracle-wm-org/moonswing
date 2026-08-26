// The Tux store: the lease, the one-shot rollover behind it, and the tap.

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/tux/tux_greetings.dart';
import 'package:graceful_shell/tux/tux_store.dart';

/// A store on a clock the test moves by hand.
({TuxStore store, void Function(DateTime) setNow}) _store({
  DateTime? start,
  String name = '',
}) {
  var now = start ?? DateTime(2026, 8, 26, 9);
  final store = TuxStore.forTesting(now: () => now, name: name);
  addTearDown(store.dispose);
  return (store: store, setNow: (value) => now = value);
}

void main() {
  group('leasing', () {
    test('arms the rollover on the first lease only', () {
      final s = _store();
      expect(s.store.waitingForRollover, isFalse);

      s.store.acquire();
      expect(s.store.leaseCount, 1);
      expect(s.store.waitingForRollover, isTrue);

      s.store.acquire();
      expect(s.store.leaseCount, 2);
      expect(s.store.waitingForRollover, isTrue);
    });

    test('cancels the rollover when the last lease goes', () {
      // An idle shell must wake for this exactly never — `TimersStore`'s rule,
      // and the reason a desktop with no Tux on it costs nothing at all.
      final s = _store();
      s.store
        ..acquire()
        ..acquire()
        ..release();
      expect(s.store.waitingForRollover, isTrue);

      s.store.release();
      expect(s.store.leaseCount, 0);
      expect(s.store.waitingForRollover, isFalse);
    });

    test('re-arms when a lease is taken again', () {
      final s = _store();
      s.store
        ..acquire()
        ..release();
      expect(s.store.waitingForRollover, isFalse);

      s.store.acquire();
      expect(s.store.waitingForRollover, isTrue);
    });

    test('an unbalanced release does not go negative', () {
      final s = _store();
      s.store
        ..release()
        ..release();
      expect(s.store.leaseCount, 0);
    });

    test('notifies nothing', () {
      // `acquire` runs inside the acquiring widget's `initState`, and a
      // synchronous notify from there is a `setState` on every other surface
      // already holding a lease, during a build.
      final s = _store();
      var notifies = 0;
      s.store.addListener(() => notifies++);

      s.store
        ..acquire()
        ..acquire()
        ..release()
        ..release();
      expect(notifies, 0);
    });
  });

  group('the greeting', () {
    test('follows the clock rather than the moment the lease was taken', () {
      final s = _store(start: DateTime(2026, 8, 26, 9));
      s.store.acquire();
      final today = s.store.greeting;

      s.setNow(DateTime(2026, 8, 27, 9));
      expect(s.store.greeting.line, isNot(today.line));
      expect(s.store.greeting, greetingForDay(DateTime(2026, 8, 27, 9)));
    });

    test('carries the name the store resolved', () {
      final s = _store(name: 'Sam');
      s.store.acquire();
      expect(s.store.greetedName, 'Sam');
      expect(s.store.greeting.salutation, endsWith(', Sam'));
    });

    test('asks the passwd database once, however many surfaces read it', () {
      // The desktop is one FlutterView per monitor and every greeting read goes
      // through this; without the memoisation it is a `getpwuid` per monitor
      // per rebuild.
      var lookups = 0;
      final store = TuxStore.forTesting(
        now: () => DateTime(2026, 8, 26, 9),
        resolveName: () {
          lookups++;
          return 'Sam';
        },
      );
      addTearDown(store.dispose);

      store
        ..acquire()
        ..acquire();
      expect(store.greetedName, 'Sam');
      expect(store.greeting.salutation, endsWith(', Sam'));
      expect(store.greeting.salutation, endsWith(', Sam'));
      expect(lookups, 1);
    });
  });

  group('another()', () {
    test('steps the line and notifies', () {
      final s = _store();
      s.store.acquire();
      var notifies = 0;
      s.store.addListener(() => notifies++);

      final first = s.store.greeting.line;
      s.store.another();
      expect(notifies, 1);
      expect(s.store.offset, 1);
      expect(s.store.greeting.line, isNot(first));
    });

    test('does not move the day', () {
      final s = _store();
      s.store
        ..acquire()
        ..another();
      // The day's own line is still what tomorrow's rollover will come back to.
      expect(s.store.greeting.line,
          greetingForDay(DateTime(2026, 8, 26, 9), offset: 1).line);
    });
  });

  group('the rollover', () {
    test('resets the offset, notifies, and re-arms', () {
      final s = _store();
      s.store
        ..acquire()
        ..another()
        ..another();
      expect(s.store.offset, 2);

      var notifies = 0;
      s.store.addListener(() => notifies++);

      s.setNow(DateTime(2026, 8, 27, 0, 0, 1));
      s.store.rollOverNow();

      expect(s.store.offset, 0);
      expect(notifies, 1);
      expect(s.store.waitingForRollover, isTrue);
      expect(s.store.greeting, greetingForDay(DateTime(2026, 8, 27)));
    });
  });

  group('tidyGreetedName', () {
    test('takes the first word of a GECOS name', () {
      expect(tidyGreetedName('Sam Fernandez-Whitmore'), 'Sam');
    });

    test('capitalises an all-lowercase account name', () {
      expect(tidyGreetedName('sam'), 'Sam');
    });

    test('leaves an already-capitalised name alone', () {
      expect(tidyGreetedName('Sam'), 'Sam');
      expect(tidyGreetedName("O'Neill Ada"), "O'Neill");
    });

    test('says nothing rather than something odd', () {
      // A bare `Hello` is the correct greeting for a machine whose passwd entry
      // says nothing about a person.
      expect(tidyGreetedName(''), '');
      expect(tidyGreetedName('   '), '');
      expect(tidyGreetedName('svc_build_agent_07'), '');
      expect(tidyGreetedName('user1'), '');
      expect(tidyGreetedName('nobody@example.com'), '');
    });

    test('keeps a non-ASCII name', () {
      expect(tidyGreetedName('Zoë Müller'), 'Zoë');
      expect(tidyGreetedName('晴 田中'), '晴');
    });
  });

  group('defaultGreetedName', () {
    test('answers rather than throwing, whatever the host', () {
      // It opens libc through `dart:ffi`; a greeting is not worth taking a
      // desktop surface down for.
      expect(() => defaultGreetedName(), returnsNormally);
    });
  });
}
