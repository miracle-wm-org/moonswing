import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/app_info.dart';
import 'package:moonswing/launcher/app_index.dart';

/// [AppIndex] builds its list off the UI isolate, so a list now *lands* some
/// time after it was asked for — and in that gap an install can be reported,
/// or the launcher can be holding pointers into the current list. Pinned here:
/// a stale walk is never shown, a list is never swapped in under a reader, every
/// list is unref'd exactly once, and only the first walk's failure is the
/// start-up task's.

AppEntry _app(String name, int address) => AppEntry(
      id: name.toLowerCase(),
      name: name,
      iconName: '',
      categories: const [],
      appInfo: ffi.Pointer.fromAddress(address),
    );

List<String> _names(Iterable<AppEntry> apps) => [for (final a in apps) a.name];

void main() {
  late List<Completer<List<AppEntry>>> walks;
  late List<List<String>> disposed;
  late int notifications;
  late AppIndex index;

  setUp(() {
    walks = [];
    disposed = [];
    notifications = 0;
    index = AppIndex.forTesting(
      load: () {
        final walk = Completer<List<AppEntry>>();
        walks.add(walk);
        return walk.future;
      },
      dispose: (apps) {
        if (apps.isNotEmpty) disposed.add(_names(apps));
      },
    )..addListener(() => notifications++);
  });

  test('the first list lands with a notification, and start waits for it',
      () async {
    var started = false;
    final start = index.start().then((_) => started = true);
    await Future<void>.delayed(Duration.zero);
    expect(started, isFalse);
    expect(index.apps, isEmpty);

    walks.single.complete([_app('Files', 1)]);
    await start;
    expect(_names(index.apps), ['Files']);
    expect(_names(index.searchable.map((s) => s.entry)), ['Files']);
    expect(notifications, 1);

    // Started once: a second call walks nothing.
    await index.start();
    expect(walks, hasLength(1));
  });

  test('a change reported mid-walk throws that walk away and walks again',
      () async {
    final start = index.start();
    index.applicationsChanged();
    walks.single.complete([_app('Old', 1)]);
    await Future<void>.delayed(Duration.zero);
    expect(walks, hasLength(2));
    expect(index.apps, isEmpty, reason: 'the stale list is never shown');
    expect(disposed, [
      ['Old'],
    ]);

    walks.last.complete([_app('New', 2)]);
    await start;
    expect(_names(index.apps), ['New']);
    expect(notifications, 1);
  });

  test('a list landing while the launcher reads is held until release',
      () async {
    final start = index.start();
    walks.single.complete([_app('Files', 1)]);
    await start;

    index.acquire();
    index.applicationsChanged();
    walks.last.complete([_app('Files', 1), _app('Terminal', 2)]);
    await Future<void>.delayed(Duration.zero);
    expect(_names(index.apps), ['Files'], reason: 'rows still point here');
    expect(disposed, isEmpty);

    // A second list while still held replaces the parked one.
    index.applicationsChanged();
    walks.last.complete([_app('Terminal', 3)]);
    await Future<void>.delayed(Duration.zero);
    expect(disposed, [
      ['Files', 'Terminal'],
    ]);

    index.release();
    expect(_names(index.apps), ['Terminal']);
    expect(disposed.last, ['Files'], reason: 'the old list, once let go');
    expect(notifications, 2);
  });

  test('a first walk that fails fails the start-up task', () async {
    final start = index.start();
    walks.single.completeError(StateError('no GIO'));
    await expectLater(start, throwsStateError);
    expect(notifications, 0);
  });

  test('a later walk that fails keeps the last good list', () async {
    final start = index.start();
    walks.single.complete([_app('Files', 1)]);
    await start;

    index.applicationsChanged();
    walks.last.completeError(StateError('gone'));
    await Future<void>.delayed(Duration.zero);
    expect(_names(index.apps), ['Files']);
    expect(disposed, isEmpty);
  });
}
