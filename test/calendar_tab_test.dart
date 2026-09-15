import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/calendar/calendar_tab.dart';
import 'package:graceful_shell/overlay/calendar/month.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/timers/timer_store.dart';
import 'package:graceful_shell/timers/timer_widgets.dart';

import 'paint_counter.dart';

/// Pumps the tab the way the overlay does: inside a ThemeScope, with the
/// Directionality and text style the overlay's panel supplies.
Future<void> pumpTab(
  WidgetTester tester, {
  Size size = const Size(800, 456),
}) async {
  const theme = ThemeConfig();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14),
        child: ThemeScope(
          theme: theme,
          // Both config seams are injected so the tab never reaches for the
          // ConfigStore singleton, which no widget test initialises — passing
          // only one of them would still hit it.
          child: SizedBox(
            width: size.width,
            height: size.height,
            // active: false is what keeps the clock column's one-second timer
            // out of the test zone; a pending timer fails the binding's
            // end-of-test invariants.
            child: const CalendarTab(
              active: false,
              weekStart: DateTime.sunday,
              worldClocks: [],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _iconButton(FaIconData icon) =>
    find.byWidgetPredicate((w) => w is SettingsIconButton && w.icon == icon);

void main() {
  final now = DateTime.now();
  final thisMonth = '${monthNames[now.month - 1]} ${now.year}';

  String label(DateTime month) =>
      '${monthNames[month.month - 1]} ${month.year}';

  testWidgets('renders the current month with every one of its days', (
    tester,
  ) async {
    await pumpTab(tester);

    expect(find.text(thisMonth), findsOneWidget);

    // Days 1..28 can also appear as spill-over from a neighbouring month, so
    // assert presence rather than an exact count.
    for (var d = 1; d <= daysInMonth(now.year, now.month); d++) {
      expect(find.text('$d'), findsWidgets, reason: 'day $d is missing');
    }
  });

  testWidgets('shows the weekday header row', (tester) async {
    await pumpTab(tester);

    // Sunday-start default: S M T W T F S.
    expect(find.text('M'), findsOneWidget);
    expect(find.text('W'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
    expect(find.text('S'), findsNWidgets(2)); // Sunday and Saturday
    expect(find.text('T'), findsNWidgets(2)); // Tuesday and Thursday
  });

  testWidgets('the chevrons page between months', (tester) async {
    await pumpTab(tester);
    final current = DateTime(now.year, now.month, 1);

    await tester.tap(_iconButton(FontAwesomeIcons.chevronRight));
    await tester.pump();
    expect(find.text(label(addMonths(current, 1))), findsOneWidget);

    await tester.tap(_iconButton(FontAwesomeIcons.chevronLeft));
    await tester.pump();
    await tester.tap(_iconButton(FontAwesomeIcons.chevronLeft));
    await tester.pump();
    expect(find.text(label(addMonths(current, -1))), findsOneWidget);
  });

  testWidgets('Today returns to the current month', (tester) async {
    await pumpTab(tester);

    await tester.tap(_iconButton(FontAwesomeIcons.chevronRight));
    await tester.pump();
    expect(find.text(thisMonth), findsNothing);

    await tester.tap(find.text('Today'));
    await tester.pump();
    expect(find.text(thisMonth), findsOneWidget);
  });

  testWidgets('lays out without overflowing the overlay panel', (tester) async {
    // overlayPanelSize clamps the panel to 800x500 at its smallest, and the tab
    // gets that minus the ~44px tab header — so this is the tightest the grid
    // and the clock column ever have to share.
    await pumpTab(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out on a pathologically short surface', (tester) async {
    // The last clamp in overlayPanelSize is against the output's own height, so
    // a very short display produces a panel shorter than the 500 minimum.
    await pumpTab(tester, size: const Size(800, 260));
    expect(tester.takeException(), isNull);
  });

  testWidgets('carries the timers section under the world clocks', (
    tester,
  ) async {
    // Its own store, hand-driven: TimersStore.forTesting starts no ticker, and
    // the singleton is shared with every other test in the suite.
    final timers = TimersStore.forTesting(now: () => DateTime(2026, 8, 24, 12));
    addTearDown(timers.dispose);
    timers.startTimer(const Duration(minutes: 5));

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 14),
          child: ThemeScope(
            theme: const ThemeConfig(),
            child: SizedBox(
              width: 800,
              height: 456,
              child: CalendarTab(
                active: true,
                weekStart: DateTime.sunday,
                worldClocks: const [],
                timers: timers,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TimersPane), findsOneWidget);
    expect(find.text('05:00'), findsOneWidget);
    expect(find.text('Start timer'), findsOneWidget);
    // The composer arrives with a duration in it, so the button is live.
    expect(find.text(kDefaultTimerDuration), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Still a full month beside it, and the clocks still above the section.
    expect(find.text(thisMonth), findsOneWidget);
    expect(find.text('World clocks'), findsOneWidget);

    // The section is under the world clocks in the right-hand column, not in
    // a strip along the bottom of the month grid.
    final clocksLabel = tester.getRect(find.text('World clocks'));
    final timersLabel = tester.getRect(find.text('Timers & stopwatches'));
    final monthLabel = tester.getRect(find.text(thisMonth));
    expect(timersLabel.top, greaterThan(clocksLabel.bottom));
    expect(timersLabel.left, greaterThan(monthLabel.right));
  });
  testWidgets('hovering a day repaints that day and nothing above it', (
    tester,
  ) async {
    // The highlight used to trail the pointer across the grid because a hover
    // repainted the whole surface: forty-two cells, the dial's painter, both
    // lists and the tab strip re-recorded to tint one 40px box, and — the GTK
    // embedder implementing no partial repaint — the whole output rastered
    // again after it. The cell owns a RepaintBoundary now, so the mark stops
    // there.
    const theme = ThemeConfig();
    final counterKey = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 14),
          child: ThemeScope(
            theme: theme,
            child: RepaintBoundary(
              child: PaintCounter(
                key: counterKey,
                child: const SizedBox(
                  width: 800,
                  height: 456,
                  child: CalendarTab(
                    active: false,
                    weekStart: DateTime.sunday,
                    worldClocks: [],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // A day in 15..22 is in every month and never spills in from a
    // neighbouring one: a 6x7 grid leaves at most fourteen trailing days (1..14
    // of the next month) and at most six leading ones, which come off the end
    // of the previous month and so are 23 or later even for a 28-day February.
    // Today is the selected day, which paints the accent whatever the pointer
    // does — and the default theme's surface_hover *is* the accent, so hovering
    // today would assert nothing. Step off it.
    final dayLabel = now.day == 15 ? '16' : '15';
    final day = find.text(dayLabel);
    expect(day, findsOneWidget);

    BoxDecoration cellDecoration() =>
        tester
                .widget<Container>(
                  find
                      .ancestor(of: day, matching: find.byType(Container))
                      .first,
                )
                .decoration!
            as BoxDecoration;

    final counter =
        counterKey.currentContext!.findRenderObject()! as RenderPaintCounter;

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await tester.pump();

    final labelBefore = tester.widget<Text>(day);
    final paintsBefore = counter.paints;

    // Resting, so the highlight below is a change and not the state it started
    // in.
    expect(cellDecoration().color, const Color(0x00000000));

    await pointer.moveTo(tester.getCenter(day));
    await tester.pump();

    // The highlight is on — without this the containment assertion below would
    // pass on a cell that had simply stopped reacting.
    expect(cellDecoration().color, theme.surfaceHover);
    // …and nothing above the cell was asked to paint for it.
    expect(counter.paints, paintsBefore);
    // The number is built outside the hover builder and handed in as a child,
    // so the rebuild the boundary contains is a decoration, not a paragraph.
    expect(identical(tester.widget<Text>(day), labelBefore), isTrue);

    await pointer.moveTo(Offset.zero);
    await tester.pump();
    expect(cellDecoration().color, const Color(0x00000000));
    expect(counter.paints, paintsBefore);
  });
}
