// Putting an emoji on the clipboard.
//
// Flutter-free apart from the debug logger, so the whole path is a unit test
// with an injected runner and nothing is ever actually forked.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Starts the clipboard helper. Injectable so tests drive the whole copy path
/// without forking anything — `FortuneReader`'s and `PolkitHelperRunner`'s
/// shape.
typedef ClipboardRunner =
    Future<Process> Function(String executable, List<String> arguments);

/// The command that owns the Wayland selection.
///
/// Flutter's own `Clipboard` is not the route here for the reason
/// `capture/capture_grab.dart` documents for screenshots: a Wayland client
/// cannot set the selection without a seat and a serial, and the shell's
/// surfaces are layer-shell ones. `wl-copy` (from `wl-clipboard`) forks a
/// daemon that serves the selection and exits, which is exactly the ownership
/// this has no other way to hold.
const String kClipboardCommand = 'wl-copy';

/// The package to name when [kClipboardCommand] is missing.
///
/// The *package*, never a package manager: it is `wl-clipboard` on Debian,
/// Fedora and Arch alike, and guessing between three managers is how a hint
/// becomes wrong on two distributions out of three — `lib/fortune/`'s rule.
const String kClipboardPackage = 'wl-clipboard';

/// What a copy did, so the caller can say something true about it.
///
/// A missing helper is a *message*, not a silence: the user pressed a key
/// expecting to paste, and the one thing worse than not copying is not
/// copying quietly. `lib/capture/`'s rule about `ffmpeg` and `wl-copy`, which
/// is the same tool.
enum ClipboardResult {
  copied,

  /// No [kClipboardCommand] on the machine.
  unavailable,

  /// It ran and refused.
  failed,
}

/// Puts [text] on the clipboard as UTF-8 plain text.
///
/// The MIME type is spelled with its charset because an emoji is not ASCII and
/// a receiver offered a bare `text/plain` is entitled to read it as Latin-1 —
/// which pastes a smiley as four bytes of mojibake.
Future<ClipboardResult> copyTextToClipboard(
  String text, {
  ClipboardRunner runner = Process.start,
}) async {
  try {
    final process = await runner(kClipboardCommand, const [
      '--type',
      'text/plain;charset=utf-8',
    ]);
    process.stdin.write(text);
    await process.stdin.flush();
    await process.stdin.close();
    // wl-copy forks a daemon to serve the selection and exits, so a non-zero
    // code here is a real refusal rather than the helper still working.
    final code = await process.exitCode;
    if (code != 0) {
      debugPrint('emoji: $kClipboardCommand exited $code');
      return ClipboardResult.failed;
    }
    return ClipboardResult.copied;
  } on ProcessException catch (error) {
    debugPrint('emoji: $kClipboardCommand unavailable: ${error.message}');
    return ClipboardResult.unavailable;
  } catch (error) {
    debugPrint('emoji: $kClipboardCommand failed: $error');
    return ClipboardResult.failed;
  }
}
