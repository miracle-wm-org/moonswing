// What Tux says, and which day he says it on.
//
// Plain unit tests with no binding behind them: `lib/tux/tux_greetings.dart`
// imports no Flutter at all, which is the point of it being its own file.

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/tux/tux_greetings.dart';

/// A local noon on the given date. Noon rather than midnight so a test cannot
/// pass by accident on a machine whose zone would push a midnight over the day
/// boundary.
DateTime _day(int year, int month, int day) =>
    DateTime(year, month, day, 12);

void main() {
  group('the greeting lists', () {
    test('name no time of day', () {
      // The greeting is fixed for the whole calendar day and is as likely to be
      // read at midnight as over breakfast, so nothing in it may name an hour.
      // `today` and `tomorrow` are deliberately absent from this list: the
      // greeting *is* today's, and saying so is the one time reference that is
      // true whenever it is read.
      const clock = ['morning', 'afternoon', 'evening', 'tonight', 'o\'clock'];
      for (final line in [...kTuxSalutations, ...kTuxGreetings]) {
        for (final word in clock) {
          expect(line.toLowerCase(), isNot(contains(word)), reason: line);
        }
      }
    });

    test('are non-empty and free of duplicates', () {
      expect(kTuxGreetings, isNotEmpty);
      expect(kTuxSalutations, isNotEmpty);
      expect(kTuxGreetings.toSet().length, kTuxGreetings.length);
      expect(kTuxSalutations.toSet().length, kTuxSalutations.length);
    });

    test('are short enough to set on a 1x1 card', () {
      // The size ladder in the widget bottoms out at 9px times the card's
      // scale, and a 96px square holds about four lines of it. Forty-five
      // characters is roughly where a greeting stops fitting in that at a size
      // anybody reads — see the widget's `_greetingSizes`.
      for (final line in kTuxGreetings) {
        expect(line.length, lessThanOrEqualTo(45), reason: line);
      }
    });

    test('read as one sentence each', () {
      for (final line in kTuxGreetings) {
        expect(line.trim(), line, reason: 'untrimmed: $line');
        expect(line, isNot(contains('\n')), reason: line);
      }
    });
  });

  group('greetingForDay', () {
    test('answers the same greeting for the same day', () {
      final first = greetingForDay(_day(2026, 8, 26));
      final second = greetingForDay(_day(2026, 8, 26));
      expect(first, second);
    });

    test('answers the same greeting at any hour of that day', () {
      final morning = greetingForDay(DateTime(2026, 8, 26, 6, 30));
      final night = greetingForDay(DateTime(2026, 8, 26, 23, 59));
      expect(morning, night);
    });

    test('moves on to a different line the next day', () {
      final today = greetingForDay(_day(2026, 8, 26));
      final tomorrow = greetingForDay(_day(2026, 8, 27));
      expect(tomorrow.line, isNot(today.line));
      expect(tomorrow.salutation, isNot(today.salutation));
    });

    test('names the user when there is a name, and does not when there is not',
        () {
      final named = greetingForDay(_day(2026, 8, 26), name: 'Sam');
      expect(named.salutation, endsWith(', Sam'));

      final anonymous = greetingForDay(_day(2026, 8, 26));
      // Bare — one of the list's own entries, verbatim. Not "contains no
      // comma": `Oh, hello` has one of its own, which is exactly the sort of
      // thing an assertion about punctuation gets wrong.
      expect(kTuxSalutations, contains(anonymous.salutation));
      expect(named.salutation, '${anonymous.salutation}, Sam');
      // The line itself never carries the name: it is the same sentence for
      // everybody, which is what lets it be a plain constant.
      expect(named.line, anonymous.line);
    });

    test('trims a name rather than leaving the comma hanging', () {
      expect(greetingForDay(_day(2026, 8, 26), name: '   ').salutation,
          greetingForDay(_day(2026, 8, 26)).salutation);
    });

    test('offset steps to another line without moving the day', () {
      final day = _day(2026, 8, 26);
      final first = greetingForDay(day);
      final second = greetingForDay(day, offset: 1);
      expect(second.line, isNot(first.line));
      // And stepping the whole rotation comes back to where it started, which
      // is the property that makes `another()` safe to press forever.
      final wrapped = greetingForDay(day, offset: kTuxGreetings.length);
      expect(wrapped.line, first.line);
    });

    test('shows every line before repeating any', () {
      final start = _day(2026, 1, 1);
      final seen = <String>{};
      for (var i = 0; i < kTuxGreetings.length; i++) {
        final day = DateTime(start.year, start.month, start.day + i, 12);
        expect(seen.add(greetingForDay(day).line), isTrue,
            reason: 'repeat on day $i');
      }
      expect(seen.length, kTuxGreetings.length);
    });

    test('does not walk the list in the order it was written', () {
      // A stride of 1 is `ordinal % n`, which reads as a list being recited.
      final start = _day(2026, 1, 1);
      final walked = [
        for (var i = 0; i < 4; i++)
          greetingForDay(DateTime(start.year, start.month, start.day + i, 12))
              .line,
      ];
      final written = kTuxGreetings.indexOf(walked.first);
      expect(walked[1], isNot(kTuxGreetings[(written + 1) % kTuxGreetings.length]));
    });

    test('answers rather than throwing for a two-entry list', () {
      // `_strideFor` has a floor at 1, and a list short enough to reach it must
      // still index rather than divide by zero or loop forever.
      final greeting = greetingForDay(
        _day(2026, 8, 26),
        lines: const ['a', 'b'],
        salutations: const ['x'],
      );
      expect(['a', 'b'], contains(greeting.line));
      expect(greeting.salutation, 'x');
    });

    test('answers rather than throwing for an empty list', () {
      final greeting = greetingForDay(
        _day(2026, 8, 26),
        lines: const [],
        salutations: const [],
      );
      expect(greeting.line, '');
      expect(greeting.salutation, 'Hello');
    });

    test('indexes rather than throws for a date before the epoch', () {
      // Nothing produces one, but a hand-set clock could, and `%` on a negative
      // left operand still answers inside the list in Dart.
      final greeting = greetingForDay(_day(1969, 6, 1));
      expect(kTuxGreetings, contains(greeting.line));
    });
  });

  group('dayOrdinal', () {
    test('counts whole days, one per calendar day', () {
      expect(dayOrdinal(_day(2026, 8, 27)) - dayOrdinal(_day(2026, 8, 26)), 1);
      expect(dayOrdinal(_day(2026, 3, 1)) - dayOrdinal(_day(2026, 2, 28)), 1);
    });

    test('moves by exactly one over a daylight-saving boundary', () {
      // A 23-hour day. Differencing the *local* instants and truncating would
      // answer 0 here, which would repeat the previous day's greeting — the bug
      // `month.dart`'s `dayDelta` documents at the other end of the shell.
      final before = DateTime(2026, 3, 8, 12);
      final after = DateTime(2026, 3, 9, 12);
      expect(dayOrdinal(after) - dayOrdinal(before), 1);

      final autumnBefore = DateTime(2026, 11, 1, 12);
      final autumnAfter = DateTime(2026, 11, 2, 12);
      expect(dayOrdinal(autumnAfter) - dayOrdinal(autumnBefore), 1);
    });

    test('ignores the time of day', () {
      expect(dayOrdinal(DateTime(2026, 8, 26, 0, 0)),
          dayOrdinal(DateTime(2026, 8, 26, 23, 59, 59)));
    });
  });

  group('nextRollover', () {
    test('is the next local midnight', () {
      final next = nextRollover(DateTime(2026, 8, 26, 15, 30));
      expect(next, DateTime(2026, 8, 27));
      expect(next.isAfter(DateTime(2026, 8, 26, 15, 30)), isTrue);
    });

    test('is built from the date rather than by adding 24 hours', () {
      // Spring forward: the day is 23 hours long, so `add(Duration(days: 1))`
      // from noon lands at 13:00 the next day rather than at midnight.
      final rollover = nextRollover(DateTime(2026, 3, 8, 12));
      expect(rollover.hour, 0);
      expect(rollover.day, 9);
    });

    test('crosses a month and a year boundary', () {
      expect(nextRollover(DateTime(2026, 8, 31, 9)), DateTime(2026, 9, 1));
      expect(nextRollover(DateTime(2026, 12, 31, 9)), DateTime(2027, 1, 1));
    });
  });
}
