// The bar's weather strip: an icon, a temperature, and a seven-day forecast
// behind a click.
//
// All the weather bookkeeping this used to carry — the IP geolocation, the
// forecast request, the parse, the refresh timer, the unit — now lives in
// `lib/weather/`, which the desktop widget reads as well. One fetcher for the
// machine, leased; two bars on two monitors used to mean two of everything, and
// the desktop widget would have made it three.
//
// What is left here is the bar's own rendering, and the config re-export that
// keeps `settings/shell/modules.dart` and anything else importing
// `WeatherConfig` from this file working.

import 'package:flutter/widgets.dart';

import 'package:graceful_shell/bar_button.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/shell_text_root.dart';
import 'package:graceful_shell/theme/theme_provider.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/weather/weather_api.dart';
import 'package:graceful_shell/weather/weather_config.dart';
import 'package:graceful_shell/weather/weather_icons.dart';
import 'package:graceful_shell/weather/weather_store.dart';

export 'package:graceful_shell/weather/weather_config.dart' show WeatherConfig;

class Weather extends StatefulWidget {
  // Not const: the default store is the process-wide singleton, which a const
  // constructor cannot reach.
  Weather({super.key, WeatherStore? store})
      : store = store ?? WeatherStore.instance;

  /// Injected by tests, which seed a store rather than reaching the network.
  final WeatherStore store;

  @override
  WeatherState createState() => WeatherState();
}

class WeatherState extends State<Weather> with PopupHost<Weather> {
  @override
  void initState() {
    super.initState();
    widget.store.acquire();
    widget.store.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(Weather oldWidget) {
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
    closePopup();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _togglePopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }

    openBarPopup(
      context,
      // Loose, so the card is exactly as tall as the number of days the API
      // actually returned. The maxima are a runaway guard, not a size.
      preferredConstraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
      child: ThemeProvider(
        child: WeatherForecastPopup(store: widget.store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final theme = ThemeScope.of(context);

    if (store.loading && !store.hasReading) {
      // The 16x16 box is kept around the 14px loader: this sits in a panel row
      // and the placeholder must not be narrower than the reading that
      // replaces it, or the modules beside it shuffle sideways when it lands.
      return SizedBox(
        width: 16,
        height: 16,
        child: Center(
          child: LoadingIndicator(color: theme.foreground, size: 14),
        ),
      );
    }

    final reading = store.current;
    if (reading == null) {
      // A failure is a visible state, not a blank space — the rule the
      // notification daemon's broken dot documents. The shell cannot tell a
      // machine with no network from an API having a quiet day, and an empty
      // bar is indistinguishable from a module the user never enabled. Clicking
      // it retries, because every failure here is recoverable without
      // restarting the shell and the shell cannot notice it recovering.
      return _WeatherUnavailable(
        message: store.error.isEmpty ? 'No weather reading' : store.error,
        onRetry: store.refresh,
      );
    }

    return BarButton(
      active: isPopupOpen,
      onTapDown: (_) => _togglePopup(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WeatherIcon(
            weatherIcon(reading.condition, night: !reading.isDay),
            size: 17,
            color: theme.foreground,
          ),
          const SizedBox(width: 5),
          Text(
            store.temperatureText,
            style: TextStyle(fontSize: 16, color: theme.foreground),
          ),
        ],
      ),
    );
  }
}

/// The bar module with nothing to show: a dimmed icon whose hover label says
/// why, and whose click asks again.
class _WeatherUnavailable extends StatelessWidget {
  const _WeatherUnavailable({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      builder: (context, hovered) => GestureDetector(
        onTapDown: (_) => onRetry(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WeatherIcon(
              kWeatherUnavailableIcon,
              size: 16,
              color: theme.muted,
            ),
            // The reason, on hover only: it is a sentence, and a sentence in
            // the bar would push every module beside it along.
            if (hovered) ...[
              const SizedBox(width: 6),
              Text(
                message,
                style: TextStyle(
                  fontSize: ShellFontSizes.caption,
                  color: theme.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The forecast card: today's conditions, then a row per day.
///
/// Takes the store rather than a snapshot of it, so the card restyles and
/// re-reads live — a popup built from values captured at open time is frozen
/// for as long as it is up, which for a ten-minute refresh is most of its life.
class WeatherForecastPopup extends StatelessWidget {
  const WeatherForecastPopup({super.key, required this.store});

  final WeatherStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = ThemeScope.of(context);
        final reading = store.current;
        final forecast = store.forecast;

        // [ShellTextRoot], not a bare [DefaultTextStyle]: popup content is laid
        // out directly under its own FlutterView, so nothing above it supplies
        // a [Directionality] and every Text and Row in this card throws
        // without one. Dropping it — which is what turned this popup into an
        // empty card — costs the whole card rather than one row, because the
        // failure is in the subtree's own layout.
        return ShellTextRoot(
          style: TextStyle(
            color: theme.popupForeground,
            fontSize: ShellFontSizes.secondary,
          ),
          child: PopupBounceIn(
            child: PopupCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                // `start`, never `stretch`: the popup surface is sized to its
                // content and a stretched column reports the full width of the
                // constraints, which is the dead space
                // `popup_content_size_test.dart` exists to keep out of this
                // card.
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (reading != null) _CurrentConditions(store: store),
                  if (store.error.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      // The last reading stays on screen through a failed
                      // refresh, so this says which one is being looked at
                      // rather than replacing it.
                      store.error,
                      style: TextStyle(
                        fontSize: ShellFontSizes.caption,
                        color: kErrorColor,
                      ),
                    ),
                  ],
                  if (forecast.length > 1) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Forecast',
                      style: TextStyle(
                        color: theme.popupForeground,
                        fontSize: ShellFontSizes.caption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _ForecastTable(
                      days: forecast.skip(1).toList(),
                      theme: theme,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CurrentConditions extends StatelessWidget {
  const _CurrentConditions({required this.store});

  final WeatherStore store;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final reading = store.current!;
    final place = store.place;
    final today = store.forecast.isEmpty ? null : store.forecast.first;

    return Row(
      // Shrink-wrapped, like the table under it, and `Flexible` rather than
      // `Expanded` for the same reason: a place name long enough to need the
      // whole card may take it, but a short one must not make the card wide.
      mainAxisSize: MainAxisSize.min,
      children: [
        WeatherIcon(
          weatherIcon(reading.condition, night: !reading.isDay),
          size: 40,
          color: theme.accent,
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                store.temperatureText,
                style: TextStyle(
                  color: theme.popupForeground,
                  fontSize: ShellFontSizes.heading,
                  fontWeight: FontWeight.w300,
                ),
              ),
              Text(
                reading.condition.label,
                style: TextStyle(color: theme.popupForeground),
              ),
              if (place != null)
                Text(
                  place.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: ShellFontSizes.caption,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (today != null)
              Text(
                'H ${today.tempMax.round()}°  L ${today.tempMin.round()}°',
                style: TextStyle(
                  color: theme.popupForeground,
                  fontSize: ShellFontSizes.caption,
                ),
              ),
            if (reading.apparentTemperature != null)
              _Metric(
                icon: kFeelsLikeIcon,
                label:
                    'Feels ${reading.apparentTemperature!.round()}${store.unitLabel}',
                theme: theme,
              ),
            if (reading.humidity != null)
              _Metric(
                icon: kHumidityIcon,
                label: '${reading.humidity}%',
                theme: theme,
              ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WeatherIcon(icon, size: 11, color: theme.muted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: theme.muted,
              fontSize: ShellFontSizes.caption,
            ),
          ),
        ],
      ),
    );
  }
}

/// A `Table` rather than a column of `Row`s, because the popup is sized to its
/// content and `MainAxisAlignment.spaceBetween` — what these rows used to use to
/// line their columns up — means nothing without a bounded width.
/// `IntrinsicColumnWidth` sizes each column to its widest cell and keeps them
/// aligned across every row, and with no flex column the table shrink-wraps, so
/// the card ends up as wide as its widest day.
class _ForecastTable extends StatelessWidget {
  const _ForecastTable({required this.days, required this.theme});

  final List<DayForecast> days;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    Widget cell(Widget child, {EdgeInsets? padding}) => Padding(
          padding: padding ?? const EdgeInsets.symmetric(vertical: 4),
          child: child,
        );

    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (final day in days)
          TableRow(
            children: [
              cell(Text(
                day.dayLabel,
                style: const TextStyle(fontWeight: FontWeight.w600),
              )),
              cell(
                WeatherIcon(
                  // A daily forecast is a forecast for that day's daylight, so
                  // the day rows never take the night glyph.
                  weatherIcon(day.condition),
                  size: 16,
                  color: theme.popupForeground,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              cell(Text(
                day.condition.label,
                style: TextStyle(
                  color: theme.muted,
                  fontSize: ShellFontSizes.caption,
                ),
              )),
              cell(
                Text(
                  '${day.tempMax.round()}° / ${day.tempMin.round()}°',
                  style: TextStyle(color: theme.popupForeground),
                ),
                padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
              ),
              cell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WeatherIcon(
                      kPrecipitationIcon,
                      size: 11,
                      color: theme.popupForeground.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${day.precipProbability}%',
                      style: TextStyle(
                        color: theme.popupForeground.withValues(alpha: 0.7),
                        fontSize: ShellFontSizes.caption,
                      ),
                    ),
                  ],
                ),
                padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
              ),
            ],
          ),
      ],
    );
  }
}

final Module weatherModule = Module.simple<WeatherConfig>(
  configKey: 'weather',
  fromMap: (map) {
    final config = WeatherConfig.fromMap(map);
    // The store, not the widget, owns the config: polling continues across
    // widget rebuilds, and every surface in the shell shares the one fetcher.
    WeatherStore.instance.configure(config);
    return config;
  },
  builder: (context, config) => Weather(),
);
