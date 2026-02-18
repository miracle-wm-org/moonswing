import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'config.dart';

BoxFit _boxFitFor(BackgroundFit fit) {
  switch (fit) {
    case BackgroundFit.fill:
      return BoxFit.cover;
    case BackgroundFit.contain:
      return BoxFit.contain;
    case BackgroundFit.natural:
      return BoxFit.none;
  }
}

bool _isVideo(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.mkv') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.avi');
}

BackgroundEntry selectCurrentEntry(List<BackgroundEntry> sorted, DateTime now) {
  final nowDur = Duration(hours: now.hour, minutes: now.minute);
  for (int i = sorted.length - 1; i >= 0; i--) {
    if (sorted[i].timeOfDay <= nowDur) return sorted[i];
  }
  return sorted.last;
}

class BackgroundWindow extends StatefulWidget {
  const BackgroundWindow({super.key, required this.config});

  final BackgroundConfig config;

  @override
  State<BackgroundWindow> createState() => _BackgroundWindowState();
}

class _BackgroundWindowState extends State<BackgroundWindow> {
  late BackgroundEntry _currentEntry;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentEntry = selectCurrentEntry(widget.config.entries, DateTime.now());
    _scheduleNextTick();
  }

  void _scheduleNextTick() {
    final now = DateTime.now();
    final msUntilNextMinute = (60 - now.second) * 1000 - now.millisecond;
    _timer = Timer(Duration(milliseconds: msUntilNextMinute), () {
      _checkAndUpdate();
      _scheduleNextTick();
    });
  }

  void _checkAndUpdate() {
    if (!mounted) return;
    final next = selectCurrentEntry(widget.config.entries, DateTime.now());
    if (next.path != _currentEntry.path) {
      setState(() => _currentEntry = next);
    }
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
          child: _buildMedia(_currentEntry),
        ),
      ),
    );
  }

  Widget _buildMedia(BackgroundEntry entry) {
    final fit = _boxFitFor(widget.config.fit);
    if (_isVideo(entry.path)) {
      return _VideoBackground(
        key: ValueKey(entry.path),
        path: entry.path,
        fit: fit,
      );
    }
    return _ImageBackground(
      key: ValueKey(entry.path),
      path: entry.path,
      fit: fit,
    );
  }
}

class _ImageBackground extends StatelessWidget {
  const _ImageBackground({super.key, required this.path, required this.fit});

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
  const _VideoBackground({super.key, required this.path, required this.fit});

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
