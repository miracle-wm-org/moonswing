import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/caldav/caldav_account_store.dart';
import 'package:moonswing/caldav/caldav_client.dart';
import 'package:moonswing/caldav/ical.dart';
import 'package:moonswing/todo/todo_caldav_map.dart';
import 'package:moonswing/todo/todo_caldav_sync.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_store.dart';

import 'caldav_fakes.dart';

void main() {
  late Directory dir;
  late FakeCalDavServer server;
  late CalDavAccountStore accounts;
  late TodoStore store;
  late TodoCalDavSync sync;
  late DateTime now;

  late CalDavCollection tasks;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('todo_caldav_sync_test');
    now = DateTime(2026, 9, 29, 9);
    server = FakeCalDavServer();
    accounts = CalDavAccountStore.forTesting(
      directory: '${dir.path}/state',
      client: server.client,
    );
    store = TodoStore.forTesting(
      directory: '${dir.path}/data',
      now: () => now,
      items: const [],
      inMemory: true,
    );
    sync = TodoCalDavSync.forTesting(
      store: store,
      accounts: accounts,
      now: () => now,
    );
    tasks = CalDavCollection(
      url: FakeCalDavServer.tasksUrl,
      name: 'Home tasks',
    );
    await accounts.load();
    expect(
      await accounts.signIn(
        url: FakeCalDavServer.host,
        username: 'me',
        password: 'secret',
      ),
      isTrue,
    );
  });

  tearDown(() {
    sync.dispose();
    store.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  ICalComponent serverTask(String path) =>
      masterTodo(parseICalendar(server.tasks[path]!.data))!;

  String pathOf(String id) => Uri.decodeFull(store.item(id)!.remote!.href);

  test('linking merges the board and the list', () async {
    final mine = store.add(TodoColumn.todo, title: 'From the board')!;
    final theirs = server.add(
      'phone.ics',
      otherAppTask(
        'phone-1',
        'SUMMARY:From the phone\r\nSTATUS:IN-PROCESS\r\n',
      ),
    );

    await sync.linkTo(tasks);
    expect(sync.error, isNull);

    final path = pathOf(mine);
    expect(serverTask(path).text('SUMMARY'), 'From the board');
    expect(serverTask(path).property('UID')!.value, '$mine@moonswing');
    final arrived = store.items.singleWhere((i) => i.title == 'From the phone');
    expect(arrived.column, TodoColumn.inProgress);
    expect(arrived.remote!.href, theirs);

    // Nothing left to say: the next run lists the collection once — the
    // writes moved its token — and writes and fetches nothing; the one after
    // does not even list it.
    server.log.clear();
    await sync.syncNow();
    expect(server.log.where((l) => l.startsWith('PUT')), isEmpty);
    expect(server.log.where((l) => l.startsWith('REPORT')), hasLength(1));
    server.log.clear();
    await sync.syncNow();
    expect(server.log, ['PROPFIND ${FakeCalDavServer.tasksPath}']);
  });

  test('an edit on the phone arrives; an edit here goes', () async {
    final id = store.add(TodoColumn.todo, title: 'Water plants')!;
    await sync.linkTo(tasks);
    final path = pathOf(id);

    server.edit(
      path,
      server.tasks[path]!.data.replaceFirst(
        'STATUS:NEEDS-ACTION',
        'STATUS:COMPLETED',
      ),
    );
    await sync.syncNow();
    expect(store.item(id)!.column, TodoColumn.finished);
    expect(store.item(id)!.history.last.to, TodoColumn.finished);

    final card = store.item(id)!;
    store.update(
      id,
      title: 'Water the plants',
      body: 'and the herbs',
      column: card.column,
      due: DateTime(2026, 10, 2),
      recurrence: null,
    );
    await sync.syncNow();
    final t = serverTask(path);
    expect(t.text('SUMMARY'), 'Water the plants');
    expect(t.text('DESCRIPTION'), 'and the herbs');
    expect(t.property('DUE')!.value, '20261002');
    expect(t.property('STATUS')!.value, 'COMPLETED');
  });

  test('deletes go both ways', () async {
    final a = store.add(TodoColumn.todo, title: 'Delete me here')!;
    final b = store.add(TodoColumn.todo, title: 'Delete me there')!;
    await sync.linkTo(tasks);
    final pathA = pathOf(a);
    final pathB = pathOf(b);

    store.delete(a);
    expect(store.tombstones, hasLength(1));
    server.remove(pathB);
    await sync.syncNow();

    expect(server.tasks.containsKey(pathA), isFalse);
    expect(store.item(b), isNull);
    expect(store.tombstones, isEmpty);
  });

  test('a task deleted there after an edit here is sent again', () async {
    final id = store.add(TodoColumn.todo, title: 'Keep me')!;
    await sync.linkTo(tasks);
    final path = pathOf(id);
    server.remove(path);
    final card = store.item(id)!;
    store.update(
      id,
      title: 'Keep me, edited',
      body: card.body,
      column: card.column,
      due: null,
      recurrence: null,
    );
    await sync.syncNow();
    expect(store.item(id)!.title, 'Keep me, edited');
    expect(serverTask(pathOf(id)).text('SUMMARY'), 'Keep me, edited');
  });

  test('both sides changing one field keeps the server and says so', () async {
    final id = store.add(TodoColumn.todo, title: 'Original')!;
    await sync.linkTo(tasks);
    final path = pathOf(id);
    server.edit(
      path,
      server.tasks[path]!.data.replaceFirst(
        'SUMMARY:Original',
        'SUMMARY:Phone title',
      ),
    );
    final card = store.item(id)!;
    store.update(
      id,
      title: 'Board title',
      body: 'board notes',
      column: card.column,
      due: null,
      recurrence: null,
    );
    await sync.syncNow();
    expect(store.item(id)!.title, 'Phone title');
    expect(store.item(id)!.body, 'board notes');
    expect(sync.conflicts.single, contains('title'));
    // The board's other edit still went.
    expect(serverTask(path).text('DESCRIPTION'), 'board notes');
  });

  test('a server that sends no ETag on a write costs one fetch', () async {
    server.sendEtagOnPut = false;
    final id = store.add(TodoColumn.todo, title: 'No etag')!;
    await sync.linkTo(tasks);
    expect(store.item(id)!.remote!.etag, isNull);
    await sync.syncNow();
    expect(store.item(id)!.remote!.etag, isNotNull);
    server.log.clear();
    await sync.syncNow();
    expect(server.log.where((l) => !l.startsWith('PROPFIND')), isEmpty);
  });

  test('meetings from the calendar are never sent', () async {
    store.applyCalendarSync([], day: now);
    final meeting = TodoItem(
      id: 'meet',
      title: 'Standup',
      body: '',
      column: TodoColumn.todo,
      created: now,
      external: TodoExternal(
        source: TodoExternal.googleCalendar,
        key: 'cal/1',
        title: 'Standup',
        start: now,
        end: now.add(const Duration(minutes: 15)),
      ),
    );
    store.applyRemotePull(TodoPull(added: [meeting]));
    await sync.linkTo(tasks);
    expect(server.tasks, isEmpty);
  });

  test('replacing the board keeps a copy of it first', () async {
    store.add(TodoColumn.todo, title: 'Local only');
    server.add('p.ics', otherAppTask('p', 'SUMMARY:On the server\r\n'));
    final kept = await sync.linkTo(tasks, replaceLocal: true);
    expect(kept, isNotNull);
    expect(File(kept!).readAsStringSync(), contains('Local only'));
    expect(store.items.map((i) => i.title), ['On the server']);
    expect(server.tasks, hasLength(1));
  });

  test('a server that is down is said, and the board keeps working', () async {
    await sync.linkTo(tasks);
    server.failWith = 503;
    final id = store.add(TodoColumn.todo, title: 'Offline edit')!;
    expect(await sync.syncNow(), contains('503'));
    expect(store.item(id), isNotNull);
    server.failWith = null;
    expect(await sync.syncNow(), isNull);
    expect(serverTask(pathOf(id)).text('SUMMARY'), 'Offline edit');
  });

  test('signed out, it says where to sign in', () async {
    await sync.linkTo(tasks);
    await accounts.signOutAll();
    expect(await sync.syncNow(), contains('Settings › Accounts'));
  });

  test('unlinking forgets every record and owed delete', () async {
    final id = store.add(TodoColumn.todo, title: 'Linked')!;
    await sync.linkTo(tasks);
    store.delete(store.add(TodoColumn.todo, title: 'Gone')!);
    await sync.unlink();
    expect(store.remoteLink, isNull);
    expect(store.item(id)!.remote, isNull);
    expect(store.tombstones, isEmpty);
  });

  test('the account is kept at 0600, and the old servers file goes', () async {
    final stateDir = '${dir.path}/state2';
    Directory(stateDir).createSync();
    File('$stateDir/todo-backup-servers.json').writeAsStringSync('{}');
    final again = CalDavAccountStore.forTesting(
      directory: stateDir,
      client: server.client,
    );
    await again.removeLegacyBackupServers();
    await again.load();
    expect(File('$stateDir/todo-backup-servers.json').existsSync(), isFalse);
    await again.signIn(
      url: FakeCalDavServer.host,
      username: 'me',
      password: 'secret',
    );
    final mode = File(again.path).statSync().mode & 0x1ff;
    expect(mode, 0x180);

    final reread = CalDavAccountStore.forTesting(directory: stateDir);
    await reread.load();
    expect(reread.accounts.single.username, 'me');
    expect(reread.taskLists.single.url, FakeCalDavServer.tasksUrl);
  });
}
