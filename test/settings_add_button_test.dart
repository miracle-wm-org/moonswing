import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';

/// Pins where a heading's add button sits: on the right of the heading, for
/// a collection that is not a [SettingsList]. A list's own adder is its last
/// row — see `settings_list_test.dart`.
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 13),
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: 400, child: child),
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

void main() {
  testWidgets('a heading carries its action on the right', (tester) async {
    await _pump(
      tester,
      SettingsSubLabel(
        'Pinned items',
        trailing: SettingsAddButton(label: 'Application…', onTap: () {}),
      ),
    );
    final label = tester.getRect(find.text('Pinned items'));
    final button = tester.getRect(find.text('Application…'));
    expect(button.left, greaterThan(label.right));
    // On the same row, not under it.
    expect(button.center.dy, closeTo(label.center.dy, 4));
  });

  testWidgets('a section heading carries its action on the right',
      (tester) async {
    // The theme picker's "New theme…": the section's whole body is the
    // collection, so the action belongs on the section label rather than on a
    // list heading inside it.
    await _pump(
      tester,
      SettingsSection(
        label: 'Theme',
        trailing: SettingsAddButton(label: 'New theme…', onTap: () {}),
        children: const [Text('moonswing')],
      ),
    );
    final label = tester.getRect(find.text('THEME'));
    final button = tester.getRect(find.text('New theme…'));
    expect(button.left, greaterThan(label.right));
    expect(button.bottom, lessThanOrEqualTo(tester
        .getRect(find.text('moonswing'))
        .top));
  });

  testWidgets('a heading with no action still renders bare', (tester) async {
    await _pump(tester, const SettingsSubLabel('Available'));
    expect(find.byType(SettingsAddButton), findsNothing);
    expect(find.text('Available'), findsOneWidget);
  });
}
