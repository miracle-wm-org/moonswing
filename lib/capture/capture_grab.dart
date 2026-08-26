// One frame, out of the compositor and onto the disk.
//
// A screenshot is a capture session that is torn down after its first ready
// frame, which is the whole of the difference between this and the recorder.
// The session is *always* disposed — on the frame, on a stop, and on the
// timeout — because an abandoned one keeps asking the compositor to copy the
// screen into a buffer nobody reads.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:graceful_shell/screencast/capture_connection.dart';
import 'package:graceful_shell/screencast/capture_session.dart';
import 'package:graceful_shell/screencast/screencast_log.dart';

import 'capture_source.dart';
import 'capture_targets.dart';
import 'frame_image.dart';

/// How long a source has to produce its first frame before the attempt is
/// given up on.
///
/// The compositor answers a fresh session's first capture immediately — it
/// only *withholds* frames once it has one it has already sent and the content
/// has not changed — so this is a stuck-source guard rather than a budget.
const Duration kGrabTimeout = Duration(seconds: 5);

/// Grabs one frame of [target] and returns it, cropped.
///
/// Throws a [CaptureException] with a sentence worth showing when the source
/// cannot be opened, dies, or never produces a frame.
Future<FrameBytes> grabFrame(
  CaptureConnection connection,
  CaptureTarget target, {
  required bool paintCursors,
  Duration timeout = kGrabTimeout,
}) async {
  final source =
      resolveCaptureSource(connection, target, paintCursors: paintCursors);
  final completer = Completer<FrameBytes>();
  CaptureSession? session;
  Timer? deadline;

  void finish(void Function() body) {
    deadline?.cancel();
    deadline = null;
    session?.dispose();
    session = null;
    body();
  }

  session = source.open()
    ..onFrame = (frame) {
      if (completer.isCompleted) return;
      // Copied out synchronously: `frame.data` points into the session's shm
      // mapping and the next capture overwrites it, and this session is about
      // to be destroyed besides.
      final bytes = copyFrame(
        frame,
        crop: source.crop?.scaledInto(
          target.outputSize,
          frame.width,
          frame.height,
        ),
        opaque: true,
      );
      finish(() => completer.complete(bytes));
    }
    ..onStopped = (reason) {
      if (completer.isCompleted) return;
      finish(() => completer.completeError(
          CaptureException('The capture stopped: $reason.')));
    };

  deadline = Timer(timeout, () {
    if (completer.isCompleted) return;
    finish(() => completer.completeError(const CaptureException(
        'The compositor produced no frame to capture.')));
  });

  session!.start();
  return completer.future;
}

/// Grabs [target], encodes it, and writes it to [path].
///
/// Returns the file *and* the encoded bytes, because the clipboard wants the
/// same PNG and re-reading it off the disk to get it would be a second encode
/// or a second read for nothing.
///
/// Throws [CaptureException] for everything the user could act on — a source
/// that went away, an encode the engine refused, a directory that cannot be
/// written to.
Future<({File file, Uint8List png})> writeScreenshot(
  CaptureConnection connection,
  CaptureTarget target, {
  required String path,
  required bool paintCursors,
}) async {
  final bytes = await grabFrame(connection, target, paintCursors: paintCursors);
  final png = await encodePng(bytes);
  if (png == null) {
    throw const CaptureException('The captured frame could not be encoded.');
  }
  final file = File(path);
  try {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png, flush: true);
  } on FileSystemException catch (error) {
    throw CaptureException(
        'Could not write ${file.path}: ${error.osError?.message ?? error.message}.');
  }
  return (file: file, png: png);
}

/// Puts [png] on the clipboard through `wl-copy`, answering whether it landed.
///
/// Flutter's own `Clipboard` carries text and nothing else, and Wayland has no
/// clipboard a client can write to without a seat, so an external helper is
/// the only route. A missing `wl-copy` is reported rather than swallowed: the
/// file has still been written, and the user who expected to paste it needs to
/// know why they cannot.
Future<bool> copyPngToClipboard(Uint8List png) async {
  try {
    final process = await Process.start('wl-copy', const ['--type', 'image/png']);
    process.stdin.add(png);
    await process.stdin.flush();
    await process.stdin.close();
    // wl-copy forks a daemon to serve the selection and exits; a non-zero code
    // here is a real refusal.
    final code = await process.exitCode;
    if (code != 0) {
      screencastLog('wl-copy exited $code');
      return false;
    }
    return true;
  } catch (error) {
    screencastLog('wl-copy unavailable: $error');
    return false;
  }
}
