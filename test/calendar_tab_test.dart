import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/calendar/calendar_tab.dart';
import 'package:graceful_shell/overlay/calendar/month.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';

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

Finder _iconButton(FaIconData icon) => find.byWidgetPredicate(
    (w) => w is SettingsIconButton && w.icon == icon);

void main() {
  final now = DateTime.now();
  final thisMonth = '${monthNames[now.month - 1]} ${now.year}';

  String label(DateTime month) =>
      '${monthNames[month.month - 1]} ${month.year}';

  testWidgets('renders the current month with every one of its days',
      (tester) async {
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
}
