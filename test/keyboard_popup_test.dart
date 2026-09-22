import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/keyboard/keyboard_store.dart';
import 'package:moonswing/keyboard/locale1_client.dart';
import 'package:moonswing/keyboard/xkb_catalog.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/modules/keyboard_layout.dart';
import 'package:moonswing/scopes.dart';

import 'keyboard_fakes.dart';

const _us = InputSource('us');
const _de = InputSource('de');

final _catalog = parseXkbRulesList('''
! layout
  us              English (US)
  de              German
  fr              French
''');

/// Pumped the way the shell actually builds it: under a [ThemeScope] and
/// **nothing else**.
///
/// A popup's child is laid out directly under its own FlutterView, so there is
/// no `_windowChrome` above it and nothing supplies a [Directionality] — which
/// `Directionality.of` null-asserts on, in release as well as debug. The card
/// supplies its own through `ShellTextRoot`; `popup_content_size_test.dart`
/// hands one down and so structurally cannot catch its absence.
Future<void> _pump(WidgetTester tester, KeyboardStore store) async {
  await tester.pumpWidget(
    ThemeScope(
      theme: const ThemeConfig(),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          // What `_KeyboardLayoutState._togglePopup` passes.
          constraints: const BoxConstraints(
            minWidth: 230,
            maxWidth: 300,
            maxHeight: 360,
          ),
          child: KeyboardLayoutPopup(store: store),
        ),
      ),
    ),
  );
  await tester.pump();
}

KeyboardStore _store({
  List<InputSource> sources = const [_us, _de],
  Locale1Keyboard system = const Locale1Keyboard(layout: 'us', model: 'pc105'),
  String error = '',
  Locale1FailureKind? errorKind,
  InputSource? pending,
  FakeLocale1Client? client,
}) {
  return KeyboardStore.forTesting(
    client: client ?? FakeLocale1Client(state: system),
  )..seed(
    sources: sources,
    systemState: system,
    status: KeyboardStatus.ready,
    error: error,
    errorKind: errorKind,
    pending: pending,
    catalog: _catalog,
  );
}

void main() {
  testWidgets('renders with no Directionality above it', (tester) async {
    await _pump(tester, _store());
    expect(tester.takeException(), isNull);
    expect(find.text('English (US)'), findsOneWidget);
    expect(find.text('German'), findsOneWidget);
    expect(find.text('Keyboard settings…'), findsOneWidget);
  });

  testWidgets('a row activates the source it names', (tester) async {
    final client = FakeLocale1Client();
    final store = _store(client: client);
    await _pump(tester, store);

    await tester.tap(find.text('German'));
    await tester.pumpAndSettle();

    expect(client.writes.single.layout, 'de');
  });

  testWidgets('every row is disabled while a write is in flight',
      (tester) async {
    final client = FakeLocale1Client();
    final store = _store(client: client, pending: _de);
    await _pump(tester, store);

    // The one in flight shows a loader…
    expect(find.byType(LoadingIndicator), findsOneWidget);
    // …and no row answers a tap, including the other one.
    await tester.tap(find.text('English (US)'));
    await tester.pump();
    expect(client.writes, isEmpty);
  });

  testWidgets('a failure is a strip above the list, with a retry',
      (tester) async {
    final client = FakeLocale1Client();
    final store = _store(
      client: client,
      error: 'The system refused the change.',
      errorKind: Locale1FailureKind.denied,
    );
    await _pump(tester, store);

    expect(find.text('Could not change the layout'), findsOneWidget);
    expect(find.text('The system refused the change.'), findsOneWidget);
    // Above the list: the rows say nothing about why nothing happened.
    expect(
      tester.getRect(find.text('Could not change the layout')).top,
      lessThan(tester.getRect(find.text('English (US)')).top),
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(client.reads, greaterThan(0));
  });

  testWidgets('an unlisted active layout is shown and is not tappable',
      (tester) async {
    final client = FakeLocale1Client(state: const Locale1Keyboard(layout: 'fr'));
    final store = _store(
      sources: const [_us],
      system: const Locale1Keyboard(layout: 'fr'),
      client: client,
    );
    await _pump(tester, store);

    expect(find.text('Not in your list'), findsOneWidget);
    expect(find.text('French'), findsOneWidget);

    await tester.tap(find.text('French'));
    await tester.pump();
    expect(client.writes, isEmpty);
  });

  testWidgets('an empty list says so rather than rendering nothing',
      (tester) async {
    await _pump(tester, _store(sources: const []));
    expect(find.text('No input sources yet.'), findsOneWidget);
  });
}
