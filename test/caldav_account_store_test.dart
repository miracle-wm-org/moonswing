import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:moonswing/caldav/caldav_account_store.dart';

import 'caldav_fakes.dart';

/// [request] as a request that can be sent again.
///
/// `MockClient` finalizes the request it hands its handler, and a finalized
/// request cannot be sent: passing it straight on to the fake server's own
/// `MockClient` throws "Can't finalize a finalized Request", which the store
/// reports as the server being unreachable.
http.Request _copy(http.Request request) =>
    http.Request(request.method, request.url)
      ..followRedirects = request.followRedirects
      ..headers.addAll(request.headers)
      ..bodyBytes = request.bodyBytes;

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
      return server.client.send(_copy(request)).then(http.Response.fromStream);
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
    expect(account.accounts, isEmpty);
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
      return server.client.send(_copy(request)).then(http.Response.fromStream);
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
    expect(account.accounts.single.password, 'secret');
    expect(account.error, isEmpty);
    expect(account.busy, isFalse);
  });
}
