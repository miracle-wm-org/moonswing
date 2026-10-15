// The clipboard history store over a fake clipboard: what the leases start and
// stop, what a change records, how duplicates and the limit are handled, what
// survives a restart, and the failures it renders.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/clipboard/clipboard_config.dart';
import 'package:moonswing/clipboard/clipboard_entry.dart';
import 'package:moonswing/clipboard/clipboard_store.dart';
import 'package:moonswing/clipboard/wl_clipboard.dart';
import 'package:moonswing/emoji/emoji_clipboard.dart' show ClipboardResult;

import 'clipboard_fakes.dart';

void main() {
  late Directory dir;
  late FakeClipboard clipboard;
  var tick = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('clipboard_store');
    clipboard = FakeClipboard();
    tick = 0;
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ClipboardHistoryStore makeStore({ClipboardConfig? config}) {
    final store = ClipboardHistoryStore.forTesting(
      backend: clipboard,
      directory: '${dir.path}/clipboard',
      // A minute per read, so every entry has its own time.
      clock: () => DateTime(2026, 10, 15, 9).add(Duration(minutes: tick++)),
    );
    if (config != null) store.configure(config);
    addTearDown(store.dispose);
    return store;
  }

  Future<void> copyText(String text) async {
    clipboard.offer({'text/plain;charset=utf-8': text, 'TEXT': text});
    clipboard.emit();
    await settle();
  }

  test(
    'the first lease starts the watcher and the last one stops it',
    () async {
      final store = makeStore();
      var notified = 0;
      store.addListener(() => notified++);

      store.acquire();
      expect(notified, 0, reason: 'acquire runs inside initState');
      await settle();
      expect(clipboard.watching, isTrue);
      expect(store.loaded, isTrue);

      store.acquire();
      await settle();
      expect(clipboard.watches, 1, reason: 'one watcher however many leases');

      store.release();
      expect(clipboard.watching, isTrue);
      store.release();
      await settle();
      expect(clipboard.watching, isFalse);
    },
  );

  test('records text, newest first, and a repeat moves to the top', () async {
    final store = makeStore();
    store.acquire();
    await settle();

    await copyText('first');
    await copyText('second');
    expect(store.entries.map((e) => e.text), ['second', 'first']);
    expect(store.entries.first.mime, kClipboardTextMime);

    await copyText('first');
    expect(store.entries.map((e) => e.text), ['first', 'second']);
    expect(store.entries, hasLength(2));
  });

  test('ignores a cleared selection, blank text and a secret', () async {
    final store = makeStore();
    store.acquire();
    await settle();

    await copyText('kept');
    clipboard.emit(ClipboardChange.cleared);
    await settle();
    await copyText('   \n');
    clipboard.offer({'text/plain': 'hunter2', kSecretClipboardHint: 'secret'});
    clipboard.emit();
    await settle();
    clipboard.offer({'text/plain': 'hunter2'});
    clipboard.emit(ClipboardChange.sensitive);
    await settle();

    expect(store.entries.map((e) => e.text), ['kept']);
  });

  test('keeps a picture as a file, and copied files as their paths', () async {
    final store = makeStore();
    store.acquire();
    await settle();

    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    clipboard.offer({'image/png': png, 'text/html': '<img>'});
    clipboard.emit();
    await settle();
    clipboard.offer({
      'text/uri-list': 'file:///home/me/clip.mp4\r\n',
      'text/plain': '/home/me/clip.mp4',
    });
    clipboard.emit();
    await settle();

    final [files, image] = store.entries;
    expect(files.kind, ClipboardKind.files);
    expect(files.paths, ['/home/me/clip.mp4']);
    expect(image.kind, ClipboardKind.image);
    expect(image.size, png.length);
    expect(await File(store.payloadPath(image)!).readAsBytes(), png);
  });

  test('a uri-list of web links is text', () async {
    final store = makeStore();
    store.acquire();
    await settle();
    clipboard.offer({'text/uri-list': 'https://example.com/\r\n'});
    clipboard.emit();
    await settle();
    expect(store.entries.single.kind, ClipboardKind.text);
    expect(store.entries.single.text, 'https://example.com/');
  });

  test('anything over max_item_mb is not recorded', () async {
    final store = makeStore(config: const ClipboardConfig(maxItemMb: 1));
    store.acquire();
    await settle();
    clipboard.offer({'image/png': Uint8List(1024 * 1024 + 1)});
    clipboard.emit();
    await settle();
    expect(store.entries, isEmpty);
  });

  test('trims the oldest past max_entries, never a pinned one', () async {
    final store = makeStore(config: const ClipboardConfig(maxEntries: 2));
    store.acquire();
    await settle();

    await copyText('a');
    store.togglePin(store.entries.single);
    await copyText('b');
    await copyText('c');
    await copyText('d');
    expect(store.entries.map((e) => e.text), ['d', 'c', 'a']);
    expect(store.entries.last.pinned, isTrue);

    store.clear();
    expect(store.entries.map((e) => e.text), ['a'], reason: 'Clear keeps pins');
  });

  test('removing a picture deletes its file', () async {
    final store = makeStore();
    store.acquire();
    await settle();
    clipboard.offer({
      'image/png': Uint8List.fromList([1, 2, 3]),
    });
    clipboard.emit();
    await settle();
    final path = store.payloadPath(store.entries.single)!;
    expect(File(path).existsSync(), isTrue);

    store.remove(store.entries.single);
    await settle();
    expect(store.entries, isEmpty);
    expect(File(path).existsSync(), isFalse);
  });

  test('copy puts an entry back as its own type and moves it up', () async {
    final store = makeStore();
    store.acquire();
    await settle();
    await copyText('older');
    clipboard.offer({
      'image/png': Uint8List.fromList([9, 9, 9]),
    });
    clipboard.emit();
    await settle();
    await copyText('newest');

    final image = store.entries[1];
    expect(await store.copy(image), ClipboardResult.copied);
    expect(clipboard.written.last.$1, 'image/png');
    expect(clipboard.written.last.$2, [9, 9, 9]);
    expect(store.entries.first.id, image.id);
    expect(store.justCopied.value, image.id);

    final text = store.entries.firstWhere((e) => e.text == 'older');
    await store.copy(text);
    expect(clipboard.written.last.$1, kClipboardTextMime);
    expect(utf8.decode(clipboard.written.last.$2), 'older');

    // The watcher then reports the shell's own copy: one entry, not two.
    clipboard.offer({kClipboardTextMime: 'older'});
    clipboard.emit();
    await settle();
    expect(store.entries.where((e) => e.text == 'older'), hasLength(1));
  });

  test('a copy that fails says so', () async {
    final store = makeStore();
    store.acquire();
    await settle();
    await copyText('x');
    clipboard.writeResult = ClipboardResult.unavailable;
    await store.copy(store.entries.single);
    expect(store.copyError, contains('wl-clipboard'));
    store.dismissCopyError();
    expect(store.copyError, isNull);
  });

  test('a dead watcher is a visible state, and Retry starts another', () async {
    final store = makeStore();
    store.acquire();
    await settle();
    clipboard.fail(
      const ClipboardWatchFailure('no data-control', unsupported: true),
    );
    await settle();
    expect(store.error, 'no data-control');
    expect(store.unsupported, isTrue);

    store.retry();
    await settle();
    expect(store.error, isNull);
    expect(clipboard.watches, 2);
    expect(clipboard.watching, isTrue);
  });

  test('the history survives a restart', () async {
    final first = makeStore();
    first.acquire();
    await settle();
    await copyText('remember me');
    clipboard.offer({
      'image/png': Uint8List.fromList([4, 5, 6]),
    });
    clipboard.emit();
    await settle();
    first.togglePin(first.entries.last);
    await first.flush();

    final second = makeStore();
    await second.ready;
    expect(second.entries.map((e) => e.kind), [
      ClipboardKind.image,
      ClipboardKind.text,
    ]);
    expect(second.entries.last.text, 'remember me');
    expect(second.entries.last.pinned, isTrue);
  });

  test(
    'a lost picture or a corrupt index costs entries, not the history',
    () async {
      final first = makeStore();
      first.acquire();
      await settle();
      await copyText('text survives');
      clipboard.offer({
        'image/png': Uint8List.fromList([1]),
      });
      clipboard.emit();
      await settle();
      await first.flush();
      await File(first.payloadPath(first.entries.first)!).delete();
      // A stray file nothing names is swept.
      final stray = File('${dir.path}/clipboard/stray');
      await stray.writeAsString('x');

      final second = makeStore();
      await second.ready;
      expect(second.entries.single.text, 'text survives');
      expect(stray.existsSync(), isFalse);

      await File(
        '${dir.path}/clipboard/history.json',
      ).writeAsString('{not json');
      final third = makeStore();
      await third.ready;
      expect(third.entries, isEmpty);
    },
  );

  test('persist = false starts empty and leaves no index', () async {
    final first = makeStore();
    first.acquire();
    await settle();
    await copyText('yesterday');
    await first.flush();
    expect(File('${dir.path}/clipboard/history.json').existsSync(), isTrue);

    final second = makeStore(config: const ClipboardConfig(persist: false));
    second.acquire();
    await settle();
    expect(second.entries, isEmpty);
    await copyText('today');
    await second.flush();
    expect(File('${dir.path}/clipboard/history.json').existsSync(), isFalse);
  });

  test('turning persist off deletes the saved index at once', () async {
    final store = makeStore();
    store.acquire();
    await settle();
    await copyText('x');
    await store.flush();
    final index = File('${dir.path}/clipboard/history.json');
    expect(index.existsSync(), isTrue);

    store.configure(const ClipboardConfig(persist: false));
    await settle();
    expect(index.existsSync(), isFalse);
    expect(store.entries, hasLength(1), reason: 'the session keeps its list');
  });
}
