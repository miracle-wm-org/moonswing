import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/emoji/emoji_clipboard.dart';

/// A `Process` that records what was written to it and answers a set code.
///
/// Enough of the interface for [copyTextToClipboard], which touches `stdin`
/// and `exitCode` and nothing else — the rest throws rather than returning a
/// plausible-looking nothing, so a change that starts reading stdout fails
/// here instead of silently passing.
class _FakeProcess implements Process {
  _FakeProcess(this._code);

  final int _code;
  final _stdin = _RecordingStdin();

  String get written => _stdin.buffer.toString();
  bool get closed => _stdin.closed;

  @override
  IOSink get stdin => _stdin;

  @override
  Future<int> get exitCode async => _code;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      throw UnimplementedError();

  @override
  int get pid => throw UnimplementedError();

  @override
  Stream<List<int>> get stderr => throw UnimplementedError();

  @override
  Stream<List<int>> get stdout => throw UnimplementedError();
}

class _RecordingStdin implements IOSink {
  final buffer = StringBuffer();
  var closed = false;

  @override
  void write(Object? object) => buffer.write(object);

  @override
  Future<void> close() async => closed = true;

  @override
  Future<void> flush() async {}

  @override
  void noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('a successful copy writes the text and reports it landed', () async {
    late final _FakeProcess process;
    late final List<String> arguments;
    final result = await copyTextToClipboard(
      '🍕',
      runner: (executable, args) async {
        expect(executable, kClipboardCommand);
        arguments = args;
        return process = _FakeProcess(0);
      },
    );

    expect(result, ClipboardResult.copied);
    expect(process.written, '🍕');
    // The stream has to be closed, or wl-copy never sees end-of-input and the
    // copy hangs rather than failing.
    expect(process.closed, isTrue);
    // The charset is spelled out: a receiver offered a bare text/plain may
    // read it as Latin-1 and paste a smiley as four bytes of mojibake.
    expect(arguments, contains('text/plain;charset=utf-8'));
  });

  test('a non-zero exit is a refusal, not a success', () async {
    final result = await copyTextToClipboard(
      '🍕',
      runner: (_, _) async => _FakeProcess(1),
    );
    expect(result, ClipboardResult.failed);
  });

  test('a missing helper is reported as unavailable, not as a failure', () {
    // The two are separated because only one of them has an answer the user
    // can act on — installing wl-clipboard.
    expect(
      copyTextToClipboard(
        '🍕',
        runner: (executable, _) =>
            throw ProcessException(executable, const [], 'No such file', 2),
      ),
      completion(ClipboardResult.unavailable),
    );
  });

  test('any other throw is a failure rather than an exception', () {
    // A copy is fired and not awaited by the root, so a throw escaping here
    // would be an unhandled asynchronous error rather than a message.
    expect(
      copyTextToClipboard('🍕', runner: (_, _) => throw StateError('nope')),
      completion(ClipboardResult.failed),
    );
  });

  test('the package named is a package, never a package manager', () {
    // `lib/fortune/`'s rule: it is wl-clipboard on Debian, Fedora and Arch
    // alike, and guessing between three managers is wrong on two of them.
    expect(kClipboardPackage, 'wl-clipboard');
    expect(kClipboardCommand, 'wl-copy');
  });
}
