// The `fortune` command: which binary is asked, what happens when there is
// none, and how the databases' 70-column wrapping is undone.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/fortune/fortune_reader.dart';

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');
ProcessResult _failed(String stderr) => ProcessResult(0, 1, '', stderr);

/// A runner that records what it was asked to run.
class _Runner {
  _Runner(this._answer);

  final ProcessResult Function(String executable, List<String> args) _answer;
  final List<(String, List<String>)> calls = [];

  Future<ProcessResult> call(String executable, List<String> args) async {
    calls.add((executable, args));
    return _answer(executable, args);
  }
}

void main() {
  group('normalizeFortune', () {
    test('unwraps a paragraph the database hard-wrapped', () {
      // What a cookie file actually contains: one sentence broken at column 70.
      final text = normalizeFortune(
        'You will be surprised by a visitor who arrives\n'
        'before you have finished reading this.\n',
      );

      expect(
        text,
        'You will be surprised by a visitor who arrives '
        'before you have finished reading this.',
      );
    });

    test('keeps a blank line as a paragraph break', () {
      final text = normalizeFortune('First one.\n\nSecond one.\n');

      expect(text, 'First one.\n\nSecond one.');
    });

    test('gives an attribution its own line', () {
      final text = normalizeFortune(
        'The future is already here.\n'
        '-- William Gibson\n',
      );

      expect(text, 'The future is already here.\n-- William Gibson');
    });

    test('keeps an indented line rather than folding it into the one above',
        () {
      final text = normalizeFortune('Roses are red\n  violets are blue\n');

      expect(text, 'Roses are red\n  violets are blue');
    });

    test('turns tabs into spaces', () {
      // One tab is eight columns of nothing in a proportional font.
      final text = normalizeFortune('Quote\n\tAttribution\n');

      expect(text, 'Quote\n    Attribution');
    });

    test('drops leading and trailing blank lines and trailing spaces', () {
      final text = normalizeFortune('\n\nA fortune.   \n\n\n');

      expect(text, 'A fortune.');
    });

    test('is empty for empty output', () {
      expect(normalizeFortune(''), isEmpty);
      expect(normalizeFortune('\n \n'), isEmpty);
    });
  });

  group('FortuneReader', () {
    test('asks for a short fortune first', () async {
      final runner = _Runner((_, _) => _ok('Short and sweet.\n'));

      final text = await FortuneReader(runner: runner.call).read();

      expect(text, 'Short and sweet.');
      expect(runner.calls, [('fortune', FortuneReader.shortArgs)]);
    });

    test('falls back to /usr/games when fortune is not on PATH', () async {
      // The Debian/Ubuntu case: `fortune-mod` installs to /usr/games, which a
      // graphical session does not inherit on its PATH.
      final runner = _Runner((executable, _) {
        if (executable == 'fortune') throw const ProcessException('fortune', []);
        return _ok('Found anyway.\n');
      });

      expect(await FortuneReader(runner: runner.call).read(), 'Found anyway.');
      expect(
        runner.calls.map((c) => c.$1),
        ['fortune', '/usr/games/fortune'],
      );
    });

    test('retries the same binary without -s before moving on', () async {
      final runner = _Runner((_, args) =>
          args.isEmpty ? _ok('A long one.\n') : _failed('no short fortunes'));

      expect(await FortuneReader(runner: runner.call).read(), 'A long one.');
      expect(runner.calls, [
        ('fortune', FortuneReader.shortArgs),
        ('fortune', const <String>[]),
      ]);
    });

    test('retries when the command succeeds but prints nothing', () async {
      final runner = _Runner((_, args) => args.isEmpty ? _ok('Here.\n') : _ok(''));

      expect(await FortuneReader(runner: runner.call).read(), 'Here.');
    });

    test('reports a missing command as missing', () async {
      final runner = _Runner((_, _) => throw const ProcessException('x', []));

      await expectLater(
        FortuneReader(runner: runner.call).read(),
        throwsA(isA<FortuneUnavailable>()
            .having((e) => e.missing, 'missing', isTrue)),
      );
      // Every candidate was tried before giving up.
      expect(
        runner.calls.map((c) => c.$1),
        FortuneReader.executableCandidates,
      );
    });

    test('reports a command that ran and failed with its own first line',
        () async {
      final runner = _Runner(
        (_, _) => _failed('fortune: no fortune found\nand a second line'),
      );

      await expectLater(
        FortuneReader(runner: runner.call).read(),
        throwsA(isA<FortuneUnavailable>()
            .having((e) => e.message, 'message', 'fortune: no fortune found')
            .having((e) => e.missing, 'missing', isFalse)),
      );
    });
  });
}
