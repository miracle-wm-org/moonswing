import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:moonswing/todo/todo_backup.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_remote_backup.dart';
import 'package:moonswing/todo/todo_store.dart';

/// A WebDAV server in a map: PUT writes, GET reads, MKCOL makes a folder, and
/// a PUT into a folder that is not there is a 409.
class _FakeDav {
  final Map<String, String> files = {};
  final Set<String> folders = {'/dav/'};
  final List<http.Request> requests = [];
  int? failWith;

  MockClient get client => MockClient((request) async {
    requests.add(request);
    final code = failWith;
    if (code != null) return http.Response('', code);
    final path = request.url.path;
    switch (request.method) {
      case 'PUT':
        final folder = path.substring(0, path.lastIndexOf('/') + 1);
        if (!folders.contains(folder)) return http.Response('', 409);
        final created = !files.containsKey(path);
        files[path] = request.body;
        return http.Response('', created ? 201 : 204);
      case 'GET':
        final body = files[path];
        return body == null
            ? http.Response('', 404)
            : http.Response.bytes(utf8.encode(body), 200);
      case 'MKCOL':
        if (folders.contains(path)) return http.Response('', 405);
        folders.add(path);
        return http.Response('', 201);
    }
    return http.Response('', 405);
  });
}

void main() {
  late Directory dir;
  late DateTime now;
  late TodoStore store;
  late _FakeDav dav;
  late TodoRemoteBackup remote;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('todo_remote_backup_test');
    now = DateTime(2026, 9, 25, 9);
    store = TodoStore.forTesting(directory: '${dir.path}/data', now: () => now);
    await store.load();
    dav = _FakeDav();
    remote = TodoRemoteBackup.forTesting(
      store: store,
      directory: '${dir.path}/state',
      client: dav.client,
      now: () => now,
    );
    await remote.load();
  });

  tearDown(() {
    remote.dispose();
    store.dispose();
    dir.deleteSync(recursive: true);
  });

  group('addresses', () {
    test('a folder gets the file name; a .json address is the file', () {
      expect(
        remoteBackupFileUri('https://h/dav/Backups/').toString(),
        'https://h/dav/Backups/moonswing-todo.json',
      );
      expect(
        remoteBackupFileUri('https://h/dav/Backups').toString(),
        'https://h/dav/Backups/moonswing-todo.json',
      );
      expect(
        remoteBackupFileUri('https://h/dav/mine.json').toString(),
        'https://h/dav/mine.json',
      );
      expect(remoteBackupFileUri('ftp://h/x'), isNull);
      expect(remoteBackupFileUri('not a url'), isNull);
    });

    test('a daily copy sits beside the file', () {
      expect(
        remoteBackupDailyUri(
          Uri.parse('https://h/dav/moonswing-todo.json'),
          DateTime(2026, 9, 5),
        ).toString(),
        'https://h/dav/moonswing-todo-2026-09-05.json',
      );
    });

    test('plain http is insecure except to this machine', () {
      expect(remoteBackupIsInsecure('http://nas.lan/dav/'), isTrue);
      expect(remoteBackupIsInsecure('http://localhost:8080/'), isFalse);
      expect(remoteBackupIsInsecure('https://nas.lan/dav/'), isFalse);
    });
  });

  test('a new server is sent the board, with a daily copy', () async {
    store.add(TodoColumn.inbox, title: 'Ship it');
    await store.flush();
    await remote.add(
      name: 'NAS',
      url: 'https://nas.example/dav/',
      username: 'me',
      password: 'secret',
    );
    await remote.runDue();

    final latest = dav.files['/dav/moonswing-todo.json'];
    expect(latest, store.backupContents);
    expect(decodeTodoBackup(latest!).items.single.title, 'Ship it');
    expect(dav.files['/dav/moonswing-todo-2026-09-25.json'], latest);
    expect(
      dav.requests.first.headers['authorization'],
      'Basic ${base64Encode(utf8.encode('me:secret'))}',
    );
    final status = remote.status(remote.servers.single.id);
    expect(status.lastSuccess, now);
    expect(status.lastError, isNull);
  });

  test('an unchanged board is never sent twice', () async {
    await remote.add(name: 'NAS', url: 'https://nas.example/dav/');
    await remote.runDue();
    final sent = dav.requests.length;
    now = now.add(const Duration(days: 3));
    await remote.runDue();
    expect(dav.requests, hasLength(sent));
  });

  test('a changed board waits for the server\'s frequency', () async {
    await remote.add(
      name: 'NAS',
      url: 'https://nas.example/dav/',
      keepDaily: false,
    );
    await remote.runDue();
    expect(dav.requests, hasLength(1));

    store.add(TodoColumn.inbox, title: 'Later');
    await store.flush();
    now = now.add(const Duration(minutes: 30));
    await remote.runDue();
    expect(dav.requests, hasLength(1));

    now = now.add(const Duration(minutes: 31));
    await remote.runDue();
    expect(dav.requests, hasLength(2));
    expect(
      decodeTodoBackup(
        dav.files['/dav/moonswing-todo.json']!,
      ).items.single.title,
      'Later',
    );
  });

  test('a missing folder is made once', () async {
    await remote.add(
      name: 'NAS',
      url: 'https://nas.example/dav/todo/',
      keepDaily: false,
    );
    await remote.runDue();
    expect(dav.requests.map((r) => r.method), ['PUT', 'MKCOL', 'PUT']);
    expect(dav.files, contains('/dav/todo/moonswing-todo.json'));
  });

  test('a refusal is recorded and retried sooner than the schedule', () async {
    dav.failWith = 401;
    await remote.add(
      name: 'NAS',
      url: 'https://nas.example/dav/',
      frequency: BackupFrequency.daily,
    );
    await remote.runDue();
    final id = remote.servers.single.id;
    expect(remote.status(id).lastError, contains('user name or password'));
    expect(remote.anyFailing, isTrue);

    dav.failWith = null;
    now = now.add(kRemoteBackupRetry);
    await remote.runDue();
    expect(remote.status(id).lastError, isNull);
    expect(remote.anyFailing, isFalse);
  });

  test('a paused server is sent nothing', () async {
    final server = await remote.add(name: 'NAS', url: 'https://h/dav/');
    await remote.update(server.copyWith(enabled: false));
    await remote.runDue();
    expect(dav.requests, isEmpty);
  });

  test('a backup is read back from the server', () async {
    store.add(TodoColumn.todo, title: 'Round trip');
    await store.flush();
    final server = await remote.add(name: 'NAS', url: 'https://h/dav/');
    expect(await remote.backUpNow(server.id), isNull);

    final backup = await remote.fetch(server.id);
    expect(backup.items.single.title, 'Round trip');
  });

  test('a board that did not read is never sent', () async {
    final broken = TodoStore.forTesting(
      directory: '${dir.path}/broken',
      now: () => now,
    );
    addTearDown(broken.dispose);
    Directory('${dir.path}/broken').createSync();
    File('${dir.path}/broken/notes.db').writeAsBytesSync(List.filled(4096, 7));
    await broken.load();
    expect(broken.editable, isFalse);

    final other = TodoRemoteBackup.forTesting(
      store: broken,
      directory: '${dir.path}/state2',
      client: dav.client,
      now: () => now,
    );
    addTearDown(other.dispose);
    await other.load();
    final server = await other.add(name: 'NAS', url: 'https://h/dav/');
    await other.runDue();
    expect(await other.backUpNow(server.id), isNotNull);
    expect(dav.requests, isEmpty);
  });

  test('the list survives a restart, and only its owner can read it', () async {
    await remote.add(
      name: 'NAS',
      url: 'https://h/dav/',
      username: 'me',
      password: 'secret',
      frequency: BackupFrequency.sixHours,
    );
    await remote.runDue();

    final again = TodoRemoteBackup.forTesting(
      store: store,
      directory: '${dir.path}/state',
      client: dav.client,
      now: () => now,
    );
    addTearDown(again.dispose);
    await again.load();
    final server = again.servers.single;
    expect(server.password, 'secret');
    expect(server.frequency, BackupFrequency.sixHours);
    expect(again.status(server.id).lastSuccess, now);

    final mode = File(again.path).statSync().mode & 0x1ff;
    expect(mode, 0x180); // 0600
  });
}
