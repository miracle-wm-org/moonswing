// The weather desktop widget: the reading, over a sky that is doing what the
// reading says.
//
// The second entry in `DesktopWidgetRegistry`, and it reads exactly what the
// bar module reads — `WeatherStore`, leased. Neither surface owns the fetch and
// neither knows the other exists; before the store, all of it lived in the bar
// module's `State`, so this widget would have meant a second geolocation
// lookup and a second forecast poller per monitor.
//
// Two things about it that the media widget did not have to answer:
//
// - **The card is the sky, so the frame gives it no padding.** Its
//   `DesktopWidgetSpec` asks for `EdgeInsets.zero` and the content carries its
//   own insets; `PopupCard` clips to the theme's radius, so the sky is rounded
//   with the card.
// - **The text is white on a scrim, not on the theme.** The palettes run from a
//   near-black thunderstorm to an almost-white snowfall, and no theme
//   foreground is legible on both. `SkyScrim` guarantees something dark under
//   the readout, the same call the lock screen makes over a wallpaper.

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

  /// Whether the sky animates. False in widget tests — a [Ticker] never
  /// settles, so **nothing rendering this may be `pumpAndSettle`ed** with it on.
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
                  padding: const EdgeInsets.all(12),
                  child: _content(
                    store: store,
                    reading: reading,
                    expanded: expanded,
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
    required double width,
    required double height,
  }) {
    if (reading == null) {
      return _NoReading(
        loading: store.loading,
        error: store.error,
        onRetry: store.refresh,
      );
    }
    if (!expanded) {
      // Centred: a `Row` takes its cross-axis size from its tallest child, so
      // left to itself the compact reading sits against the top of a card the
      // user has made taller than one row of content.
      return Center(child: _CompactLayout(store: store, reading: reading));
    }
    return _ExpandedLayout(
      store: store,
      reading: reading,
      // Independent decisions, all about pixels rather than cells: a widget
      // three columns wide on a 48px grid is narrower than one two columns
      // wide on a 120px one.
      showForecast:
          width >= _forecastMinWidth && height >= _forecastMinHeight,
      showDetails: height >= _detailsMinHeight,
      // The day's high and low share the reading's row with a 46px icon and
      // the temperature itself, and it is the one of the three that says least
      // — the big number above it is today's actual temperature.
      showHighLow: width >= _highLowMinWidth,
      forecastDays: _forecastDays(width),
    );
  }

  /// How many days fit across [width]. Each column needs about 44px to carry a
  /// day label, an icon and a high; fewer days is better than a strip of
  /// clipped ones.
  int _forecastDays(double width) =>
      ((width - 24) / 44).floor().clamp(0, 7);
}

/// Before the first reading, or after a failure with nothing cached.
class _NoReading extends StatelessWidget {
  const _NoReading({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: LoadingIndicator(color: kSkyForeground, size: 18),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SkyText(
            error.isEmpty ? 'No weather yet' : error,
            size: ShellFontSizes.secondary,
            muted: true,
            align: TextAlign.center,
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          // A tap, not a pan: the card is dragged from anywhere on it, and the
          // two recognizers resolve against each other — a press that moves is
          // the drag, one that does not is this. `desktop_widget_grid_test`
          // pins both halves for the media widget's buttons.
          _RetryButton(onTap: onRetry),
        ],
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF).withValues(alpha: hovered ? 0.3 : 0.18),
            borderRadius: BorderRadius.circular(ShellRadii.control),
          ),
          child: const _SkyText('Retry', size: ShellFontSizes.caption),
        ),
      ),
    );
  }
}

/// The 2x1 layout: an icon, the temperature, and what it is doing.
class _CompactLayout extends StatelessWidget {
  const _CompactLayout({required this.store, required this.reading});

  final WeatherStore store;
  final WeatherReading reading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        WeatherIcon(
          weatherIcon(reading.condition, night: !reading.isDay),
          size: 30,
          color: kSkyForeground,
          shadows: kSkyTextShadows,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _SkyText(
                store.temperatureText,
                size: ShellFontSizes.title,
                weight: FontWeight.w600,
              ),
              _SkyText(
                reading.condition.label,
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

/// Two rows or taller: the place, a large reading, and — as the card grows —
/// the day's detail and a forecast strip.
class _ExpandedLayout extends StatelessWidget {
  const _ExpandedLayout({
    required this.store,
    required this.reading,
    required this.showForecast,
    required this.showDetails,
    required this.showHighLow,
    required this.forecastDays,
  });

  final WeatherStore store;
  final WeatherReading reading;
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
              WeatherIcon(
                kLocationIcon,
                size: 11,
                color: kSkyMutedForeground,
                shadows: kSkyTextShadows,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _SkyText(
                  place.name,
                  size: ShellFontSizes.caption,
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
              size: 46,
              color: kSkyForeground,
              shadows: kSkyTextShadows,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SkyText(
                    store.temperatureText,
                    size: 30,
                    weight: FontWeight.w300,
                  ),
                  _SkyText(
                    reading.condition.label,
                    size: ShellFontSizes.secondary,
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
                  size: ShellFontSizes.caption,
                  muted: true,
                ),
              ),
          ],
        ),
        if (showDetails) ...[
          const SizedBox(height: 10),
          _DetailRow(reading: reading, unit: store.unitLabel),
        ],
        const Spacer(),
        if (showForecast && forecast.length > 1)
          _ForecastStrip(
            // Today is already spelled out above, in three times the size.
            days: forecast.skip(1).take(forecastDays).toList(),
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
/// console nobody is reading.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.reading, required this.unit});

  final WeatherReading reading;
  final String unit;

  /// The icon, the gap, and the padding after each detail — everything in a
  /// [_Detail] that is not its text.
  static const double _chrome = 12 + 4 + 12;

  @override
  Widget build(BuildContext context) {
    final feels = reading.apparentTemperature;
    final humidity = reading.humidity;
    final wind = reading.windSpeed;

    final candidates = <(IconData, String)>[
      if (feels != null) (kFeelsLikeIcon, '${feels.round()}$unit'),
      if (humidity != null) (kHumidityIcon, '$humidity%'),
      if (wind != null) (kWindIcon, '${wind.round()} ${_windUnit(unit)}'),
    ];
    if (candidates.isEmpty) return const SizedBox.shrink();

    const style = TextStyle(fontSize: ShellFontSizes.caption);

    return LayoutBuilder(
      builder: (context, constraints) {
        var used = 0.0;
        final shown = <(IconData, String)>[];
        for (final candidate in candidates) {
          final width = _measure(candidate.$2, style) + _chrome;
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
              Flexible(child: _Detail(icon: detail.$1, value: detail.$2)),
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
  const _Detail({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WeatherIcon(
            icon,
            size: 12,
            color: kSkyMutedForeground,
            shadows: kSkyTextShadows,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: _SkyText(value, size: ShellFontSizes.caption, muted: true),
          ),
        ],
      ),
    );
  }
}

/// The days-ahead strip along the bottom.
class _ForecastStrip extends StatelessWidget {
  const _ForecastStrip({required this.days});

  final List<DayForecast> days;

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
                _SkyText(day.dayLabel, size: 10, muted: true),
                const SizedBox(height: 2),
                WeatherIcon(
                  // The day columns are always daytime: a forecast for Thursday
                  // is a forecast for Thursday's daylight, not for the moment
                  // the card happens to be looked at.
                  weatherIcon(day.condition),
                  size: 16,
                  color: kSkyForeground,
                  shadows: kSkyTextShadows,
                ),
                const SizedBox(height: 2),
                _SkyText('${day.tempMax.round()}°', size: 10),
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
  // room to be looked at.
  minSpan: (columns: 2, rows: 1),
  maxSpan: (columns: 6, rows: 4),
  defaultSpan: (columns: 3, rows: 2),
  // The sky is the card. See the file's header.
  padding: EdgeInsets.zero,
  builder: (context, widget) => WeatherWidget(span: widget.span),
);
