import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:moonswing/caldav/caldav_account_store.dart';

import 'caldav_fakes.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('caldav_account'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('a cancelled sign-in keeps nothing, even when answered', () async {
    final server = FakeCalDavServer();
    final gate = Completer<void>();
    final slow = MockClient((request) async {
      await gate.future;
      return server.client.send(request).then(http.Response.fromStream);
    });
    final account = CalDavAccountStore.forTesting(
      directory: dir.path,
      client: slow,
    );
    await account.load();

    final signIn = account.signIn(
      url: FakeCalDavServer.host,
      username: 'me',
      password: 'secret',
    );
    expect(account.signingIn, isTrue);
    expect(account.busy, isTrue);

    account.cancelSignIn();
    expect(account.signingIn, isFalse);
    expect(account.busy, isFalse);

    gate.complete();
    expect(await signIn, isFalse);
    expect(account.account, isNull);
    expect(account.error, isEmpty);
    expect(File(account.path).existsSync(), isFalse);
  });

  test('a sign-in after a cancelled one is not undone by it', () async {
    final server = FakeCalDavServer();
    final gate = Completer<void>();
    var first = true;
    final client = MockClient((request) async {
      if (first) {
        first = false;
        await gate.future;
        return http.Response('', 401);
      }
      return server.client.send(request).then(http.Response.fromStream);
    });
    final account = CalDavAccountStore.forTesting(
      directory: dir.path,
      client: client,
    );
    await account.load();

    final mistyped = account.signIn(
      url: FakeCalDavServer.host,
      username: 'me',
      password: 'secrte',
    );
    account.cancelSignIn();
    expect(
      await account.signIn(
        url: FakeCalDavServer.host,
        username: 'me',
        password: 'secret',
      ),
      isTrue,
    );

    gate.complete();
    expect(await mistyped, isFalse);
    expect(account.account?.password, 'secret');
    expect(account.error, isEmpty);
    expect(account.busy, isFalse);
  });
}
