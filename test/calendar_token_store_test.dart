import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/overlay/calendar/google_oauth.dart';
import 'package:graceful_shell/overlay/calendar/token_store.dart';

void main() {
  late Directory tempDir;
  late String path;
  late CalendarTokenStore store;

  setUp(() async {
    // Never the real ~/.local/share — the store is always given a temp path.
    tempDir = await Directory.systemTemp.createTemp('gs_calendar_tokens_test');
    path = '${tempDir.path}/calendar_tokens.json';
    store = CalendarTokenStore(path: path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  OAuthTokens tokens({String access = 'at', String? refresh = 'rt'}) {
    return OAuthTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: DateTime(2026, 7, 13, 12),
      email: 'user@gmail.com',
    );
  }

  test('loadAll on a missing file yields an empty map', () async {
    expect(await store.loadAll(), isEmpty);
  });

  test('save then load round-trips', () async {
    await store.save('google', tokens());
    final all = await store.loadAll();

    expect(all.keys, ['google']);
    expect(all['google']!.accessToken, 'at');
    expect(all['google']!.refreshToken, 'rt');
    expect(all['google']!.email, 'user@gmail.com');
    expect(all['google']!.expiresAt, DateTime(2026, 7, 13, 12));
  });

  test('saving one provider leaves the others alone', () async {
    await store.save('google', tokens(access: 'g'));
    await store.save('caldav', tokens(access: 'c'));

    final all = await store.loadAll();
    expect(all.keys, containsAll(['google', 'caldav']));
    expect(all['google']!.accessToken, 'g');
    expect(all['caldav']!.accessToken, 'c');
  });

  test('clear removes only the named provider', () async {
    await store.save('google', tokens());
    await store.save('caldav', tokens());

    await store.clear('google');

    final all = await store.loadAll();
    expect(all.keys, ['caldav']);
  });

  test('clearing an absent provider is a no-op', () async {
    await store.clear('google');
    expect(await store.loadAll(), isEmpty);
  });

  test('a corrupt file reads back as empty instead of throwing', () async {
    await File(path).writeAsString('{not json');
    expect(await store.loadAll(), isEmpty);
  });

  test('the token file is not readable by other users', () async {
    await store.save('google', tokens());

    final mode = await File(path).stat().then((s) => s.mode & 0x1FF);
    expect(mode, 0x180, reason: 'expected 0600, got ${mode.toRadixString(8)}');
  });

  test('no temp file is left behind after a save', () async {
    await store.save('google', tokens());
    expect(await File('$path.tmp').exists(), isFalse);
  });
}
