// The weather desktop widget: the reading, over a picture of the sky it
// describes.
//
// The second entry in `DesktopWidgetRegistry`, reading exactly what the bar
// module reads — `WeatherStore`, leased. Neither surface owns the fetch.
//
// Five things about it:
//
// - **Nothing on this card moves** — see `weather_sky.dart`'s header. A tree
//   containing this may be `pumpAndSettle`ed.
// - **The card is the sky, so the frame gives it no padding.** Its
//   `DesktopWidgetSpec` asks for `EdgeInsets.zero` and the content carries its
//   own insets; `PopupCard` clips to the theme's radius.
// - **There is no hero glyph.** The expanded layout used to set a 58px Meteocon
//   beside the temperature — a drawn sun over a sky already drawing one. The sky
//   is the condition's picture and the label under the reading is its name; the
//   small tinted glyphs survive in the detail row and forecast strip. The
//   compact layout keeps its icon, because at 2x1 there is no sky to read.
// - **The text is white on a scrim, not on the theme.** The palettes run from a
//   near-black thunderstorm to an almost-white snowfall, and no theme foreground
//   is legible on both.
// - **Every size is one table times one factor, and what fits is *measured*.**
//   This is the only widget the user resizes, in a grid whose cell size they
//   also choose (see [_CardScale]), so a literal or a pixel threshold chosen
//   against one card is wrong on every other. [_Sections] answers how tall each
//   block is at the size it will be set in, and the layout takes blocks in
//   priority order until the next will not fit — which is what lets the column
//   use plain `SizedBox` slack rather than `Spacer`s.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/desktop/desktop_layout.dart' show GridSpan;
import 'package:moonswing/desktop/widgets/desktop_widget.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/weather/weather_api.dart';
import 'package:moonswing/weather/weather_condition.dart';
import 'package:moonswing/weather/weather_icons.dart';
import 'package:moonswing/weather/weather_sky.dart';
import 'package:moonswing/weather/weather_store.dart';

/// The smallest box each layout draws in. Content measurements, not cell
/// counts: a cell is configurable down to 32px and the content is not.
const double _minWidth = 150;
const double _minHeight = 64;
const double _expandedMinHeight = 128;

/// The narrowest card a forecast strip is drawn on. The one dimension still
/// decided by a threshold rather than by [_Sections], because a strip's problem
/// is horizontal: three columns under a card this narrow is not a smaller
/// forecast but an unreadable one.
const double _forecastMinWidth = 250;

/// The card every base size below was chosen against: the registry's own
/// `defaultSpan` of 3x2 on the default grid — `cellWidth`/`cellHeight` 96 with
/// `spacing` 12, so `3*96 + 2*12` by `2*96 + 12`.
const Size _referenceCard = Size(312, 204);

/// The card's inner inset, at [_referenceCard].
const double _basePadding = 13;

/// How far the type is allowed to grow. `maxSpan` is 6x4, which on the default
/// grid asks for about 1.51 — so nothing the registry permits is clamped by
/// this, and it is here for the grid whose cell size the user has set large.
const double _maxScale = 1.6;

/// How much of the card's growth the type takes. See [_CardScale] — this is the
/// number that decides whether a bigger card means *more* or merely *larger*,
/// and 1.0 means only ever larger.
const double _scaleExponent = 0.6;

// The type table, at [_referenceCard]. Every size on the card is one of these
// through [_CardScale]; a literal that is not is a bug waiting for the user to
// drag a corner.
const double _placeSize = ShellFontSizes.caption;
const double _placeIconSize = 13;
const double _placeGap = 8;
const double _temperatureSize = 36;
const double _conditionSize = ShellFontSizes.label;
const double _highLowSize = ShellFontSizes.caption;
const double _detailIconSize = 17;
const double _detailTextSize = ShellFontSizes.caption;
const double _forecastLabelSize = ShellFontSizes.caption;
const double _forecastIconSize = 20;
const double _forecastTempSize = ShellFontSizes.caption;

/// The air between a forecast column's three lines.
const double _forecastGap = 3;

/// The gap above and below a hairline rule.
const double _ruleGapAbove = 8;
const double _ruleGapBelow = 6;

/// What a line of text occupies beyond its font size. A little over what the
/// shell's own font does (Roboto's ascent and descent come to about 1.17), so
/// that a theme naming a face with taller metrics costs a pixel of clipping
/// rather than a section that should have been shed.
const double _lineFactor = 1.32;

/// The same, for the temperature — one line of digits, no descenders.
const double _temperatureLineFactor = 1.15;

/// The slack a section has to clear before it is drawn, on top of its own
/// measured height. Absorbs the difference between [_lineFactor] and whatever
/// the theme's font actually does.
const double _fitMargin = 5;

/// The card's type and icon scale.
///
/// Every size used to be a literal chosen against [_referenceCard], so a user who
/// dragged the widget to 6x4 got the same 10px day labels in four times the area.
/// The sizes are now that table multiplied by one factor derived from the box the
/// grid handed the card.
///
/// It starts from the **geometric mean** of the two edge ratios rather than
/// either alone: a card stretched wide but left one row tall has no more room for
/// bigger type, and taking the wider edge would set it in a size its height
/// cannot carry.
///
/// It then takes that to [_scaleExponent], which is the difference between a card
/// that shows *more* and a photographic enlargement of the small one: the
/// geometric mean **is** the linear scale, so applying it exactly is the one law
/// under which nothing new can ever fit however far the widget is dragged out.
///
/// And it never goes **below 1** — the literals are a floor, and a card smaller
/// than the reference is already laid out at its own minimum and clipped.
class _CardScale {
  const _CardScale(this.factor);

  factory _CardScale.forBox(double width, double height) {
    final linear = math.sqrt(
      (width / _referenceCard.width) * (height / _referenceCard.height),
    );
    final ratio = math.pow(linear, _scaleExponent).toDouble();
    return _CardScale(ratio.clamp(1.0, _maxScale));
  }

  final double factor;

  /// [base] — a size read off the table above — at this card's size.
  double call(double base) => base * factor;
}

/// How tall each block of the expanded card is, at the size it will be set in.
///
/// The layout used to decide what to draw from pixel thresholds, which were only
/// ever right for one type size and one font and quietly disagreed about the
/// order things were shed in. This is the same arithmetic the layout is about to
/// perform, done once in advance.
class _Sections {
  const _Sections(this.scale, this.textScaler);

  final _CardScale scale;

  /// The theme's `font_size`, which reaches this card's [Text] widgets through
  /// the ambient scaler rather than through their styles — so a block's height
  /// has to be asked for through it too, or the card sheds nothing as the type
  /// grows and simply clips the last section it drew.
  final TextScaler textScaler;

  /// A size off the table above, at this card's size *and* the theme's. The
  /// icon sizes deliberately do not go through it: an icon is not type, and
  /// [WeatherIcon] draws at the size it is given.
  double _text(double base) => textScaler.scale(scale(base));

  double get place =>
      math.max(scale(_placeIconSize), _text(_placeSize) * _lineFactor) +
      scale(_placeGap);

  double get temperature => _text(_temperatureSize) * _temperatureLineFactor;

  double get condition => _text(_conditionSize) * _lineFactor;

  double get highLow => _text(_highLowSize) * _lineFactor + scale(2);

  double get details =>
      _rule +
      math.max(scale(_detailIconSize), _text(_detailTextSize) * _lineFactor);

  double get forecast =>
      _rule +
      _text(_forecastLabelSize) * _lineFactor +
      scale(_forecastGap) +
      scale(_forecastIconSize) +
      scale(_forecastGap) +
      _text(_forecastTempSize) * _lineFactor;

  /// A hairline and the air either side of it.
  double get _rule => scale(_ruleGapAbove) + 1 + scale(_ruleGapBelow);
}

/// The widget's body. Public and store-injectable so a widget test can seed a
/// reading and pump it with nothing behind it.
class WeatherWidget extends StatefulWidget {
  WeatherWidget({super.key, required this.span, WeatherStore? store})
    : store = store ?? WeatherStore.instance;

  /// The widget's size in cells. Two wide by one is the minimum, and the
  /// compact layout is what everything else is derived from.
  final GridSpan span;

  final WeatherStore store;

  @override
  State<WeatherWidget> createState() => _WeatherWidgetState();
}

class _WeatherWidgetState extends State<WeatherWidget> {
  @override
  void initState() {
    super.initState();
    widget.store.acquire();
    widget.store.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(WeatherWidget oldWidget) {
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
    final reading = store.current;

    // With no reading there is still a card on the desktop, so there is still a
    // sky: an even, mainly-clear one, which says "nothing to report" without
    // pretending to a forecast the shell does not have.
    final condition = reading?.condition ?? conditionForCode(1);
    final cover = reading?.cloudCover ?? 0.25;
    final night = reading != null && !reading.isDay;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Laid out at its own minimum and clipped when the grid gives it less,
        // the media widget's rule: the alternative is a flex overflow reported
        // every frame on a surface whose console nobody is reading.
        final width = math.max(constraints.maxWidth, _minWidth);
        final height = math.max(constraints.maxHeight, _minHeight);
        final expanded = widget.span.rows >= 2 && height >= _expandedMinHeight;
        final scale = _CardScale.forBox(width, height);

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
                WeatherSky(
                  condition: condition,
                  cloudCover: cover,
                  night: night,
                ),
                const SkyScrim(),
                Padding(
                  // The inset grows with the type it surrounds; a 24px readout
                  // pressed against a 12px rim reads as a layout accident.
                  padding: EdgeInsets.all(scale(_basePadding)),
                  child: _content(
                    store: store,
                    reading: reading,
                    expanded: expanded,
                    scale: scale,
                    textScaler: MediaQuery.textScalerOf(context),
                    width: width,
                    height: height,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _content({
    required WeatherStore store,
    required WeatherReading? reading,
    required bool expanded,
    required _CardScale scale,
    required TextScaler textScaler,
    required double width,
    required double height,
  }) {
    if (reading == null) {
      return _NoReading(
        loading: store.loading,
        error: store.error,
        onRetry: store.refresh,
        scale: scale,
      );
    }
    if (!expanded) {
      // Centred: a `Row` takes its cross-axis size from its tallest child, so
      // left to itself the compact reading sits against the top of a card the
      // user has made taller than one row of content.
      return Center(
        child: _CompactLayout(store: store, reading: reading, scale: scale),
      );
    }

    // What fits, in the order the card gives things up. The forecast strip goes
    // first — most height for the least often wanted answer — then the day's high
    // and low; the detail row survives longest, because "what does it feel like
    // out there" is what somebody puts a weather widget on their desktop for.
    final sections = _Sections(scale, textScaler);
    final place = store.place;
    final forecast = store.forecast;
    final margin = scale(_fitMargin);

    var used = sections.temperature + sections.condition;
    if (place != null) used += sections.place;

    final showDetails =
        used + sections.details + margin <= _available(height, scale);
    if (showDetails) used += sections.details;

    final showHighLow =
        forecast.isNotEmpty &&
        used + sections.highLow + margin <= _available(height, scale);
    if (showHighLow) used += sections.highLow;

    final showForecast =
        width >= _forecastMinWidth &&
        forecast.length > 1 &&
        used + sections.forecast + margin <= _available(height, scale);
    if (showForecast) used += sections.forecast;

    return _ExpandedLayout(
      store: store,
      reading: reading,
      scale: scale,
      sections: sections,
      slack: math.max(0, _available(height, scale) - used),
      showDetails: showDetails,
      showHighLow: showHighLow,
      showForecast: showForecast,
      forecastDays: _forecastDays(width, scale, textScaler),
    );
  }

  /// The height the content column actually gets, inside the card's own inset.
  double _available(double height, _CardScale scale) =>
      height - 2 * scale(_basePadding);

  /// How many days fit across [width]. Each column needs about 48px at
  /// [_referenceCard], and that budget scales with the type — or a card twice the
  /// size would answer "twice as many days" rather than "the same days,
  /// legibly". Fewer days is better than a strip of clipped ones.
  int _forecastDays(double width, _CardScale scale, TextScaler textScaler) {
    final content = width - 2 * scale(_basePadding);
    // Through the text scaler as well: the budget is mostly the day label and
    // the temperature under it, so a theme set two sizes up needs the same
    // column wider rather than the same number of narrower ones.
    return (content / textScaler.scale(scale(48))).floor().clamp(0, 7);
  }
}

/// Before the first reading, or after a failure with nothing cached.
class _NoReading extends StatelessWidget {
  const _NoReading({
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.scale,
  });

  final bool loading;
  final String error;
  final VoidCallback onRetry;
  final _CardScale scale;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
        child: LoadingIndicator(color: kSkyForeground, size: scale(18)),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SkyText(
            error.isEmpty ? 'No weather yet' : error,
            size: scale(ShellFontSizes.secondary),
            muted: true,
            align: TextAlign.center,
            maxLines: 2,
          ),
          SizedBox(height: scale(10)),
          // A tap, not a pan: the card is dragged from anywhere on it, and the
          // two recognizers resolve against each other — a press that moves is
          // the drag, one that does not is this. `desktop_widget_grid_test`
          // pins both halves for the media widget's buttons.
          _RetryButton(onTap: onRetry, scale: scale),
        ],
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onTap, required this.scale});

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
          color: const Color(
            0xFFFFFFFF,
          ).withValues(alpha: hovered ? 0.28 : 0.16),
          borderRadius: BorderRadius.circular(ShellRadii.pill),
          border: Border.all(color: kSkyHairline),
        ),
        child: _SkyText(
          'Retry',
          size: scale(ShellFontSizes.caption),
          weight: FontWeight.w500,
          tracking: 0.3,
        ),
      ),
    );
  }
}

/// The 2x1 layout: a glyph, the temperature, and what it is doing.
///
/// The one layout that keeps an icon: at two cells by one the sky behind it is a
/// strip barely taller than the text, so the glyph *is* the condition here.
class _CompactLayout extends StatelessWidget {
  const _CompactLayout({
    required this.store,
    required this.reading,
    required this.scale,
  });

  final WeatherStore store;
  final WeatherReading reading;
  final _CardScale scale;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        WeatherIcon(
          weatherIcon(reading.condition, night: !reading.isDay),
          size: scale(38),
        ),
        SizedBox(width: scale(10)),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _SkyText(
                store.temperatureText,
                size: scale(ShellFontSizes.title),
                weight: FontWeight.w300,
              ),
              _SkyText(
                reading.condition.label,
                size: scale(ShellFontSizes.caption),
                muted: true,
                tracking: 0.2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Two rows or taller: the place along the top, the reading set large in the
/// lower half, and — as the card grows — the day's detail and a forecast strip.
///
/// The composition is the sky's. `kCelestialCentre` puts the sun or moon at 0.78
/// of the width and 0.27 of the height, so the top-right is the one part that is
/// never text; the place name runs along the top-left and everything else is
/// anchored to the bottom, where `SkyScrim` is darkest.
class _ExpandedLayout extends StatelessWidget {
  const _ExpandedLayout({
    required this.store,
    required this.reading,
    required this.scale,
    required this.sections,
    required this.slack,
    required this.showDetails,
    required this.showHighLow,
    required this.showForecast,
    required this.forecastDays,
  });

  final WeatherStore store;
  final WeatherReading reading;
  final _CardScale scale;
  final _Sections sections;

  /// The height left over once every section that fits has been accounted for.
  /// Distributed as plain gaps rather than handed to `Spacer`s, so a section
  /// can never be squeezed below the height it was measured at.
  final double slack;

  final bool showDetails;
  final bool showHighLow;
  final bool showForecast;
  final int forecastDays;

  @override
  Widget build(BuildContext context) {
    final place = store.place;
    final forecast = store.forecast;

    // Unbounded vertically: the belt to [_Sections]' braces. The fit arithmetic
    // gets each block's height right to a pixel or two, and this makes that pixel
    // or two cost a clipped row of anti-aliasing rather than a flex overflow
    // reported every frame. Only this layout needs it — the compact and
    // no-reading ones centre themselves in the box.
    return OverflowBox(
      alignment: Alignment.topLeft,
      minHeight: 0,
      maxHeight: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (place != null) ...[
            Row(
              children: [
                // The one Material Symbol on this card: Meteocons is a weather
                // set and has no place marker. See `kLocationIcon`.
                Icon(
                  kLocationIcon,
                  size: scale(_placeIconSize),
                  color: kSkyMutedForeground,
                  fill: 0.7,
                  weight: 500,
                  shadows: kSkyTextShadows,
                ),
                SizedBox(width: scale(4)),
                Expanded(
                  child: _SkyText(
                    place.name,
                    size: scale(_placeSize),
                    weight: FontWeight.w500,
                    muted: true,
                    // Set wide, the way a caption over a picture is. It is the
                    // one line on the card that is a label rather than a reading.
                    tracking: 0.6,
                  ),
                ),
              ],
            ),
            SizedBox(height: scale(_placeGap)),
          ],
          // Most of the slack above the reading, so it sits low on the card with
          // the sky open above it; the rest under, so the rule below is not
          // pinned to the last line of text.
          SizedBox(height: slack * 0.72),
          _SkyText(
            store.temperatureText,
            size: scale(_temperatureSize),
            // Light and tight: a large number set at the body weight is the
            // difference between a display face and a heading.
            weight: FontWeight.w200,
            tracking: -0.5,
          ),
          _SkyText(
            reading.condition.label,
            size: scale(_conditionSize),
            weight: FontWeight.w500,
            tracking: 0.2,
          ),
          if (showHighLow && forecast.isNotEmpty) ...[
            SizedBox(height: scale(2)),
            _SkyText(
              'H ${forecast.first.tempMax.round()}°   '
              'L ${forecast.first.tempMin.round()}°',
              size: scale(_highLowSize),
              muted: true,
              tracking: 0.3,
            ),
          ],
          SizedBox(height: slack * 0.28),
          if (showDetails) ...[
            _Rule(scale: scale),
            _DetailRow(reading: reading, unit: store.unitLabel, scale: scale),
          ],
          if (showForecast && forecast.length > 1) ...[
            _Rule(scale: scale),
            _ForecastStrip(
              // Today is already spelled out above, in three times the size.
              days: forecast.skip(1).take(forecastDays).toList(),
              scale: scale,
            ),
          ],
        ],
      ),
    );
  }
}

/// The hairline the card rules its sections off with, and the air either side.
///
/// Its height is [_Sections._rule] exactly; the two have to move together or
/// the fit arithmetic is a guess.
class _Rule extends StatelessWidget {
  const _Rule({required this.scale});

  final _CardScale scale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: scale(_ruleGapAbove),
        bottom: scale(_ruleGapBelow),
      ),
      child: const SizedBox(
        width: double.infinity,
        height: 1,
        child: ColoredBox(color: kSkyHairline),
      ),
    );
  }
}

/// Feels-like, humidity and wind — each dropped rather than truncated when the
/// reading does not carry it, or the card is not wide enough.
///
/// The shed order is deliberate: wind before humidity before feels-like, because
/// feels-like is the one somebody glances at a weather widget for. And it
/// **measures** rather than counting characters — the `TrackMarquee` discipline:
/// the same three readings fit at one theme's font and overflow at another's. The
/// measurement is taken at the card's own scale.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.reading,
    required this.unit,
    required this.scale,
  });

  final WeatherReading reading;
  final String unit;
  final _CardScale scale;

  /// The glyph, the gap, and the padding after each detail — everything in a
  /// [_Detail] that is not its text, at [_referenceCard].
  static const double _baseChrome = _detailIconSize + 5 + 14;

  @override
  Widget build(BuildContext context) {
    final feels = reading.apparentTemperature;
    final humidity = reading.humidity;
    final wind = reading.windSpeed;

    final candidates = <(WeatherGlyph, String)>[
      if (feels != null) (kFeelsLikeIcon, '${feels.round()}$unit'),
      if (humidity != null) (kHumidityIcon, '$humidity%'),
      if (wind != null) (kWindIcon, '${wind.round()} ${_windUnit(unit)}'),
    ];
    if (candidates.isEmpty) return const SizedBox.shrink();

    final fontSize = scale(_detailTextSize);
    final chrome = scale(_baseChrome);

    return LayoutBuilder(
      builder: (context, constraints) {
        var used = 0.0;
        final shown = <(WeatherGlyph, String)>[];
        for (final candidate in candidates) {
          final width =
              _measureText(context, candidate.$2, fontSize) + chrome;
          // Break rather than continue: the priority order is the drop order,
          // and skipping a wide reading to fit a narrow one after it would
          // leave the wind on screen with the feels-like missing.
          if (used + width > constraints.maxWidth) break;
          used += width;
          shown.add(candidate);
        }
        if (shown.isEmpty) return const SizedBox.shrink();

        return Row(
          children: [
            for (final detail in shown)
              // Flexible over the measured decision, not instead of it: the
              // measurement is a text layout and the row is a flex, and this
              // is what turns any disagreement between them into an ellipsis
              // rather than an assertion.
              Flexible(
                child: _Detail(icon: detail.$1, value: detail.$2, scale: scale),
              ),
          ],
        );
      },
    );
  }

  /// Open-Meteo reports wind in the unit system the temperature was asked for:
  /// mph alongside Fahrenheit, km/h alongside Celsius. Labelling it from the
  /// degree suffix is what keeps the two in step without a second request
  /// parameter to remember.
  static String _windUnit(String degreeSuffix) =>
      degreeSuffix == '°F' ? 'mph' : 'km/h';
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.value, required this.scale});

  final WeatherGlyph icon;
  final String value;
  final _CardScale scale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(right: scale(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tinted: at this size a Meteocon's own palette is three pixels of
          // colour on a sky that is already coloured, and these are the row's
          // labels rather than its subject.
          WeatherIcon(
            icon,
            size: scale(_detailIconSize),
            color: kSkyMutedForeground,
          ),
          SizedBox(width: scale(5)),
          Flexible(
            child: _SkyText(value, size: scale(_detailTextSize), muted: true),
          ),
        ],
      ),
    );
  }
}

/// How wide [text] is set at [size], in the font the card will actually use.
///
/// The `TrackMarquee` discipline, and what both rows that decide what fits are
/// built on: the same readings fit under one theme's font and overflow under
/// another's, and counting characters gets it wrong.
///
/// The style comes from [DefaultTextStyle] rather than a bare [TextStyle]: the
/// shell's text root supplies the *theme's* `fontFamily`, and a measurement taken
/// in the platform default measures a different font. It is the same lookup the
/// [Text] widgets beside it do, so the two cannot disagree.
double _measureText(BuildContext context, String text, double size) {
  final style = DefaultTextStyle.of(context).style.copyWith(fontSize: size);
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    // The theme's `font_size` reaches the Text widgets beside this through the
    // ambient TextScaler rather than through their styles, so a measurement
    // that left it out would answer for a smaller card than the one drawn.
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The days-ahead strip along the bottom.
///
/// The one part of this card that was illegible at every size: set at 10px
/// against a 30px reading, and still 10px on a card four times the area. Its base
/// is [ShellFontSizes.caption] now and scales with the rest — and because
/// `_forecastDays` scales its per-column budget by the same factor, a bigger card
/// answers with the same days set larger. A column too narrow for both keeps the
/// high, which is the number a forecast is read for.
class _ForecastStrip extends StatelessWidget {
  const _ForecastStrip({required this.days, required this.scale});

  final List<DayForecast> days;
  final _CardScale scale;

  /// The gap between a day's high and its low.
  static const double _baseGap = 5;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();

    final tempSize = scale(_forecastTempSize);
    final gap = scale(_baseGap);

    return LayoutBuilder(
      builder: (context, constraints) {
        final column = constraints.maxWidth / days.length;
        // Measured against the widest pair the strip actually holds, not
        // against a specimen: one day below zero is three glyphs wider than
        // its neighbours, and it is the column that would have overflowed.
        var widest = 0.0;
        for (final day in days) {
          widest = math.max(
            widest,
            _measureText(context, _high(day), tempSize) +
                gap +
                _measureText(context, _low(day), tempSize),
          );
        }
        final showLow = widest <= column - gap;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final day in days)
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SkyText(
                      day.dayLabel,
                      size: scale(_forecastLabelSize),
                      muted: true,
                      tracking: 0.4,
                    ),
                    SizedBox(height: scale(_forecastGap)),
                    WeatherIcon(
                      // The day columns are always daytime: a forecast for
                      // Thursday is a forecast for Thursday's daylight, not for
                      // the moment the card happens to be looked at.
                      weatherIcon(day.condition),
                      size: scale(_forecastIconSize),
                    ),
                    SizedBox(height: scale(_forecastGap)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Flexible over the measured decision, not instead of
                        // it: the measurement is made without the theme's own
                        // font metrics, so this is what turns a few pixels of
                        // error into an ellipsis rather than an assertion.
                        Flexible(
                          child: _SkyText(
                            _high(day),
                            size: tempSize,
                            weight: FontWeight.w500,
                          ),
                        ),
                        if (showLow) ...[
                          SizedBox(width: gap),
                          Flexible(
                            child: _SkyText(
                              _low(day),
                              size: tempSize,
                              faint: true,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  static String _high(DayForecast day) => '${day.tempMax.round()}°';
  static String _low(DayForecast day) => '${day.tempMin.round()}°';
}

/// One line of the readout: white, shadowed, ellipsised, and never wrapping
/// into the sky. The one place the sky's text style is spelled.
class _SkyText extends StatelessWidget {
  const _SkyText(
    this.text, {
    required this.size,
    this.weight = FontWeight.w400,
    this.muted = false,
    this.faint = false,
    this.tracking = 0,
    this.align,
    this.maxLines = 1,
  });

  final String text;
  final double size;
  final FontWeight weight;

  /// The secondary tier — labels and units beside a reading.
  final bool muted;

  /// The third tier, for the one number that is a footnote to another: a
  /// forecast day's low beside its high. Below [muted], and only ever next to
  /// something brighter that gives it its context.
  final bool faint;

  /// Letter spacing. Small text set wide reads as a label and large text set
  /// tight reads as a display face, which is most of what separates this card
  /// from a form.
  final double tracking;

  final TextAlign? align;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      textAlign: align,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
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

/// The "Add widget…" menu's icon for this type. Named, so a test can build a
/// [DesktopWidgetSpec] without picking an unrelated glyph.
const FaIconData weatherDesktopWidgetIcon = FontAwesomeIcons.cloudSun;

/// The registry entry. Registered from `main()` beside the media player's.
final DesktopWidgetSpec weatherDesktopWidget = DesktopWidgetSpec(
  type: 'weather',
  name: 'Weather',
  description: 'Conditions and forecast, over a painted sky',
  icon: weatherDesktopWidgetIcon,
  // Two cells wide is the floor for the media widget's reason: one cell is an
  // icon. The default is larger deliberately — 3x2 is the smallest span carrying
  // the place, the reading, the detail row and a sky with room to be looked at,
  // and it is the span `_referenceCard` is the size of.
  minSpan: (columns: 2, rows: 1),
  maxSpan: (columns: 6, rows: 4),
  defaultSpan: (columns: 3, rows: 2),
  // The sky is the card. See the file's header.
  padding: EdgeInsets.zero,
  builder: (context, widget) => WeatherWidget(span: widget.span),
);
