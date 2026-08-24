import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config_reader.dart';
import 'package:graceful_shell/media/media_controls.dart';
import 'package:graceful_shell/media/mpris_store.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

class MediaPlayerConfig {
  final double maxTextWidth;

  const MediaPlayerConfig({this.maxTextWidth = 200.0});

  factory MediaPlayerConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const MediaPlayerConfig();
    return MediaPlayerConfig(
      maxTextWidth: map.doubleOr('max_text_width', 200.0),
    );
  }
}

/// The bar's now-playing strip: transport buttons and the track title.
///
/// All the MPRIS bookkeeping this used to carry — the session-bus connection,
/// the per-player `PropertiesChanged` subscriptions, the active-player rule —
/// now lives in [MprisStore], which the desktop's media widget reads as well.
/// One connection for the machine, leased; two bars on two monitors used to
/// mean two of everything.
class MediaPlayer extends StatefulWidget {
  // Not const: the default store is the process-wide singleton, which a const
  // constructor cannot reach.
  MediaPlayer({super.key, required this.config, MprisStore? store})
      : store = store ?? MprisStore.instance;

  final MediaPlayerConfig config;

  /// Injected by tests, which seed a store rather than reaching a session bus.
  final MprisStore store;

  @override
  MediaPlayerState createState() => MediaPlayerState();
}

class MediaPlayerState extends State<MediaPlayer> {
  @override
  void initState() {
    super.initState();
    // A light lease: the bar shows no progress, so it does not want the
    // one-second `Position` poll a detail lease adds.
    widget.store.acquire();
    widget.store.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(MediaPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store == widget.store) return;
    oldWidget.store
      ..removeListener(_onChanged)
      ..release();
    widget.store
      ..acquire()
      ..addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.store
      ..removeListener(_onChanged)
      ..release();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.store.active;
    // Nothing playing and nothing paused: the module takes no room at all,
    // rather than leaving a gap in the bar where a title will one day be.
    if (player == null) return const SizedBox.shrink();

    final theme = ThemeScope.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (player.canGoPrevious && player.canControl)
          MediaTransportButton(
            icon: FontAwesomeIcons.backwardStep,
            onPressed: widget.store.previous,
            semanticLabel: 'Previous track',
          ),
        if (player.canControl && (player.canPlay || player.canPause))
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: MediaTransportButton(
              icon: player.isPlaying
                  ? FontAwesomeIcons.pause
                  : FontAwesomeIcons.play,
              onPressed: widget.store.playPause,
              semanticLabel: player.isPlaying ? 'Pause' : 'Play',
            ),
          ),
        if (player.canControl)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: MediaTransportButton(
              icon: FontAwesomeIcons.stop,
              onPressed: widget.store.stop,
              semanticLabel: 'Stop',
            ),
          ),
        if (player.canGoNext && player.canControl)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: MediaTransportButton(
              icon: FontAwesomeIcons.forwardStep,
              onPressed: widget.store.next,
              semanticLabel: 'Next track',
            ),
          ),
        const SizedBox(width: 6),
        // The marquee measures the text itself and only scrolls what genuinely
        // does not fit, so the strip's width is `max_text_width` either way and
        // the modules beside it never shift as tracks change.
        TrackMarquee(
          text: player.displayText,
          maxWidth: widget.config.maxTextWidth,
          style: TextStyle(
            fontFamily: theme.fontFamily,
            fontSize: ShellFontSizes.secondary,
            color: theme.foreground,
          ),
        ),
      ],
    );
  }
}

final Module mediaPlayerModule = Module.simple(
  configKey: 'media_player',
  fromMap: MediaPlayerConfig.fromMap,
  builder: (context, config) => MediaPlayer(config: config),
);
