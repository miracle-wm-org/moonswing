// The `fortune` command, and what comes back out of it.
//
// Follows the [DiskReader]/[FontCatalog] shape: the runner is injectable so tests
// never fork, and the parse is a pure function over stdout so the wrapping rules
// are a plain unit test with no `fortune` installed anywhere near the runner.
//
// Unlike those two a failure here is *reported* rather than swallowed. A fortune
// widget with no fortune in it is a blank card, and the likely reason is that the
// package is not installed — which the user can fix in one command if the card
// says so.

import 'dart:io';

import 'package:graceful_shell/host_process.dart';

/// A fortune that could not be fetched, with a line the card can show.
///
/// [missing] separates "this machine has no `fortune`" — actionable, and by far
/// the common case — from a command that ran and failed, whose own stderr is
/// the more useful thing to print.
class FortuneUnavailable implements Exception {
  const FortuneUnavailable(this.message, {this.missing = false});

  final String message;

  /// Whether no `fortune` binary was found at all.
  final bool missing;

  @override
  String toString() => 'FortuneUnavailable: $message';
}

/// Runs `fortune` and normalizes what it prints.
class FortuneReader {
  FortuneReader({
    Future<ProcessResult> Function(String, List<String>)? runner,
  }) : _run = runner ?? runHostProcess;

  final Future<ProcessResult> Function(String, List<String>) _run;

  /// Where to look for the binary, in order.
  ///
  /// `PATH` first, then the Debian/Ubuntu location explicitly: `fortune-mod`
  /// installs to `/usr/games`, which is on a login shell's `PATH` through
  /// `/etc/profile` but is **not** inherited by a graphical session started from a
  /// display manager — so on the distributions where `fortune` is most likely to
  /// be installed, `Process.run('fortune')` is also most likely to answer ENOENT.
  static const List<String> executableCandidates = [
    'fortune',
    '/usr/games/fortune',
    '/usr/local/bin/fortune',
  ];

  /// Ask for a short one.
  ///
  /// A desktop widget is a card of a few square inches and the cookie files carry
  /// entries running to forty lines; `-s` keeps to the ones under the database's
  /// own short limit. A build that refuses the flag, or a database with no short
  /// entries, is retried without it rather than reported — a long fortune the card
  /// has to shrink to fit still beats no fortune.
  static const List<String> shortArgs = ['-s'];

  /// One fortune, normalized. Throws [FortuneUnavailable] and nothing else.
  Future<String> read() async {
    Object? lastFailure;

    for (final executable in executableCandidates) {
      final ProcessResult result;
      try {
        result = await _run(executable, shortArgs);
      } on ProcessException catch (e) {
        // Not on this path. Try the next one rather than giving up: this is the
        // ENOENT the `/usr/games` note above is about.
        lastFailure = e;
        continue;
      } catch (e) {
        lastFailure = e;
        continue;
      }

      final text = await _resolve(executable, result);
      if (text != null) return text;
      lastFailure = result;
    }

    if (lastFailure is ProcessResult) {
      final stderr = lastFailure.stderr.toString().trim();
      throw FortuneUnavailable(
        stderr.isEmpty ? 'fortune said nothing' : _firstLine(stderr),
      );
    }
    throw const FortuneUnavailable(
      'The fortune command is not installed',
      missing: true,
    );
  }

  /// [result] as text, or null when this candidate has nothing to give.
  ///
  /// The retry without `-s` lives here rather than in the loop so a candidate that
  /// exists is fully exhausted before the next path is tried — the second
  /// candidate is the *same program* at another path.
  Future<String?> _resolve(String executable, ProcessResult result) async {
    final direct = _textOf(result);
    if (direct != null) return direct;

    try {
      return _textOf(await _run(executable, const []));
    } catch (_) {
      // The binary was there a moment ago and is not now, or the fork failed.
      // Either way this candidate is spent.
      return null;
    }
  }

  String? _textOf(ProcessResult result) {
    if (result.exitCode != 0) return null;
    final text = normalizeFortune(result.stdout.toString());
    return text.isEmpty ? null : text;
  }

  static String _firstLine(String text) => text.split('\n').first.trim();
}

/// Unwraps a fortune into paragraphs the card can set at its own width.
///
/// The cookie files are hard-wrapped at about 70 columns, which is wider than
/// this widget is ever drawn — so printing the newlines verbatim gives a ragged
/// left-hand column of half-lines with the card's own wrap happening inside
/// them. Joining every line instead would run a quote into its attribution and
/// flatten verse into prose, so the rule is:
///
/// - A blank line is a paragraph break, and survives as one.
/// - A line that starts with whitespace (indented verse, a table, ASCII art) or
///   with an attribution dash keeps its own break.
/// - Anything else is joined to the line above with a single space.
///
/// The one thing this cannot do well is art whose lines all start at column
/// zero — those get joined. That is a rare shape in the default databases,
/// which are quotations, and the alternative rule loses the far more common
/// wrapped-paragraph case on every single card.
String normalizeFortune(String stdout) {
  final paragraphs = <String>[];
  final current = <String>[];

  void flush() {
    if (current.isEmpty) return;
    paragraphs.add(current.join('\n'));
    current.clear();
  }

  for (final raw in stdout.split('\n')) {
    // Tabs are what the databases indent and align with, and one tab is eight
    // columns of nothing in a proportional font.
    final line = raw.replaceAll('\t', '    ').trimRight();

    if (line.trim().isEmpty) {
      flush();
      continue;
    }

    if (current.isEmpty || _startsNewLine(line)) {
      current.add(line);
    } else {
      current[current.length - 1] = '${current.last} ${line.trim()}';
    }
  }
  flush();

  return paragraphs.join('\n\n');
}

/// Whether [line] is one the wrap must not swallow into the line above it.
bool _startsNewLine(String line) {
  if (line.startsWith(' ')) return true;
  final trimmed = line.trimLeft();
  // `--`, `-- `, an em dash: how every attribution in the databases begins.
  return trimmed.startsWith('--') ||
      trimmed.startsWith('—') ||
      trimmed.startsWith('–');
}
