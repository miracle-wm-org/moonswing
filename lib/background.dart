import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'config.dart';
import 'media_paths.dart';

// [isVideoPath] was defined here before the predicates moved to
// `lib/media_paths.dart`, and its importers still reach it through this file;
// `config.dart` re-exports the rest of that library, as it always provided it.
export 'media_paths.dart' show isVideoPath;

BoxFit boxFitFor(BackgroundFit fit) {
  switch (fit) {
    case BackgroundFit.fill:
      return BoxFit.cover;
    case BackgroundFit.contain:
      return BoxFit.contain;
    case BackgroundFit.natural:
      return BoxFit.none;
  }
}

/// Renders a wallpaper from a filesystem path, picking the image or video
/// renderer from the extension.
///
/// Shared by the desktop background and the lock screen; both want the same
/// muted, looping, no-controls video behaviour and the same graceful fallback
/// when a file is missing or undecodable.
class MediaBackground extends StatelessWidget {
  const MediaBackground({super.key, required this.path, required this.fit});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (isVideoPath(path)) {
      return _VideoBackground(path: path, fit: fit);
    }
    return _ImageBackground(path: path, fit: fit);
  }
}

/// The entries eligible to be shown: flagged `shown`, a valid image extension,
/// and present on disk. This is the pool the rotation cycles through, in
/// configuration (presentation) order.
List<BackgroundEntry> shownEntries(BackgroundConfig config) {
  return config.entries
      .where((e) =>
          e.shown && isImagePath(e.path) && File(e.path).existsSync())
      .toList();
}

class BackgroundWindow extends StatefulWidget {
  const BackgroundWindow({super.key, required this.config});

  final BackgroundConfig config;

  @override
  State<BackgroundWindow> createState() => _BackgroundWindowState();
}

class _BackgroundWindowState extends State<BackgroundWindow> {
  List<BackgroundEntry> _entries = const [];
  int _index = 0;
  Timer? _timer;

  /// The interval the running [_timer] was built with, so [_sameRotation] can
  /// tell a real interval edit from an unrelated config write.
  int _intervalMinutes = 0;

  @override
  void initState() {
    super.initState();
    _entries = shownEntries(widget.config);
    _restartTimer();
  }

  @override
  void didUpdateWidget(BackgroundWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = shownEntries(widget.config);

    // Every ConfigStore write rebuilds the whole shell, and this widget sees a
    // new (equal) BackgroundConfig each time. Restarting the timer on all of
    // them would reset the rotation clock on every unrelated edit — dragging a
    // desktop icon around would mean the wallpaper never advanced at all.
    if (_sameRotation(next, widget.config)) return;

    // Keep pointing at the same wallpaper across edits when it's still shown,
    // otherwise clamp back into range.
    final currentPath = _currentPath;
    final nextIndex =
        currentPath == null ? 0 : next.indexWhere((e) => e.path == currentPath);
    setState(() {
      _entries = next;
      _index = nextIndex >= 0 ? nextIndex : 0;
    });
    _restartTimer();
  }

  /// Whether [next] and [config] would produce the timer and image sequence
  /// already running — i.e. nothing about the rotation actually changed.
  bool _sameRotation(List<BackgroundEntry> next, BackgroundConfig config) {
    if (config.intervalMinutes != _intervalMinutes) return false;
    if (next.length != _entries.length) return false;
    for (var i = 0; i < next.length; i++) {
      if (next[i].path != _entries[i].path) return false;
    }
    return true;
  }

  String? get _currentPath =>
      (_index >= 0 && _index < _entries.length) ? _entries[_index].path : null;

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    _intervalMinutes = widget.config.intervalMinutes;
    // Nothing to rotate through with 0 or 1 wallpapers.
    if (_entries.length <= 1) return;
    final minutes =
        widget.config.intervalMinutes < 1 ? 1 : widget.config.intervalMinutes;
    _timer = Timer.periodic(Duration(minutes: minutes), (_) {
      if (!mounted || _entries.length <= 1) return;
      setState(() => _index = (_index + 1) % _entries.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox.expand(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 1500),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
          child: _buildMedia(_currentPath),
        ),
      ),
    );
  }

  Widget _buildMedia(String? path) {
    if (path == null) {
      return const ColoredBox(key: ValueKey('__empty__'), color: Color(0xFF1A1A1A));
    }
    return MediaBackground(
      key: ValueKey(path),
      path: path,
      fit: boxFitFor(widget.config.fit),
    );
  }
}

class _ImageBackground extends StatelessWidget {
  const _ImageBackground({required this.path, required this.fit});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) =>
          const ColoredBox(color: Color(0xFF1A1A1A)),
    );
  }
}

class _VideoBackground extends StatefulWidget {
  const _VideoBackground({required this.path, required this.fit});

  final String path;
  final BoxFit fit;

  @override
  State<_VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<_VideoBackground> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player(
      configuration: const PlayerConfiguration(
        libass: false,
      ),
    );
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: false,
      ),
    );
    _player.setVolume(0);
    _player.setPlaylistMode(PlaylistMode.loop);
    _player.open(Media(Uri.file(widget.path).toString()), play: true);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Video(
      controller: _controller,
      fit: widget.fit,
      fill: const Color(0xFF000000),
      controls: NoVideoControls,
    );
  }
}
