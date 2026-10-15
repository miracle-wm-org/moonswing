// The clipboard history's way in and out of the Wayland selection: the
// `wl-clipboard` tools.
//
// The shell cannot hold the selection itself — `emoji/emoji_clipboard.dart`
// says why — and it cannot *watch* it from its own surfaces either: a client
// only hears about the selection while one of its surfaces has keyboard focus,
// and the history panel exists precisely to never take it. What can watch is a
// data-control client, which `wl-paste --watch` is (wlr- or ext-data-control,
// whichever the compositor offers). So:
//
// - `wl-paste --watch` runs a command every time the selection changes. The
//   command here is an `echo` of `CLIPBOARD_STATE`, which wl-clipboard sets to
//   `data`, `nil`/`clear`, or `sensitive` for a password manager's copy — so a
//   change costs one small fork, and the content the shell keeps is read only
//   once it has decided it wants it.
//
//   The command is handed the selection on stdin, written by the application
//   that copied it, and it **drains that before answering**. Exiting with the
//   pipe unread would have the copying application's write fail with EPIPE —
//   and one that has not ignored SIGPIPE would be killed by it, for the crime
//   of having copied something while the shell was watching.
// - `wl-paste --list-types` and `wl-paste --type` read what was copied.
// - `wl-copy --type` puts an entry back, as the rest of the shell already does.
//
// Behind [ClipboardBackend] so the store's tests drive every path with nothing
// forked.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:moonswing/emoji/emoji_clipboard.dart'
    show ClipboardResult, ClipboardRunner, kClipboardCommand, kClipboardPackage;
import 'package:moonswing/host_process.dart';

/// The command that reads and watches the selection. Same package as
/// [kClipboardCommand].
const String kClipboardPasteCommand = 'wl-paste';

/// What the selection did, as `wl-paste --watch` reports it.
enum ClipboardChange {
  /// Something was copied.
  data,

  /// The selection was cleared, or its owner went away.
  cleared,

  /// Something was copied that its owner asked not to be remembered.
  sensitive,
}

/// Why the watcher is not running — a state the panel renders, with a retry.
class ClipboardWatchFailure implements Exception {
  const ClipboardWatchFailure(
    this.message, {
    this.missing = false,
    this.unsupported = false,
  });

  final String message;

  /// No [kClipboardPasteCommand] on the machine: the one failure whose fix is
  /// to install something, and the package is named.
  final bool missing;

  /// The compositor offers no data-control protocol, so nothing outside the
  /// focused window can watch the clipboard. A retry will not change this, but
  /// one is offered all the same: the compositor may be restarted under the
  /// shell.
  final bool unsupported;

  @override
  String toString() => message;
}

/// The clipboard, as the history store sees it.
abstract interface class ClipboardBackend {
  /// Every change of the selection, until cancelled. Ends with a
  /// [ClipboardWatchFailure] error if the watcher dies on its own.
  Stream<ClipboardChange> watch();

  /// The types the current selection offers, or null when there is none (or
  /// it could not be asked).
  Future<List<String>?> listTypes();

  /// The selection's content as [mime], or null when it could not be read or
  /// is bigger than [maxBytes] — which is not recorded rather than truncated.
  Future<Uint8List?> read(String mime, {required int maxBytes});

  /// Takes the selection and offers [data] as [mime].
  Future<ClipboardResult> write(String mime, Stream<List<int>> data);
}

/// [ClipboardBackend] over `wl-paste` and `wl-copy`.
class WlClipboardBackend implements ClipboardBackend {
  const WlClipboardBackend({this.runner = startHostProcess});

  /// Starts a process. Injectable, `copyTextToClipboard`'s shape.
  final ClipboardRunner runner;

  /// How long a read may take. The owner of the selection writes the data
  /// itself, and an application that has hung would otherwise hold the
  /// capture — and every capture after it — forever.
  static const Duration readTimeout = Duration(seconds: 10);

  @override
  Stream<ClipboardChange> watch() {
    late final StreamController<ClipboardChange> controller;
    Process? process;
    var cancelled = false;

    Future<void> run() async {
      try {
        process = await runner(kClipboardPasteCommand, const [
          '--watch',
          'sh',
          '-c',
          // An older wl-clipboard sets no CLIPBOARD_STATE; every change it
          // reports is then data, and the type list says whether it is empty.
          r'cat > /dev/null; echo "${CLIPBOARD_STATE:-data}"',
        ]);
      } on ProcessException catch (error) {
        debugPrint('clipboard: $kClipboardPasteCommand unavailable: $error');
        if (!controller.isClosed) {
          controller.addError(
            const ClipboardWatchFailure(
              'The clipboard history needs $kClipboardPasteCommand, from the '
              '$kClipboardPackage package.',
              missing: true,
            ),
          );
          await controller.close();
        }
        return;
      }
      final watcher = process!;
      if (cancelled) {
        watcher.kill();
        return;
      }
      final stderr = StringBuffer();
      final stderrDone = watcher.stderr
          .transform(utf8.decoder)
          .listen(stderr.write)
          .asFuture<void>();
      final stdoutDone = watcher.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (controller.isClosed) return;
            controller.add(switch (line.trim()) {
              'sensitive' => ClipboardChange.sensitive,
              'nil' || 'clear' => ClipboardChange.cleared,
              _ => ClipboardChange.data,
            });
          })
          .asFuture<void>();
      final code = await watcher.exitCode;
      await Future.wait([stdoutDone, stderrDone]).catchError((_) => <void>[]);
      if (cancelled || controller.isClosed) return;
      controller.addError(watchFailureFor(code, stderr.toString()));
      await controller.close();
    }

    controller = StreamController<ClipboardChange>(
      onListen: () => unawaited(run()),
      onCancel: () {
        cancelled = true;
        process?.kill();
      },
    );
    return controller.stream;
  }

  @override
  Future<List<String>?> listTypes() async {
    try {
      final process = await runner(kClipboardPasteCommand, const [
        '--list-types',
      ]);
      unawaited(process.stdin.close());
      final out = process.stdout.transform(utf8.decoder).join();
      final err = process.stderr.drain<void>();
      final code = await process.exitCode.timeout(
        readTimeout,
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      final text = await out;
      await err;
      // Non-zero is "Nothing is copied", which is not an error worth a word.
      if (code != 0) return null;
      return const LineSplitter()
          .convert(text)
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } on ProcessException {
      return null;
    } catch (error) {
      debugPrint('clipboard: listing types failed: $error');
      return null;
    }
  }

  @override
  Future<Uint8List?> read(String mime, {required int maxBytes}) async {
    try {
      final process = await runner(kClipboardPasteCommand, [
        '--no-newline',
        '--type',
        mime,
      ]);
      unawaited(process.stdin.close());
      unawaited(process.stderr.drain<void>());
      final builder = BytesBuilder(copy: false);
      var tooBig = false;
      final done = Completer<void>();
      late final StreamSubscription<List<int>> sub;
      sub = process.stdout.listen(
        (chunk) {
          if (tooBig) return;
          if (builder.length + chunk.length > maxBytes) {
            tooBig = true;
            process.kill();
            return;
          }
          builder.add(chunk);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      final code = await process.exitCode.timeout(
        readTimeout,
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      await done.future.timeout(readTimeout, onTimeout: () => sub.cancel());
      if (tooBig) {
        debugPrint(
          'clipboard: $mime is over ${maxBytes ~/ 1024} KiB, not kept',
        );
        return null;
      }
      if (code != 0) return null;
      return builder.takeBytes();
    } on ProcessException {
      return null;
    } catch (error) {
      debugPrint('clipboard: reading $mime failed: $error');
      return null;
    }
  }

  @override
  Future<ClipboardResult> write(String mime, Stream<List<int>> data) async {
    try {
      final process = await runner(kClipboardCommand, ['--type', mime]);
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      await process.stdin.addStream(data);
      await process.stdin.flush();
      await process.stdin.close();
      // wl-copy forks a daemon to serve the selection and exits, so a non-zero
      // code is a refusal rather than the helper still working.
      final code = await process.exitCode;
      if (code != 0) {
        debugPrint('clipboard: $kClipboardCommand exited $code');
        return ClipboardResult.failed;
      }
      return ClipboardResult.copied;
    } on ProcessException catch (error) {
      debugPrint('clipboard: $kClipboardCommand unavailable: ${error.message}');
      return ClipboardResult.unavailable;
    } catch (error) {
      debugPrint('clipboard: $kClipboardCommand failed: $error');
      return ClipboardResult.failed;
    }
  }
}

/// What a watcher that exited with [code] and printed [stderr] is reported as.
@visibleForTesting
ClipboardWatchFailure watchFailureFor(int code, String stderr) {
  final said = stderr.trim();
  final lower = said.toLowerCase();
  // wl-clipboard's own words when the compositor has no data-control manager:
  // "Watch mode requires a compositor that supports the wlroots data-control
  // protocol" (and, in newer releases, ext-data-control).
  if (lower.contains('data-control') || lower.contains('watch mode requires')) {
    return const ClipboardWatchFailure(
      'This compositor does not let the shell watch the clipboard: it offers '
      'neither the wlr- nor the ext-data-control protocol.',
      unsupported: true,
    );
  }
  final line = said.split('\n').where((l) => l.trim().isNotEmpty).lastOrNull;
  return ClipboardWatchFailure(
    line == null
        ? 'The clipboard watcher stopped (exit code $code).'
        : 'The clipboard watcher stopped: $line',
  );
}
