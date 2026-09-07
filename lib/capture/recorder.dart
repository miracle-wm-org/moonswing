// Screen recording: a capture session on one side, an ffmpeg process on the
// other, and a constant-rate clock in between.
//
// The clock is the whole design. `ext-image-copy-capture` is *event driven* — the
// compositor holds each copy until the content changes — and a video file is the
// opposite, because ffmpeg's rawvideo demuxer has nowhere to put a timestamp.
// Handing it only the frames the compositor produced would render a minute of
// somebody reading a document as a fraction of a second.
//
// So the recorder keeps the newest frame in a canvas and writes it
// [RecorderConfig.fps] times a second whether or not anything moved, working out
// *how many* writes it owes from the wall clock rather than counting its own
// ticks — a late timer would otherwise shorten the recording by however late.
//
// Three more rules:
//
// - **The geometry is pinned at the first frame.** The demuxer is told the frame
//   size once, so a window resized mid-recording is clipped into the canvas it
//   started in. Both dimensions round *down* to even, because `yuv420p` cannot
//   represent an odd one and an area drag very often is.
// - **Writes are copied, pooled, and bounded.** `IOSink.add` does not copy, so
//   handing it the canvas would let the next frame tear the one being written,
//   and a slow encoder would grow the sink's queue without limit. Bounding to
//   [_maxInFlight] turns overload into dropped frames rather than into memory.
// - **A missing ffmpeg is a message, not a silence.** It names the package, never
//   a package manager.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:graceful_shell/host_process.dart';
import 'package:graceful_shell/screencast/capture_connection.dart';
import 'package:graceful_shell/screencast/capture_session.dart';
import 'package:graceful_shell/screencast/screencast_log.dart';

import 'capture_config.dart';
import 'capture_grab.dart' show kGrabTimeout;
import 'capture_source.dart';
import 'capture_targets.dart';
import 'frame_image.dart';

/// How many writes may be outstanding before frames are dropped.
const int _maxInFlight = 3;

/// The most duplicate frames one tick may emit to catch up.
///
/// Without a cap a machine that was suspended mid-recording would come back
/// and try to write minutes of identical frames in one turn of the event loop.
const int _maxCatchUp = 4;

/// How long ffmpeg is given to finish writing the file after its input closes.
const Duration _flushTimeout = Duration(seconds: 20);

/// Records one target to one file.
///
/// Single-use: a stopped recorder is finished, and the store makes a new one.
class ScreenRecorder {
  ScreenRecorder({
    required this.connection,
    required this.target,
    required this.config,
    required this.path,
  });

  final CaptureConnection connection;
  final CaptureTarget target;
  final RecorderConfig config;
  final String path;

  CaptureSession? _session;
  Process? _ffmpeg;
  IOSink? _stdin;
  Timer? _ticker;

  final Completer<void> _firstFrame = Completer<void>();
  final List<Uint8List> _pool = [];
  final StringBuffer _stderr = StringBuffer();

  Uint8List? _canvas;
  CaptureRect? _bufferCrop;
  int _width = 0;
  int _height = 0;
  int _inFlight = 0;
  int _written = 0;
  int _dropped = 0;
  DateTime? _startedAt;
  bool _stopping = false;
  String? _sourceFailure;

  /// When the first frame landed and the clock started, or null before that.
  DateTime? get startedAt => _startedAt;

  /// How many frames were dropped because the encoder could not keep up.
  int get droppedFrames => _dropped;

  /// Fired if the capture source dies while recording — the window was closed,
  /// the output unplugged. The store stops and keeps what has been written.
  void Function(String reason)? onSourceLost;

  /// Opens the source, waits for a frame to learn the geometry from, starts
  /// ffmpeg, and begins writing.
  ///
  /// Throws [CaptureException] if any of that fails; nothing is left running
  /// when it does.
  Future<void> start() async {
    final source = resolveCaptureSource(connection, target,
        paintCursors: config.showCursor);
    try {
      _session = source.open()
        // A block body, not an arrow: `=> _onFrame(...)` followed by a cascade
        // parses as a cascade on `_onFrame`'s own (void) result.
        ..onFrame = (frame) {
          _onFrame(frame, source.crop);
        }
        ..onStopped = _onSourceStopped;
      _session!.start();

      await _firstFrame.future.timeout(
        kGrabTimeout,
        onTimeout: () => throw const CaptureException(
            'The compositor produced no frame to record.'),
      );
      final failure = _sourceFailure;
      if (failure != null) throw CaptureException(failure);

      await _startFfmpeg();
      _startedAt = DateTime.now();
      _ticker = Timer.periodic(
        Duration(microseconds: (1000000 / config.fps).round()),
        (_) => _onTick(),
      );
    } catch (_) {
      await _teardown();
      rethrow;
    }
  }

  /// Stops recording and returns the finished file.
  ///
  /// Throws [CaptureException] when ffmpeg failed — the message carries its
  /// last line of output, which is the only thing that says why.
  Future<File> stop() async {
    if (_stopping) throw const CaptureException('Already stopping.');
    _stopping = true;

    _ticker?.cancel();
    _ticker = null;
    _session?.dispose();
    _session = null;

    final process = _ffmpeg;
    final sink = _stdin;
    _ffmpeg = null;
    _stdin = null;
    _canvas = null;
    _pool.clear();

    if (process == null || sink == null) {
      throw const CaptureException('The recording never started.');
    }

    try {
      await sink.flush();
      await sink.close();
    } catch (_) {
      // A broken pipe here means ffmpeg is already gone; its exit code below
      // is the real answer.
    }

    final code = await process.exitCode.timeout(_flushTimeout, onTimeout: () {
      screencastLog('ffmpeg did not exit; killing it');
      process.kill(ProcessSignal.sigkill);
      return -1;
    });

    if (_dropped > 0) {
      screencastLog('recording dropped $_dropped frame(s): the encoder could '
          'not keep up');
    }

    final file = File(path);
    if (code != 0 || !file.existsSync()) {
      throw CaptureException('ffmpeg failed: ${_lastStderrLine()}');
    }
    return file;
  }

  /// Abandons the recording without waiting for a file — shell teardown.
  Future<void> dispose() => _teardown();

  void _onFrame(CapturedFrame frame, CaptureRect? logicalCrop) {
    if (_stopping) return;
    if (_canvas == null) {
      _negotiatedOrder = byteOrderFor(frame.shmFormat);
      final crop = logicalCrop?.scaledInto(
        target.outputSize,
        frame.width,
        frame.height,
      );
      // Rounded down to even: `yuv420p` subsamples chroma by two, so an odd
      // dimension is not representable and ffmpeg refuses the whole stream.
      final width = ((crop?.width ?? frame.width) ~/ 2) * 2;
      final height = ((crop?.height ?? frame.height) ~/ 2) * 2;
      if (width <= 0 || height <= 0) {
        _sourceFailure = 'The selected area is too small to record.';
        if (!_firstFrame.isCompleted) _firstFrame.complete();
        return;
      }
      _bufferCrop = crop == null
          ? null
          : CaptureRect(crop.x, crop.y, width, height);
      _width = width;
      _height = height;
      _canvas = Uint8List(width * height * 4);
    }
    blitIntoCanvas(frame, _canvas!, _width, _height, crop: _bufferCrop);
    if (!_firstFrame.isCompleted) _firstFrame.complete();
  }

  void _onSourceStopped(String reason) {
    if (!_firstFrame.isCompleted) {
      _sourceFailure = 'The capture stopped: $reason.';
      _firstFrame.complete();
      return;
    }
    _session = null;
    onSourceLost?.call(reason);
  }

  /// Emits however many frames the wall clock says are owed.
  ///
  /// Derived from the elapsed time rather than incremented per tick, the
  /// discipline `lib/timers/` states: a ticker counting its own wakeups would
  /// lose however late each was, and the file would come out shorter than the
  /// thing it recorded.
  void _onTick() {
    final started = _startedAt;
    final canvas = _canvas;
    if (started == null || canvas == null || _stopping) return;

    final elapsed = DateTime.now().difference(started);
    if (elapsed.isNegative) return; // a clock step backwards is dropped
    final owed =
        (elapsed.inMicroseconds * config.fps / 1000000).floor() - _written;
    if (owed <= 0) return;

    final count = owed > _maxCatchUp ? _maxCatchUp : owed;
    for (var i = 0; i < count; i++) {
      if (!_write(canvas)) break;
    }
    // Counted as written even when dropped, so a stall does not leave the
    // recorder permanently behind and writing catch-up bursts for ever.
    _written += count;
  }

  bool _write(Uint8List canvas) {
    final sink = _stdin;
    if (sink == null) return false;
    if (_inFlight >= _maxInFlight) {
      _dropped++;
      return false;
    }
    final buffer = _pool.isNotEmpty ? _pool.removeLast() : Uint8List(canvas.length);
    buffer.setRange(0, canvas.length, canvas);
    _inFlight++;
    try {
      sink.add(buffer);
    } catch (_) {
      _inFlight--;
      return false;
    }
    sink.flush().then((_) => _release(buffer), onError: (_) => _release(buffer));
    return true;
  }

  void _release(Uint8List buffer) {
    _inFlight--;
    if (_pool.length < _maxInFlight) _pool.add(buffer);
  }

  Future<void> _startFfmpeg() async {
    final args = ffmpegArguments(
      config: config,
      width: _width,
      height: _height,
      pixelFormat: _pixelFormat,
      path: path,
    );
    Process process;
    try {
      process = await startHostProcess('ffmpeg', args);
    } on ProcessException {
      throw const CaptureException(
          'Recording needs ffmpeg, which is not installed.');
    }
    _ffmpeg = process;
    _stdin = process.stdin;
    // Bounded: a failing encoder can be very chatty, and the only part of it
    // anybody is shown is the last line.
    process.stderr.transform(utf8.decoder).listen((chunk) {
      if (_stderr.length > 8192) return;
      _stderr.write(chunk);
    }, onError: (_) {});
    // Drained so the pipe cannot fill and block ffmpeg; nothing reads it.
    unawaited(process.stdout.drain<void>().catchError((_) {}));
  }

  /// The `-pix_fmt` name for whatever the session negotiated.
  ///
  /// Read off the canvas's own frames rather than assumed: the session prefers
  /// XRGB, which is BGRA in memory, but a compositor offering only the
  /// byte-swapped variants would produce RGBA and be encoded with its red and
  /// blue channels exchanged.
  String get _pixelFormat => _negotiatedOrder?.ffmpegPixelFormat ?? 'bgra';
  FrameByteOrder? _negotiatedOrder;

  Future<void> _teardown() async {
    _stopping = true;
    _ticker?.cancel();
    _ticker = null;
    _session?.dispose();
    _session = null;
    _canvas = null;
    _pool.clear();
    final sink = _stdin;
    final process = _ffmpeg;
    _stdin = null;
    _ffmpeg = null;
    if (sink != null) {
      try {
        await sink.close();
      } catch (_) {}
    }
    process?.kill();
  }

  String _lastStderrLine() {
    final lines = _stderr
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.isEmpty ? 'no output' : lines.last;
  }
}

/// The ffmpeg command line for one recording.
///
/// A top-level function so it is a plain unit test: the part of this file most
/// likely to be wrong and the only part checkable without a compositor.
/// Per-encoder quality flags rather than one set for all, because `-preset` is an
/// x26x option that VP9 rejects outright and a user-supplied hardware encoder may
/// take neither — so an unrecognised encoder is handed no quality flags rather
/// than flags that would stop it from starting.
List<String> ffmpegArguments({
  required RecorderConfig config,
  required int width,
  required int height,
  required String pixelFormat,
  required String path,
}) {
  final encoder = config.resolvedEncoder;
  final container = config.resolvedContainer;
  return [
    '-hide_banner',
    '-loglevel', 'error',
    '-y',
    '-f', 'rawvideo',
    '-pix_fmt', pixelFormat,
    '-video_size', '${width}x$height',
    '-framerate', '${config.fps}',
    '-i', 'pipe:0',
    '-an',
    '-c:v', encoder,
    ...switch (encoder) {
      'libx264' || 'libx265' => [
          '-preset', 'ultrafast',
          '-crf', '${config.quality}',
          '-pix_fmt', 'yuv420p',
        ],
      'libvpx-vp9' || 'libvpx' => [
          '-crf', '${config.quality}',
          '-b:v', '0',
          '-deadline', 'realtime',
          '-cpu-used', '8',
          '-pix_fmt', 'yuv420p',
        ],
      _ => const <String>[],
    },
    if (container == 'mp4') ...['-movflags', '+faststart'],
    path,
  ];
}
