// The fortune desktop widget: a line out of `fortune(6)`, over a lamp in the
// dark, with a button that asks for another one.
//
// The fourth entry in `DesktopWidgetRegistry`, and built the way the weather
// and lunar widgets are: a lease on a store nobody owns, a picture painted to
// the rim of a card with no padding, and white text on it rather than the
// theme's — the scene runs from a near-black sky to the glare beside the flame,
// and no theme foreground is legible across both.
//
// Three things that are its own:
//
// - **It is the first widget whose content the user asks for.** The weather and
//   the Moon refresh themselves because the thing they report on moves; a
//   fortune does not, so nothing here polls and the only thing that ever
//   replaces the text is somebody pressing for it. That makes the button the
//   feature rather than an affordance beside it, which is why there are two of
//   them: the explicit one in the corner, and the lamp itself.
// - **The type size is measured, not chosen.** A fortune is four words or
//   twelve lines and the card is the same size either way — see
//   `fitFortuneText`.
// - **A missing `fortune` is a visible state.** The overwhelmingly likely
//   reason this card is empty is that the package is not installed, which the
//   user can fix in one command; the card says so rather than sitting blank.
//   `NotificationDaemonStatus`'s rule, and `WeatherStore.error`'s.
//
// And one thing it shares with the lunar widget rather than the weather one:
// **nothing on this card animates.** No ticker, no transition on a new fortune,
// no spinning glyph — the picture is a still frame of a plume and the text is
// replaced outright. A wallpaper decoration on a machine that may be doing
// nothing else has no business repainting, and the only thing left that moves
// is the hover tint every control in the shell has (`DesktopWidgetFrame`'s own
// selection rim included). The card is therefore `pumpAndSettle`-able, which
// the weather widget is not.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:graceful_shell/desktop/desktop_layout.dart' show GridSpan;
import 'package:graceful_shell/desktop/widgets/desktop_widget.dart';
import 'package:graceful_shell/fortune/fortune_store.dart';
import 'package:graceful_shell/fortune/fortune_text_fit.dart';
import 'package:graceful_shell/fortune/lamp_scene.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/sky_icon_button.dart';
import 'package:graceful_shell/theme/tokens.dart';
// The three tokens for text over a picture, borrowed the way `moon_widget.dart`
// borrows them: they live beside the weather because that is where the first
// surface needing them was, and nothing about any of them is about the weather.
import 'package:graceful_shell/weather/weather_sky.dart'
    show kSkyForeground, kSkyMutedForeground, kSkyTextShadows;

/// The smallest box the card draws in — a content measurement, not a cell
/// count, because a cell is configurable down to 32px and the content is not.
const double _minWidth = 150;
const double _minHeight = 70;

/// The card every base size below was chosen against: the registry's own
/// `defaultSpan` of 3x2 on the default grid — `cellWidth`/`cellHeight` 96 with
/// `spacing` 12, so `3*96 + 2*12` by `2*96 + 12`. The weather widget's
/// reference, and the same 3x2, so the two cards side by side agree about what
/// "normal size" is.
const Size _referenceCard = Size(312, 204);

/// The card's inner inset at [_referenceCard].
const double _basePadding = 14;

/// How far the chrome is allowed to grow. `maxSpan` is 6x4, which on the
/// default grid wants about 2.05, so nothing the registry permits is being
/// clamped away.
const double _maxScale = 2.0;

/// The card's chrome scale — the button, the paddings, and the rungs of the
/// text ladder.
///
/// The weather widget's `_CardScale`, for its reasons: the **geometric mean**
/// of the two edge ratios, because a card stretched wide but left one row tall
/// has no more room for bigger type than it started with; and never below 1,
/// because the literals are a floor rather than a midpoint and a card under the
/// reference is already being laid out at its own minimum and clipped.
class _CardScale {
  const _CardScale(this.factor);

  factory _CardScale.forBox(double width, double height) {
    final ratio = math.sqrt((width / _referenceCard.width) *
        (height / _referenceCard.height));
    return _CardScale(ratio.clamp(1.0, _maxScale));
  }

  final double factor;

  double call(double base) => base * factor;
}

/// The widget's body. Store-injectable so a widget test can seed a fortune and
/// pump it with nothing behind it.
class FortuneWidget extends StatefulWidget {
  FortuneWidget({
    super.key,
    required this.span,
    FortuneStore? store,
  }) : store = store ?? FortuneStore.instance;

  /// The widget's size in cells.
  final GridSpan span;

  final FortuneStore store;

  @override
  State<FortuneWidget> createState() => _FortuneWidgetState();
}

class _FortuneWidgetState extends State<FortuneWidget> {
  /// How hard the lamp is being looked at, handed to the painter.
  bool _rubbing = false;

  @override
  void initState() {
    super.initState();
    widget.store.acquire();
    widget.store.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(FortuneWidget oldWidget) {
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
    final store = widget.store;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Laid out at its own minimum and clipped when the grid gives it less —
        // the media, weather and lunar widgets' rule. The alternative is a flex
        // overflow reported every frame on a surface whose console nobody is
        // reading.
        final width = math.max(constraints.maxWidth, _minWidth);
        final height = math.max(constraints.maxHeight, _minHeight);
        final size = Size(width, height);
        final scale = _CardScale.forBox(width, height);
        final lamp = LampGeometry.forCard(size);
        final button = scale(_buttonBox);
        final text = lamp.textArea(
          size,
          padding: scale(_basePadding),
          reserve: button + scale(6),
        );

        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                LampScene(glow: _rubbing ? 1 : 0),
                const LampScrim(),
                Positioned.fromRect(
                  rect: text,
                  child: _FortuneBody(store: store, scale: scale),
                ),
                // The lamp is the second way to ask, and the one the card is
                // built around: a genie's lamp that could not be rubbed would
                // be a picture of the wrong thing. It sits *above* the text so
                // the gesture works wherever the two overlap, and its box is
                // the body alone — see [LampGeometry.tapTarget].
                Positioned.fromRect(
                  rect: lamp.tapTarget,
                  child: HoverRegion(
                    onTap: store.refresh,
                    onEnter: () => setState(() => _rubbing = true),
                    onExit: () => setState(() => _rubbing = false),
                    builder: (context, hovered) => const SizedBox.expand(),
                  ),
                ),
                Positioned(
                  top: scale(8),
                  right: scale(8),
                  child: FortuneRefreshButton(
                    onTap: store.refresh,
                    size: button,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The refresh button's box at [_referenceCard].
const double _buttonBox = 26;

/// The button that asks for another fortune.
///
/// Public because it is the feature: a test that pins "pressing this refreshes"
/// should not have to find it by walking the card's private types.
///
/// A named [SkyIconButton] rather than its own implementation — that control
/// was generalized out of this one when a second card wanted the same
/// button, and a second copy of it here is what the settings library's
/// "generalize, do not clone" rule exists to prevent. What was said about it
/// still holds and is said there: no spin on tap and no loader while the store
/// fetches (a fork of `fortune` returns in single-digit milliseconds, so
/// anything driven by the in-flight flag is a frame of flicker, and this card
/// does not animate), and it is a *tap* rather than a pan, so the card stays
/// draggable from under it.
class FortuneRefreshButton extends StatelessWidget {
  const FortuneRefreshButton({
    super.key,
    required this.onTap,
    this.size = _buttonBox,
  });

  final VoidCallback onTap;

  /// The pointer target, never the glyph.
  final double size;

  @override
  Widget build(BuildContext context) =>
      SkyIconButton(onTap: onTap, icon: Symbols.autorenew, size: size);
}

/// The fortune, the loader, or why there is neither.
class _FortuneBody extends StatelessWidget {
  const _FortuneBody({required this.store, required this.scale});

  final FortuneStore store;
  final _CardScale scale;

  @override
  Widget build(BuildContext context) {
    if (store.loading) {
      return Align(
        alignment: Alignment.topLeft,
        child: LoadingIndicator(color: kSkyMutedForeground, size: scale(16)),
      );
    }
    if (!store.hasFortune) {
      return _NoFortune(store: store, scale: scale);
    }
    return _FortuneText(text: store.text, scale: scale);
  }
}

/// The fortune itself, set at whatever size fits.
class _FortuneText extends StatelessWidget {
  const _FortuneText({required this.text, required this.scale});

  final String text;
  final _CardScale scale;

  @override
  Widget build(BuildContext context) {
    // The style the card renders in, which is also the style the fit is
    // measured with — `fitFortuneText` answers for a different piece of text
    // than the one on screen if those two ever come apart. The family comes
    // from `ShellTextRoot`'s `DefaultTextStyle`, so the fortune follows the
    // theme's font like everything else the shell sets.
    final base = DefaultTextStyle.of(context).style.copyWith(
          color: kSkyForeground,
          fontWeight: FontWeight.w400,
          shadows: kSkyTextShadows,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = fitFortuneText(
          text: text,
          style: base,
          box: Size(constraints.maxWidth, constraints.maxHeight),
          scale: scale.factor,
          // The theme's `font_size` is applied to the Text below at paint, so
          // the fit has to be measured through it as well.
          textScaler: MediaQuery.textScalerOf(context),
        );

        // Replaced outright rather than faded or slid in. A transition here
        // would be the only moving thing on an otherwise still card, and it
        // would be moving exactly when the user has just asked to *read*
        // something.
        return Align(
          alignment: Alignment.topLeft,
          child: Text(
            text,
            maxLines: fit.maxLines,
            overflow: TextOverflow.ellipsis,
            style: base.copyWith(
              fontSize: fit.fontSize,
              height: kFortuneLineHeight,
            ),
          ),
        );
      },
    );
  }
}

/// No fortune, and what to do about it.
class _NoFortune extends StatelessWidget {
  const _NoFortune({required this.store, required this.scale});

  final FortuneStore store;
  final _CardScale scale;

  @override
  Widget build(BuildContext context) {
    final error = store.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _CardText(
          error.isEmpty ? 'No fortune yet' : error,
          size: scale(ShellFontSizes.secondary),
          weight: FontWeight.w500,
          maxLines: 2,
        ),
        if (store.commandMissing) ...[
          SizedBox(height: scale(4)),
          // The one thing the user can act on, and the reason this state says
          // anything at all instead of leaving the card blank. Deliberately not
          // a package manager command: the package is `fortune-mod` on Debian,
          // Fedora and Arch alike, and guessing which of three managers to name
          // is how a hint becomes wrong on two distributions out of three.
          _CardText(
            'Install the fortune-mod package',
            size: scale(ShellFontSizes.caption),
            muted: true,
            maxLines: 2,
          ),
        ],
      ],
    );
  }
}

/// One line of the card's own chrome — the error and the hint. The fortune
/// itself does not go through this: its size is measured rather than named.
class _CardText extends StatelessWidget {
  const _CardText(
    this.text, {
    required this.size,
    this.weight = FontWeight.w400,
    this.muted = false,
    this.maxLines = 1,
  });

  final String text;
  final double size;
  final FontWeight weight;
  final bool muted;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        height: 1.3,
        color: muted ? kSkyMutedForeground : kSkyForeground,
        shadows: kSkyTextShadows,
      ),
    );
  }
}

/// The "Add widget…" menu's icon for this type. Named so a test can build a
/// [DesktopWidgetSpec] without picking an unrelated glyph.
const FaIconData fortuneDesktopWidgetIcon = FontAwesomeIcons.wandMagicSparkles;

/// The registry entry. Registered from `main()` beside the lunar widget's.
final DesktopWidgetSpec fortuneDesktopWidget = DesktopWidgetSpec(
  type: 'fortune',
  name: 'Fortune',
  description: 'A line from the lamp, whenever you rub it',
  icon: fortuneDesktopWidgetIcon,
  // Two cells wide is the floor the other picture-backed widgets take: one cell
  // is an icon, and there is no width of text in it. The default is larger than
  // the floor deliberately — 3x2 is the smallest span that sets a short fortune
  // at a size worth reading with the lamp still visible beside it.
  minSpan: (columns: 2, rows: 1),
  maxSpan: (columns: 6, rows: 4),
  defaultSpan: (columns: 3, rows: 2),
  // The lamp and its sky are the card, the way the weather widget's sky is.
  padding: EdgeInsets.zero,
  builder: (context, widget) => FortuneWidget(span: widget.span),
);
