import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/modules/clock.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/timers/quick_timers.dart';
import 'package:moonswing/timers/timer_sound.dart';
import 'package:moonswing/timers/timer_store.dart';
import 'package:moonswing/timers/timer_widgets.dart';

import 'glyph_finder.dart';

/// Every store here is hand-driven: [TimersStore.forTesting] starts no ticker,
/// and a pending [Timer] fails the binding's end-of-test invariants.
///
/// The clock is frozen unless a test steps its own, which is not fastidiousness —
/// a readout truncates, so a countdown started against the real clock reads
/// `02:29` a millisecond after it was asked for two and a half minutes.
TimersStore _store({DateTime Function()? now}) =>
    TimersStore.forTesting(now: now ?? () => DateTime(2026, 8, 24, 12));

Widget _host(Widget child, {Size size = const Size(560, 200)}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: DefaultTextStyle(
      style: const TextStyle(fontSize: 14),
      child: ThemeScope(
        theme: const ThemeConfig(),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: size.width, height: size.height, child: child),
        ),
      ),
    ),
  );
}

Finder _icon(ShellGlyph icon) => findGlyph(icon);

/// The composer at the width the overview's card gives it.
///
/// The sound store is passed in for the reason the timers one is: the composer
/// renders the alarm's failure, and a test must reach that without the
/// singleton the shell actually plays through.
Widget _composer(
  TimersStore store, {
  TimerSoundStore? sound,
  ConfigStore? config,
  ValueChanged<int>? onStarted,
}) => _host(
  TimerComposer(
    store: store,
    sound: sound,
    config: config,
    onStarted: onStarted,
  ),
  size: const Size(264, 320),
);

/// The composer's duration field, then its name field.
Finder get _durationField => find.byType(EditableText).first;
Finder get _nameField => find.byType(EditableText).last;

/// The bar popup, which is where [TimerRow] is drawn.
Widget _popup(TimersStore store) =>
    _host(TimersPopupContent(store: store), size: const Size(264, 320));

/// A sound store that has already failed, with every seam answered in memory.
TimerSoundStore _brokenSound() {
  final sound = TimerSoundStore.forTesting();
  sound.resolve = (spelling) => TimerSoundChoice.missing(spelling);
  sound.configure(const TimerSoundConfig(sound: 'nonesuch'));
  return sound;
}

void main() {
  group('TimerComposer', () {
    testWidgets('an alarm that made no noise says so, and only then', (
      tester,
    ) async {
      final store = _store();
      addTearDown(store.dispose);
      final sound = _brokenSound();
      addTearDown(sound.dispose);

      await tester.pumpWidget(_composer(store, sound: sound));
      expect(find.textContaining('nonesuch'), findsNothing,
          reason: 'nothing has failed until something tried to play');

      sound.playNow();
      // The store notifies from a microtask (its `_notifyLater`), so the
      // reason is built on the frame after the one that delivers it.
      await tester.pump();
      await tester.pump();

      // The notification arrives whether or not the sound worked, so this line
      // is the only sign that anything went wrong.
      expect(find.textContaining('nonesuch'), findsOneWidget);
    });

    testWidgets('arrives with a duration already typed', (tester) async {
      final store = _store();
      addTearDown(store.dispose);
      await tester.pumpWidget(_composer(store));

      // find.text matches an EditableText by its controller, so this is the
      // field's seeded value and not a placeholder painted behind it.
      expect(find.text(kDefaultTimerDuration), findsOneWidget);
    });

    testWidgets('the seeded duration starts a countdown on one click', (
      tester,
    ) async {
      final store = _store();
      addTearDown(store.dispose);
      final started = <int>[];
      await tester.pumpWidget(_composer(store, onStarted: started.add));

      // Nothing typed: the field arrives at five minutes and the primary
      // button is live, which is the whole point of seeding it.
      await tester.tap(find.text('Start timer'));
      await tester.pump();

      expect(store.length, 1);
      expect(store.entries.single.total, const Duration(minutes: 5));
      expect(started, [store.entries.single.id]);
    });

    testWidgets('a typed duration starts a countdown', (tester) async {
      final store = _store();
      addTearDown(store.dispose);
      await tester.pumpWidget(_composer(store));

      // Inert while what is in the field does not parse.
      await tester.enterText(_durationField, 'soon');
      await tester.pump();
      await tester.tap(find.text('Start timer'));
      await tester.pump();
      expect(store.isEmpty, isTrue);

      await tester.enterText(_durationField, '2:30');
      await tester.pump();
      await tester.tap(find.text('Start timer'));
      await tester.pump();

      expect(store.entries.single.total, const Duration(minutes: 2, seconds: 30));
      // The field goes back to the default rather than being emptied, so the
      // next timer is one click away too.
      expect(
        tester.widget<EditableText>(_durationField).controller.text,
        kDefaultTimerDuration,
      );
    });

    testWidgets('a typed name labels the timer it starts', (tester) async {
      final store = _store();
      addTearDown(store.dispose);
      await tester.pumpWidget(_composer(store));

      await tester.enterText(_nameField, '  Tea ');
      await tester.pump();
      await tester.tap(find.text('Start timer'));
      await tester.pump();

      expect(store.entries.single.label, 'Tea');
      expect(timerSubtitle(store.entries.single), 'Tea · 05:00');
      expect(tester.widget<EditableText>(_nameField).controller.text, isEmpty);
    });

    testWidgets('offers no quick timers without a config to keep them in', (
      tester,
    ) async {
      final store = _store();
      addTearDown(store.dispose);
      await tester.pumpWidget(_composer(store));
      expect(find.text('Save as quick timer'), findsNothing);
      expect(find.text('Quick timers'), findsNothing);
    });

    group('quick timers', () {
      late Directory tempDir;
      late ConfigStore config;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('quick_timers_widget');
        final path = '${tempDir.path}/config.toml';
        await File(path).writeAsString('''
[[modules.clock.quick_timers]]
name = "Tea"
duration = "3m"
''');
        config = await ConfigStore.loadFrom(path);
      });

      tearDown(() async {
        config.dispose();
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      testWidgets('a chip starts its timer, named, in one click', (
        tester,
      ) async {
        final store = _store();
        addTearDown(store.dispose);
        final started = <int>[];
        await tester.pumpWidget(
          _composer(store, config: config, onStarted: started.add),
        );

        expect(find.text('Quick timers'), findsOneWidget);
        await tester.tap(find.text('Tea'));
        await tester.pump();

        final entry = store.entries.single;
        expect(entry.label, 'Tea');
        expect(entry.total, const Duration(minutes: 3));
        expect(started, [entry.id]);
      });

      testWidgets('saving keeps the name and length as a new chip', (
        tester,
      ) async {
        final store = _store();
        addTearDown(store.dispose);
        await tester.pumpWidget(_composer(store, config: config));

        // A quick timer is found by its name, so it cannot be saved unnamed.
        await tester.tap(find.text('Save as quick timer'));
        await tester.pump();
        expect(QuickTimerBook(config).timers, hasLength(1));

        await tester.enterText(_durationField, '10');
        await tester.enterText(_nameField, 'Pasta');
        await tester.pump();
        await tester.tap(find.text('Save as quick timer'));
        await tester.pump();

        expect(
          QuickTimerBook(config).timers.map((t) => (t.name, t.duration)),
          [
            ('Tea', const Duration(minutes: 3)),
            ('Pasta', const Duration(minutes: 10)),
          ],
        );
        expect(find.text('Pasta'), findsOneWidget);
        // Saving starts nothing: it is putting a timer by for later.
        expect(store.isEmpty, isTrue);
        // Lets the config's debounced write fire so no timer outlives the test.
        await tester.pump(const Duration(milliseconds: 500));
      });

      testWidgets('the × forgets a quick timer and starts nothing', (
        tester,
      ) async {
        final store = _store();
        addTearDown(store.dispose);
        await tester.pumpWidget(_composer(store, config: config));

        await tester.tap(_icon(ShellGlyph.close));
        await tester.pump();

        expect(QuickTimerBook(config).timers, isEmpty);
        expect(config.get<Object>(kQuickTimersPath), isNull);
        expect(find.text('Tea'), findsNothing);
        expect(store.isEmpty, isTrue);
        await tester.pump(const Duration(milliseconds: 500));
      });
    });
  });

  group('TimerRow', () {
    testWidgets('pauses, resets and stops', (tester) async {
      var clock = DateTime(2026, 8, 24, 12);
      final store = _store(now: () => clock);
      addTearDown(store.dispose);
      final id = store.startStopwatch();
      await tester.pumpWidget(_popup(store));

      clock = clock.add(const Duration(seconds: 30));
      await tester.tap(_icon(ShellGlyph.pause));
      await tester.pump();
      expect(find.text('Stopwatch · Paused'), findsOneWidget);
      expect(find.text('00:30'), findsOneWidget);

      await tester.tap(_icon(ShellGlyph.undo));
      await tester.pump();
      expect(find.text('00:00'), findsOneWidget);

      await tester.tap(_icon(ShellGlyph.play));
      await tester.pump();
      expect(store.entry(id)!.running, isTrue);

      await tester.tap(_icon(ShellGlyph.stop));
      await tester.pump();
      expect(store.isEmpty, isTrue);
    });

    testWidgets('the controls fire from the edges of their boxes', (
      tester,
    ) async {
      // The reported bug, end to end. These three used to hover and cursor over
      // a 26-square box and fire over the ~11px glyph in the middle of it, so a
      // centre tap — which is what every other case here does — passed while
      // the button was unusable for anyone not aiming at its exact middle.
      var clock = DateTime(2026, 8, 24, 12);
      final store = _store(now: () => clock);
      addTearDown(store.dispose);
      final id = store.startStopwatch();
      await tester.pumpWidget(_popup(store));

      clock = clock.add(const Duration(seconds: 30));
      final pause = find.ancestor(
        of: _icon(ShellGlyph.pause),
        matching: find.byType(SettingsIconButton),
      );
      expect(
        tester.getSize(pause),
        const Size(ShellSizes.iconButton, ShellSizes.iconButton),
      );
      await tester.tapAt(tester.getRect(pause).topLeft + const Offset(2, 2));
      await tester.pump();
      expect(store.entry(id)!.running, isFalse);

      await tester.tapAt(
        tester
                .getRect(find.ancestor(
                  of: _icon(ShellGlyph.stop),
                  matching: find.byType(SettingsIconButton),
                ))
                .bottomRight +
            const Offset(-2, -2),
      );
      await tester.pump();
      expect(store.isEmpty, isTrue);
    });
  });

  group('TimerBarIndicator', () {
    Widget bar(TimersStore store, {void Function(BuildContext)? onTap}) =>
        _host(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [TimerBarIndicator(store: store, onTap: onTap ?? (_) {})],
          ),
          size: const Size(300, 40),
        );

    testWidgets('renders nothing at all when nothing is running', (
      tester,
    ) async {
      final store = _store();
      addTearDown(store.dispose);
      await tester.pumpWidget(bar(store));

      expect(find.byType(ShellIcon), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('one entry renders as its live readout', (tester) async {
      var clock = DateTime(2026, 8, 24, 12);
      final store = _store(now: () => clock);
      addTearDown(store.dispose);
      store.startTimer(const Duration(hours: 1, minutes: 23, seconds: 45));
      await tester.pumpWidget(bar(store));

      expect(find.text('1:23:45'), findsOneWidget);
      expect(_icon(ShellGlyph.hourglass), findsOneWidget);

      clock = clock.add(const Duration(seconds: 45));
      store.tick();
      await tester.pump();
      expect(find.text('1:23:00'), findsOneWidget);
    });

    testWidgets('several entries collapse to an icon and a count', (
      tester,
    ) async {
      final store = _store();
      addTearDown(store.dispose);
      store.startTimer(const Duration(minutes: 5));
      store.startStopwatch();
      await tester.pumpWidget(bar(store));

      expect(find.text('2'), findsOneWidget);
      expect(find.text('05:00'), findsNothing);
      expect(_icon(ShellGlyph.stopwatch), findsOneWidget);
    });

    testWidgets('stopping the last entry takes the readout out of the bar', (
      tester,
    ) async {
      final store = _store();
      addTearDown(store.dispose);
      final id = store.startStopwatch();
      await tester.pumpWidget(bar(store));
      expect(find.byType(ShellIcon), findsOneWidget);

      store.stop(id);
      await tester.pump();
      expect(find.byType(ShellIcon), findsNothing);
    });

    testWidgets('the readout opens the popup', (tester) async {
      final store = _store();
      addTearDown(store.dispose);
      store.startStopwatch();
      var taps = 0;
      await tester.pumpWidget(bar(store, onTap: (_) => taps++));

      await tester.tap(find.text('00:00'));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('TimersPopupContent', () {
    testWidgets('lists every entry with its controls', (tester) async {
      final store = _store();
      addTearDown(store.dispose);
      store.startTimer(const Duration(minutes: 5));
      store.startStopwatch();
      await tester.pumpWidget(
        _host(TimersPopupContent(store: store), size: const Size(264, 320)),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('05:00'), findsOneWidget);
      expect(_icon(ShellGlyph.pause), findsNWidgets(2));
      expect(_icon(ShellGlyph.stop), findsNWidgets(2));
      expect(find.text('Stop all'), findsOneWidget);

      await tester.tap(_icon(ShellGlyph.stop).first);
      await tester.pump();
      expect(store.length, 1);
      expect(find.text('Stop all'), findsNothing);
    });
  });

  group('the clock module', () {
    testWidgets('shows the timer beside the time, and drops it when stopped', (
      tester,
    ) async {
      final store = _store();
      addTearDown(store.dispose);
      final id = store.startTimer(
        const Duration(hours: 1, minutes: 23, seconds: 45),
      );

      await tester.pumpWidget(
        _host(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [Clock(config: const ClockConfig(), timers: store)],
          ),
          size: const Size(400, 40),
        ),
      );

      expect(find.text('1:23:45'), findsOneWidget);

      store.stop(id);
      await tester.pump();
      expect(find.text('1:23:45'), findsNothing);
      // The clock itself is untouched by any of it.
      expect(find.byType(Clock), findsOneWidget);
    });
  });
}
