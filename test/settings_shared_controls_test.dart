import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';

/// Pins the bug class the shared-controls migration closed: whole settings
/// pages used to drift off the theme font because a cloned control's
/// TextStyle dropped `fontFamily:`. Every text-bearing shared control must
/// carry the theme's family explicitly.
const _kFamily = 'PinnedTestFamily';

Widget _host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: ThemeScope(
        theme: const ThemeConfig(fontFamily: _kFamily),
        child: Center(child: child),
      ),
    );

void _expectAllTextThemed(WidgetTester tester) {
  final texts = tester.widgetList<Text>(find.byType(Text));
  expect(texts, isNotEmpty);
  for (final text in texts) {
    expect(text.style?.fontFamily, _kFamily,
        reason: '"${text.data}" does not carry the theme font');
  }
}

void main() {
  testWidgets('SettingsActionButton text carries the theme font',
      (tester) async {
    await tester.pumpWidget(
        _host(SettingsActionButton(label: 'Apply', onTap: () {})));
    _expectAllTextThemed(tester);
  });

  testWidgets('SettingsBadge text carries the theme font', (tester) async {
    await tester.pumpWidget(_host(const SettingsBadge('Connected')));
    _expectAllTextThemed(tester);
  });

  testWidgets('SettingsRescanButton text carries the theme font',
      (tester) async {
    await tester.pumpWidget(_host(SettingsRescanButton(onTap: () {})));
    _expectAllTextThemed(tester);
  });

  testWidgets('SettingsOptionButton text carries the theme font',
      (tester) async {
    await tester.pumpWidget(_host(
        SettingsOptionButton(label: 'Fill', selected: true, onTap: () {})));
    _expectAllTextThemed(tester);
  });

  testWidgets('SettingsSectionLabel text carries the theme font',
      (tester) async {
    await tester.pumpWidget(_host(const SettingsSectionLabel('Devices')));
    _expectAllTextThemed(tester);
  });

  testWidgets('SettingsListRow text carries the theme font', (tester) async {
    await tester.pumpWidget(_host(SettingsListRow(
      onMoveUp: () {},
      onMoveDown: () {},
      onRemove: () {},
      trailing: const SettingsBadge('Active'),
      child: const Text('English (US)',
          style: TextStyle(fontFamily: _kFamily)),
    )));
    _expectAllTextThemed(tester);
  });

  testWidgets('SettingsBanner text carries the theme font', (tester) async {
    await tester.pumpWidget(_host(SizedBox(
      width: 420,
      child: SettingsBanner(
        title: 'Could not change the layout',
        message: 'The system refused the change.',
        action: SettingsActionButton(
            label: 'Retry', compact: true, onTap: () {}),
      ),
    )));
    _expectAllTextThemed(tester);
  });

  testWidgets('SettingsNotice text carries the theme font', (tester) async {
    await tester.pumpWidget(_host(SizedBox(
      width: 420,
      child: SettingsNotice(
        title: 'Saved — now tell miracle to read it',
        message: 'Press Action Key + Shift + R to apply it.',
        onDismiss: () {},
      ),
    )));
    _expectAllTextThemed(tester);
  });

  testWidgets('SettingsChipToggles text carries the theme font',
      (tester) async {
    await tester.pumpWidget(_host(SizedBox(
      width: 420,
      child: SettingsChipToggles<String>(
        options: const ['Ctrl', 'Shift'],
        selected: const {'Shift'},
        labelOf: (value) => value,
        onChanged: (_) {},
      ),
    )));
    _expectAllTextThemed(tester);
  });

  // The multi-select is the single-select with more than one pill lit, so what
  // is worth pinning is the selection arithmetic rather than the chrome: a
  // toggle that replaced the set instead of adding to it would look identical
  // until the second chip was tapped.
  testWidgets('SettingsChipToggles adds to and removes from the set',
      (tester) async {
    var latest = <String>{'Shift'};
    await tester.pumpWidget(_host(SizedBox(
      width: 420,
      child: SettingsChipToggles<String>(
        options: const ['Ctrl', 'Shift'],
        selected: latest,
        labelOf: (value) => value,
        onChanged: (next) => latest = next,
      ),
    )));

    await tester.tap(find.text('Ctrl'));
    expect(latest, {'Shift', 'Ctrl'});

    await tester.tap(find.text('Shift'));
    expect(latest, isEmpty);
  });
}
