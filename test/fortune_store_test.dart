// The fortune store: one fork for the machine, a refresh that cannot stack on
// itself, and a failure that keeps the last fortune on screen.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/fortune/fortune_reader.dart';
import 'package:graceful_shell/fortune/fortune_store.dart';

/// A runner that answers with each of [texts] in turn, counting the calls.
class _Sequence {
  _Sequence(this.texts);

  final List<String> texts;
  int calls = 0;

  Future<ProcessResult> call(String executable, List<String> args) async {
    final text = texts[calls.clamp(0, texts.length - 1)];
    calls++;
    return ProcessResult(0, 0, '$text\n', '');
  }
}

FortuneStore _store(Future<ProcessResult> Function(String, List<String>) run) {
  final store = FortuneStore.forTesting(reader: FortuneReader(runner: run));
  addTearDown(store.dispose);
  return store;
}

void main() {
  group('FortuneStore', () {
    test('the first lease fetches and later ones do not', () async {
      final runner = _Sequence(['One', 'Two']);
      final store = _store(runner.call);

      store.acquire();
      await pumpEventQueue();
      expect(store.text, 'One');
      expect(runner.calls, 1);

      // The second monitor's surface: same fortune, no second fork.
      store.acquire();
      await pumpEventQueue();
      expect(store.text, 'One');
      expect(runner.calls, 1);
      expect(store.leaseCount, 2);
    });

    test('loading is true until the first fortune lands', () async {
      final completer = Completer<ProcessResult>();
      final store = _store((_, _) => completer.future);

      store.acquire();
      expect(store.loading, isTrue);
      expect(store.hasFortune, isFalse);

      completer.complete(ProcessResult(0, 0, 'At last.\n', ''));
      await pumpEventQueue();
      expect(store.loading, isFalse);
      expect(store.text, 'At last.');
    });

    test('a refresh over an existing fortune does not report as loading',
        () async {
      // Replacing the card's whole contents with a spinner for the few
      // milliseconds a fork takes is a flash, not feedback.
      final completer = Completer<ProcessResult>();
      var first = true;
      final store = _store((_, _) {
        if (first) {
          first = false;
          return Future.value(ProcessResult(0, 0, 'One\n', ''));
        }
        return completer.future;
      });

      store.acquire();
      await pumpEventQueue();

      unawaited(store.refresh());
      expect(store.fetching, isTrue);
      expect(store.loading, isFalse);
      expect(store.text, 'One');

      completer.complete(ProcessResult(0, 0, 'Two\n', ''));
      await pumpEventQueue();
      expect(store.text, 'Two');
    });

    test('a refresh arriving mid-flight is dropped, not queued', () async {
      final completer = Completer<ProcessResult>();
      var calls = 0;
      final store = _store((_, _) {
        calls++;
        return completer.future;
      });

      unawaited(store.refresh());
      unawaited(store.refresh());
      unawaited(store.refresh());
      expect(calls, 1);

      completer.complete(ProcessResult(0, 0, 'Only once.\n', ''));
      await pumpEventQueue();
      expect(store.text, 'Only once.');
      expect(calls, 1, reason: 'the two dropped calls never forked');
    });

    test('the revision moves even when the fortune repeats', () async {
      // A small cookie database repeats itself, and the card animates on the
      // revision so the button still reads as having done something.
      final runner = _Sequence(['Same', 'Same']);
      final store = _store(runner.call);

      store.acquire();
      await pumpEventQueue();
      final first = store.revision;

      await store.refresh();
      expect(store.text, 'Same');
      expect(store.revision, first + 1);
    });

    test('notifies its listeners once per fetch', () async {
      final runner = _Sequence(['One', 'Two']);
      final store = _store(runner.call);
      var notifications = 0;
      store.addListener(() => notifications++);

      store.acquire();
      await pumpEventQueue();
      expect(notifications, 1);

      await store.refresh();
      expect(notifications, 2);
    });

    test('a failure keeps the last fortune and records why', () async {
      var succeed = true;
      final store = _store((_, _) async {
        if (succeed) return ProcessResult(0, 0, 'Kept.\n', '');
        throw const ProcessException('fortune', []);
      });

      store.acquire();
      await pumpEventQueue();
      expect(store.text, 'Kept.');

      succeed = false;
      await store.refresh();
      expect(store.text, 'Kept.', reason: 'an old fortune beats a blank card');
      expect(store.error, isNotEmpty);
      expect(store.commandMissing, isTrue);
    });

    test('clears the error once a fortune arrives', () async {
      var succeed = false;
      final store = _store((_, _) async {
        if (succeed) return ProcessResult(0, 0, 'Back.\n', '');
        throw const ProcessException('fortune', []);
      });

      store.acquire();
      await pumpEventQueue();
      expect(store.commandMissing, isTrue);

      succeed = true;
      await store.refresh();
      expect(store.error, isEmpty);
      expect(store.commandMissing, isFalse);
      expect(store.text, 'Back.');
    });

    test('releasing below zero is a no-op', () async {
      final store = _store((_, _) async => ProcessResult(0, 0, 'x\n', ''));

      store.release();
      expect(store.leaseCount, 0);
    });
  });
}
