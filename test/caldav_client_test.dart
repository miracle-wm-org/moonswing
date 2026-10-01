import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/caldav/caldav_client.dart';

import 'caldav_fakes.dart';

void main() {
  late FakeCalDavServer server;
  late CalDavClient client;

  setUp(() {
    server = FakeCalDavServer();
    client = CalDavClient(
      username: 'me',
      password: 'secret',
      client: server.client,
    );
  });

  group('discovery', () {
    test('from the bare server, through the well-known redirect', () async {
      final lists = await client.discoverTaskLists(
        Uri.parse(FakeCalDavServer.host),
      );
      // The events-only calendar is not a task list.
      expect(lists, [
        CalDavCollection(
          url: FakeCalDavServer.tasksUrl,
          name: 'Home tasks',
          color: '#ff8800',
          components: {'VTODO'},
        ),
      ]);
    });

    test('finds calendars of events as well as task lists', () async {
      final calendars = await client.discoverCalendars(
        Uri.parse(FakeCalDavServer.host),
      );
      expect(calendars.map((c) => (c.name, c.holdsTasks, c.holdsEvents)), [
        ('Home tasks', true, false),
        ('Home calendar', false, true),
      ]);
    });

    test('from the address of the list itself', () async {
      final lists = await client.discoverTaskLists(FakeCalDavServer.tasksUrl);
      expect(lists.single.url, FakeCalDavServer.tasksUrl);
    });

    test('a wrong password says so', () async {
      final wrong = CalDavClient(
        username: 'me',
        password: 'nope',
        client: server.client,
      );
      await expectLater(
        wrong.discoverTaskLists(Uri.parse(FakeCalDavServer.host)),
        throwsA(
          isA<CalDavException>().having(
            (e) => e.message,
            'message',
            contains('refused the user name or password'),
          ),
        ),
      );
    });
  });

  test('the change token moves when anything changes', () async {
    final before = await client.changeToken(FakeCalDavServer.tasksUrl);
    server.add('a.ics', otherAppTask('a', 'SUMMARY:A\r\n'));
    final after = await client.changeToken(FakeCalDavServer.tasksUrl);
    expect(before, isNotNull);
    expect(after, isNot(before));
  });

  test('lists and fetches tasks', () async {
    final a = server.add('a.ics', otherAppTask('a', 'SUMMARY:A\r\n'));
    server.add(
      'event.ics',
      'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:e\r\nEND:VEVENT\r\n'
          'END:VCALENDAR\r\n',
    );
    final listed = await client.listTasks(FakeCalDavServer.tasksUrl);
    expect(listed, [(href: a, etag: server.tasks[a]!.etag)]);
    final fetched = await client.fetch(FakeCalDavServer.tasksUrl, [a]);
    expect(fetched.single.data, contains('SUMMARY:A'));
  });

  test('writes are conditional', () async {
    final url = FakeCalDavServer.tasksUrl.resolve('new.ics');
    final etag = await client.put(url, 'BEGIN:VCALENDAR', create: true);
    expect(etag, isNotNull);
    await expectLater(
      client.put(url, 'again', create: true),
      throwsA(isA<CalDavConflict>()),
    );
    await expectLater(
      client.put(url, 'stale', etag: '"stale"'),
      throwsA(isA<CalDavConflict>()),
    );
    final next = await client.put(url, 'fresh', etag: etag);
    await expectLater(
      client.delete(url, etag: etag),
      throwsA(isA<CalDavConflict>()),
    );
    await client.delete(url, etag: next);
    // Already gone is gone.
    await client.delete(url);
  });

  test('a server that is down is an error, not a crash', () async {
    server.failWith = 503;
    await expectLater(
      client.changeToken(FakeCalDavServer.tasksUrl),
      throwsA(
        isA<CalDavException>().having((e) => e.statusCode, 'status', 503),
      ),
    );
  });

  test('insecure addresses are flagged', () {
    expect(calDavIsInsecure('http://dav.example.com'), isTrue);
    expect(calDavIsInsecure('http://localhost:5232'), isFalse);
    expect(calDavIsInsecure('https://dav.example.com'), isFalse);
    expect(calDavServerUri('ftp://x'), isNull);
  });
}
