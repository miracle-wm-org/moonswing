import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';

import 'tap_target.dart';

void main() {
  final today = DateTime(2026, 9, 24);

  Future<List<DateTime>> pump(
    WidgetTester tester, {
    DateTime? selected,
    int weekStart = DateTime.sunday,
  }) async {
    final picked = <DateTime>[];
    await tester.pumpWidget(
      ThemeScope(
        theme: const ThemeConfig(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          // Keyed afresh per pump: an Overlay reads its initial entries once.
          child: Overlay(
            key: UniqueKey(),
            initialEntries: [
              OverlayEntry(
                builder: (_) => Align(
                  alignment: Alignment.topLeft,
                  child: SettingsDatePickerCard(
                    selected: selected,
                    today: today,
                    weekStart: weekStart,
                    onPicked: picked.add,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return picked;
  }

  Finder day(int n) => find.text('$n');
  Finder icon(FaIconData data) =>
      find.byWidgetPredicate((w) => w is FaIcon && w.icon == data.data);

  testWidgets('opens on the chosen day\'s month, else today\'s', (
    tester,
  ) async {
    await pump(tester, selected: DateTime(2027, 2, 3));
    expect(find.text('February 2027'), findsOneWidget);
    await pump(tester);
    expect(find.text('September 2026'), findsOneWidget);
  });

  testWidgets('a click anywhere in a cell picks its day', (tester) async {
    final picked = await pump(tester);
    // 24 appears once: September 2026's grid spills no 24th from a
    // neighbouring month.
    final cell = find.ancestor(of: day(24), matching: find.byType(SizedBox));
    await tapEveryCorner(tester, cell.first);
    expect(picked, List.filled(4, DateTime(2026, 9, 24)));
  });

  testWidgets('a day spilling over from a neighbouring month is pickable', (
    tester,
  ) async {
    final picked = await pump(tester);
    // September 2026 starts on a Tuesday, so its grid opens on Sunday 30
    // and Monday 31 August — and only August has a 31st on it.
    await tester.tap(day(31));
    expect(picked, [DateTime(2026, 8, 31)]);
  });

  testWidgets('pages by month without changing size', (tester) async {
    await pump(tester);
    final card = find.byType(SettingsDatePickerCard);
    final before = tester.getSize(card);
    await tester.tap(icon(FontAwesomeIcons.chevronRight));
    await tester.pump();
    expect(find.text('October 2026'), findsOneWidget);
    expect(tester.getSize(card), before);
    await tester.tap(icon(FontAwesomeIcons.chevronLeft));
    await tester.tap(icon(FontAwesomeIcons.chevronLeft));
    await tester.pump();
    expect(find.text('August 2026'), findsOneWidget);
    expect(tester.getSize(card), before);
  });

  testWidgets('the week starts where the calendar\'s does', (tester) async {
    String firstHeader() =>
        tester.widgetList<Text>(find.byType(Text)).elementAt(1).data!;
    await pump(tester);
    expect(firstHeader(), 'S');
    await pump(tester, weekStart: DateTime.monday);
    expect(firstHeader(), 'M');
  });

  testWidgets('the chosen day is filled with the accent, today ringed', (
    tester,
  ) async {
    const theme = ThemeConfig();
    await pump(tester, selected: DateTime(2026, 9, 10));
    BoxDecoration decorationOf(int n) =>
        tester
                .widget<Container>(
                  find
                      .ancestor(of: day(n), matching: find.byType(Container))
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(decorationOf(10).color, theme.accent);
    expect(decorationOf(24).color, isNull);
    expect(decorationOf(24).border, isNotNull);
    expect(decorationOf(11).border, isNull);
  });
}
