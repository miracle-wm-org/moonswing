// The state behind the two bar modules: what is being recorded, what the last
// still capture did, and why the last attempt failed.
//
// Singleton `ChangeNotifier`, the shape `OsdStore`/`TrayStore`/`ThemeStore` have.
// The shell renders one panel per monitor, so a recorder module keeping its own
// state would show a stopwatch running on one bar and an idle icon on the other,
// and clicking either would start a *second* recording of the same screen. One
// recording for the machine, one shutter for the machine.
//
// The ticker follows `TimersStore._syncTicker`'s rule: it exists only while
// something is being recorded, so an idle shell wakes for this never.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:miracle/miracle.dart';

import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/screencast/capture_connection.dart';
import 'package:graceful_shell/screencast/capture_host.dart';

import 'capture_config.dart';
import 'capture_grab.dart';
import 'capture_sound.dart';
import 'capture_source.dart';
import 'capture_targets.dart';
import 'recorder.dart';

/// One line the user is told, through the shell's own notification daemon.
class CaptureNotice {
  const CaptureNotice(this.summary, this.body, {this.failed = false});

  final String summary;
  final String body;
  final bool failed;
}

/// How often the recording readout in the bar is re-rendered.
///
/// One second, the resolution the readout shows. Unlike `lib/timers/`, which
/// ticks four times a second, there is only ever one of these and it is started
/// at a known instant, so its own boundary is never more than a few milliseconds
/// late.
const Duration kRecordingTick = Duration(seconds: 1);

class CaptureStore extends ChangeNotifier {
  CaptureStore._();

  static final CaptureStore instance = CaptureStore._();

  /// A store with no singleton behind it, for tests.
  @visibleForTesting
  factory CaptureStore.forTesting() => CaptureStore._();

  ScreenshotConfig _screenshot = const ScreenshotConfig();
  RecorderConfig _recorder = const RecorderConfig();

  ScreenshotConfig get screenshotConfig => _screenshot;
  RecorderConfig get recorderConfig => _recorder;

  /// Where the connection comes from. Injectable so a unit test can answer
  /// null (there is no compositor behind `flutter_test`) and exercise the
  /// unavailable path without the FFI ever being loaded.
  CaptureConnection? Function() connect = CaptureHost.connect;

  /// How the user is told. Injectable for the reason
  /// `TimersStore.onFinished` is: a unit test of this store must not write
  /// into the notification daemon's own list.
  void Function(CaptureNotice notice) notify = postCaptureNotification;

  /// What makes the shutter noise. Injectable for [notify]'s reason: the real
  /// one opens libmpv, which no test may depend on being installed.
  void Function() shutter = playShutterSound;

  /// `$HOME`, resolved once. Injectable so the directory rules are testable
  /// without writing to the machine's real home.
  String home = Platform.environment['HOME'] ?? '';

  /// One `GET_TREE`, or null when the shell is not connected to miracle.
  ///
  /// Wired at start-up from the shell's one `MiracleManager`, which is built
  /// above `runWidget` and cannot be reached from a global shortcut's
  /// callback; injectable for [connect]'s reason, since `flutter_test` has no
  /// compositor behind it either.
  ///
  /// Only `runScreenRecordingShortcut` reads it, and only to answer "which
  /// screen is the user on" without putting a selection surface up. Null is an
  /// answer: the shortcut falls back to asking.
  Future<BaseNode>? Function() readTree = () => null;

  ScreenRecorder? _recording;
  DateTime? _recordingStartedAt;
  CaptureTarget? _recordingTarget;
  Timer? _ticker;
  bool _busy = false;
  bool _stopping = false;
  String? _error;
  String? _lastFile;

  /// True while a still capture is in flight — the shutter is a round trip to
  /// the compositor plus a PNG encode, and the module dims its icon rather
  /// than letting a second click queue a second shot.
  bool get busy => _busy;

  bool get recording => _recording != null;

  /// True from the moment Stop is pressed until the file is closed. ffmpeg
  /// needs a moment to finish the container, and a button that looked idle
  /// during it would invite a second recording on top of the first.
  bool get stopping => _stopping;

  CaptureTarget? get recordingTarget => _recordingTarget;

  /// How long the current recording has been running, or zero.
  Duration get recordingElapsed {
    final started = _recordingStartedAt;
    if (started == null) return Duration.zero;
    final elapsed = DateTime.now().difference(started);
    // A backwards clock step is dropped rather than subtracted — `lib/timers/`
    // states the same rule, and for the same reason: a readout may stall, but
    // it must never run backwards.
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  /// Why the last attempt failed, or null. Cleared when the next one starts.
  String? get error => _error;

  /// The path of the last capture written, for the module's tooltip.
  String? get lastFile => _lastFile;

  void configureScreenshot(ScreenshotConfig config) {
    if (_screenshot == config) return;
    _screenshot = config;
    notifyListeners();
  }

  void configureRecorder(RecorderConfig config) {
    if (_recorder == config) return;
    _recorder = config;
    notifyListeners();
  }

  /// Takes one still capture of [target].
  ///
  /// Never throws: every failure lands in [error] and in a notification,
  /// because this is called from a tap handler and the only useful thing to do
  /// with a broken shutter is say so.
  Future<void> capture(CaptureTarget target) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final connection = _requireConnection();
      // The delay is honoured *before* the grab and after the selection
      // surface has already come down, which is what makes it useful: it is
      // for getting a menu on screen, and a menu opened while the selector was
      // up would have closed it.
      if (_screenshot.delaySeconds > 0) {
        await Future<void>.delayed(Duration(seconds: _screenshot.delaySeconds));
      }
      final directory = resolveCaptureDirectory(
        _screenshot.directory,
        home: home,
        fallback: kDefaultScreenshotDirectory,
      );
      final name = captureFileName(
          _screenshot.filenamePrefix, DateTime.now(), 'png');
      final result = await writeScreenshot(
        connection,
        withToplevelIdentifier(connection, target),
        path: '$directory/$name',
        paintCursors: _screenshot.showCursor,
      );
      _lastFile = result.file.path;

      // Here, and not a line earlier or later. The frame has been taken and the
      // PNG is on the disk, so this is the moment there is a photograph — the
      // clipboard round trip below can take a second and may fail, and a
      // shutter that waited for it would land after the thing it is describing.
      // Fire and forget: `ShutterSoundStore.playNow` catches its own failures
      // and never awaits mpv, which is what keeps a shutter that made no noise
      // from costing the user a screenshot that otherwise worked.
      shutter();

      var body = result.file.path;
      if (_screenshot.copyToClipboard) {
        final copied = await copyPngToClipboard(result.png);
        // Named rather than swallowed: the file is on disk either way, and a
        // user who went to paste it needs to know why they cannot.
        body = copied
            ? '$body — copied to the clipboard'
            : '$body — install wl-clipboard to copy it too';
      }
      notify(CaptureNotice('Screenshot saved', body));
    } on CaptureException catch (error) {
      _fail('Screenshot failed', error.message);
    } catch (error) {
      _fail('Screenshot failed', '$error');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Starts recording [target]. A second call while one is running is ignored
  /// — one recording for the machine.
  Future<void> startRecording(CaptureTarget target) async {
    if (_recording != null || _stopping || _busy) return;
    _busy = true;
    _error = null;
    notifyListeners();

    ScreenRecorder? recorder;
    try {
      final connection = _requireConnection();
      final directory = resolveCaptureDirectory(
        _recorder.directory,
        home: home,
        fallback: kDefaultRecordingDirectory,
      );
      await Directory(directory).create(recursive: true);
      final name = captureFileName(
          _recorder.filenamePrefix, DateTime.now(), _recorder.resolvedContainer);
      recorder = ScreenRecorder(
        connection: connection,
        target: withToplevelIdentifier(connection, target),
        config: _recorder,
        path: '$directory/$name',
      );
      // A source that dies mid-recording — the window closed, the output
      // unplugged — stops the recording and keeps what has been written, which
      // is the only outcome that does not throw away the user's footage.
      recorder.onSourceLost = (reason) => unawaited(stopRecording(
          because: 'The recorded source went away ($reason).'));
      await recorder.start();
      _recording = recorder;
      _recordingTarget = target;
      _recordingStartedAt = recorder.startedAt ?? DateTime.now();
      _syncTicker();
    } on CaptureException catch (error) {
      unawaited(recorder?.dispose());
      _fail('Recording failed', error.message);
    } catch (error) {
      unawaited(recorder?.dispose());
      _fail('Recording failed', '$error');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Stops the current recording and notifies with where the file went.
  ///
  /// [because] is prepended to the notification when the stop was not the
  /// user's — a source that went away — so the file appearing unbidden is
  /// explained.
  Future<void> stopRecording({String? because}) async {
    final recorder = _recording;
    if (recorder == null || _stopping) return;
    _stopping = true;
    _recording = null;
    _syncTicker();
    notifyListeners();
    try {
      final file = await recorder.stop();
      _lastFile = file.path;
      final dropped = recorder.droppedFrames;
      final tail = dropped > 0
          ? ' — $dropped frame(s) dropped: the encoder could not keep up'
          : '';
      notify(CaptureNotice(
        'Recording saved',
        because == null ? '${file.path}$tail' : '$because ${file.path}$tail',
      ));
    } on CaptureException catch (error) {
      _fail('Recording failed', error.message);
    } catch (error) {
      _fail('Recording failed', '$error');
    } finally {
      _stopping = false;
      _recordingTarget = null;
      _recordingStartedAt = null;
      notifyListeners();
    }
  }

  CaptureConnection _requireConnection() {
    final connection = connect();
    if (connection == null) {
      throw const CaptureException(
          'The shell cannot reach the compositor to capture the screen.');
    }
    return connection;
  }

  void _fail(String summary, String message) {
    _error = message;
    notify(CaptureNotice(summary, message, failed: true));
  }

  /// Starts the readout ticker while something is recording and stops it
  /// otherwise, so an idle shell holds no timer for this store at all.
  void _syncTicker() {
    final wanted = _recording != null;
    if (wanted == (_ticker != null)) return;
    if (wanted) {
      _ticker = Timer.periodic(kRecordingTick, (_) => notifyListeners());
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    final recorder = _recording;
    _recording = null;
    unawaited(recorder?.dispose());
    super.dispose();
  }
}

/// Posts one capture outcome to the shell's own notification store.
///
/// A store write rather than a D-Bus round trip, for
/// `postTimerFinishedNotification`'s reason: the shell *is*
/// `org.freedesktop.Notifications`. A success expires on its own after a few
/// seconds; a failure stays until dismissed, because it is the only place the
/// reason is written down.
void postCaptureNotification(CaptureNotice notice) {
  final store = NotificationStore.instance;
  store.addOrReplace(
    NotificationItem(
      id: store.allocateId(),
      appName: 'Graceful Shell',
      summary: notice.summary,
      body: notice.body,
      actions: const [],
      expireTimeout: notice.failed ? 0 : 6000,
      arrivedAt: DateTime.now(),
    ),
  );
}

/// The recording readout: `M:SS`, or `H:MM:SS` past an hour.
///
/// Its own function rather than `formatTimerDuration`'s, which pads the minutes
/// for a countdown aligned to nothing. This one sits in a bar next to a clock,
/// where a leading zero reads as a stopwatch that has not started.
String formatRecordingElapsed(Duration elapsed) {
  final seconds = elapsed.inSeconds;
  final s = (seconds % 60).toString().padLeft(2, '0');
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes % 60}:$s';
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '${minutes ~/ 60}:$m:$s';
}
