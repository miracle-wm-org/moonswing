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
Future<void> pumpTab(WidgetTester tester) async {
  const theme = ThemeConfig();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14),
        child: ThemeScope(
          theme: theme,
          // The week start is injected so the tab never reaches for the
          // ConfigStore singleton, which no widget test initialises.
          child: const SizedBox(
            width: 800,
            height: 500,
            child: CalendarTab(weekStart: DateTime.sunday),
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
    // The tab is sized by the overlay's fixed 800x560 panel minus its header,
    // so a grid that does not fit would silently clip in the real shell.
    await pumpTab(tester);
    expect(tester.takeException(), isNull);
  });
}
