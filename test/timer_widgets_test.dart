import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/modules/clock.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/timers/timer_store.dart';
import 'package:graceful_shell/timers/timer_widgets.dart';

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

/// [FaIcon.icon] answers the wrapped [IconData], not the [FaIconData] the
/// constant is, so the comparison has to unwrap — the two never compare equal.
Finder _icon(FaIconData icon) =>
    find.byWidgetPredicate((w) => w is FaIcon && w.icon == icon.data);

/// The pane at the shape the calendar gives it: the width of the clock column,
/// and about the half of it below the world clocks.
Widget _pane(TimersStore store, {bool active = true}) => _host(
      TimersPane(active: active, store: store),
      size: const Size(280, 300),
    );

void main() {
  group('TimersPane', () {
    testWidgets('says nothing is running, with a duration already typed', (
      tester,
    ) async {
      final store = _store();
      addTearDown(store.dispose);
      await tester.pumpWidget(_pane(store));

      expect(find.textContaining('Nothing running'), findsOneWidget);
      // find.text matches an EditableText by its controller, so this is the
      // field's seeded value and not a placeholder painted behind it.
      expect(find.text(kDefaultTimerDuration), findsOneWidget);
    });

    testWidgets('the seeded duration starts a countdown on one click', (
      tester,
    ) async {
      var clock = DateTime(2026, 8, 24, 12);
      final store = _store(now: () => clock);
      addTearDown(store.dispose);
      await tester.pumpWidget(_pane(store));

      // Nothing typed: the field arrives at five minutes and the primary
      // button is live, which is the whole point of seeding it.
      await tester.tap(find.text('Start timer'));
      await tester.pump();

      expect(store.length, 1);
      expect(find.text('05:00'), findsOneWidget);
      expect(find.text('Timer · 05:00'), findsOneWidget);

      // The readout is live: the store's notify is what repaints it.
      clock = clock.add(const Duration(minutes: 2));
      store.tick();
      await tester.pump();
      expect(find.text('03:00'), findsOneWidget);
    });

    testWidgets('a typed duration starts a countdown', (tester) async {
      final store = _store();
      addTearDown(store.dispose);
      await tester.pumpWidget(_pane(store));

      // Inert while what is in the field does not parse.
      await tester.enterText(find.byType(EditableText), 'soon');
      await tester.pump();
      await tester.tap(find.text('Start timer'));
      await tester.pump();
      expect(store.isEmpty, isTrue);

      await tester.enterText(find.byType(EditableText), '2:30');
      await tester.pump();
      await tester.tap(find.text('Start timer'));
      await tester.pump();

      expect(store.length, 1);
      expect(find.text('02:30'), findsOneWidget);
      // The field goes back to the default rather than being emptied, so the
      // next timer is one click away too.
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        kDefaultTimerDuration,
      );
    });

    testWidgets('the stopwatch button needs no duration', (tester) async {
      final store = _store();
      addTearDown(store.dispose);
      await tester.pumpWidget(_pane(store));

      await tester.tap(find.text('Stopwatch'));
      await tester.pump();

      expect(store.entries.single.kind, ShellTimerKind.stopwatch);
      expect(
        find.text('Stopwatch'),
        findsNWidgets(2),
      ); // the button and the row
    });

    testWidgets('the row pauses, resets and stops', (tester) async {
      var clock = DateTime(2026, 8, 24, 12);
      final store = _store(now: () => clock);
      addTearDown(store.dispose);
      final id = store.startStopwatch();
      await tester.pumpWidget(_pane(store));

      clock = clock.add(const Duration(seconds: 30));
      await tester.tap(_icon(FontAwesomeIcons.pause));
      await tester.pump();
      expect(find.text('Stopwatch · Paused'), findsOneWidget);
      expect(find.text('00:30'), findsOneWidget);

      await tester.tap(_icon(FontAwesomeIcons.arrowRotateLeft));
      await tester.pump();
      expect(find.text('00:00'), findsOneWidget);

      await tester.tap(_icon(FontAwesomeIcons.play));
      await tester.pump();
      expect(store.entry(id)!.running, isTrue);

      await tester.tap(_icon(FontAwesomeIcons.stop));
      await tester.pump();
      expect(store.isEmpty, isTrue);
      expect(find.textContaining('Nothing running'), findsOneWidget);
    });

    testWidgets('the row controls fire from the edges of their boxes', (
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
      await tester.pumpWidget(_pane(store));

      clock = clock.add(const Duration(seconds: 30));
      final pause = find.ancestor(
        of: _icon(FontAwesomeIcons.pause),
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
                  of: _icon(FontAwesomeIcons.stop),
                  matching: find.byType(SettingsIconButton),
                ))
                .bottomRight +
            const Offset(-2, -2),
      );
      await tester.pump();
      expect(store.isEmpty, isTrue);
    });

    testWidgets('Stop all appears only with more than one entry', (
      tester,
    ) async {
      final store = _store();
      addTearDown(store.dispose);
      store.startStopwatch();
      await tester.pumpWidget(_pane(store));
      expect(find.text('Stop all'), findsNothing);

      store.startTimer(const Duration(minutes: 1));
      await tester.pump();
      expect(find.text('Stop all'), findsOneWidget);

      await tester.tap(find.text('Stop all'));
      await tester.pump();
      expect(store.isEmpty, isTrue);
    });

    testWidgets('an inactive pane does not follow the store', (tester) async {
      final store = _store();
      addTearDown(store.dispose);
      await tester.pumpWidget(_pane(store, active: false));

      store.startTimer(const Duration(minutes: 5));
      await tester.pump();

      // The overlay's IndexedStack keeps this alive behind whatever tab the
      // user moved to; it re-reads when it is shown again.
      expect(find.text('05:00'), findsNothing);
      await tester.pumpWidget(_pane(store));
      expect(find.text('05:00'), findsOneWidget);
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

      expect(find.byType(FaIcon), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('one entry renders as its live readout', (tester) async {
      var clock = DateTime(2026, 8, 24, 12);
      final store = _store(now: () => clock);
      addTearDown(store.dispose);
      store.startTimer(const Duration(hours: 1, minutes: 23, seconds: 45));
      await tester.pumpWidget(bar(store));

      expect(find.text('1:23:45'), findsOneWidget);
      expect(_icon(FontAwesomeIcons.hourglassHalf), findsOneWidget);

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
      expect(_icon(FontAwesomeIcons.stopwatch), findsOneWidget);
    });

    testWidgets('stopping the last entry takes the readout out of the bar', (
      tester,
    ) async {
      final store = _store();
      addTearDown(store.dispose);
      final id = store.startStopwatch();
      await tester.pumpWidget(bar(store));
      expect(find.byType(FaIcon), findsOneWidget);

      store.stop(id);
      await tester.pump();
      expect(find.byType(FaIcon), findsNothing);
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
      expect(_icon(FontAwesomeIcons.pause), findsNWidgets(2));
      expect(_icon(FontAwesomeIcons.stop), findsNWidgets(2));
      expect(find.text('Stop all'), findsOneWidget);

      await tester.tap(_icon(FontAwesomeIcons.stop).first);
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
