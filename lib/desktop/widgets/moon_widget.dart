// The lunar desktop widget: what the Moon looks like tonight, and what it is
// doing to the world while it does.
//
// The third entry in `DesktopWidgetRegistry`, and built the way the weather
// widget is: a lease on a store nobody owns, a picture painted to the rim of a
// card with no padding, and white text on it rather than the theme's — the
// backdrop runs from a starlit indigo to the glare beside a full Moon, and the
// call is the one the weather widget and the lock screen both make.
//
// Two things that are its own:
//
// - **There is no loading state, and there is no error state.** The phase is
//   arithmetic over the current time; the widget can always draw. What can be
//   missing is the *location*, and the only thing that costs is the rise and
//   set times — so that is the one row that has something else to say.
// - **The location is the weather module's.** `[modules.weather] location`, or
//   whatever the weather has already resolved, or one IP lookup shared with it
//   (`WeatherStore.resolvePlace`). Setting a place for the weather sets it for
//   the Moon, which is the only behaviour that would not surprise somebody.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:graceful_shell/desktop/desktop_layout.dart' show GridSpan;
import 'package:graceful_shell/desktop/widgets/desktop_widget.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/moon/moon_facts.dart';
import 'package:graceful_shell/moon/moon_format.dart';
import 'package:graceful_shell/moon/moon_phase.dart';
import 'package:graceful_shell/moon/moon_render.dart';
import 'package:graceful_shell/moon/moon_store.dart';
import 'package:graceful_shell/theme/tokens.dart';
// The place marker and the three tokens for text over a picture. Both live
// beside the weather because that is where the first surface needing them was;
// nothing about either is about the weather. `WeatherIcon` is deliberately not
// borrowed with them — it draws Meteocons now, which is a weather set with no
// glyph for anything on this card.
import 'package:graceful_shell/weather/weather_icons.dart' show kLocationIcon;
import 'package:graceful_shell/weather/weather_sky.dart'
    show kSkyForeground, kSkyMutedForeground, kSkyTextShadows;

/// The smallest box each layout draws in — content measurements, not cell
/// counts, because a cell is configurable down to 32px and the content is not.
const double _minWidth = 150;
const double _minHeight = 64;
const double _expandedMinHeight = 128;
const double _timesMinHeight = 150;
const double _factsMinHeight = 210;
const double _factDetailMinWidth = 230;

/// One fact, as a heading and a sentence.
const double _factRowHeight = 46;

/// One fact, as a heading alone — what a card too short for the sentences
/// falls back to.
const double _factTitleHeight = 21;

/// The widget's body. Store-injectable so a widget test can drive it with a
/// fixed instant and a fixed place, and with nothing behind either.
class MoonWidget extends StatefulWidget {
  MoonWidget({super.key, required this.span, MoonStore? store})
      : store = store ?? MoonStore.instance;

  /// The widget's size in cells.
  final GridSpan span;

  final MoonStore store;

  @override
  State<MoonWidget> createState() => _MoonWidgetState();
}

class _MoonWidgetState extends State<MoonWidget> {
  @override
  void initState() {
    super.initState();
    widget.store.acquire();
    widget.store.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(MoonWidget oldWidget) {
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
    final reading = store.reading;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Laid out at its own minimum and clipped when the grid gives it less —
        // the media and weather widgets' rule. The alternative is a flex
        // overflow reported every frame on a surface whose console nobody
        // reads.
        final width = math.max(constraints.maxWidth, _minWidth);
        final height = math.max(constraints.maxHeight, _minHeight);
        final expanded = widget.span.rows >= 2 && height >= _expandedMinHeight;

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
                MoonNightSky(illumination: reading.illumination),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: expanded
                      ? _ExpandedLayout(
                          store: store,
                          reading: reading,
                          // Independent decisions, all about pixels rather than
                          // cells: three columns on a 48px grid is narrower
                          // than two on a 120px one.
                          showTimes: height >= _timesMinHeight,
                          showFacts: height >= _factsMinHeight,
                          detailedFacts: width >= _factDetailMinWidth,
                          discSize: (height * 0.34).clamp(48.0, 104.0),
                        )
                      : _CompactLayout(
                          reading: reading,
                          // The card's own padding, subtracted: the disc is a
                          // fixed square inside a row, so a box shorter than it
                          // is a flex overflow rather than a smaller Moon.
                          discSize: (height - 24).clamp(20.0, 46.0),
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

/// The 2x1 layout: the disc, the phase, and how lit it is.
class _CompactLayout extends StatelessWidget {
  const _CompactLayout({required this.reading, required this.discSize});

  final MoonReading reading;
  final double discSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: discSize,
          height: discSize,
          child: MoonDisc(
            illumination: reading.illumination,
            waxing: reading.waxing,
            southernView: reading.southernView,
            // No room for a halo to fall off in; it would read as a smudge.
            glow: false,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _MoonText(
                reading.phase.label,
                size: ShellFontSizes.label,
                weight: FontWeight.w600,
              ),
              _MoonText(
                '${reading.illuminationPercent}% lit',
                size: ShellFontSizes.caption,
                muted: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Two rows or taller: the place, the disc at size, the phase, tonight's rise
/// and set, and as much consequence as the card has room for.
class _ExpandedLayout extends StatelessWidget {
  const _ExpandedLayout({
    required this.store,
    required this.reading,
    required this.showTimes,
    required this.showFacts,
    required this.detailedFacts,
    required this.discSize,
  });

  final MoonStore store;
  final MoonReading reading;
  final bool showTimes;
  final bool showFacts;
  final bool detailedFacts;
  final double discSize;

  @override
  Widget build(BuildContext context) {
    final place = store.place;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (place != null)
          Row(
            children: [
              const _MoonIcon(kLocationIcon, size: 12),
              const SizedBox(width: 4),
              Expanded(
                child: _MoonText(
                  place.name,
                  size: ShellFontSizes.caption,
                  muted: true,
                ),
              ),
            ],
          ),
        const SizedBox(height: 6),
        // Centred in what is left when there are no facts under it: the card
        // is a picture with a readout on it, and a readout pinned to the top of
        // a tall empty sky reads as a layout that ran out rather than one that
        // fits.
        if (!showFacts) const Spacer(flex: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: discSize,
              height: discSize,
              child: MoonDisc(
                illumination: reading.illumination,
                waxing: reading.waxing,
                southernView: reading.southernView,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MoonText(
                    reading.phase.label,
                    size: ShellFontSizes.title,
                    weight: FontWeight.w600,
                  ),
                  _MoonText(
                    '${reading.illuminationPercent}% lit · '
                    'day ${reading.ageDays.floor()} of 29',
                    size: ShellFontSizes.caption,
                    muted: true,
                  ),
                  if (showTimes) ...[
                    const SizedBox(height: 6),
                    _TimesRow(store: store, reading: reading),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (showFacts) ...[
          const SizedBox(height: 10),
          Expanded(
            child: _Facts(
              facts: moonFacts(reading),
              detailed: detailedFacts,
            ),
          ),
        ] else
          const Spacer(flex: 4),
      ],
    );
  }
}

/// Tonight's moonrise and moonset — or, when there is none of either, which of
/// the two reasons that is.
class _TimesRow extends StatelessWidget {
  const _TimesRow({required this.store, required this.reading});

  final MoonStore store;
  final MoonReading reading;

  @override
  Widget build(BuildContext context) {
    final times = store.times;

    if (times == null) {
      if (store.locating) {
        return const Row(
          children: [
            LoadingIndicator(color: kSkyMutedForeground, size: 11),
            SizedBox(width: 6),
            // Expanded, not a bare `Text`: this row shares a column with a
            // disc whose size follows the card's, so how much is left for it is
            // not something the string can be written to fit.
            Expanded(
              child: _MoonText(
                'Finding your location',
                size: ShellFontSizes.caption,
                muted: true,
              ),
            ),
          ],
        );
      }
      // Not an error — the phase and everything derived from it is unaffected,
      // and the row says what would be gained rather than what went wrong.
      return const _MoonText(
        'Set a weather location for rise and set times',
        size: ShellFontSizes.caption,
        muted: true,
        maxLines: 2,
      );
    }

    if (times.alwaysUp) {
      return const _MoonText(
        'Up all day and all night',
        size: ShellFontSizes.caption,
        muted: true,
      );
    }
    if (times.alwaysDown) {
      return const _MoonText(
        'Below the horizon all day',
        size: ShellFontSizes.caption,
        muted: true,
      );
    }

    return Row(
      children: [
        Flexible(
          child: _TimeCell(
            icon: Symbols.arrow_upward,
            label: times.rise == null ? '—' : formatMoonTime(times.rise!),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: _TimeCell(
            icon: Symbols.arrow_downward,
            label: times.set == null ? '—' : formatMoonTime(times.set!),
          ),
        ),
      ],
    );
  }
}

class _TimeCell extends StatelessWidget {
  const _TimeCell({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MoonIcon(icon, size: 12),
        const SizedBox(width: 4),
        Flexible(child: _MoonText(label, size: ShellFontSizes.caption)),
      ],
    );
  }
}

/// As many facts as fit, in the order [moonFacts] returned them.
///
/// The count is arithmetic against the height the column has left rather than
/// a scroll view: a desktop widget is dragged from anywhere on its card, and a
/// vertical scroller inside one would be a pan recognizer fighting the drag —
/// the rule the media widget's buttons are allowed by, and a slider would not
/// be.
class _Facts extends StatelessWidget {
  const _Facts({required this.facts, required this.detailed});

  final List<MoonFact> facts;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    if (facts.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final rowHeight = detailed ? _factRowHeight : _factTitleHeight;
        final fits = (constraints.maxHeight / rowHeight).floor();
        final count = fits.clamp(0, facts.length);
        if (count == 0) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final fact in facts.take(count))
              SizedBox(
                height: rowHeight,
                child: _FactRow(fact: fact, detailed: detailed),
              ),
          ],
        );
      },
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.fact, required this.detailed});

  final MoonFact fact;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: _MoonIcon(
            _factIcon(fact.kind),
            size: 13,
            bright: fact.notable,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _MoonText(
                fact.title,
                size: ShellFontSizes.caption,
                weight: fact.notable ? FontWeight.w600 : FontWeight.w500,
              ),
              if (detailed)
                _MoonText(
                  fact.detail,
                  size: 10,
                  muted: true,
                  maxLines: 2,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The glyph for a fact kind. The mapping lives here rather than on
/// [MoonFactKind] so `moon_facts.dart` stays Flutter-free and its wording stays
/// a plain unit test.
IconData _factIcon(MoonFactKind kind) => switch (kind) {
      MoonFactKind.tides => Symbols.waves,
      MoonFactKind.nightLight => Symbols.nightlight,
      MoonFactKind.stargazing => Symbols.star,
      MoonFactKind.eclipse => Symbols.dark_mode,
      MoonFactKind.distance => Symbols.straighten,
      MoonFactKind.nextPhase => Symbols.schedule,
    };

/// One glyph of the readout, at the fill and weight a Material Symbol needs to
/// read at these sizes.
///
/// Spelled here rather than borrowed from `weather_icons.dart`: that wrapper
/// draws Meteocons now, which is a weather set — it has no moon-rise arrow, no
/// wave and no ruler, and its own author's note says the place marker beside
/// the weather is a plain [Icon] for the same reason.
class _MoonIcon extends StatelessWidget {
  const _MoonIcon(this.icon, {required this.size, this.bright = false});

  final IconData icon;
  final double size;

  /// Full foreground rather than the muted one — what a notable fact's glyph
  /// takes.
  final bool bright;

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size,
      color: bright ? kSkyForeground : kSkyMutedForeground,
      fill: 0.7,
      weight: 500,
      opticalSize: 20,
      shadows: kSkyTextShadows,
    );
  }
}

/// One line of the readout: white, shadowed, ellipsised. The moon's copy of the
/// weather widget's `_SkyText`, for the same reason — the card is a picture and
/// no theme foreground is legible across the whole of it.
class _MoonText extends StatelessWidget {
  const _MoonText(
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
        height: 1.25,
        color: muted ? kSkyMutedForeground : kSkyForeground,
        shadows: kSkyTextShadows,
      ),
    );
  }
}

/// The "Add widget…" menu's icon for this type. Named so a test can build a
/// [DesktopWidgetSpec] without picking an unrelated glyph.
const FaIconData moonDesktopWidgetIcon = FontAwesomeIcons.moon;

/// The registry entry. Registered from `main()` beside the weather widget's.
final DesktopWidgetSpec moonDesktopWidget = DesktopWidgetSpec(
  type: 'moon_phase',
  name: 'Moon phase',
  description: 'Tonight\'s Moon, and what it is pulling on',
  icon: moonDesktopWidgetIcon,
  // Two cells wide is the floor for the weather widget's reason: one cell is an
  // icon, and a phase name beside a disc does not fit in the width of a
  // launcher tile. The default is larger than the floor deliberately — 3x2 is
  // the smallest span that carries the disc at a size worth looking at, the
  // rise and set times, and a line of consequence under them.
  minSpan: (columns: 2, rows: 1),
  maxSpan: (columns: 6, rows: 4),
  defaultSpan: (columns: 3, rows: 2),
  // The night sky is the card, the way the weather widget's sky is.
  padding: EdgeInsets.zero,
  builder: (context, widget) => MoonWidget(span: widget.span),
);
