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
}
