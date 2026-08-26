// `[modules.screenshot]` and `[modules.screen_recorder]`, beside the feature
// they configure — the shape `weather/weather_config.dart` and
// `power/power_config.dart` have, and for the same reason: the settings UI and
// the stores both read these, and neither is the module.
//
// Both carry value equality, which is load-bearing rather than tidy:
// `Module.loadAll` pushes a fresh object on every sweep and `ConfigStore`
// notifies on every keystroke anywhere in the settings UI, so the stores
// compare before acting on a change (`WeatherStore.configure`'s rule).

import 'package:graceful_shell/config_reader.dart';

/// Where a still capture goes and what it does on the way.
class ScreenshotConfig {
  const ScreenshotConfig({
    this.directory = '',
    this.filenamePrefix = 'Screenshot',
    this.copyToClipboard = true,
    this.delaySeconds = 0,
    this.showCursor = false,
  });

  /// Empty means [kDefaultScreenshotDirectory] under `$HOME`. A leading `~` is
  /// expanded — this is a hand-edited TOML file, and `~/Pictures` is what a
  /// person writes.
  final String directory;

  final String filenamePrefix;

  /// Whether the PNG is also put on the clipboard, via `wl-copy`. On by
  /// default: pasting the shot straight into a chat window is the common case,
  /// and the file is written either way.
  final bool copyToClipboard;

  /// A pause between the selection surface coming down and the shutter, for
  /// putting a menu on screen first.
  final int delaySeconds;

  /// Whether the pointer is painted into the frame. Off by default: a cursor
  /// frozen in the middle of a screenshot is nearly always an accident, which
  /// is the opposite of the call [RecorderConfig.showCursor] makes.
  final bool showCursor;

  factory ScreenshotConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ScreenshotConfig();
    const defaults = ScreenshotConfig();
    return ScreenshotConfig(
      directory: map.stringOr('directory', defaults.directory),
      filenamePrefix:
          map.stringOr('filename_prefix', defaults.filenamePrefix),
      copyToClipboard:
          map.boolOr('copy_to_clipboard', defaults.copyToClipboard),
      // Capped rather than unbounded: a mistyped 600 is ten minutes of the
      // shell looking like it did nothing.
      delaySeconds:
          map.intOr('delay_seconds', defaults.delaySeconds, min: 0, max: 60),
      showCursor: map.boolOr('show_cursor', defaults.showCursor),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScreenshotConfig &&
      other.directory == directory &&
      other.filenamePrefix == filenamePrefix &&
      other.copyToClipboard == copyToClipboard &&
      other.delaySeconds == delaySeconds &&
      other.showCursor == showCursor;

  @override
  int get hashCode => Object.hash(
      directory, filenamePrefix, copyToClipboard, delaySeconds, showCursor);
}

/// Where a recording goes and how it is encoded.
class RecorderConfig {
  const RecorderConfig({
    this.directory = '',
    this.filenamePrefix = 'Screencast',
    this.fps = 30,
    this.container = 'mp4',
    this.encoder = '',
    this.quality = 23,
    this.showCursor = true,
  });

  final String directory;
  final String filenamePrefix;

  /// The constant rate the recorder writes at. It is *not* the rate the
  /// compositor produces at — `ext-image-copy-capture` delivers a frame only
  /// when the content changes, so a still screen produces none at all and the
  /// recorder repeats the last one to keep the timeline honest.
  final int fps;

  /// `mp4`, `webm` or `mkv`. Anything else falls back to the default rather
  /// than being handed to ffmpeg as a muxer name it may not know.
  final String container;

  /// Empty means [defaultEncoderFor] the container.
  final String encoder;

  /// The encoder's CRF: lower is better and larger.
  final int quality;

  /// Whether the pointer is recorded. On by default, unlike a screenshot's:
  /// a recording is usually of something being *done*, and following the
  /// pointer is most of what makes it followable.
  final bool showCursor;

  /// The container actually used — [container] when it is one this knows.
  String get resolvedContainer =>
      kRecorderContainers.contains(container) ? container : 'mp4';

  /// The encoder actually used.
  String get resolvedEncoder =>
      encoder.isNotEmpty ? encoder : defaultEncoderFor(resolvedContainer);

  factory RecorderConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const RecorderConfig();
    const defaults = RecorderConfig();
    return RecorderConfig(
      directory: map.stringOr('directory', defaults.directory),
      filenamePrefix: map.stringOr('filename_prefix', defaults.filenamePrefix),
      // Floored at 1 and capped at 120: the recorder writes an uncompressed
      // frame per tick, so this is the one key here that can cost a gigabyte a
      // second of pipe traffic.
      fps: map.intOr('fps', defaults.fps, min: 1, max: 120),
      container: map.stringOr('container', defaults.container),
      encoder: map.stringOr('encoder', defaults.encoder),
      quality: map.intOr('quality', defaults.quality, min: 0, max: 51),
      showCursor: map.boolOr('show_cursor', defaults.showCursor),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecorderConfig &&
      other.directory == directory &&
      other.filenamePrefix == filenamePrefix &&
      other.fps == fps &&
      other.container == container &&
      other.encoder == encoder &&
      other.quality == quality &&
      other.showCursor == showCursor;

  @override
  int get hashCode => Object.hash(directory, filenamePrefix, fps, container,
      encoder, quality, showCursor);
}

/// The containers the recorder offers. Ordered as the settings UI shows them.
const List<String> kRecorderContainers = ['mp4', 'webm', 'mkv'];

const String kDefaultScreenshotDirectory = 'Pictures/Screenshots';
const String kDefaultRecordingDirectory = 'Videos/Screencasts';

/// The encoder a container is written with when the user names none.
///
/// WebM cannot carry H.264, so this is a correctness mapping rather than a
/// preference: handing `libx264` to the WebM muxer is an ffmpeg error at
/// start-up, which would read as "recording is broken".
String defaultEncoderFor(String container) =>
    container == 'webm' ? 'libvpx-vp9' : 'libx264';

/// The directory a capture is written to.
///
/// [configured] wins when it names one, with `~` and a leading `$HOME`
/// expanded; otherwise it is [fallback] under [home]. A relative path is taken
/// as relative to [home] rather than to the shell's working directory, which
/// is wherever the session manager happened to start it and is never what
/// somebody typing `Pictures/shots` meant.
String resolveCaptureDirectory(
  String configured, {
  required String home,
  required String fallback,
}) {
  final trimmed = configured.trim();
  if (trimmed.isEmpty) return _join(home, fallback);
  if (trimmed == '~') return home;
  if (trimmed.startsWith('~/')) return _join(home, trimmed.substring(2));
  if (trimmed == r'$HOME') return home;
  if (trimmed.startsWith(r'$HOME/')) return _join(home, trimmed.substring(6));
  if (trimmed.startsWith('/')) return trimmed;
  return _join(home, trimmed);
}

/// The file name one capture is written under: the prefix, then the local date
/// and time, then the extension.
///
/// Seconds are included and the whole thing is sortable, because a burst of
/// three shots a few seconds apart is the normal way this feature is used and
/// `Screenshot (3)` tells the user nothing about which one it is.
String captureFileName(String prefix, DateTime at, String extension) {
  String two(int value) => value.toString().padLeft(2, '0');
  final cleaned = prefix.trim().isEmpty ? 'Capture' : prefix.trim();
  final stamp = '${at.year}-${two(at.month)}-${two(at.day)}'
      '_${two(at.hour)}-${two(at.minute)}-${two(at.second)}';
  return '${cleaned}_$stamp.$extension';
}

String _join(String a, String b) =>
    a.endsWith('/') ? '$a$b' : '$a/$b';
