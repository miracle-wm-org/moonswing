import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';

/// Pins where an add button sits: at the **top** of the list it adds to, on
/// the right. Every one of these used to be a block under its list, which is
/// the one place that walks away from the user as the list grows.
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
        children: const [Text('graceful')],
      ),
    );
    final label = tester.getRect(find.text('THEME'));
    final button = tester.getRect(find.text('New theme…'));
    expect(button.left, greaterThan(label.right));
    expect(button.bottom, lessThanOrEqualTo(tester
        .getRect(find.text('graceful'))
        .top));
  });

  testWidgets('a heading with no action still renders bare', (tester) async {
    await _pump(tester, const SettingsSubLabel('Available'));
    expect(find.byType(SettingsAddButton), findsNothing);
    expect(find.text('Available'), findsOneWidget);
  });

  group('the string-list editor', () {
    testWidgets('puts its adder above the rows, not under them',
        (tester) async {
      await _pump(
        tester,
        SettingsStringListEditor(
          label: 'Left modules',
          addLabel: 'Add module',
          items: const ['clock', 'workspaces', 'battery'],
          suggestions: const ['clock', 'workspaces', 'battery', 'weather'],
          onChanged: (_) {},
          width: null,
        ),
      );
      final button = tester.getRect(find.text('Add module'));
      for (final item in ['clock', 'workspaces', 'battery']) {
        expect(tester.getRect(find.text(item)).top, greaterThan(button.bottom),
            reason: '"$item" is above the add button');
      }
    });

    testWidgets('with no heading the adder is still top-right',
        (tester) async {
      await _pump(
        tester,
        SettingsStringListEditor(
          items: const ['discord', 'steam'],
          addHint: 'SNI id or title',
          onChanged: (_) {},
        ),
      );
      final button = tester.getRect(find.byType(SettingsAddButton));
      final row = tester.getRect(find.text('discord'));
      expect(button.bottom, lessThanOrEqualTo(row.top));
      // Right-aligned inside the editor's own 260px column.
      final column = tester.getRect(find.byType(SettingsStringListEditor));
      expect(button.right, closeTo(column.right, 1));
    });

    testWidgets('the free-form field is revealed by the button, and closes',
        (tester) async {
      await _pump(
        tester,
        SettingsStringListEditor(
          items: const ['discord'],
          addHint: 'SNI id or title',
          onChanged: (_) {},
        ),
      );
      expect(find.text('SNI id or title'), findsNothing);

      await tester.tap(find.byType(SettingsAddButton));
      await tester.pump();
      expect(find.text('SNI id or title'), findsOneWidget);
      // Above the row it will produce, so the field stays put as the list
      // grows under it.
      expect(
        tester.getRect(find.text('SNI id or title')).bottom,
        lessThanOrEqualTo(tester.getRect(find.text('discord')).top),
      );

      await tester.tap(find.byType(SettingsAddButton));
      await tester.pump();
      expect(find.text('SNI id or title'), findsNothing);
    });

    testWidgets('a typed value is appended and the field stays open',
        (tester) async {
      List<String>? emitted;
      await _pump(
        tester,
        SettingsStringListEditor(
          items: const ['discord'],
          addHint: 'SNI id or title',
          onChanged: (list) => emitted = list,
        ),
      );
      await tester.tap(find.byType(SettingsAddButton));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'steam');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(emitted, ['discord', 'steam']);
      expect(find.byType(EditableText), findsOneWidget);
    });
  });
}
