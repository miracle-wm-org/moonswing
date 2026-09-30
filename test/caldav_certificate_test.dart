// A CalDAV server behind a certificate no system trusts — self-signed, as a
// home server's often is — reached over real TLS, since the trust decision is
// made inside `dart:io`'s handshake where `MockClient` cannot follow.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/caldav/caldav_account_store.dart';
import 'package:moonswing/caldav/caldav_client.dart';

// `openssl req -x509 -days 36500 -subj /CN=localhost`, for this test alone.
const String _cert = '''
-----BEGIN CERTIFICATE-----
MIIBmjCCAUGgAwIBAgIUG7jkXl320xWl2VAGyDNUUGxNomowCgYIKoZIzj0EAwIw
FDESMBAGA1UEAwwJbG9jYWxob3N0MCAXDTI2MDkzMDEyMTMyOVoYDzIxMjYwOTA2
MTIxMzI5WjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwWTATBgcqhkjOPQIBBggqhkjO
PQMBBwNCAATBbb4NM2WS75vI+BfciliTTQhObQysfPX35dcU1NhP0QToxZomnJRY
hSLOTWCOjOXgPpqEbw1haFz0ElHAmFDno28wbTAdBgNVHQ4EFgQUsS+s6fH3VD21
kpZrqrv6VUWDMtswHwYDVR0jBBgwFoAUsS+s6fH3VD21kpZrqrv6VUWDMtswDwYD
VR0TAQH/BAUwAwEB/zAaBgNVHREEEzARgglsb2NhbGhvc3SHBH8AAAEwCgYIKoZI
zj0EAwIDRwAwRAIgHMvgrJtCNvnE7GIT2a+7z3Q8OxQPWOUlz/MWmjddiIICIFP+
u4ATZF9dLXWb6d1d52X4O0z9PUrlUbNK1Rw5E1D4
-----END CERTIFICATE-----
''';

const String _key = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg/3zYU8wi9lELOJAK
JR14SD7JWgC5AEnj/ae6l/C9f7+hRANCAATBbb4NM2WS75vI+BfciliTTQhObQys
fPX35dcU1NhP0QToxZomnJRYhSLOTWCOjOXgPpqEbw1haFz0ElHAmFDn
-----END PRIVATE KEY-----
''';

// `openssl x509 -in cert.pem -noout -fingerprint -sha256`, which the one the
// shell shows has to match character for character.
const String _fingerprint =
    '5A:E3:A1:A1:9E:0F:32:A1:B9:4B:2B:BE:12:AC:26:56:'
    '7B:8D:F4:4E:80:2B:EF:D3:0B:AD:56:DD:8B:EE:8A:B6';

const String _taskList = '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:response>
    <d:href>/tasks/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
        <d:displayname>Tasks</d:displayname>
        <c:supported-calendar-component-set>
          <c:comp name="VTODO"/>
        </c:supported-calendar-component-set>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>
''';

void main() {
  late HttpServer server;
  late Uri url;
  late Directory dir;

  setUp(() async {
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(_cert))
      ..usePrivateKeyBytes(utf8.encode(_key));
    server = await HttpServer.bindSecure('localhost', 0, context);
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = 207
        ..headers.contentType = ContentType('application', 'xml')
        ..write(_taskList);
      await request.response.close();
    });
    url = Uri.parse('https://localhost:${server.port}/tasks/');
    dir = Directory.systemTemp.createTempSync('caldav_certificate');
  });

  tearDown(() async {
    await server.close(force: true);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('an untrusted certificate is refused, and named', () async {
    final client = CalDavClient(username: 'me', password: 'secret');
    await expectLater(
      client.discoverTaskLists(url),
      throwsA(
        isA<CalDavUntrustedCertificate>()
            .having(
              (e) => e.certificate.fingerprint,
              'fingerprint',
              _fingerprint,
            )
            .having((e) => e.certificate.host, 'host', 'localhost'),
      ),
    );
  });

  test('the pinned certificate is trusted, and only it', () async {
    final pinned = CalDavClient(
      username: 'me',
      password: 'secret',
      trustedCertificate: _fingerprint,
    );
    final lists = await pinned.discoverTaskLists(url);
    expect(lists.single.name, 'Tasks');

    final other = CalDavClient(
      username: 'me',
      password: 'secret',
      trustedCertificate: _fingerprint.replaceFirst('5A', '5B'),
    );
    await expectLater(
      other.discoverTaskLists(url),
      throwsA(isA<CalDavUntrustedCertificate>()),
    );
  });

  test(
    'the account offers the certificate, and keeps it once trusted',
    () async {
      final account = CalDavAccountStore.forTesting(directory: dir.path);
      await account.load();

      expect(
        await account.signIn(
          url: url.toString(),
          username: 'me',
          password: 'secret',
        ),
        isFalse,
      );
      final offered = account.untrustedCertificate;
      expect(offered?.fingerprint, _fingerprint);
      expect(account.account, isNull);

      expect(
        await account.signIn(
          url: url.toString(),
          username: 'me',
          password: 'secret',
          trustedCertificate: offered!.fingerprint,
        ),
        isTrue,
      );
      expect(account.untrustedCertificate, isNull);

      final reloaded = CalDavAccountStore.forTesting(directory: dir.path);
      await reloaded.load();
      expect(reloaded.account?.trustedCertificate, _fingerprint);
      expect(
        (await reloaded.client()!.discoverTaskLists(url)).single.name,
        'Tasks',
      );
    },
  );
}
