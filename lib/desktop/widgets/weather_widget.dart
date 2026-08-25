// The weather desktop widget: the reading, over a sky that is doing what the
// reading says.
//
// The second entry in `DesktopWidgetRegistry`, and it reads exactly what the
// bar module reads — `WeatherStore`, leased. Neither surface owns the fetch and
// neither knows the other exists; before the store, all of it lived in the bar
// module's `State`, so this widget would have meant a second geolocation
// lookup and a second forecast poller per monitor.
//
// Three things about it that the media widget did not have to answer:
//
// - **The card is the sky, so the frame gives it no padding.** Its
//   `DesktopWidgetSpec` asks for `EdgeInsets.zero` and the content carries its
//   own insets; `PopupCard` clips to the theme's radius, so the sky is rounded
//   with the card.
// - **The text is white on a scrim, not on the theme.** The palettes run from a
//   near-black thunderstorm to an almost-white snowfall, and no theme
//   foreground is legible on both. `SkyScrim` guarantees something dark under
//   the readout, the same call the lock screen makes over a wallpaper.
// - **Every size in it is one table times one factor.** This is the only widget
//   in the shell the *user* resizes, in a grid whose cell size they also
//   choose, so a literal chosen against one card is wrong on every other one —
//   see [_CardScale]. The media widget sheds content as it shrinks and is done;
//   this one has to look deliberate at four times the area as well.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/desktop/desktop_layout.dart' show GridSpan;
import 'package:graceful_shell/desktop/widgets/desktop_widget.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/weather/weather_api.dart';
import 'package:graceful_shell/weather/weather_condition.dart';
import 'package:graceful_shell/weather/weather_icons.dart';
import 'package:graceful_shell/weather/weather_sky.dart';
import 'package:graceful_shell/weather/weather_store.dart';

/// The smallest box each layout draws in. Content measurements, not cell
/// counts: a cell is configurable down to 32px and the content is not.
const double _minWidth = 150;
const double _minHeight = 64;
const double _expandedMinHeight = 128;
const double _forecastMinWidth = 250;
const double _forecastMinHeight = 190;
const double _detailsMinHeight = 250;
const double _highLowMinWidth = 260;

/// The card every base size below was chosen against: the registry's own
/// `defaultSpan` of 3x2 on the default grid — `cellWidth`/`cellHeight` 96 with
/// `spacing` 12, so `3*96 + 2*12` by `2*96 + 12`.
const Size _referenceCard = Size(312, 204);

/// The card's inner inset, at [_referenceCard].
const double _basePadding = 12;

/// How far the type is allowed to grow. `maxSpan` is 6x4, which on the default
/// grid wants about 2.05 — so this is the ceiling reached by the largest card
/// the registry permits, and nothing above it is being clamped away.
const double _maxScale = 2.0;

/// The card's type and icon scale.
///
/// Every size in this widget used to be a literal chosen against
/// [_referenceCard], so a user who dragged the widget out to 6x4 got the same
/// 10px day labels in four times the area — and the forecast strip in
/// particular read as an afterthought rather than as the content it is. The
/// sizes are now that same table multiplied through by one factor derived from
/// the box the grid actually handed the card.
///
/// Two things about the factor. It is the **geometric mean** of the two edge
/// ratios rather than either one alone: a card stretched wide but left one row
/// tall has no more room for a bigger type than it started with, and taking the
/// wider edge would set it in a size its own height cannot carry. And it never
/// goes **below 1** — the literals are a floor rather than a midpoint, and a
/// card smaller than the reference is already being laid out at its own minimum
/// and clipped (see `_minWidth`/`_minHeight`) rather than being asked to draw a
/// smaller version of itself.
class _CardScale {
  const _CardScale(this.factor);

  factory _CardScale.forBox(double width, double height) {
    final ratio = math.sqrt((width / _referenceCard.width) *
        (height / _referenceCard.height));
    return _CardScale(ratio.clamp(1.0, _maxScale));
  }

  final double factor;

  /// [base] — a size read off the table above — at this card's size.
  double call(double base) => base * factor;
}

/// The widget's body. Public and store-injectable so a widget test can seed a
/// reading and pump it with nothing behind it.
class WeatherWidget extends StatefulWidget {
  WeatherWidget({
    super.key,
    required this.span,
    WeatherStore? store,
    this.animate = true,
  }) : store = store ?? WeatherStore.instance;

  /// The widget's size in cells. Two wide by one is the minimum, and the
  /// compact layout is what everything else is derived from.
  final GridSpan span;

  final WeatherStore store;

  /// Whether the sky — and the reading's own glyph, which is a Lottie — animate.
  /// False in widget tests: a [Ticker] never settles, so **nothing rendering
  /// this may be `pumpAndSettle`ed** with it on.
  final bool animate;

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
        final expanded =
            widget.span.rows >= 2 && height >= _expandedMinHeight;
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
                  animate: widget.animate,
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
        child: _CompactLayout(
          store: store,
          reading: reading,
          scale: scale,
          animate: widget.animate,
        ),
      );
    }
    return _ExpandedLayout(
      store: store,
      reading: reading,
      scale: scale,
      animate: widget.animate,
      // Independent decisions, all about pixels rather than cells: a widget
      // three columns wide on a 48px grid is narrower than one two columns
      // wide on a 120px one.
      showForecast:
          width >= _forecastMinWidth && height >= _forecastMinHeight,
      showDetails: height >= _detailsMinHeight,
      // The day's high and low share the reading's row with the glyph and the
      // temperature itself, and it is the one of the three that says least
      // — the big number above it is today's actual temperature.
      showHighLow: width >= _highLowMinWidth,
      forecastDays: _forecastDays(width, scale),
    );
  }

  /// How many days fit across [width]. Each column needs about 48px at
  /// [_referenceCard] to carry a day label, a glyph and a high — and that
  /// budget scales with the type, or a card twice the size would answer
  /// "twice as many days" rather than "the same days, legibly". Fewer days is
  /// better than a strip of clipped ones.
  int _forecastDays(double width, _CardScale scale) {
    final content = width - 2 * scale(_basePadding);
    return (content / scale(48)).floor().clamp(0, 7);
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
          SizedBox(height: scale(8)),
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
          horizontal: scale(10),
          vertical: scale(5),
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF).withValues(alpha: hovered ? 0.3 : 0.18),
          borderRadius: BorderRadius.circular(ShellRadii.control),
        ),
        child: _SkyText('Retry', size: scale(ShellFontSizes.caption)),
      ),
    );
  }
}

/// The 2x1 layout: a glyph, the temperature, and what it is doing.
class _CompactLayout extends StatelessWidget {
  const _CompactLayout({
    required this.store,
    required this.reading,
    required this.scale,
    required this.animate,
  });

  final WeatherStore store;
  final WeatherReading reading;
  final _CardScale scale;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        WeatherIcon(
          weatherIcon(reading.condition, night: !reading.isDay),
          size: scale(38),
          animate: animate,
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
                weight: FontWeight.w600,
              ),
              _SkyText(
                reading.condition.label,
                size: scale(ShellFontSizes.caption),
                muted: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Two rows or taller: the place, a large reading, and — as the card grows —
/// the day's detail and a forecast strip.
class _ExpandedLayout extends StatelessWidget {
  const _ExpandedLayout({
    required this.store,
    required this.reading,
    required this.scale,
    required this.animate,
    required this.showForecast,
    required this.showDetails,
    required this.showHighLow,
    required this.forecastDays,
  });

  final WeatherStore store;
  final WeatherReading reading;
  final _CardScale scale;
  final bool animate;
  final bool showForecast;
  final bool showDetails;
  final bool showHighLow;
  final int forecastDays;

  @override
  Widget build(BuildContext context) {
    final place = store.place;
    final forecast = store.forecast;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (place != null)
          Row(
            children: [
              // The one Material Symbol on this card: Meteocons is a weather
              // set and has no place marker. See `kLocationIcon`.
              Icon(
                kLocationIcon,
                size: scale(13),
                color: kSkyMutedForeground,
                fill: 0.7,
                weight: 500,
                shadows: kSkyTextShadows,
              ),
              SizedBox(width: scale(4)),
              Expanded(
                child: _SkyText(
                  place.name,
                  size: scale(ShellFontSizes.caption),
                  muted: true,
                ),
              ),
            ],
          ),
        const Spacer(flex: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            WeatherIcon(
              weatherIcon(reading.condition, night: !reading.isDay),
              size: scale(58),
              // No tint: this is the card's subject, drawn over a sky that is
              // already the weather, and the Meteocon's own palette is what
              // makes it read as the picture rather than as a control.
              animate: animate,
            ),
            SizedBox(width: scale(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SkyText(
                    store.temperatureText,
                    size: scale(30),
                    weight: FontWeight.w300,
                  ),
                  _SkyText(
                    reading.condition.label,
                    size: scale(ShellFontSizes.secondary),
                    muted: true,
                  ),
                ],
              ),
            ),
            if (showHighLow && forecast.isNotEmpty)
              // Flexible over the width decision, not instead of it: a theme
              // with a wide font can still push this past what was budgeted
              // for it, and an ellipsis is a better answer than an assertion
              // on a surface nobody reads the console for.
              Flexible(
                child: _SkyText(
                  'H ${forecast.first.tempMax.round()}°  '
                  'L ${forecast.first.tempMin.round()}°',
                  size: scale(ShellFontSizes.caption),
                  muted: true,
                ),
              ),
          ],
        ),
        if (showDetails) ...[
          SizedBox(height: scale(10)),
          _DetailRow(reading: reading, unit: store.unitLabel, scale: scale),
        ],
        const Spacer(),
        if (showForecast && forecast.length > 1)
          _ForecastStrip(
            // Today is already spelled out above, in three times the size.
            days: forecast.skip(1).take(forecastDays).toList(),
            scale: scale,
          ),
      ],
    );
  }
}

/// Feels-like, humidity and wind — each one dropped rather than truncated when
/// the reading does not carry it, or the card is not wide enough for it.
///
/// The order it sheds them in is deliberate, the media widget's rule: wind goes
/// before humidity and humidity before feels-like, because feels-like is the
/// one somebody glances at a weather widget for. And it **measures** rather
/// than counting characters — the `TrackMarquee` discipline: the same three
/// readings fit at one theme's font and overflow at another's, and a row that
/// guessed is a row that reports a flex overflow every frame on a surface whose
/// console nobody is reading. The measurement is taken at the card's own scale,
/// or growing the type would silently start overflowing the row it sizes.
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
  static const double _baseChrome = _detailIconSize + 4 + 12;

  static const double _detailIconSize = 15;

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

    final fontSize = scale(ShellFontSizes.caption);
    final chrome = scale(_baseChrome);
    final style = TextStyle(fontSize: fontSize);

    return LayoutBuilder(
      builder: (context, constraints) {
        var used = 0.0;
        final shown = <(WeatherGlyph, String)>[];
        for (final candidate in candidates) {
          final width = _measure(candidate.$2, style) + chrome;
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
              // measurement is made without the theme's own font metrics, so
              // this is what turns a few pixels of error into an ellipsis
              // rather than an assertion.
              Flexible(
                child: _Detail(
                  icon: detail.$1,
                  value: detail.$2,
                  scale: scale,
                ),
              ),
          ],
        );
      },
    );
  }

  static double _measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// Open-Meteo reports wind in the unit system the temperature was asked for:
  /// mph alongside Fahrenheit, km/h alongside Celsius. Labelling it from the
  /// degree suffix is what keeps the two in step without a second request
  /// parameter to remember.
  static String _windUnit(String degreeSuffix) =>
      degreeSuffix == '°F' ? 'mph' : 'km/h';
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.icon,
    required this.value,
    required this.scale,
  });

  final WeatherGlyph icon;
  final String value;
  final _CardScale scale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(right: scale(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tinted, unlike the reading's own glyph above: at this size the
          // Meteocon's palette is three pixels of colour on a sky that is
          // already coloured, and these are the row's labels rather than its
          // subject.
          WeatherIcon(
            icon,
            size: scale(_DetailRow._detailIconSize),
            color: kSkyMutedForeground,
          ),
          SizedBox(width: scale(4)),
          Flexible(
            child: _SkyText(
              value,
              size: scale(ShellFontSizes.caption),
              muted: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// The days-ahead strip along the bottom.
///
/// The one part of this card that was illegible at every size: it was set at
/// 10px against a 30px reading, and stayed at 10px on a card four times the
/// area. Its base is [ShellFontSizes.caption] now, and it scales with the rest
/// — and because `_forecastDays` scales its per-column budget by the same
/// factor, a bigger card answers with the same days set larger rather than with
/// more days set just as small.
class _ForecastStrip extends StatelessWidget {
  const _ForecastStrip({required this.days, required this.scale});

  final List<DayForecast> days;
  final _CardScale scale;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (final day in days)
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SkyText(
                  day.dayLabel,
                  size: scale(ShellFontSizes.caption),
                  muted: true,
                ),
                SizedBox(height: scale(2)),
                WeatherIcon(
                  // The day columns are always daytime: a forecast for Thursday
                  // is a forecast for Thursday's daylight, not for the moment
                  // the card happens to be looked at.
                  //
                  // Still, never animated: seven Lotties along the bottom of a
                  // wallpaper widget is six more running tickers than the card
                  // has anything to say with.
                  weatherIcon(day.condition),
                  size: scale(22),
                ),
                SizedBox(height: scale(2)),
                _SkyText(
                  '${day.tempMax.round()}°',
                  size: scale(ShellFontSizes.caption),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One line of the readout: white, shadowed, ellipsised, and never wrapping
/// into the sky. The one place the sky's text style is spelled.
class _SkyText extends StatelessWidget {
  const _SkyText(
    this.text, {
    required this.size,
    this.weight = FontWeight.w400,
    this.muted = false,
    this.align,
    this.maxLines = 1,
  });

  final String text;
  final double size;
  final FontWeight weight;
  final bool muted;
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
        color: muted ? kSkyMutedForeground : kSkyForeground,
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
  description: 'Conditions and forecast, over a live sky',
  icon: weatherDesktopWidgetIcon,
  // Two cells wide is the floor for the media widget's reason: one cell is an
  // icon, and a temperature beside a condition does not fit in the width of a
  // launcher tile. The default is larger than the floor deliberately — 3x2 is
  // the smallest span that carries the place, the detail row and a sky with
  // room to be looked at, and it is the span `_referenceCard` is the size of.
  minSpan: (columns: 2, rows: 1),
  maxSpan: (columns: 6, rows: 4),
  defaultSpan: (columns: 3, rows: 2),
  // The sky is the card. See the file's header.
  padding: EdgeInsets.zero,
  builder: (context, widget) => WeatherWidget(span: widget.span),
);
