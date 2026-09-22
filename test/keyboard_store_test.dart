import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/keyboard/keyboard_store.dart';
import 'package:moonswing/keyboard/locale1_client.dart';

import 'keyboard_fakes.dart';

const _us = InputSource('us');
const _de = InputSource('de');

void main() {
  late Directory tempDir;
  late String path;
  late FakeLocale1Client client;

  Future<ConfigStore> configWith(String contents) async {
    await File(path).writeAsString(contents);
    return ConfigStore.loadFrom(path);
  }

  Future<KeyboardStore> leased(ConfigStore config) async {
    final store = KeyboardStore.forTesting(client: client, configStore: config);
    store.acquire();
    // The first read, the seed and the catalogue load are all off the
    // microtask queue.
    await pumpEventQueue();
    return store;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gs_keyboard_test');
    path = '${tempDir.path}/config.toml';
    client = FakeLocale1Client();
  });

  tearDown(() async {
    client.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('the first lease reads locale1 and settles ready', () async {
    final store = await leased(await configWith('''
[[keyboard.sources]]
layout = "us"
'''));
    expect(store.status, KeyboardStatus.ready);
    expect(store.sources, const [_us]);
    expect(store.activeIndex, 0);
    expect(store.error, isEmpty);
  });

  test('the last release drops the subscription; state survives it', () async {
    final store = await leased(await configWith('''
[[keyboard.sources]]
layout = "us"
'''));
    store.acquire();
    store.release();
    // Still leased once: an external change still lands.
    client.push(const Locale1Keyboard(layout: 'de'));
    await pumpEventQueue();
    expect(store.unlistedActive, _de);

    store.release();
    client.push(const Locale1Keyboard(layout: 'fr'));
    await pumpEventQueue();
    // Unsubscribed — but nothing was cleared, because a popup closing must not
    // throw away what the user has not read.
    expect(store.unlistedActive, _de);
    expect(store.sources, const [_us]);
  });

  test('activate re-sends model and options unchanged', () async {
    client = FakeLocale1Client(
      state: const Locale1Keyboard(
        layout: 'us',
        model: 'pc105',
        options: 'compose:ralt,caps:escape',
      ),
    );
    final store = await leased(await configWith('''
[[keyboard.sources]]
layout = "us"

[[keyboard.sources]]
layout = "de"
'''));
    await store.activate(_de);

    expect(client.writes, hasLength(1));
    final write = client.writes.single;
    expect(write.layout, 'de');
    expect(write.variant, '');
    // Sending '' for these silently deletes the user's compose and caps
    // options, and nothing shows it until they reach for the key.
    expect(write.model, 'pc105');
    expect(write.options, 'compose:ralt,caps:escape');
  });

  test('a refused activate keeps the old active row and reports why', () async {
    client.writeFailure = const Locale1Failure(
      Locale1FailureKind.denied,
      'refused',
    );
    final store = await leased(await configWith('''
[[keyboard.sources]]
layout = "us"

[[keyboard.sources]]
layout = "de"
'''));
    await store.activate(_de);

    expect(store.activeIndex, 0, reason: 'never set optimistically');
    expect(store.error, 'refused');
    expect(store.errorKind, Locale1FailureKind.denied);
    expect(store.pending, isNull);
  });

  test('activate refuses to stack', () async {
    final store = await leased(await configWith('''
[[keyboard.sources]]
layout = "us"

[[keyboard.sources]]
layout = "de"
'''));
    client.gate = Completer<void>();
    final first = store.activate(_de);
    await pumpEventQueue();
    expect(store.pending, _de);

    // A second click while a polkit prompt is up must not queue a second
    // write.
    await store.activate(_us);
    expect(store.pending, _de);

    client.gate!.complete();
    await first;
    expect(client.writes, hasLength(1));
  });

  test('retry re-issues the write that failed', () async {
    client.writeFailure = const Locale1Failure(
      Locale1FailureKind.denied,
      'refused',
    );
    final store = await leased(await configWith('''
[[keyboard.sources]]
layout = "us"

[[keyboard.sources]]
layout = "de"
'''));
    await store.activate(_de);
    expect(client.writes, hasLength(1));

    client.writeFailure = null;
    await store.retry();
    await pumpEventQueue();

    expect(client.writes, hasLength(2));
    expect(client.writes.last.layout, 'de');
    expect(store.error, isEmpty);
    expect(store.activeIndex, 1);
  });

  test('an external change moves the active row with no call', () async {
    final store = await leased(await configWith('''
[[keyboard.sources]]
layout = "us"

[[keyboard.sources]]
layout = "de"
'''));
    expect(store.activeIndex, 0);

    client.push(const Locale1Keyboard(layout: 'de', model: 'pc105'));
    await pumpEventQueue();

    expect(store.activeIndex, 1);
    expect(client.writes, isEmpty);
  });

  test('a layout in no source is reported, not corrected', () async {
    final store = await leased(await configWith('''
[[keyboard.sources]]
layout = "us"
'''));
    client.push(const Locale1Keyboard(layout: 'fr'));
    await pumpEventQueue();

    expect(store.activeIndex, -1);
    expect(store.unlistedActive, const InputSource('fr'));
    expect(client.writes, isEmpty, reason: 'never rewrites locale1 itself');
  });

  test('an unreachable locale1 is unavailable, and the list still loads',
      () async {
    client.readFailure = const Locale1Failure(
      Locale1FailureKind.unavailable,
      'no bus',
    );
    final store = await leased(await configWith('''
[[keyboard.sources]]
layout = "us"
'''));
    expect(store.status, KeyboardStatus.unavailable);
    expect(store.error, 'no bus');
    expect(store.sources, const [_us], reason: "it is moonswing's own config");
  });

  group('seeding', () {
    test('an absent key is seeded from locale1, once', () async {
      client = FakeLocale1Client(
        state: const Locale1Keyboard(
          layout: 'us,de',
          variant: ',nodeadkeys',
          model: 'pc105',
        ),
      );
      final config = await configWith('theme = "moonswing"\n');
      final store = await leased(config);

      expect(store.sources, const [
        _us,
        InputSource('de', variant: 'nodeadkeys'),
      ]);
      expect(
        config.getList<Map<String, dynamic>>(['keyboard', 'sources']).length,
        2,
      );
    });

    test('a present-but-empty list is left alone', () async {
      // The user removed everything; re-seeding would put it back.
      final config = await configWith('''
[keyboard]
sources = []
''');
      final store = await leased(config);
      expect(store.sources, isEmpty);
      expect(config.get<List>(['keyboard', 'sources']), isEmpty);
    });

    test('a second lease does not re-seed', () async {
      final config = await configWith('theme = "moonswing"\n');
      final store = await leased(config);
      expect(store.sources, const [_us]);

      store.removeAt(0);
      expect(store.sources, isEmpty);

      store.release();
      store.acquire();
      await pumpEventQueue();
      expect(store.sources, isEmpty);
    });
  });

  group('list edits', () {
    test('add, remove and move each write the whole list once', () async {
      final config = await configWith('''
[[keyboard.sources]]
layout = "us"

[[keyboard.sources]]
layout = "de"
''');
      final store = await leased(config);
      var writes = 0;
      config.addListener(() => writes++);

      store.moveBy(0, 1);
      expect(store.sources, const [_de, _us]);
      expect(writes, 1);

      store.addSource(const InputSource('fr'));
      expect(store.sources.last, const InputSource('fr'));
      expect(writes, 2);

      // Already listed: no write at all.
      store.addSource(const InputSource('fr'));
      expect(writes, 2);

      store.removeAt(0);
      expect(store.sources, const [_us, InputSource('fr')]);
      expect(writes, 3);
    });

    test('a move off either end is refused', () async {
      final store = await leased(await configWith('''
[[keyboard.sources]]
layout = "us"

[[keyboard.sources]]
layout = "de"
'''));
      store.moveBy(0, -1);
      store.moveBy(1, 1);
      expect(store.sources, const [_us, _de]);
    });
  });

  test('short codes follow the list', () async {
    final store = await leased(await configWith('''
[[keyboard.sources]]
layout = "us"

[[keyboard.sources]]
layout = "gb"

[[keyboard.sources]]
layout = "de"
'''));
    expect(store.shortCodes, ['en', 'en2', 'de']);
    expect(store.activeShortCode, 'en');
  });
}
