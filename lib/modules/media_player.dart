import 'package:flutter/widgets.dart';

import 'package:moonswing/bar_button.dart';
import 'package:moonswing/config_reader.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/media/media_controls.dart';
import 'package:moonswing/media/mpris_store.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

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
/// All the MPRIS bookkeeping this used to carry — the session-bus connection, the
/// per-player `PropertiesChanged` subscriptions, the active-player rule — lives
/// in [MprisStore] now, which the desktop's media widget reads as well. One
/// connection for the machine, leased.
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

    // Down the bar on a side bar: the buttons stacked, and the title turned
    // on its side so it scrolls along the bar rather than across it, where a
    // bar's depth is no room for a title at all.
    return BarFlex(
      children: [
        BarFlex(
          spacing: 2,
          children: [
            if (player.canGoPrevious && player.canControl)
              MediaTransportButton(
                icon: ShellGlyph.skipBack,
                onPressed: widget.store.previous,
                semanticLabel: 'Previous track',
              ),
            if (player.canControl && (player.canPlay || player.canPause))
              MediaTransportButton(
                icon: player.isPlaying ? ShellGlyph.pause : ShellGlyph.play,
                onPressed: widget.store.playPause,
                semanticLabel: player.isPlaying ? 'Pause' : 'Play',
              ),
            if (player.canControl)
              MediaTransportButton(
                icon: ShellGlyph.stop,
                onPressed: widget.store.stop,
                semanticLabel: 'Stop',
              ),
            if (player.canGoNext && player.canControl)
              MediaTransportButton(
                icon: ShellGlyph.skipForward,
                onPressed: widget.store.next,
                semanticLabel: 'Next track',
              ),
          ],
        ),
        const SizedBox(width: 6, height: 6),
        // The marquee measures the text itself and only scrolls what genuinely
        // does not fit, so the strip's length is `max_text_width` either way and
        // the modules beside it never shift as tracks change.
        BarRotated(
          child: TrackMarquee(
            text: player.displayText,
            maxWidth: widget.config.maxTextWidth,
            style: TextStyle(
              fontFamily: theme.fontFamily,
              fontSize: ShellFontSizes.secondary,
              color: theme.foreground,
            ),
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
