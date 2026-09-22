import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/keyboard/keyboard_store.dart';
import 'package:moonswing/keyboard/locale1_client.dart';
import 'package:moonswing/keyboard/xkb_catalog.dart';
import 'package:moonswing/modules/keyboard_layout.dart';
import 'package:moonswing/scopes.dart';

import 'keyboard_fakes.dart';

const _us = InputSource('us');
const _de = InputSource('de');

KeyboardStore _store({
  List<InputSource> sources = const [_us, _de],
  Locale1Keyboard system = const Locale1Keyboard(layout: 'us', model: 'pc105'),
  String error = '',
}) {
  // The fake carries the same state the store is seeded with: `acquire()`
  // reads through the client, so a fake left on its default would overwrite
  // the seed a frame later.
  return KeyboardStore.forTesting(client: FakeLocale1Client(state: system))
    ..seed(
      sources: sources,
      systemState: system,
      status: KeyboardStatus.ready,
      error: error,
      catalog: parseXkbRulesList('''
! layout
  us              English (US)
  de              German
'''),
    );
}

Future<void> _pump(WidgetTester tester, KeyboardStore store,
    {KeyboardLayoutConfig config = const KeyboardLayoutConfig()}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ThemeScope(
        theme: const ThemeConfig(),
        child: BarScope(
          anchor: 'top',
          child: Align(
            alignment: Alignment.topLeft,
            child: KeyboardLayout(config: config, store: store),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('one source and nothing to report renders nothing',
      (tester) async {
    await _pump(tester, _store(sources: const [_us]));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('two sources show the active one', (tester) async {
    await _pump(tester, _store());
    expect(find.text('en'), findsOneWidget);
  });

  testWidgets('hide_when_single = false shows a lone source', (tester) async {
    await _pump(
      tester,
      _store(sources: const [_us]),
      config: const KeyboardLayoutConfig(hideWhenSingle: false),
    );
    expect(find.text('en'), findsOneWidget);
  });

  testWidgets('a failure keeps the badge up even with one source',
      (tester) async {
    // WeatherStore.error's rule: an empty bar module is indistinguishable from
    // one the user never enabled.
    await _pump(tester, _store(sources: const [_us], error: 'refused'));
    expect(find.text('en'), findsOneWidget);
    final text = tester.widget<Text>(find.text('en'));
    expect(text.style?.color, const Color(0xFFE06C75));
  });

  testWidgets('an unlisted active layout keeps the badge up', (tester) async {
    await _pump(
      tester,
      _store(
        sources: const [_us],
        system: const Locale1Keyboard(layout: 'fr'),
      ),
    );
    // Its own short code, not the list's first entry's.
    expect(find.text('fr'), findsOneWidget);
  });

  testWidgets('uppercase draws the code in caps', (tester) async {
    await _pump(
      tester,
      _store(),
      config: const KeyboardLayoutConfig(uppercase: true),
    );
    expect(find.text('EN'), findsOneWidget);
  });

  testWidgets('collisions are disambiguated on the badge', (tester) async {
    await _pump(
      tester,
      _store(
        sources: const [_us, InputSource('gb')],
        system: const Locale1Keyboard(layout: 'gb'),
      ),
    );
    expect(find.text('en2'), findsOneWidget);
  });

  testWidgets('locale1 reporting nothing yet is not a lie', (tester) async {
    await _pump(
      tester,
      _store(system: const Locale1Keyboard(), sources: const [_us, _de]),
    );
    // Never source 0: the shell does not claim a layout it has not been told
    // about.
    expect(find.text('--'), findsOneWidget);
  });

  test('the module registers under its config key with its defaults', () {
    expect(keyboardLayoutModule.configKey, 'keyboard_layout');
    const defaults = KeyboardLayoutConfig();
    expect(defaults.hideWhenSingle, isTrue);
    expect(defaults.uppercase, isFalse);
    expect(
      KeyboardLayoutConfig.fromMap({'hide_when_single': 'nope'}),
      defaults,
      reason: 'a wrongly-typed value costs that key, never the table',
    );
    expect(
      KeyboardLayoutConfig.fromMap({'uppercase': true}),
      const KeyboardLayoutConfig(uppercase: true),
    );
  });
}
