import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'config.dart';
import 'media_paths.dart';
import 'scopes.dart';
import 'theme/theme_wallpaper.dart';

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

/// The wallpapers eligible to be shown: from entries flagged `shown`, a valid
/// image extension, and present on disk. This is the pool the rotation cycles
/// through, in configuration (presentation) order.
///
/// A `theme = true` entry stands for [themeWallpaper] — the active theme's,
/// already resolved to a file, or null when the theme has none, in which case
/// the entry contributes nothing. A path listed twice (the theme's wallpaper
/// also picked as a file) is shown once.
List<String> shownPaths(BackgroundConfig config, {String? themeWallpaper}) {
  final paths = <String>[];
  for (final e in config.entries) {
    if (!e.shown) continue;
    final path = e.theme ? themeWallpaper : e.path;
    if (path == null || paths.contains(path)) continue;
    if (!isImagePath(path) || !File(path).existsSync()) continue;
    paths.add(path);
  }
  return paths;
}

class BackgroundWindow extends StatefulWidget {
  const BackgroundWindow({
    super.key,
    required this.config,
    this.themeWallpaperOf = resolveThemeWallpaper,
  });

  final BackgroundConfig config;

  /// Turns the theme above into its wallpaper's file. Injectable so tests need
  /// no installed wallpapers.
  final String? Function(ThemeConfig theme) themeWallpaperOf;

  @override
  State<BackgroundWindow> createState() => _BackgroundWindowState();
}

class _BackgroundWindowState extends State<BackgroundWindow> {
  List<String> _paths = const [];
  int _index = 0;
  Timer? _timer;

  /// The interval the running [_timer] was built with, so [_sameRotation] can
  /// tell a real interval edit from an unrelated config write.
  int _intervalMinutes = 0;

  /// The active theme's `wallpaper` value, and the file it resolved to.
  ///
  /// Keyed on the *value*: a theme switch hands this window a new
  /// [ThemeConfig] on every frame of its colour blend, and resolving is a stat
  /// or three — but the value only changes once, on the switch's first frame.
  String? _themeValue;
  String? _themeWallpaper;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = ThemeScope.maybeOf(context);
    final value = theme?.wallpaper ?? '';
    if (_started && value == _themeValue) return;
    _themeValue = value;
    _themeWallpaper = theme == null ? null : widget.themeWallpaperOf(theme);
    if (!_started) {
      _started = true;
      _paths = shownPaths(widget.config, themeWallpaper: _themeWallpaper);
      _restartTimer();
      return;
    }
    // The theme with its wallpaper selected changed: the rotation follows it.
    // No `setState`: a dependency change already rebuilds this widget.
    _update(rebuild: false);
  }

  @override
  void didUpdateWidget(BackgroundWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update({bool rebuild = true}) {
    final next = shownPaths(widget.config, themeWallpaper: _themeWallpaper);

    // Every ConfigStore write rebuilds the whole shell, and this widget sees a
    // new (equal) BackgroundConfig each time. Restarting the timer on all of
    // them would reset the rotation clock on every unrelated edit — dragging a
    // desktop icon around would mean the wallpaper never advanced at all.
    if (_sameRotation(next, widget.config)) return;

    // Keep pointing at the same wallpaper across edits when it's still shown;
    // otherwise stay in the same *slot* — which is what moves a theme entry on
    // to the new theme's wallpaper rather than back to the first — clamped
    // back into range.
    final currentPath = _currentPath;
    final kept = currentPath == null ? -1 : next.indexOf(currentPath);
    final nextIndex = kept >= 0
        ? kept
        : (_index < next.length ? _index : 0);
    void apply() {
      _paths = next;
      _index = nextIndex;
    }

    rebuild ? setState(apply) : apply();
    _restartTimer();
  }

  /// Whether [next] and [config] would produce the timer and image sequence
  /// already running — i.e. nothing about the rotation actually changed.
  bool _sameRotation(List<String> next, BackgroundConfig config) {
    if (config.intervalMinutes != _intervalMinutes) return false;
    return listEquals(next, _paths);
  }

  String? get _currentPath =>
      (_index >= 0 && _index < _paths.length) ? _paths[_index] : null;

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    _intervalMinutes = widget.config.intervalMinutes;
    // Nothing to rotate through with 0 or 1 wallpapers.
    if (_paths.length <= 1) return;
    final minutes =
        widget.config.intervalMinutes < 1 ? 1 : widget.config.intervalMinutes;
    _timer = Timer.periodic(Duration(minutes: minutes), (_) {
      if (!mounted || _paths.length <= 1) return;
      setState(() => _index = (_index + 1) % _paths.length);
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
              ?currentChild,
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
