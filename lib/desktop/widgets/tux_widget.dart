// The Tux desktop widget: a penguin who says something nice, once a day.
//
// The fifth entry in `DesktopWidgetRegistry`, and the smallest — everything
// before it takes two cells at its floor because a phase name or a track title
// needs a width of text to sit in. This one is asked to work at **1x1**, 96
// logical pixels on the default grid, and that constraint is what every decision
// below comes out of.
//
// Four things a change here has to keep true:
//
// - **1x1 is the design, not the degraded case.** A 96px square holds a picture
//   or a sentence and not both, so at that size the card is Tux and the greeting
//   is revealed by hovering him. Setting the line under him at 7px would be a
//   card that technically shows the greeting and factually shows nobody it.
//   Widen him to two cells and the line moves out beside him; two cells *and*
//   two rows and it moves under him, larger.
// - **The type size is measured, never chosen.** This borrows `fitFortuneText`
//   rather than growing a second ladder beside it: it measures a string against
//   a box with the very `TextStyle` about to be rendered, which is exactly this
//   problem, and two copies of a measured ladder is drift waiting to happen.
// - **He is on the theme's card, not a picture of his own.** The other widgets
//   paint a backdrop and set white text on it because their pictures run from
//   near-black to near-white; Tux is one drawing on a flat surface, so the
//   greeting is plain themed text and a theme that changes its font changes his.
// - **Nothing animates but the hover.** A new line replaces the old outright: a
//   transition would be the only moving thing on the desktop, moving exactly
//   when somebody has just asked to read something.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/desktop/desktop_layout.dart' show GridSpan;
import 'package:moonswing/desktop/widgets/desktop_widget.dart';
// The measured type ladder. Borrowed the way `moon_widget.dart` borrows the
// weather's text-over-a-picture tokens: it lives beside the fortune because
// that is where the first card needing it was, and nothing about it is about
// fortunes.
import 'package:moonswing/fortune/fortune_text_fit.dart'
    show fitFortuneText, kFortuneLineHeight;
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/tux/tux_art.dart';
import 'package:moonswing/tux/tux_greetings.dart';
import 'package:moonswing/tux/tux_store.dart';

/// The smallest box the card draws in — a content measurement, not a cell
/// count, because a cell is configurable down to 32px and Tux is not. Below
/// this the card is laid out at its minimum and clipped, which is what the
/// media, weather, lunar and fortune widgets all do rather than report a flex
/// overflow every frame on a surface whose console nobody is reading.
const double _minSide = 64;

/// The card the sizes below were chosen against: 1x1 on the default grid, whose
/// `cell_width`/`cell_height` are 96. The other widgets' reference is their own
/// 3x2 default; this one's is 1x1, because that is the size it is *for*.
const double _referenceSide = 96;

/// How far the type is allowed to grow. `maxSpan` is 4x3, which on the default
/// grid is a little over three times the reference side — sub-linear growth (see
/// [_CardScale]) lands that around 2.4, so the clamp is a ceiling on the very
/// largest cards rather than something most of them meet.
const double _maxScale = 2.2;

/// The sizes the greeting is set at, largest first, before the card's scale.
///
/// A shorter ladder than the fortune's and a lower top: a greeting is one
/// sentence and the card is often a square, so the useful range is narrow, and a
/// four-word line set as a headline would be shouting the friendly thing.
const List<double> _greetingSizes = [17, 16, 15, 14, 13, 12, 11, 10, 9];

/// The card's chrome scale.
///
/// The weather and fortune widgets' `_CardScale`: the **geometric mean** of the
/// two edge ratios, because a card stretched wide but left one row tall has no
/// more room for bigger type than it started with; and never below 1, because
/// the literals are a floor and a card under the reference is already being
/// laid out at its own minimum and clipped.
class _CardScale {
  const _CardScale(this.factor);

  factory _CardScale.forBox(double width, double height) {
    final ratio = math.sqrt(
      (width / _referenceSide) * (height / _referenceSide),
    );
    return _CardScale(ratio.clamp(1.0, _maxScale));
  }

  final double factor;

  double call(double base) => base * factor;
}

/// Which of the three arrangements a card gets.
enum TuxLayout {
  /// Tux alone, with the greeting on hover. 1x1.
  portrait,

  /// Tux beside the greeting. Two or more columns, one row.
  beside,

  /// Tux above the greeting. Two or more columns and two or more rows.
  stacked;

  /// The arrangement [span] earns.
  ///
  /// Chosen by *span* rather than by pixels, which is the registry's own rule —
  /// a widget switches layout on the cells it was given and only glances at the
  /// pixels, because the pixels follow a cell size the user sets.
  static TuxLayout forSpan(GridSpan span) {
    if (span.columns < 2) return TuxLayout.portrait;
    return span.rows < 2 ? TuxLayout.beside : TuxLayout.stacked;
  }
}

/// The widget's body. Store-injectable so a widget test can name the day it is
/// pretending to be and never arm a timer or read the passwd database.
class TuxWidget extends StatefulWidget {
  TuxWidget({super.key, required this.span, TuxStore? store})
      : store = store ?? TuxStore.instance;

  /// The widget's size in cells.
  final GridSpan span;

  final TuxStore store;

  @override
  State<TuxWidget> createState() => _TuxWidgetState();
}

class _TuxWidgetState extends State<TuxWidget> {
  @override
  void initState() {
    super.initState();
    widget.store.acquire();
    widget.store.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(TuxWidget oldWidget) {
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
    final greeting = widget.store.greeting;
    final layout = TuxLayout.forSpan(widget.span);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(constraints.maxWidth, _minSide);
        final height = math.max(constraints.maxHeight, _minSide);
        final scale = _CardScale.forBox(width, height);

        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: switch (layout) {
              TuxLayout.portrait => _TuxPortrait(
                  greeting: greeting,
                  scale: scale,
                  onTap: widget.store.another,
                ),
              TuxLayout.beside => _TuxBeside(
                  greeting: greeting,
                  scale: scale,
                  onTap: widget.store.another,
                ),
              TuxLayout.stacked => _TuxStacked(
                  greeting: greeting,
                  scale: scale,
                  onTap: widget.store.another,
                ),
            },
          ),
        );
      },
    );
  }
}

/// The card's inner inset at [_referenceSide].
const double _basePadding = 8;

/// 1x1: Tux fills the card, and hovering him says the nice thing.
///
/// The greeting covers the whole card rather than sitting in a corner of it,
/// because at this size a corner is four words wide. It is over a scrim rather
/// than straight on the drawing for the reason every caption over a picture in
/// this shell is: the white front and the black cap are both underneath it, and
/// no single text colour is legible on both.
class _TuxPortrait extends StatelessWidget {
  const _TuxPortrait({
    required this.greeting,
    required this.scale,
    required this.onTap,
  });

  final TuxGreeting greeting;
  final _CardScale scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final pad = scale(_basePadding);

    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.all(pad),
            child: const TuxArt(),
          ),
          // The one moving thing on the card, and the same tint every control
          // in the shell has. `IgnorePointer` because the hover that raises it
          // is the region's, and a bubble that took the pointer would flicker
          // itself off the moment it appeared.
          IgnorePointer(
            child: AnimatedOpacity(
              duration: ShellDurations.fast,
              opacity: hovered ? 1 : 0,
              child: Container(
                color: theme.popupBackground.withValues(alpha: 0.92),
                padding: EdgeInsets.all(pad),
                alignment: Alignment.center,
                child: _GreetingText(
                  // Both halves in one sentence: there is no room to set a
                  // salutation apart from the line it introduces, and a bubble
                  // that dropped the name would be the one place Tux does not
                  // know who he is talking to.
                  text: greeting.combined,
                  color: theme.foreground,
                  scale: scale,
                  align: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two or more columns, one row: Tux at the left, the greeting beside him.
class _TuxBeside extends StatelessWidget {
  const _TuxBeside({
    required this.greeting,
    required this.scale,
    required this.onTap,
  });

  final TuxGreeting greeting;
  final _CardScale scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pad = scale(_basePadding);

    return Padding(
      padding: EdgeInsets.all(pad),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Square, so `BoxFit.contain` inside `TuxArt` has nothing to letterbox
          // and he is as large as the row's height allows.
          _TuxTap(
            onTap: onTap,
            child: AspectRatio(aspectRatio: 1, child: const TuxArt()),
          ),
          SizedBox(width: pad),
          Expanded(
            child: _Speech(greeting: greeting, scale: scale),
          ),
        ],
      ),
    );
  }
}

/// Two or more columns and rows: Tux above, the greeting under him.
///
/// He takes the upper share rather than half: the greeting is at most three
/// lines and everything left over is better spent on the picture, which is what
/// the widget is.
class _TuxStacked extends StatelessWidget {
  const _TuxStacked({
    required this.greeting,
    required this.scale,
    required this.onTap,
  });

  final TuxGreeting greeting;
  final _CardScale scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pad = scale(_basePadding);

    return Padding(
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: _TuxTap(onTap: onTap, child: const TuxArt()),
          ),
          SizedBox(height: pad),
          Expanded(
            flex: 2,
            child: _Speech(greeting: greeting, scale: scale),
          ),
        ],
      ),
    );
  }
}

/// The tap target around the drawing.
///
/// A *tap*, not a pan: the card is dragged from anywhere on it, and the two
/// recognizers resolve against each other — a press that moves is the drag, one
/// that does not is this. `desktop_widget_grid_test` pins both halves for the
/// media widget's buttons, and it is why nothing on this card may grow a
/// pan-driven control.
class _TuxTap extends StatelessWidget {
  const _TuxTap({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => AnimatedOpacity(
        duration: ShellDurations.fast,
        // The only feedback a tap gets, and the only thing on the card that
        // moves. Barely there, because the alternative on a drawing with no rim
        // to light up is nothing at all.
        opacity: hovered ? 1 : 0.88,
        child: child,
      ),
    );
  }
}

/// The salutation and the line, set apart.
class _Speech extends StatelessWidget {
  const _Speech({required this.greeting, required this.scale});

  final TuxGreeting greeting;
  final _CardScale scale;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final salutationSize = scale(ShellFontSizes.caption);
        // What the salutation costs the line below it, measured the way the
        // weather card's `_Sections` measures its rows rather than assumed from
        // a constant: the family and the theme's scaler both move it.
        final salutationHeight =
            MediaQuery.textScalerOf(context).scale(salutationSize) * 1.3;
        final gap = scale(2);
        final lineBox = Size(
          constraints.maxWidth,
          math.max(0, constraints.maxHeight - salutationHeight - gap),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              greeting.salutation,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: salutationSize,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: theme.accentText,
              ),
            ),
            SizedBox(height: gap),
            Flexible(
              child: _GreetingText(
                text: greeting.line,
                color: theme.foreground,
                scale: scale,
                box: lineBox,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One piece of greeting, set at whatever size fits the box it is given.
class _GreetingText extends StatelessWidget {
  const _GreetingText({
    required this.text,
    required this.color,
    required this.scale,
    this.align = TextAlign.start,
    this.box,
  });

  final String text;
  final Color color;
  final _CardScale scale;
  final TextAlign align;

  /// The box to measure against, when the caller has already worked out what is
  /// left after its own chrome. Null measures against the incoming constraints.
  final Size? box;

  @override
  Widget build(BuildContext context) {
    // The style the card renders in, which is also the style the fit is
    // measured with — the ladder answers for a different piece of text than the
    // one on screen if those two ever come apart. The family comes from
    // `ShellTextRoot`'s `DefaultTextStyle`, so the greeting follows the theme's
    // font like everything else the shell sets.
    final base = DefaultTextStyle.of(context).style.copyWith(
          color: color,
          fontWeight: FontWeight.w400,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final measured = box ??
            Size(constraints.maxWidth, constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : constraints.maxWidth);
        final fit = fitFortuneText(
          text: text,
          style: base,
          box: measured,
          scale: scale.factor,
          sizes: _greetingSizes,
          // The theme's `font_size` reaches the `Text` below through the
          // ambient scaler rather than through `base`, so the fit has to be
          // measured through it as well.
          textScaler: MediaQuery.textScalerOf(context),
        );

        return Text(
          text,
          textAlign: align,
          maxLines: fit.maxLines,
          overflow: TextOverflow.ellipsis,
          style: base.copyWith(
            fontSize: fit.fontSize,
            height: kFortuneLineHeight,
          ),
        );
      },
    );
  }
}

/// The "Add widget…" menu's icon for this type. Named so a test can build a
/// [DesktopWidgetSpec] without picking an unrelated glyph.
const FaIconData tuxDesktopWidgetIcon = FontAwesomeIcons.linux;

/// The registry entry. Registered from `main()` beside the fortune widget's.
final DesktopWidgetSpec tuxDesktopWidget = DesktopWidgetSpec(
  type: 'tux',
  name: 'Tux',
  description: 'A penguin with something nice to say each day',
  icon: tuxDesktopWidgetIcon,
  // The first widget in the registry whose floor *and* default are one cell.
  // Everything before it needs a width of text at its smallest; this one is a
  // picture, and a picture is exactly what a single cell holds.
  minSpan: (columns: 1, rows: 1),
  // Lower than the other widgets' 6x4 on purpose: he is one drawing and one
  // sentence, and past this the card is mostly empty surface around a penguin.
  maxSpan: (columns: 4, rows: 3),
  defaultSpan: (columns: 1, rows: 1),
  // The card is the theme's, but the insets are per-layout — a 1x1 hover bubble
  // has to reach the rim, and `PopupCard` already clips to the theme's radius.
  padding: EdgeInsets.zero,
  builder: (context, widget) => TuxWidget(span: widget.span),
);
