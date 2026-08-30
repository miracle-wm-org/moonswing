import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/calendar/calendar_tab.dart';
import 'package:graceful_shell/overlay/calendar/clock_column.dart';
import 'package:graceful_shell/overlay/calendar/time_zones.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// 10:30 on 9 August 2026, read as UTC — the one part of the day where the
/// inhabited world spans three calendar dates at once, so a single instant
/// exercises the `+1d`, `-1d` and no-badge cases together.
final _now = DateTime(2026, 8, 9, 10, 30, 12);

FixedClockSource _source() => FixedClockSource(
      now: _now,
      offsets: const {
        'Asia/Tokyo': Duration(hours: 9),
        'Europe/London': Duration(hours: 1),
        'Pacific/Kiritimati': Duration(hours: 14),
        'Pacific/Midway': Duration(hours: -11),
      },
      zones: const [
        'Asia/Tokyo',
        'Europe/London',
        'Pacific/Kiritimati',
        'Pacific/Midway',
      ],
    );

/// Pumps the column with a root Overlay for the picker to float into.
///
/// `active: false` throughout: the timer is the production tick, and a pending
/// one fails the binding's end-of-test invariants. The frozen [FixedClockSource]
/// is what the assertions read instead.
Future<void> pumpColumn(
  WidgetTester tester, {
  required List<WorldClock> clocks,
  ValueChanged<TimeZoneName>? onAdd,
  ValueChanged<String>? onRemove,
  ClockSource? clock,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14),
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: kClockColumnWidth,
                    height: 456,
                    child: CalendarClockColumn(
                      active: false,
                      clock: clock ?? _source(),
                      clocks: clocks,
                      onAdd: onAdd ?? (_) {},
                      onRemove: onRemove ?? (_) {},
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Font Awesome icons are [FaIconData], which `find.byIcon` cannot take; the
/// [FaIcon] widget unwraps them to plain [IconData].
Finder _faIcon(FaIconData icon) => find.byIcon(icon.data);

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byWidgetPredicate(
      (w) => w is SettingsIconButton && w.icon == FontAwesomeIcons.plus));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows the local time and date', (tester) async {
    await pumpColumn(tester, clocks: const []);

    expect(find.text('10:30:12'), findsOneWidget);
    expect(find.text('Sunday, Aug 9'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('prompts when there are no world clocks', (tester) async {
    await pumpColumn(tester, clocks: const []);
    expect(find.text('Add a time zone with +'), findsOneWidget);
  });

  testWidgets('badges a world clock that is on another day', (tester) async {
    await pumpColumn(tester, clocks: const [
      WorldClock(zone: 'Pacific/Kiritimati'),
      WorldClock(zone: 'Pacific/Midway'),
      WorldClock(zone: 'Europe/London'),
    ]);

    // 10:30 UTC is already the 10th on Kiritimati (+14) and still the 8th on
    // Midway (-11).
    expect(find.text('Kiritimati'), findsOneWidget);
    expect(find.text('00:30'), findsOneWidget);
    expect(find.text('+1d'), findsOneWidget);

    expect(find.text('Midway'), findsOneWidget);
    expect(find.text('23:30'), findsOneWidget);
    expect(find.text('-1d'), findsOneWidget);

    // Same calendar day, so no badge at all.
    expect(find.text('London'), findsOneWidget);
    expect(find.text('11:30'), findsOneWidget);
  });

  testWidgets('shows the UTC offset under each clock', (tester) async {
    await pumpColumn(tester, clocks: const [WorldClock(zone: 'Asia/Tokyo')]);
    expect(find.text('UTC+9'), findsOneWidget);
  });

  testWidgets('a label overrides the city', (tester) async {
    await pumpColumn(tester,
        clocks: const [WorldClock(zone: 'Asia/Tokyo', label: 'HQ')]);
    expect(find.text('HQ'), findsOneWidget);
    expect(find.text('Tokyo'), findsNothing);
  });

  testWidgets('an unknown zone still renders, and can still be removed',
      (tester) async {
    String? removed;
    await pumpColumn(
      tester,
      clocks: const [WorldClock(zone: 'Nowhere/Nothing')],
      onRemove: (zone) => removed = zone,
    );

    expect(find.text('Nothing'), findsOneWidget);
    expect(find.text('Unknown time zone'), findsOneWidget);

    await tester.tap(_faIcon(FontAwesomeIcons.xmark));
    await tester.pump();
    expect(removed, 'Nowhere/Nothing');
  });

  testWidgets('the remove button reports its own row', (tester) async {
    String? removed;
    await pumpColumn(
      tester,
      clocks: const [
        WorldClock(zone: 'Asia/Tokyo'),
        WorldClock(zone: 'Europe/London'),
      ],
      onRemove: (zone) => removed = zone,
    );

    await tester.tap(_faIcon(FontAwesomeIcons.xmark).last);
    await tester.pump();
    expect(removed, 'Europe/London');
  });

  testWidgets('the remove button is a box, and fires from its corners',
      (tester) async {
    // Dense (18 square, not 26) because the row already carries two lines of
    // text — but a box all the same, where it used to be an 11px glyph inside
    // a `SizedBox` that hit-tested nothing.
    String? removed;
    await pumpColumn(
      tester,
      clocks: const [WorldClock(zone: 'Asia/Tokyo')],
      onRemove: (zone) => removed = zone,
    );

    final button = find.ancestor(
      of: _faIcon(FontAwesomeIcons.xmark),
      matching: find.byType(SettingsIconButton),
    );
    expect(
      tester.getSize(button),
      const Size(ShellSizes.iconButtonDense, ShellSizes.iconButtonDense),
    );
    await tester.tapAt(tester.getRect(button).topLeft + const Offset(2, 2));
    await tester.pump();
    expect(removed, 'Asia/Tokyo');
  });

  group('the picker', () {
    testWidgets('opens on + and lists the zones', (tester) async {
      await pumpColumn(tester, clocks: const []);
      expect(find.text('Tokyo'), findsNothing);

      await _openPicker(tester);
      expect(find.text('Tokyo'), findsOneWidget);
      expect(find.text('London'), findsOneWidget);
    });

    testWidgets('filters as the user types, and Enter takes the top match',
        (tester) async {
      String? added;
      await pumpColumn(tester, clocks: const [], onAdd: (z) => added = z.name);
      await _openPicker(tester);

      await tester.enterText(find.byType(EditableText), 'tok');
      await tester.pump();
      expect(find.text('Tokyo'), findsOneWidget);
      expect(find.text('London'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(added, 'Asia/Tokyo');
      // Closed before the callback fired, so the list is gone.
      expect(find.byType(EditableText), findsNothing);
    });

    testWidgets('the arrows move the selection Enter takes', (tester) async {
      String? added;
      await pumpColumn(tester, clocks: const [], onAdd: (z) => added = z.name);
      await _openPicker(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // The list is alphabetical, so one down from Tokyo is London.
      expect(added, 'Europe/London');
    });

    testWidgets('says so when nothing matches', (tester) async {
      await pumpColumn(tester, clocks: const []);
      await _openPicker(tester);

      await tester.enterText(find.byType(EditableText), 'zzzz');
      await tester.pump();
      expect(find.text('No matching time zone'), findsOneWidget);
    });

    testWidgets('marks a zone that is already on the list', (tester) async {
      await pumpColumn(tester, clocks: const [WorldClock(zone: 'Asia/Tokyo')]);
      await _openPicker(tester);
      expect(_faIcon(FontAwesomeIcons.check), findsOneWidget);
    });

    testWidgets('Escape closes the list and stops there', (tester) async {
      // The overlay's own KeyboardListener closes the whole panel on Escape, so
      // the picker has to mark the event handled.
      var escaped = false;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 14),
            child: ThemeScope(
              theme: const ThemeConfig(),
              // No autofocus: the picker's search field takes focus when the
              // list opens, and this only has to see what propagates past it.
              child: Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    escaped = true;
                  }
                  return KeyEventResult.ignored;
                },
                child: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: kClockColumnWidth,
                          height: 456,
                          child: CalendarClockColumn(
                            active: false,
                            clock: _source(),
                            clocks: const [],
                            onAdd: (_) {},
                            onRemove: (_) {},
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await _openPicker(tester);
      expect(find.byType(EditableText), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byType(EditableText), findsNothing);
      expect(escaped, isFalse);
    });
  });

  group('the tab writes the list', () {
    Future<List<List<WorldClock>>> pumpTabWith(
      WidgetTester tester,
      List<WorldClock> clocks,
    ) async {
      final writes = <List<WorldClock>>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 14),
            child: ThemeScope(
              theme: const ThemeConfig(),
              child: Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (_) => SizedBox(
                      width: 800,
                      height: 456,
                      child: CalendarTab(
                        active: false,
                        weekStart: DateTime.sunday,
                        worldClocks: clocks,
                        onWorldClocksChanged: writes.add,
                        clock: _source(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return writes;
    }

    testWidgets('appends a picked zone', (tester) async {
      final writes = await pumpTabWith(tester, const []);
      await _openPicker(tester);
      await tester.tap(find.text('Tokyo'));
      await tester.pump();

      expect(writes.single.map((c) => c.zone), ['Asia/Tokyo']);
    });

    testWidgets('picking a zone already on the list writes nothing',
        (tester) async {
      final writes =
          await pumpTabWith(tester, const [WorldClock(zone: 'Asia/Tokyo')]);
      await _openPicker(tester);
      await tester.tap(find.text('Tokyo').last);
      await tester.pump();

      expect(writes, isEmpty);
    });

    testWidgets('removing drops just that zone', (tester) async {
      final writes = await pumpTabWith(tester, const [
        WorldClock(zone: 'Asia/Tokyo'),
        WorldClock(zone: 'Europe/London'),
      ]);

      await tester.tap(_faIcon(FontAwesomeIcons.xmark).first);
      await tester.pump();

      expect(writes.single.map((c) => c.zone), ['Europe/London']);
    });
  });
}
