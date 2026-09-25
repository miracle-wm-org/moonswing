import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_search.dart';
import 'package:moonswing/scopes.dart';

const _kFamily = 'PinnedTestFamily';

/// A root [Overlay] under the theme, the way the settings window has one.
///
/// The child goes through a notifier: an [Overlay] builds its initial entries
/// once, so pumping a new host would leave the old child on screen.
Future<void> _pump(WidgetTester tester, Widget child) async {
  final current = _current;
  if (current != null) {
    current.value = child;
    await tester.pump();
    return;
  }
  final notifier = _current = ValueNotifier<Widget>(child);
  addTearDown(() {
    _current = null;
    notifier.dispose();
  });
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ThemeScope(
        theme: const ThemeConfig(fontFamily: _kFamily),
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => ValueListenableBuilder<Widget>(
                valueListenable: notifier,
                builder: (context, child, _) => Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: 500, child: child),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

ValueNotifier<Widget>? _current;

final _field = miracleField(
  'miracle.test',
  'Test setting',
  section: 'General',
  description: 'What the test setting does.',
);

Finder get _infoIcon => find.byType(SettingsInfoTip);

Future<TestGesture> _hover(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets('the tip shows on hover, in the theme font, and hides on exit', (
    tester,
  ) async {
    await _pump(tester, const SettingsInfoTip('Explained here.'));
    expect(find.text('Explained here.'), findsNothing);

    final gesture = await _hover(tester, find.byType(SettingsInfoTip));
    expect(find.text('Explained here.'), findsOneWidget);
    final text = tester.widget<Text>(find.text('Explained here.'));
    expect(text.style?.fontFamily, _kFamily);

    await gesture.moveTo(const Offset(490, 590));
    await tester.pump();
    expect(find.text('Explained here.'), findsNothing);
  });

  testWidgets('a tap toggles the tip for a pointer that never hovers', (
    tester,
  ) async {
    await _pump(tester, const SettingsInfoTip('Explained here.'));
    await tester.tap(
      find.byType(SettingsInfoTip),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(find.text('Explained here.'), findsOneWidget);
    await tester.tap(
      find.byType(SettingsInfoTip),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(find.text('Explained here.'), findsNothing);
  });

  testWidgets('the tip goes with the icon', (tester) async {
    await _pump(tester, const SettingsInfoTip('Explained here.'));
    await _hover(tester, find.byType(SettingsInfoTip));
    expect(find.text('Explained here.'), findsOneWidget);
    await _pump(tester, const SizedBox());
    // Removed during the build, so the overlay drops it on the next frame.
    await tester.pump();
    expect(find.text('Explained here.'), findsNothing);
  });

  testWidgets('a catalogued row explains itself only where the pane asks', (
    tester,
  ) async {
    final row = SettingsRow.field(_field, control: const SizedBox(width: 40));
    await _pump(tester, row);
    expect(_infoIcon, findsNothing);

    await _pump(tester, SettingsPaneStyle(fieldInfo: true, child: row));
    expect(_infoIcon, findsOneWidget);
    await _hover(tester, find.byType(SettingsInfoTip));
    expect(find.text('What the test setting does.'), findsOneWidget);
  });

  testWidgets('an explicit info wins over the description', (tester) async {
    await _pump(
      tester,
      SettingsPaneStyle(
        fieldInfo: true,
        child: SettingsRow.field(
          _field,
          info: 'Something more.',
          control: const SizedBox(width: 40),
        ),
      ),
    );
    await _hover(tester, find.byType(SettingsInfoTip));
    expect(find.text('Something more.'), findsOneWidget);
    expect(find.text('What the test setting does.'), findsNothing);
  });

  testWidgets('a roomy pane spaces its rows further apart', (tester) async {
    const row = SettingsRow(label: 'Row', control: SizedBox(height: 20));
    await _pump(tester, const Column(children: [row]));
    final dense = tester.getSize(find.byType(SettingsRow)).height;
    await _pump(
      tester,
      const SettingsPaneStyle(roomy: true, child: Column(children: [row])),
    );
    final roomy = tester.getSize(find.byType(SettingsRow)).height;
    expect(roomy, greaterThan(dense));
  });

  group('SettingsTooltip', () {
    Widget button(VoidCallback onTap) => SettingsIconButton(
      icon: FontAwesomeIcons.plus,
      onTap: onTap,
      tooltip: 'Add a card',
    );

    testWidgets('speaks only once the pointer has rested, and not after', (
      tester,
    ) async {
      await _pump(tester, button(() {}));
      final gesture = await _hover(tester, find.byType(SettingsIconButton));
      expect(find.text('Add a card'), findsNothing);

      await tester.pump(kSettingsTooltipDelay);
      expect(find.text('Add a card'), findsOneWidget);
      final text = tester.widget<Text>(find.text('Add a card'));
      expect(text.style?.fontFamily, _kFamily);

      await gesture.moveTo(const Offset(490, 590));
      await tester.pump(kSettingsTooltipDelay);
      expect(find.text('Add a card'), findsNothing);
    });

    testWidgets('a press hides it and still reaches the button', (
      tester,
    ) async {
      var taps = 0;
      await _pump(tester, button(() => taps++));
      final gesture = await _hover(tester, find.byType(SettingsIconButton));
      await tester.pump(kSettingsTooltipDelay);
      expect(find.text('Add a card'), findsOneWidget);

      await gesture.down(tester.getCenter(find.byType(SettingsIconButton)));
      await tester.pump();
      expect(find.text('Add a card'), findsNothing);
      await gesture.up();
      await tester.pump(kSettingsTooltipDelay);
      expect(taps, 1);
      expect(find.text('Add a card'), findsNothing);
    });

    testWidgets('an exit before the delay cancels it', (tester) async {
      await _pump(tester, button(() {}));
      final gesture = await _hover(tester, find.byType(SettingsIconButton));
      await gesture.moveTo(const Offset(490, 590));
      await tester.pump(kSettingsTooltipDelay * 2);
      expect(find.text('Add a card'), findsNothing);
    });

    testWidgets('the tip goes with the button', (tester) async {
      await _pump(tester, button(() {}));
      await _hover(tester, find.byType(SettingsIconButton));
      await tester.pump(kSettingsTooltipDelay);
      expect(find.text('Add a card'), findsOneWidget);
      await _pump(tester, const SizedBox());
      await tester.pump();
      expect(find.text('Add a card'), findsNothing);
    });

    testWidgets('no message shows nothing', (tester) async {
      await _pump(
        tester,
        SettingsIconButton(icon: FontAwesomeIcons.plus, onTap: () {}),
      );
      await _hover(tester, find.byType(SettingsIconButton));
      await tester.pump(kSettingsTooltipDelay);
      expect(find.byType(IgnorePointer), findsNothing);
    });
  });
}
