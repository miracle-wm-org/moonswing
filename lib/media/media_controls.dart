// The pieces both media surfaces are made of: the transport buttons, the
// scrolling title, and the playing animation.
//
// Everything here takes what it draws as parameters and reaches for no store, so
// the bar module and the desktop widget share one implementation and a widget
// test can pump any of them alone.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// A transport control: a hover-lit icon in a rounded box.
///
/// One class for both surfaces, sized by [size]. [prominent] is the play/pause
/// button, filled with the theme's accent so the primary action is findable
/// without reading the glyphs.
class MediaTransportButton extends StatefulWidget {
  const MediaTransportButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 12,
    this.padding = 4,
    this.prominent = false,
    this.circular = false,
    this.semanticLabel,
  });

  final FaIconData icon;
  final VoidCallback onPressed;

  /// The glyph's size. The box grows from it and [padding].
  final double size;
  final double padding;

  final bool prominent;
  final bool circular;

  final String? semanticLabel;

  @override
  State<MediaTransportButton> createState() => _MediaTransportButtonState();
}

class _MediaTransportButtonState extends State<MediaTransportButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final radius = widget.circular
        ? BorderRadius.circular(widget.size * 2)
        : BorderRadius.circular(ShellRadii.barButton);

    return HoverRegion(
      onExit: () {
        if (_pressed) setState(() => _pressed = false);
      },
      builder: (context, hovered) {
        final Color background;
        if (widget.prominent) {
          background = _pressed
              ? theme.accent.withValues(alpha: 0.75)
              : hovered
                  ? theme.accent
                  : theme.accent.withValues(alpha: 0.9);
        } else {
          background = _pressed
              ? theme.surfacePressed
              : hovered
                  ? theme.surfaceHover
                  : const Color(0x00000000);
        }
        final foreground =
            widget.prominent ? kOnAccent : theme.foreground;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onPressed();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: ShellDurations.fast,
            padding: EdgeInsets.all(widget.padding),
            decoration: BoxDecoration(color: background, borderRadius: radius),
            child: SizedBox(
              width: widget.size + 2,
              height: widget.size + 2,
              child: Center(
                child: FaIcon(
                  widget.icon,
                  size: widget.size,
                  color: foreground,
                  semanticLabel: widget.semanticLabel,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A single line of text that scrolls when it does not fit, and sits still when
/// it does.
///
/// The measurement is what decides, not a character count: the same 30 characters
/// fit at 11px and overflow at 16px, and the bar module's old `length > 32` rule
/// got both wrong under a theme with a wider font. A [TextPainter] answers
/// exactly, and re-answers whenever the text, the style or [maxWidth] moves.
///
/// The theme's `font_size` reaches the [Text] below through the ambient
/// `TextScaler`, so the measurement takes the same scaler; a marquee measuring
/// unscaled would sit still at exactly the size the track runs off its box.
class TrackMarquee extends StatefulWidget {
  const TrackMarquee({
    super.key,
    required this.text,
    required this.style,
    required this.maxWidth,
    this.gap = 40,
    this.pixelsPerMs = 0.033,
    this.alignment = Alignment.centerLeft,
  });

  final String text;
  final TextStyle style;

  /// The width the text has to fit in. Also the width the scrolling form
  /// occupies, so a marquee never changes the layout around it as tracks
  /// change.
  final double maxWidth;

  /// The blank run between the end of one pass and the start of the next.
  final double gap;

  /// Scroll speed. The default is a readable walking pace for a bar.
  final double pixelsPerMs;

  final Alignment alignment;

  @override
  State<TrackMarquee> createState() => _TrackMarqueeState();
}

class _TrackMarqueeState extends State<TrackMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this);

  double _textWidth = 0;
  double _textHeight = 0;
  bool _measured = false;

  bool get _scrolling => _textWidth > widget.maxWidth;

  /// The scaler the last measurement was made with, so a `font_size` edit
  /// re-measures and an unrelated dependency change does not.
  TextScaler _scaler = TextScaler.noScaling;

  /// Measured from here rather than from `initState`: the scaler comes off the
  /// [MediaQuery] `ThemeProvider` publishes, and an inherited widget cannot be
  /// depended on before the first `didChangeDependencies`. This runs once
  /// before the first build either way.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scaler = MediaQuery.textScalerOf(context);
    if (scaler == _scaler && _measured) return;
    _scaler = scaler;
    _measure();
  }

  @override
  void didUpdateWidget(TrackMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.maxWidth != widget.maxWidth ||
        oldWidget.gap != widget.gap ||
        oldWidget.pixelsPerMs != widget.pixelsPerMs) {
      _measure();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _measure() {
    _measured = true;
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: TextDirection.ltr,
      textScaler: _scaler,
      maxLines: 1,
    )..layout();
    _textWidth = painter.width;
    // Measured, not assumed: the scrolling form is a Stack, which needs a
    // height, and hard-coding one clips a larger font's descenders.
    _textHeight = painter.height;
    painter.dispose();

    if (!_scrolling) {
      // Stop *and* reset: a track that shortens must not leave the next one
      // starting half-way through a pass.
      _controller.stop();
      _controller.reset();
      return;
    }
    final distance = _textWidth + widget.gap;
    _controller.duration =
        Duration(milliseconds: (distance / widget.pixelsPerMs).round());
    _controller
      ..reset()
      ..repeat();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) return const SizedBox.shrink();

    if (!_scrolling) {
      return SizedBox(
        width: widget.maxWidth,
        child: Align(
          alignment: widget.alignment,
          child: Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    final line = Text(
      widget.text,
      style: widget.style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
    );
    final distance = _textWidth + widget.gap;

    // Two absolutely-positioned copies a [distance] apart, so the second arrives
    // as the first leaves and the loop has no visible seam.
    //
    // A `Row` inside the clip is the obvious spelling and it is wrong: the box is
    // exactly [maxWidth] wide and hands that down as a tight constraint, so the
    // row — which is by definition wider — overflows and Flutter reports it every
    // frame. Positioned children are laid out against the measured text width
    // instead and are simply clipped.
    return SizedBox(
      width: widget.maxWidth,
      height: _textHeight,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final offset = -_controller.value * distance;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(left: offset, width: _textWidth, child: child!),
                Positioned(
                  left: offset + distance,
                  width: _textWidth,
                  child: child,
                ),
              ],
            );
          },
          child: line,
        ),
      ),
    );
  }
}

/// The bouncing level meter that says, without words, that audio is playing.
///
/// Deliberately not a visualiser: the shell has no access to the stream's samples,
/// so this is an *ornament* driven by one repeating controller and a per-bar
/// phase. Honest about it, too — when [playing] goes false the bars settle to a
/// flat rest line rather than freezing mid-bounce.
class PlayingBars extends StatefulWidget {
  const PlayingBars({
    super.key,
    required this.playing,
    required this.color,
    this.bars = 4,
    this.barWidth = 3,
    this.spacing = 2,
    this.height = 14,
    this.period = const Duration(milliseconds: 900),
  });

  final bool playing;
  final Color color;
  final int bars;
  final double barWidth;
  final double spacing;
  final double height;
  final Duration period;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars>
    // Two controllers — the phase loop and the settle — so the *single*-ticker
    // mixin is not an option, however tempting the name.
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  /// How far the bars are towards their bouncing state, 0 at rest and 1 while
  /// playing. Separate from the phase controller so pausing *settles* rather
  /// than stops dead — and so a paused widget costs no ticker at all once it
  /// has settled.
  late final AnimationController _amplitude = AnimationController(
    vsync: this,
    duration: ShellDurations.slow,
    value: widget.playing ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PlayingBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) _controller.duration = widget.period;
    if (oldWidget.playing != widget.playing) _sync();
  }

  void _sync() {
    if (widget.playing) {
      _amplitude.forward();
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      // The phase controller keeps running until the settle finishes, so the
      // bars glide down instead of snapping.
      _amplitude.reverse().whenComplete(() {
        if (mounted && !widget.playing) _controller.stop();
      });
    }
  }

  @override
  void dispose() {
    _amplitude.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width =
        widget.bars * widget.barWidth + (widget.bars - 1) * widget.spacing;
    return SizedBox(
      width: width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: Listenable.merge([_controller, _amplitude]),
        builder: (context, _) => CustomPaint(
          painter: PlayingBarsPainter(
            phase: _controller.value,
            amplitude: _amplitude.value,
            color: widget.color,
            bars: widget.bars,
            barWidth: widget.barWidth,
            spacing: widget.spacing,
          ),
        ),
      ),
    );
  }
}

/// Paints [PlayingBars]. Colours arrive as parameters — the
/// `time_series_chart.dart` convention, so the painter stays `const`-able and
/// comparable.
class PlayingBarsPainter extends CustomPainter {
  const PlayingBarsPainter({
    required this.phase,
    required this.amplitude,
    required this.color,
    required this.bars,
    required this.barWidth,
    required this.spacing,
  });

  /// 0..1 around the loop.
  final double phase;

  /// 0 at rest, 1 bouncing.
  final double amplitude;

  final Color color;
  final int bars;
  final double barWidth;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    // A rest line rather than zero: bars that vanish read as a broken widget.
    final rest = size.height * 0.2;
    for (var i = 0; i < bars; i++) {
      // Irrational-ish stride so the bars never line up into one pulse.
      final wave = math.sin((phase + i * 0.27) * 2 * math.pi);
      final full = size.height * (0.35 + 0.65 * (0.5 + 0.5 * wave));
      final height = rest + (full - rest) * amplitude;
      final left = i * (barWidth + spacing);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - height, barWidth, height),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(PlayingBarsPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.amplitude != amplitude ||
      oldDelegate.color != color ||
      oldDelegate.bars != bars ||
      oldDelegate.barWidth != barWidth ||
      oldDelegate.spacing != spacing;
}
