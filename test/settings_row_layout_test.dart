import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';

const _theme = ThemeConfig();

Future<void> _pump(WidgetTester tester, double width, Widget child) =>
    tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ThemeScope(
          theme: _theme,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

const _controlKey = Key('control');

const _row = SettingsRow(
  label: 'Short',
  control: SizedBox(key: _controlKey, width: 40, height: 20),
);

void main() {
  testWidgets('the control sits beside its label on a wide pane', (
    tester,
  ) async {
    await _pump(tester, 800, _row);
    final row = tester.getRect(find.byType(SettingsRow));
    final control = tester.getRect(find.byKey(_controlKey));
    // The label column and the gap, not the far edge of an 800px row.
    expect(control.left - row.left, kSettingsLabelWidth + kSettingsLabelGap);
    expect(row.right - control.right, greaterThan(400));
  });

  testWidgets('every control on a page starts in the same column', (
    tester,
  ) async {
    await _pump(
      tester,
      800,
      const Column(
        children: [
          SettingsRow(
            label: 'A',
            control: SizedBox(key: Key('a'), width: 40, height: 20),
          ),
          SettingsRow(
            label: 'A much longer label than the other one',
            control: SizedBox(key: Key('b'), width: 90, height: 20),
          ),
        ],
      ),
    );
    expect(
      tester.getRect(find.byKey(const Key('a'))).left,
      tester.getRect(find.byKey(const Key('b'))).left,
    );
  });

  testWidgets('a wide control squeezes its label rather than overflowing', (
    tester,
  ) async {
    await _pump(
      tester,
      400,
      const SettingsRow(
        label: 'Wide',
        control: SizedBox(key: _controlKey, width: 300, height: 20),
      ),
    );
    expect(tester.takeException(), isNull);
    final control = tester.getRect(find.byKey(_controlKey));
    expect(control.right, 400);
    expect(control.left, 400 - 300);
  });

  testWidgets('a section puts its rows on a card under the heading', (
    tester,
  ) async {
    await _pump(
      tester,
      600,
      const SettingsSection(label: 'Group', children: [_row]),
    );
    final card = find.byWidgetPredicate(
      (w) => w is Container && w.decoration == settingsCardDecoration(_theme),
    );
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.byType(SettingsRow)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('GROUP')),
      findsNothing,
    );
  });

  testWidgets('an empty section draws no card', (tester) async {
    await _pump(
      tester,
      600,
      const SettingsSection(label: 'Group', children: []),
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is Container && w.decoration == settingsCardDecoration(_theme),
      ),
      findsNothing,
    );
  });
}
