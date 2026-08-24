import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/timers/timer_format.dart';
import 'package:graceful_shell/timers/timer_store.dart';

void main() {
  late DateTime clock;
  late TimersStore store;

  setUp(() {
    clock = DateTime(2026, 8, 24, 12, 0, 0);
    store = TimersStore.forTesting(now: () => clock);
  });

  tearDown(() => store.dispose());

  ShellTimer only() => store.entries.single;

  test('a countdown counts down against the wall clock', () {
    store.startTimer(const Duration(minutes: 5));
    expect(only().displayAt(clock), const Duration(minutes: 5));

    clock = clock.add(const Duration(seconds: 90));
    expect(formatTimerDuration(only().displayAt(clock)), '03:30');
  });

  test('a stopwatch counts up and never finishes', () {
    store.startStopwatch();
    clock = clock.add(const Duration(hours: 2));
    store.tick();

    expect(only().finished, isFalse);
    expect(formatTimerDuration(only().displayAt(clock)), '2:00:00');
  });

  test('pause banks the run, and the readout stops moving', () {
    final id = store.startTimer(const Duration(minutes: 5));
    clock = clock.add(const Duration(minutes: 1));
    store.pause(id);

    final atPause = only().displayAt(clock);
    clock = clock.add(const Duration(minutes: 3));

    expect(only().running, isFalse);
    expect(only().displayAt(clock), atPause);
    expect(atPause, const Duration(minutes: 4));
  });

  test('resume picks up from where pause left off', () {
    final id = store.startTimer(const Duration(minutes: 5));
    clock = clock.add(const Duration(minutes: 1));
    store.pause(id);
    // Three minutes of being paused cost the countdown nothing.
    clock = clock.add(const Duration(minutes: 3));
    store.resume(id);
    clock = clock.add(const Duration(minutes: 1));

    expect(only().displayAt(clock), const Duration(minutes: 3));
  });

  test('toggle is pause then resume', () {
    final id = store.startStopwatch();
    store.toggle(id);
    expect(only().running, isFalse);
    store.toggle(id);
    expect(only().running, isTrue);
  });

  test('reset returns to the start, keeping whether it was running', () {
    final running = store.startStopwatch();
    final paused = store.startStopwatch();
    store.pause(paused);
    clock = clock.add(const Duration(minutes: 2));

    store.reset(running);
    store.reset(paused);

    expect(store.entry(running)!.running, isTrue);
    expect(store.entry(running)!.displayAt(clock), Duration.zero);
    expect(store.entry(paused)!.running, isFalse);
    expect(store.entry(paused)!.displayAt(clock), Duration.zero);
  });

  test('a finished countdown is parked at zero and announced once', () {
    final announced = <ShellTimer>[];
    store.onFinished = announced.add;

    store.startTimer(const Duration(seconds: 30));
    clock = clock.add(const Duration(seconds: 31));
    store.tick();

    expect(only().finished, isTrue);
    expect(only().running, isFalse);
    // Parked at its total rather than a third of a second past it, so the
    // readout reads 00:00 exactly.
    expect(only().displayAt(clock), Duration.zero);
    expect(announced, hasLength(1));

    clock = clock.add(const Duration(seconds: 30));
    store.tick();
    expect(announced, hasLength(1), reason: 'announced again on a later tick');
  });

  test('a finished countdown restarts rather than resuming into nothing', () {
    final id = store.startTimer(const Duration(seconds: 30));
    clock = clock.add(const Duration(seconds: 31));
    store.tick();

    store.resume(id);
    expect(only().finished, isFalse);
    expect(only().running, isTrue);
    expect(only().displayAt(clock), const Duration(seconds: 30));
  });

  test('stop removes the entry — the bar readout has nothing left to show', () {
    final id = store.startStopwatch();
    store.stop(id);
    expect(store.isEmpty, isTrue);
    expect(store.entry(id), isNull);
  });

  test('several entries run at once, and onlyEntry answers for one', () {
    final first = store.startTimer(const Duration(minutes: 1));
    store.startStopwatch();
    expect(store.length, 2);
    expect(store.onlyEntry, isNull);

    store.stop(first);
    expect(store.onlyEntry, isNotNull);

    store.startStopwatch();
    store.stopAll();
    expect(store.isEmpty, isTrue);
  });

  test('ids are never reused, so a stale control cannot hit a new entry', () {
    final first = store.startStopwatch();
    store.stop(first);
    final second = store.startStopwatch();
    expect(second, isNot(first));
    // The removed entry's stop is now a no-op rather than the new one's.
    store.stop(first);
    expect(store.length, 1);
  });

  test('a backwards clock step stalls the readout instead of reversing it', () {
    store.startStopwatch();
    clock = clock.add(const Duration(minutes: 1));
    final atMinute = only().displayAt(clock);

    clock = clock.subtract(const Duration(minutes: 5));
    expect(only().displayAt(clock), Duration.zero);
    expect(atMinute, const Duration(minutes: 1));
  });

  test('a duration past the cap is clamped rather than laid out wrong', () {
    store.startTimer(const Duration(hours: 500));
    expect(only().total, kMaxTimerDuration);
  });

  test('notifies on every mutation', () {
    var notifies = 0;
    store.addListener(() => notifies++);

    final id = store.startStopwatch();
    store.pause(id);
    store.resume(id);
    store.reset(id);
    store.stop(id);
    expect(notifies, 5);

    // A no-op mutation stays silent: every panel in the shell listens to this.
    store.pause(id);
    store.stop(id);
    expect(notifies, 5);
  });

  test('the ticker runs only while something is counting', () async {
    final ticking = TimersStore.forTesting(
      tickInterval: const Duration(milliseconds: 10),
      autoTick: true,
    );
    addTearDown(ticking.dispose);

    var notifies = 0;
    ticking.addListener(() => notifies++);

    // Idle: nothing to count, so nothing wakes.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(notifies, 0);

    final id = ticking.startStopwatch();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(notifies, greaterThan(1));

    ticking.pause(id);
    final atPause = notifies;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(notifies, atPause, reason: 'the ticker outlived the last run');
  });
}
