import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config_store.dart';
import 'package:moonswing/timers/quick_timers.dart';
import 'package:moonswing/timers/timer_format.dart';
import 'package:moonswing/timers/timer_store.dart';

void main() {
  group('formatCompactDuration', () {
    test('is the shortest unit form, and reads back as the same length', () {
      final cases = {
        Duration(minutes: 3): '3m',
        Duration(seconds: 45): '45s',
        Duration(minutes: 2, seconds: 30): '2m30s',
        Duration(hours: 1, minutes: 30): '1h30m',
        Duration(hours: 1, seconds: 5): '1h5s',
        Duration.zero: '0s',
      };
      for (final MapEntry(key: d, value: spelled) in cases.entries) {
        expect(formatCompactDuration(d), spelled);
        if (d > Duration.zero) expect(parseDurationInput(spelled), d);
      }
    });
  });

  group('parseQuickTimers', () {
    test('a bad row costs that row, and the rest keep their file index', () {
      final timers = parseQuickTimers([
        {'name': 'Tea', 'duration': '3m'},
        {'name': '', 'duration': '3m'},
        {'name': 'No length'},
        'not a table',
        {'name': 'Too long', 'duration': '200h'},
        {'name': 'Seconds', 'duration': 90},
        {'name': '  Pasta   al dente ', 'duration': '10:00'},
        {'name': 7, 'duration': '1m'},
      ]);
      expect(timers, [
        const QuickTimer(name: 'Tea', duration: Duration(minutes: 3), index: 0),
        const QuickTimer(
          name: 'Seconds',
          duration: Duration(seconds: 90),
          index: 5,
        ),
        const QuickTimer(
          name: 'Pasta al dente',
          duration: Duration(minutes: 10),
          index: 6,
        ),
      ]);
    });

    test('anything but a list is no presets', () {
      expect(parseQuickTimers(null), isEmpty);
      expect(parseQuickTimers({'name': 'Tea'}), isEmpty);
      expect(parseQuickTimers('Tea'), isEmpty);
    });

    test('a name is kept to one line and a bounded length', () {
      expect(normalizeQuickTimerName(' a\n b\t'), 'a b');
      expect(
        normalizeQuickTimerName('x' * 100).length,
        kQuickTimerNameMaxLength,
      );
    });
  });

  group('QuickTimerBook', () {
    late Directory tempDir;
    late String path;
    late ConfigStore config;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('quick_timers_test');
      path = '${tempDir.path}/config.toml';
      await File(path).writeAsString('''
[modules.clock]
show_date = false

[[modules.clock.quick_timers]]
name = "Broken"

[[modules.clock.quick_timers]]
name = "Tea"
duration = "3m"
note = "green, not black"
''');
      config = await ConfigStore.loadFrom(path);
    });

    tearDown(() async {
      config.dispose();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('saving a new name appends it and survives a reload', () async {
      final book = QuickTimerBook(config);
      expect(book.save('Pasta', const Duration(minutes: 10)), isTrue);
      await config.save();

      final reloaded = await ConfigStore.loadFrom(path);
      addTearDown(reloaded.dispose);
      expect(
        QuickTimerBook(reloaded).timers.map((t) => (t.name, t.duration)),
        [
          ('Tea', const Duration(minutes: 3)),
          ('Pasta', const Duration(minutes: 10)),
        ],
      );
      // The row the reader dropped is still the user's.
      expect(reloaded.get<List>(kQuickTimersPath), hasLength(3));
      expect(reloaded.get<bool>(['modules', 'clock', 'show_date']), isFalse);
    });

    test('saving a name already kept changes its length in place', () {
      final book = QuickTimerBook(config);
      book.save('tea', const Duration(minutes: 4));
      expect(book.timers.single.duration, const Duration(minutes: 4));
      final row = config.get<List>(kQuickTimersPath)![1] as Map;
      // Its other keys are the user's and survive.
      expect(row['note'], 'green, not black');
      expect(row['duration'], '4m');
    });

    test('an empty name is refused', () {
      final book = QuickTimerBook(config);
      expect(book.save('   ', const Duration(minutes: 1)), isFalse);
      expect(book.timers, hasLength(1));
    });

    test('removing addresses the file row, and a stale one is a no-op', () {
      final book = QuickTimerBook(config);
      final tea = book.timers.single;
      // A row that no longer matches what the chip was drawn from.
      book.remove(const QuickTimer(
        name: 'Tea',
        duration: Duration(minutes: 9),
        index: 1,
      ));
      expect(book.timers, hasLength(1));

      book.remove(tea);
      expect(book.timers, isEmpty);
      expect(config.get<List>(kQuickTimersPath), hasLength(1));
    });
  });

  group('a named timer', () {
    test('keeps its label through pause, resume and reset', () {
      final store = TimersStore.forTesting(now: () => DateTime(2026, 11, 12));
      addTearDown(store.dispose);
      final id = store.startTimer(const Duration(minutes: 3), label: ' Tea ');
      store.pause(id);
      store.resume(id);
      store.reset(id);
      expect(store.entry(id)!.label, 'Tea');
      expect(
        store.entry(store.startTimer(const Duration(minutes: 1), label: ' '))!
            .label,
        isNull,
      );
    });
  });
}
