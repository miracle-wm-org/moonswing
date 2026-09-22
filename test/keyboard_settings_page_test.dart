import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/keyboard/keyboard_store.dart';
import 'package:moonswing/keyboard/locale1_client.dart';
import 'package:moonswing/keyboard/xkb_catalog.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/keyboard.dart';
import 'package:moonswing/overlay/settings/keyboard/input_source_picker.dart';
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

void main() {
  late Directory tempDir;
  late String path;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gs_keyboard_page_test');
    path = '${tempDir.path}/config.toml';
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// Through [WidgetTester.runAsync], because writing and parsing the file is
  /// real I/O and a `testWidgets` fake-async zone never pumps it — the note
  /// `weather_location_field_test.dart` carries about its own config store.
  Future<ConfigStore> configWith(
    WidgetTester tester,
    String contents,
  ) async {
    final store = await tester.runAsync(() async {
      await File(path).writeAsString(contents);
      return ConfigStore.loadFrom(path);
    });
    addTearDown(store!.dispose);
    return store;
  }

  Future<void> pump(WidgetTester tester, KeyboardStore store) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ThemeScope(
          theme: const ThemeConfig(),
          // Keyed on the store, so a second `pump` with a different one
          // rebuilds all of this. `initialEntries` is read once, in `Overlay`'s
          // own `initState`, so an unkeyed re-pump keeps the first entry and
          // its builder — and the page would go on rendering the first store
          // however the widget under it is keyed.
          child: Overlay(
            key: ObjectKey(store),
            initialEntries: [
              OverlayEntry(
                builder: (_) => SizedBox(
                  width: 620,
                  height: 560,
                  child: KeyboardSettingsPage(store: store),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  KeyboardStore seeded({
    List<InputSource> sources = const [_us, _de],
    Locale1Keyboard system = const Locale1Keyboard(
      layout: 'us',
      model: 'pc105',
    ),
    String error = '',
    Locale1FailureKind? errorKind,
    XkbCatalog? catalog,
    ConfigStore? config,
    FakeLocale1Client? client,
  }) {
    return KeyboardStore.forTesting(
      client: client ?? FakeLocale1Client(state: system),
      configStore: config,
    )..seed(
      sources: sources,
      systemState: system,
      status: KeyboardStatus.ready,
      error: error,
      errorKind: errorKind,
      catalog: catalog ?? _catalog,
    );
  }

  testWidgets('lists the sources, marks the active one, offers Use on others',
      (tester) async {
    await pump(tester, seeded());
    expect(find.text('English (US)'), findsOneWidget);
    expect(find.text('German'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Use'), findsOneWidget);
  });

  testWidgets('reorder and remove each issue exactly one config write',
      (tester) async {
    final config = await configWith(tester, '''
[[keyboard.sources]]
layout = "us"

[[keyboard.sources]]
layout = "de"
''');
    final store = seeded(config: config);
    await pump(tester, store);
    // The page's own lease re-read the config, so start from what it shows.
    var writes = 0;
    config.addListener(() => writes++);

    // Three icon buttons per row, in order: move up, move down, remove.
    // The first row's "move down".
    await tester.tap(find.byType(SettingsIconButton).at(1));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(store.sources, const [_de, _us]);

    // The (new) first row's remove.
    await tester.tap(find.byType(SettingsIconButton).at(2));
    await tester.pumpAndSettle();
    expect(writes, 2);
    expect(store.sources, const [_us]);

    // Each `ConfigStore.set` leaves its 400ms debounce behind, and a timer
    // still pending when the tree comes down fails the test binding's own
    // invariants. `flush` is the API for it; through `runAsync` because the
    // write it then makes is real I/O.
    await tester.runAsync(config.flush);
  });

  testWidgets('a failure is a banner with a retry, and the list stays editable',
      (tester) async {
    final client = FakeLocale1Client();
    await pump(
      tester,
      seeded(
        client: client,
        error: 'The system refused the change.',
        errorKind: Locale1FailureKind.denied,
      ),
    );

    expect(find.byType(SettingsBanner), findsOneWidget);
    expect(find.text('Could not change the layout'), findsOneWidget);
    expect(
      find.textContaining('org.freedesktop.locale1.set-keyboard'),
      findsWidgets,
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(client.reads, greaterThan(0));
  });

  testWidgets('an unavailable bus says so and still lists the sources',
      (tester) async {
    await pump(
      tester,
      seeded(
        error: "systemd's org.freedesktop.locale1 did not answer.",
        errorKind: Locale1FailureKind.unavailable,
      ),
    );
    expect(find.text('Keyboard layout service unavailable'), findsOneWidget);
    expect(find.text('English (US)'), findsOneWidget);
  });

  testWidgets('"Add to input sources" only appears for an unlisted layout',
      (tester) async {
    await pump(tester, seeded());
    expect(find.text('Add to input sources'), findsNothing);

    final store = seeded(
      sources: const [_us],
      system: const Locale1Keyboard(layout: 'fr'),
    );
    await pump(tester, store);
    expect(find.text('Not in your list'), findsOneWidget);
    await tester.tap(find.text('Add to input sources'));
    await tester.pumpAndSettle();
    expect(store.sources, const [_us, InputSource('fr')]);
  });

  testWidgets('the picker degrades to a free-form field with no catalogue',
      (tester) async {
    final store = seeded(catalog: XkbCatalog.empty);
    await pump(tester, store);

    // `[keyboard]` must never become a key the UI can no longer set.
    expect(find.byType(InputSourcePicker), findsOneWidget);
    expect(find.byType(SettingsTextField), findsNothing);

    await tester.tap(find.text('Add Input Source'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsTextField), findsOneWidget);

    await tester.enterText(find.byType(SettingsTextField), 'fr+azerty');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(store.sources.last, const InputSource('fr', variant: 'azerty'));
  });

  testWidgets('the footer says this edits the whole machine', (tester) async {
    await pump(tester, seeded());
    expect(find.textContaining('/etc/default/keyboard'), findsOneWidget);
  });

  testWidgets('an empty list says what to do about it', (tester) async {
    await pump(tester, seeded(sources: const []));
    expect(
      find.text('No input sources yet. Add one to switch between layouts.'),
      findsOneWidget,
    );
  });
}
