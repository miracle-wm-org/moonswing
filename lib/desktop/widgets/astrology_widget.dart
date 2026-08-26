// The astrology desktop widget: your sign, its constellation, and what today is
// supposed to hold.
//
// The sixth entry in `DesktopWidgetRegistry`, and built the way the weather,
// lunar and fortune cards are: a lease on a store nobody owns, a picture
// painted to the rim of a card with no padding, and white text on it rather
// than the theme's — the sky runs from a tinted zenith to near-black and no
// theme foreground is legible across both.
//
// Four things that are its own:
//
// - **Half the card cannot fail and half of it can.** The sign, its
//   constellation and its attributes are arithmetic and a table — they are
//   drawn whatever the network is doing. Only the paragraph comes from a
// server,   so a failure costs the paragraph and leaves a card that still says
// something   true. That split is why the header is built outside `_Body`
// rather than   inside it.
// - **The empty state is the actionable one.** With no birthday configured
// there   is no sign, no request to make and nothing to draw a constellation
// for; the   card says where to set it. `_NoFortune`'s rule, and
//   `NotificationDaemonStatus`'s: an empty card is indistinguishable from one
//   the user never enabled.
// - **The text is measured, not chosen.** A horoscope is forty words on one
//   card and forty words on a card four times the area — `fitFortuneText`, from
//   the fortune widget, because the problem is the identical one and the
//   alternative is a second implementation of a `TextPainter` ladder that would
//   drift from it. (Borrowed across features the way `moon_widget.dart` borrows
//   the weather's sky tokens: it lives where the first surface that needed it
//   was, and nothing about it is about fortunes.)
// - **It says where the words came from.** The paragraph is somebody else's
//   copy, fetched from a server the shell does not run, and the footer names
// it.   A horoscope presented as the shell's own would be the one thing on this
//   desktop pretending to an authority it has not got.
//
// And, with the lunar and fortune widgets rather than the weather one:
// **nothing on this card animates.** No ticker and no transition on a new
// horoscope — the sky is a still frame and the paragraph is replaced outright.
// The card is therefore `pumpAndSettle`-able.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:graceful_shell/astrology/astrology_store.dart';
import 'package:graceful_shell/astrology/horoscope_api.dart'
    show kHoroscopeAttribution;
import 'package:graceful_shell/astrology/zodiac.dart';
import 'package:graceful_shell/astrology/zodiac_sky.dart';
import 'package:graceful_shell/desktop/desktop_layout.dart' show GridSpan;
import 'package:graceful_shell/desktop/widgets/desktop_widget.dart';
// The measured type ladder. See the note above.
import 'package:graceful_shell/fortune/fortune_text_fit.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/overlay/settings_route.dart';
import 'package:graceful_shell/sky_icon_button.dart';
import 'package:graceful_shell/theme/tokens.dart';
// The tokens for text over a picture, borrowed the way `moon_widget.dart` and
// `fortune_widget.dart` borrow them: they live beside the weather because that
// is where the first surface needing them was, and nothing about any of them is
// about the weather.
import 'package:graceful_shell/weather/weather_sky.dart'
    show
        kSkyFaintForeground,
        kSkyForeground,
        kSkyHairline,
        kSkyMutedForeground,
        kSkyTextShadows,
        SkyScrim;

/// The smallest box the card draws in — a content measurement, not a cell
/// count, because a cell is configurable down to 32px and the content is not.
const double _minWidth = 170;
const double _minHeight = 76;

/// The card every base size below was chosen against: the registry's own
/// `defaultSpan` of 3x2 on the default grid — `cellWidth`/`cellHeight` 96 with
/// `spacing` 12. The weather, lunar and fortune widgets' reference, so the
/// cards side by side agree about what "normal size" is.
const Size _referenceCard = Size(312, 204);

/// The card's inner inset at [_referenceCard].
const double _basePadding = 14;

/// How far the chrome is allowed to grow. `maxSpan` is 6x4, which on the
/// default grid wants about 2.05.
const double _maxScale = 2.0;

/// The rungs the horoscope is set on.
///
/// Shorter and lower-topped than `kFortuneTextSizes`: a fortune can be four
/// words and wants a headline size when it is, while a horoscope is a paragraph
/// of roughly constant length, so the large rungs would never be reached and
/// the small ones are what a 2x1 card actually needs.
const List<double> kHoroscopeTextSizes = [17, 16, 15, 14, 13, 12, 11, 10];

/// The floor under the paragraph: about two lines at the default body size.
/// What a chrome line has to leave behind before it is allowed on the card.
const double _bodyFloor = 34;

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
    final ratio = math.sqrt(
      (width / _referenceCard.width) * (height / _referenceCard.height),
    );
    return _CardScale(ratio.clamp(1.0, _maxScale));
  }

  final double factor;

  double call(double base) => base * factor;
}

/// Which of the card's optional lines fit, decided in the order they are given
/// up.
///
/// Measured rather than thresholded — the weather widget's `_Sections` rule, in
/// the small: the same three lines fit under one theme's font and overflow
/// under another's, and a threshold in raw pixels is a measurement of whichever
/// font it was written against. Each line is admitted only if the paragraph
/// would still have [_bodyFloor] left afterwards, so what is dropped first is
/// the least useful thing on the card rather than whatever happened to be last.
class _Chrome {
  factory _Chrome({
    required double available,
    required _CardScale scale,
    required TextScaler textScaler,
    required bool onCusp,
  }) {
    double lineFor(double base) => textScaler.scale(scale(base)) * 1.3;
    final gap = scale(4);
    final floor = scale(_bodyFloor);

    var used = lineFor(ShellFontSizes.heading);

    bool admit(double base) {
      final cost = lineFor(base) + gap;
      if (available - used - cost < floor) return false;
      used += cost;
      return true;
    }

    // Attributes first: they are what the card says about the sign itself, and
    // the sign is the half of this widget that is always true. The footer is
    // next because it is the attribution. The cusp note goes last — it is the
    // most interesting line on the card on two days a month and dead weight on
    // the other twenty-eight, which is exactly the trade a shed order is for.
    final attributes = admit(ShellFontSizes.caption);
    final footer = admit(ShellFontSizes.caption);
    final cusp = onCusp && admit(ShellFontSizes.caption);

    return _Chrome._(attributes: attributes, footer: footer, cusp: cusp);
  }

  const _Chrome._({
    required this.attributes,
    required this.footer,
    required this.cusp,
  });

  final bool attributes;
  final bool footer;
  final bool cusp;
}

/// The widget's body. Store-injectable so a widget test can seed a horoscope
/// and pump it with nothing behind it.
class AstrologyWidget extends StatefulWidget {
  AstrologyWidget({
    super.key,
    required this.span,
    AstrologyStore? store,
  }) : store = store ?? AstrologyStore.instance;

  /// The widget's size in cells.
  final GridSpan span;

  final AstrologyStore store;

  @override
  State<AstrologyWidget> createState() => _AstrologyWidgetState();
}

class _AstrologyWidgetState extends State<AstrologyWidget> {
  @override
  void initState() {
    super.initState();
    widget.store.acquire();
    widget.store.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(AstrologyWidget oldWidget) {
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
    final zodiac = store.zodiac;
    final sign = zodiac?.sign;
    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Laid out at its own minimum and clipped when the grid gives it less —
        // the media, weather, lunar and fortune widgets' rule. The alternative
        // is a flex overflow reported every frame on a surface whose console
        // nobody is reading.
        final width = math.max(constraints.maxWidth, _minWidth);
        final height = math.max(constraints.maxHeight, _minHeight);
        final scale = _CardScale.forBox(width, height);
        final padding = scale(_basePadding);

        final chrome = _Chrome(
          available: height - padding * 2,
          scale: scale,
          textScaler: textScaler,
          onCusp: zodiac?.onCusp ?? false,
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
                ZodiacSky(sign: sign),
                const SkyScrim(),
                Padding(
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(
                        store: store,
                        scale: scale,
                        showAttributes: chrome.attributes,
                        showCusp: chrome.cusp,
                      ),
                      SizedBox(height: scale(6)),
                      Expanded(child: _Body(store: store, scale: scale)),
                      // Nothing to attribute, and no horoscope to label,
                      // when there is no sign — the empty state is one
                      // sentence and a path, and a stray "Today" under it
                      // would be the card labelling something that is not
                      // there.
                      if (chrome.footer && sign != null) ...[
                        SizedBox(height: scale(4)),
                        _Footer(store: store, scale: scale),
                      ],
                    ],
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

/// The sign, what it is made of, and the button that asks again.
class _Header extends StatelessWidget {
  const _Header({
    required this.store,
    required this.scale,
    required this.showAttributes,
    required this.showCusp,
  });

  final AstrologyStore store;
  final _CardScale scale;
  final bool showAttributes;
  final bool showCusp;

  @override
  Widget build(BuildContext context) {
    final zodiac = store.zodiac;
    final sign = zodiac?.sign;
    final neighbour = zodiac?.neighbour;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _SkyText(
                // With no birthday there is no sign to name, and naming one
                // anyway — a default, a placeholder — would be the card
                // answering a question it is about to say it cannot answer.
                sign?.label ?? 'Astrology',
                size: scale(ShellFontSizes.heading),
                weight: FontWeight.w600,
                tracking: 0.4,
              ),
              if (showAttributes && sign != null)
                _SkyText(
                  sign.attributes,
                  size: scale(ShellFontSizes.caption),
                  muted: true,
                ),
              if (showCusp && neighbour != null)
                _SkyText(
                  // The Sun changed signs during the day they were born, and a
                  // date with no time on it cannot say which side of the change
                  // they fell. Naming both is the only honest answer.
                  'Born on the cusp — the Sun entered '
                  '${_laterOf(sign, neighbour).label} that day',
                  size: scale(ShellFontSizes.caption),
                  faint: true,
                  maxLines: 2,
                ),
            ],
          ),
        ),
        // No button with no birthday: there is nothing to fetch, and an action
        // that cannot do anything is worse than no action at all.
        if (sign != null) ...[
          SizedBox(width: scale(8)),
          SkyIconButton(
            onTap: store.refresh,
            icon: Symbols.autorenew,
            size: scale(kSkyIconButtonBox),
          ),
        ],
      ],
    );
  }
}

/// Which of a cusp's two signs the Sun moved *into* — the one later in the
/// ecliptic order, except across the Pisces/Aries wrap where it is Aries.
ZodiacSign _laterOf(ZodiacSign? a, ZodiacSign b) {
  if (a == null) return b;
  if (a == ZodiacSign.pisces && b == ZodiacSign.aries) return b;
  if (b == ZodiacSign.pisces && a == ZodiacSign.aries) return a;
  return a.index > b.index ? a : b;
}

/// The horoscope, the loader, or why there is neither.
class _Body extends StatelessWidget {
  const _Body({required this.store, required this.scale});

  final AstrologyStore store;
  final _CardScale scale;

  @override
  Widget build(BuildContext context) {
    if (store.zodiac == null) return _clipped(_NoBirthday(scale: scale));
    if (store.loading) {
      return Align(
        alignment: Alignment.topLeft,
        child: LoadingIndicator(color: kSkyMutedForeground, size: scale(16)),
      );
    }
    final reading = store.reading;
    if (reading == null) {
      return _clipped(
        _NoHoroscope(
          error: store.error,
          onRetry: store.refresh,
          scale: scale,
        ),
      );
    }
    return _HoroscopeText(text: reading.text, scale: scale);
  }

  /// Laid out at its natural height and clipped, never a flex overflow.
  ///
  /// The paragraph is *measured* into whatever box it is given, so it always
  /// fits; these two states are a fixed stack of lines and a button, and on the
  /// smallest span the registry allows there is less room than that. The card's
  /// own rule, applied one level in — a `RenderFlex overflowed` reported every
  /// frame on a surface whose console nobody is reading is the alternative.
  Widget _clipped(Widget child) => ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxHeight: double.infinity,
          child: child,
        ),
      );
}

/// The paragraph, set at whatever size fits.
class _HoroscopeText extends StatelessWidget {
  const _HoroscopeText({required this.text, required this.scale});

  final String text;
  final _CardScale scale;

  @override
  Widget build(BuildContext context) {
    // The style the card renders in, which is also the style the fit is
    // measured with — the ladder answers for a different piece of text than the
    // one on screen if those two ever come apart. The family comes from
    // `ShellTextRoot`'s `DefaultTextStyle`, so the horoscope follows the
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
          sizes: kHoroscopeTextSizes,
          // The theme's `font_size` reaches the `Text` below through the
          // ambient scaler, so the fit has to be measured through it as well.
          textScaler: MediaQuery.textScalerOf(context),
        );

        // Replaced outright rather than faded in. A transition here would be
        // the only moving thing on an otherwise still card, and it would be
        // moving exactly when the user has just asked to *read* something.
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

/// No birthday, and the one action that fixes it.
///
/// The one state on this card the user can act on, and the reason it says
/// anything at all instead of sitting blank. The button goes through
/// [SettingsController] — the seam the desktop's own "Change background…" and
/// "Desktop settings…" menu items already use, because the settings overlay is
/// a root-owned window and nothing on the background surface may open one
/// directly.
class _NoBirthday extends StatelessWidget {
  const _NoBirthday({required this.scale});

  final _CardScale scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SkyText(
          'Set your birthday to see your sign',
          size: scale(ShellFontSizes.secondary),
          weight: FontWeight.w500,
          maxLines: 2,
        ),
        SizedBox(height: scale(8)),
        _ActionButton(
          label: 'Set birthday…',
          onTap: () =>
              SettingsController.instance.open(SettingsRoute.astrology),
          scale: scale,
        ),
      ],
    );
  }
}

/// A sign, but no paragraph for it.
class _NoHoroscope extends StatelessWidget {
  const _NoHoroscope({
    required this.error,
    required this.onRetry,
    required this.scale,
  });

  final String error;
  final VoidCallback onRetry;
  final _CardScale scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SkyText(
          error.isEmpty ? 'No horoscope yet' : error,
          size: scale(ShellFontSizes.secondary),
          muted: true,
          maxLines: 2,
        ),
        SizedBox(height: scale(8)),
        // Offered because every failure here is recoverable without restarting
        // the shell — the network comes back, the server stops rate-limiting —
        // and the shell cannot detect either happening. A tap, not a pan: the
        // card is dragged from anywhere on it and the two recognizers resolve
        // against each other.
        _ActionButton(label: 'Retry', onTap: onRetry, scale: scale),
      ],
    );
  }
}

/// The card's one text action — "Retry" over a failure, "Set birthday…" over
/// the empty state.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    required this.scale,
  });

  final String label;
  final VoidCallback onTap;
  final _CardScale scale;

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: scale(12),
          vertical: scale(6),
        ),
        decoration: BoxDecoration(
          color: kSkyForeground.withValues(alpha: hovered ? 0.28 : 0.16),
          borderRadius: BorderRadius.circular(ShellRadii.pill),
          border: Border.all(color: kSkyHairline),
        ),
        child: _SkyText(
          label,
          size: scale(ShellFontSizes.caption),
          weight: FontWeight.w500,
          tracking: 0.3,
        ),
      ),
    );
  }
}

/// Which horoscope this is, and whose words they are.
///
/// The attribution is not optional chrome that happened to land here: the
/// paragraph above it is somebody else's copy, fetched from a server the shell
/// does not run. `_Chrome` may drop this line on a card with no room for it,
/// and on such a card there is no paragraph either — the floor it admits
/// against is two lines of one.
class _Footer extends StatelessWidget {
  const _Footer({required this.store, required this.scale});

  final AstrologyStore store;
  final _CardScale scale;

  @override
  Widget build(BuildContext context) {
    final reading = store.reading;
    final parts = <String>[
      store.period.label,
      if (reading != null && reading.date.isNotEmpty) reading.date,
      if (reading != null) kHoroscopeAttribution,
    ];
    return _SkyText(
      parts.join(' · '),
      size: scale(ShellFontSizes.caption),
      faint: true,
    );
  }
}

/// One line of the card's chrome. The horoscope itself does not go through this
/// — its size is measured rather than named.
class _SkyText extends StatelessWidget {
  const _SkyText(
    this.text, {
    required this.size,
    this.weight = FontWeight.w400,
    this.muted = false,
    this.faint = false,
    this.tracking,
    this.maxLines = 1,
  });

  final String text;
  final double size;
  final FontWeight weight;
  final bool muted;
  final bool faint;
  final double? tracking;
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
        letterSpacing: tracking,
        color: faint
            ? kSkyFaintForeground
            : muted
                ? kSkyMutedForeground
                : kSkyForeground,
        shadows: kSkyTextShadows,
      ),
    );
  }
}

/// The "Add widget…" menu's icon for this type. Named so a test can build a
/// [DesktopWidgetSpec] without picking an unrelated glyph.
///
/// Dots joined by lines: the menu entry is a small constellation, which is what
/// the card is. Deliberately not one of Font Awesome's actual zodiac-adjacent
/// glyphs — they are religious symbols, and the wand this file's neighbour took
/// is the fortune widget's.
const FaIconData astrologyDesktopWidgetIcon = FontAwesomeIcons.circleNodes;

/// The registry entry. Registered from `main()` beside the fortune widget's.
final DesktopWidgetSpec astrologyDesktopWidget = DesktopWidgetSpec(
  type: 'astrology',
  name: 'Astrology',
  description: "Your sign, its constellation, and today's horoscope",
  icon: astrologyDesktopWidgetIcon,
  // Two cells wide is the floor the other picture-backed widgets take: one cell
  // is an icon, and there is no width of paragraph in it. The default is larger
  // than the floor deliberately — a horoscope is forty words, and 3x2 is the
  // smallest span that sets them at a size worth reading with the chart still
  // legible behind.
  minSpan: (columns: 2, rows: 1),
  maxSpan: (columns: 6, rows: 4),
  defaultSpan: (columns: 3, rows: 2),
  // The sky and its constellation are the card, the way the weather widget's
  // sky is.
  padding: EdgeInsets.zero,
  builder: (context, widget) => AstrologyWidget(span: widget.span),
);
