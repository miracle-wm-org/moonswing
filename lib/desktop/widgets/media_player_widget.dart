// The media player desktop widget: what is playing, with the controls for it.
//
// The first widget in `DesktopWidgetRegistry`, and the shape the next one should
// copy — a `DesktopWidgetSpec` at the bottom of the file, a body that takes its
// store as a parameter, and layout that switches on the *span* the user has
// resized it to rather than on pixel widths.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';

import 'package:graceful_shell/desktop/desktop_layout.dart' show GridSpan;
import 'package:graceful_shell/desktop/widgets/desktop_widget.dart';
import 'package:graceful_shell/media/media_controls.dart';
import 'package:graceful_shell/media/mpris_store.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// The widget's body. Public and store-injectable so a widget test can seed a
/// player and pump it with no session bus behind it.
class MediaPlayerWidget extends StatefulWidget {
  MediaPlayerWidget({
    super.key,
    required this.span,
    MprisStore? store,
  }) : store = store ?? MprisStore.instance;

  /// The widget's size in cells. Two cells wide by one is the minimum and the
  /// layout everything else is derived from.
  final GridSpan span;

  final MprisStore store;

  /// Whether there is room for the second line of metadata, the progress bar
  /// and a full-size transport row.
  bool get expanded => span.rows >= 2;

  @override
  State<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends State<MediaPlayerWidget> {
  @override
  void initState() {
    super.initState();
    // A *detail* lease: unlike the bar module this draws a progress bar, which
    // is the one thing that needs `Position` polled.
    widget.store.acquire(detailed: true);
    widget.store.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(MediaPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store == widget.store) return;
    oldWidget.store
      ..removeListener(_onChanged)
      ..release(detailed: true);
    widget.store
      ..acquire(detailed: true)
      ..addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.store
      ..removeListener(_onChanged)
      ..release(detailed: true);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final player = widget.store.active;

    return LayoutBuilder(
      builder: (context, constraints) {
        // A cell can be configured down to 32px, which makes a 2x1 card smaller
        // than this content can be drawn in. Laying it out at its own minimum and
        // clipping is the honest answer: the alternative is a flex overflow
        // reported every frame on a surface whose console nobody reads.
        final width = math.max(constraints.maxWidth, _minWidth);
        final height = math.max(constraints.maxHeight, _minHeight);

        // The span asks for the expanded layout; the pixels decide whether it
        // fits. A 2-row widget on a short grid falls back rather than
        // overflowing.
        final expanded = widget.expanded && height >= _expandedMinHeight;

        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            // Unlike the bar module, the widget cannot render nothing: the
            // user put a rectangle on their desktop and it has to still be
            // there — and still be draggable — when the music stops.
            child: player == null
                ? _Idle(theme: theme)
                : expanded
                    ? _ExpandedLayout(
                        store: widget.store,
                        player: player,
                        theme: theme,
                      )
                    : _CompactLayout(
                        store: widget.store,
                        player: player,
                        theme: theme,
                      ),
          ),
        );
      },
    );
  }
}

/// The smallest box the compact layout draws in, and the height at which the
/// expanded one starts to fit. Both are content measurements, not cell counts:
/// the cell size is configurable and the content is not.
const double _minWidth = 160;
const double _minHeight = 56;
const double _expandedMinHeight = 150;

/// Nothing is playing and nothing is paused.
class _Idle extends StatelessWidget {
  const _Idle({required this.theme});

  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(FontAwesomeIcons.music, size: 14, color: theme.muted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Nothing playing',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: theme.fontFamily,
                fontSize: ShellFontSizes.secondary,
                color: theme.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The 2x1 layout: art, one line of text, three small buttons.
class _CompactLayout extends StatelessWidget {
  const _CompactLayout({
    required this.store,
    required this.player,
    required this.theme,
  });

  final MprisStore store;
  final MprisPlayer player;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final art = math.min(constraints.maxHeight, 56.0);
        // At the 2x1 minimum there is not room for five controls and a
        // readable title. Skip-track is what goes: play/pause is the control
        // somebody put a media player on their desktop *for*.
        final showSkip = constraints.maxWidth >= 220;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AlbumArt(player: player, size: art, theme: theme),
            const SizedBox(width: 8),
            // Flexible rather than a width computed from the transport's own
            // size: the buttons a player offers vary (a stream has no previous
            // track), and arithmetic kept in step with another widget's layout is
            // arithmetic that will drift out of it and overflow.
            Expanded(
              child: LayoutBuilder(
                // The marquee measures against a number, so it needs the width
                // the Expanded actually resolved to.
                builder: (context, text) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TrackMarquee(
                      text: player.title.isEmpty
                          ? player.displayText
                          : player.title,
                      maxWidth: text.maxWidth,
                      style: TextStyle(
                        fontFamily: theme.fontFamily,
                        fontSize: ShellFontSizes.body,
                        color: theme.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        // The ornament is the first thing to go when the card
                        // is narrow: an artist name the user can read beats a
                        // level meter they cannot, and a fixed-width child in
                        // a row this tight is an overflow.
                        if (text.maxWidth >= 40) ...[
                          PlayingBars(
                            playing: player.isPlaying,
                            color: theme.accent,
                            height: 10,
                            bars: 3,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            player.artist.isEmpty
                                ? player.identity
                                : player.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: theme.fontFamily,
                              fontSize: ShellFontSizes.caption,
                              color: theme.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            _Transport(
              store: store,
              player: player,
              compact: true,
              showSkip: showSkip,
            ),
          ],
        );
      },
    );
  }
}

/// Two rows or taller: bigger art, album line, progress bar, full transport.
class _ExpandedLayout extends StatelessWidget {
  const _ExpandedLayout({
    required this.store,
    required this.player,
    required this.theme,
  });

  final MprisStore store;
  final MprisPlayer player;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final art = math.min(constraints.maxHeight * 0.55, 96.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AlbumArt(player: player, size: art, theme: theme),
                const SizedBox(width: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, text) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TrackMarquee(
                          text: player.title.isEmpty
                              ? player.displayText
                              : player.title,
                          maxWidth: text.maxWidth,
                          style: TextStyle(
                            fontFamily: theme.fontFamily,
                            fontSize: ShellFontSizes.title,
                            color: theme.foreground,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          player.artist.isEmpty
                              ? player.identity
                              : player.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: theme.fontFamily,
                            fontSize: ShellFontSizes.body,
                            color: theme.foreground.withValues(alpha: 0.8),
                          ),
                        ),
                        if (player.album.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            player.album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: theme.fontFamily,
                              fontSize: ShellFontSizes.caption,
                              color: theme.muted,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        PlayingBars(
                          playing: player.isPlaying,
                          color: theme.accent,
                          bars: 5,
                          height: 12,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            MediaProgressBar(store: store, theme: theme),
            const SizedBox(height: 8),
            _Transport(store: store, player: player, compact: false),
          ],
        );
      },
    );
  }
}

/// The transport row, in both sizes.
class _Transport extends StatelessWidget {
  const _Transport({
    required this.store,
    required this.player,
    required this.compact,
    this.showSkip = true,
  });

  final MprisStore store;
  final MprisPlayer player;
  final bool compact;

  /// Whether there is room for previous/next beside play/pause.
  final bool showSkip;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 12.0 : 16.0;
    final padding = compact ? 4.0 : 8.0;

    // A player that refuses control gets no buttons rather than dead ones —
    // the same answer the bar module gives. The widget is still a widget: the
    // art, the title and the animation carry it.
    if (!player.canControl) return const SizedBox.shrink();
    final canSkip = showSkip;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment:
          compact ? MainAxisAlignment.end : MainAxisAlignment.center,
      children: [
        if (canSkip && player.canGoPrevious)
          MediaTransportButton(
            icon: FontAwesomeIcons.backwardStep,
            onPressed: store.previous,
            size: size,
            padding: padding,
            circular: !compact,
            semanticLabel: 'Previous track',
          ),
        SizedBox(width: compact ? 2 : 8),
        MediaTransportButton(
          icon: player.isPlaying
              ? FontAwesomeIcons.pause
              : FontAwesomeIcons.play,
          onPressed: store.playPause,
          size: size,
          padding: padding,
          // The primary action is filled with the accent so it is findable
          // without reading the glyphs — the one place this widget spends
          // colour.
          prominent: !compact,
          circular: !compact,
          semanticLabel: player.isPlaying ? 'Pause' : 'Play',
        ),
        SizedBox(width: compact ? 2 : 8),
        if (canSkip && player.canGoNext)
          MediaTransportButton(
            icon: FontAwesomeIcons.forwardStep,
            onPressed: store.next,
            size: size,
            padding: padding,
            circular: !compact,
            semanticLabel: 'Next track',
          ),
      ],
    );
  }
}

/// The album art, or the spinning disc that stands in for it.
///
/// The disc turns only while playing and the art breathes only while playing:
/// both are the signal [PlayingBars] carry, and a still one is how the widget
/// says "paused" without a word of text.
class AlbumArt extends StatefulWidget {
  const AlbumArt({
    super.key,
    required this.player,
    required this.size,
    required this.theme,
  });

  final MprisPlayer player;
  final double size;
  final ThemeConfig theme;

  @override
  State<AlbumArt> createState() => _AlbumArtState();
}

class _AlbumArtState extends State<AlbumArt> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );

  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  /// Resolved once per change of `artUrl`: [MprisPlayer.artFile] stats the
  /// file, and `build` runs on every store notification.
  File? _art;
  String _artUrl = '';

  @override
  void initState() {
    super.initState();
    _syncArt();
    _sync();
  }

  @override
  void didUpdateWidget(AlbumArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncArt();
    _sync();
  }

  @override
  void dispose() {
    _spin.dispose();
    _breathe.dispose();
    super.dispose();
  }

  void _syncArt() {
    if (widget.player.artUrl == _artUrl) return;
    _artUrl = widget.player.artUrl;
    _art = widget.player.artFile;
  }

  void _sync() {
    if (widget.player.isPlaying) {
      if (!_spin.isAnimating) _spin.repeat();
      if (!_breathe.isAnimating) _breathe.repeat(reverse: true);
    } else {
      _spin.stop();
      // Settled rather than stopped: a half-scaled card frozen mid-breath reads
      // as a rendering bug.
      _breathe.animateTo(0, duration: ShellDurations.slow);
    }
  }

  @override
  Widget build(BuildContext context) {
    final art = _art;
    final Widget face = art != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(ShellRadii.control),
            child: Image.file(
              art,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              // The file is often replaced in place as tracks change; without
              // this the widget flashes empty between decodes.
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, _, _) => _Disc(
                spin: _spin,
                size: widget.size,
                theme: widget.theme,
              ),
            ),
          )
        : _Disc(spin: _spin, size: widget.size, theme: widget.theme);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _breathe,
        builder: (context, child) => Transform.scale(
          scale: 1 + 0.04 * Curves.easeInOut.transform(_breathe.value),
          child: child,
        ),
        child: face,
      ),
    );
  }
}

/// The stand-in for missing art: a record that turns while the music does.
class _Disc extends StatelessWidget {
  const _Disc({required this.spin, required this.size, required this.theme});

  final AnimationController spin;
  final double size;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: spin,
      builder: (context, _) => CustomPaint(
        size: Size.square(size),
        painter: DiscPainter(
          turn: spin.value,
          face: theme.surfacePressed,
          groove: theme.divider,
          label: theme.accent,
        ),
      ),
    );
  }
}

/// Paints [_Disc]. Colours as parameters, the `time_series_chart.dart`
/// convention.
class DiscPainter extends CustomPainter {
  const DiscPainter({
    required this.turn,
    required this.face,
    required this.groove,
    required this.label,
  });

  /// 0..1 around one revolution.
  final double turn;
  final Color face;
  final Color groove;
  final Color label;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    canvas.drawCircle(centre, radius, Paint()..color = face);

    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = groove.withValues(alpha: 0.7);
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(centre, radius * (0.45 + i * 0.15), groovePaint);
    }

    canvas.drawCircle(centre, radius * 0.32, Paint()..color = label);
    canvas.drawCircle(centre, radius * 0.08, Paint()..color = face);

    // One highlight, so the rotation is visible on an otherwise radially
    // symmetric disc — without it a spinning record looks stationary.
    final angle = turn * 2 * math.pi;
    canvas.drawCircle(
      centre + Offset(math.cos(angle), math.sin(angle)) * radius * 0.6,
      radius * 0.06,
      Paint()..color = groove,
    );
  }

  @override
  bool shouldRepaint(DiscPainter oldDelegate) =>
      oldDelegate.turn != turn ||
      oldDelegate.face != face ||
      oldDelegate.groove != groove ||
      oldDelegate.label != label;
}

/// Elapsed time, a track-position bar, and the remaining time.
///
/// Owns its own tick: [MprisStore] re-reads `Position` once a second but
/// *interpolates* between reads, so a four-times-a-second repaint turns that
/// into a bar that moves smoothly. `lib/timers/`'s rule applies — the tick exists
/// only while something is playing.
class MediaProgressBar extends StatefulWidget {
  const MediaProgressBar({
    super.key,
    required this.store,
    required this.theme,
  });

  final MprisStore store;
  final ThemeConfig theme;

  @override
  State<MediaProgressBar> createState() => _MediaProgressBarState();
}

class _MediaProgressBarState extends State<MediaProgressBar>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastFrame = Duration.zero;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(MediaProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _sync() {
    final playing = widget.store.active?.isPlaying ?? false;
    if (playing == _ticker.isActive) return;
    if (playing) {
      _lastFrame = Duration.zero;
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    // Four times a second, not every frame: the bar advances by well under a
    // pixel per frame, and this widget is drawn on every monitor's desktop.
    if (elapsed - _lastFrame < const Duration(milliseconds: 250)) return;
    _lastFrame = elapsed;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // The ticker is (re)synced here as well as in didUpdateWidget: the store
    // notifies the parent, which rebuilds this with the same widget config, and
    // a play/pause has to start or stop the tick either way.
    _sync();

    final theme = widget.theme;
    final progress = widget.store.progress;
    final position = widget.store.position;
    final length = widget.store.active?.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 4,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: theme.divider.withValues(alpha: 0.6),
                  ),
                ),
                if (progress != null)
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: ColoredBox(color: theme.accent),
                  )
                else
                  // No length published (a live stream): a full-width wash
                  // rather than a bar stuck at zero, which would read as a
                  // track that never starts.
                  Positioned.fill(
                    child: ColoredBox(
                      color: theme.accent.withValues(alpha: 0.25),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              formatTrackTime(position),
              style: TextStyle(
                fontFamily: theme.fontFamily,
                fontSize: ShellFontSizes.caption,
                color: theme.muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              length == null ? '--:--' : formatTrackTime(length),
              style: TextStyle(
                fontFamily: theme.fontFamily,
                fontSize: ShellFontSizes.caption,
                color: theme.muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// `m:ss`, or `h:mm:ss` for anything past an hour. Pure, like
/// `lib/timers/timer_format.dart`'s formatter, and tested the same way.
String formatTrackTime(Duration duration) {
  final total = duration.isNegative ? Duration.zero : duration;
  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60);
  final seconds = total.inSeconds.remainder(60);
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  return '$minutes:$ss';
}

/// The registry entry. Registered from `main()` beside the bar modules.
final DesktopWidgetSpec mediaPlayerDesktopWidget = DesktopWidgetSpec(
  type: 'media_player',
  name: 'Media player',
  description: 'What is playing, with transport controls',
  icon: FontAwesomeIcons.music,
  // Two cells wide is the floor because one cell is an *icon*: art plus a title
  // plus a button does not fit in a launcher tile's width. The default is larger
  // deliberately — a widget somebody has just added should show what it can do,
  // and 3x2 is the smallest span carrying the album, the progress bar and a
  // full-size transport row.
  minSpan: (columns: 2, rows: 1),
  maxSpan: (columns: 6, rows: 4),
  defaultSpan: (columns: 3, rows: 2),
  builder: (context, widget) => MediaPlayerWidget(span: widget.span),
);
