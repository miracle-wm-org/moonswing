import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:graceful_shell/bar_button.dart';
import 'package:graceful_shell/config_reader.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:http/http.dart' as http;
import 'package:graceful_shell/theme/theme_provider.dart';

class WeatherConfig {
  final String unit;
  final int refreshMinutes;

  const WeatherConfig({
    this.unit = 'fahrenheit',
    this.refreshMinutes = 10,
  });

  factory WeatherConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const WeatherConfig();
    return WeatherConfig(
      unit: map.stringOr('unit', 'fahrenheit'),
      refreshMinutes: map.intOr('refresh_minutes', 10),
    );
  }
}

enum TemperatureUnit { celsius, fahrenheit }

class DayForecast {
  final String dayLabel;
  final int weatherCode;
  final double tempMax;
  final double tempMin;
  final int precipProbability;

  const DayForecast({
    required this.dayLabel,
    required this.weatherCode,
    required this.tempMax,
    required this.tempMin,
    required this.precipProbability,
  });
}

/// The weather reading for the whole shell.
///
/// Same singleton-`ChangeNotifier` shape as `OsdStore`/`TrayStore`, with
/// `SystemStatsStore`'s lease rule: the HTTP fetches run only while at least
/// one widget holds a lease, so a two-monitor setup shares one fetcher instead
/// of hitting the geolocation and forecast APIs once per bar.
class WeatherStore extends ChangeNotifier {
  WeatherStore._();

  static final WeatherStore instance = WeatherStore._();

  @visibleForTesting
  factory WeatherStore.forTesting({
    WeatherConfig config = const WeatherConfig(),
  }) {
    final store = WeatherStore._();
    store.configure(config);
    return store;
  }

  WeatherConfig _config = const WeatherConfig();

  /// Applies [config]; the module's `fromMap` pushes it here. A cadence change
  /// while leased restarts the timer at the new interval. A unit change takes
  /// effect on the next fetch — same as before, when the widget read its config
  /// at fetch time.
  void configure(WeatherConfig config) {
    final cadenceChanged = config.refreshMinutes != _config.refreshMinutes;
    _config = config;
    if (cadenceChanged && _timer != null) {
      _stopTimer();
      _startTimer();
    }
  }

  TemperatureUnit get unit => _config.unit == 'celsius'
      ? TemperatureUnit.celsius
      : TemperatureUnit.fahrenheit;

  String get unitLabel =>
      unit == TemperatureUnit.fahrenheit ? '°F' : '°C';

  // --- published state -----------------------------------------------------

  String _weatherText = '';
  String get weatherText => _weatherText;

  /// True until the first fetch settles. The bar shows a fixed-size loader in
  /// its place so the modules beside it don't shuffle when the reading lands.
  bool _loading = true;
  bool get loading => _loading;

  List<DayForecast> _forecast = [];
  List<DayForecast> get forecast => List.unmodifiable(_forecast);

  // --- polling state -------------------------------------------------------

  int _leases = 0;
  Timer? _timer;

  /// A tick that arrives while the previous fetch is still in flight is
  /// dropped, not queued behind it.
  bool _fetchInFlight = false;

  /// Take a lease. The first active lease starts the refresh timer and fetches
  /// immediately so the bar never waits a full interval for its first reading.
  void acquire() {
    _leases++;
    if (_timer == null) {
      _startTimer();
      unawaited(_fetchWeather());
    }
  }

  void release() {
    if (_leases > 0) _leases--;
    if (_leases == 0) _stopTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(
      Duration(minutes: _config.refreshMinutes),
      (_) => unawaited(_fetchWeather()),
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _fetchWeather() async {
    if (_fetchInFlight) return;
    _fetchInFlight = true;
    try {
      // Captured once, so the text and the forecast of one fetch always agree
      // even if the config changes mid-flight.
      final unit = this.unit;

      // Get location from IP
      final geoResponse = await http.get(Uri.parse('https://ipapi.co/json/'));
      if (geoResponse.statusCode != 200) return;

      final geo = jsonDecode(geoResponse.body);
      final lat = geo['latitude'];
      final lon = geo['longitude'];

      // Fetch current weather + 7-day daily forecast from Open-Meteo
      final unitParam = unit == TemperatureUnit.fahrenheit
          ? '&temperature_unit=fahrenheit'
          : '';
      final weatherResponse = await http.get(Uri.parse(
          'https://api.open-meteo.com/v1/forecast'
          '?latitude=$lat&longitude=$lon'
          '&current=temperature_2m,weather_code'
          '&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max'
          '$unitParam'));
      if (weatherResponse.statusCode != 200) return;

      final weather = jsonDecode(weatherResponse.body);
      final current = weather['current'];
      final temp = current['temperature_2m'];
      final code = current['weather_code'] as int;
      final condition = _weatherCondition(code);
      final unitLabel = unit == TemperatureUnit.fahrenheit ? '°F' : '°C';

      final daily = weather['daily'] as Map<String, dynamic>;
      final times = daily['time'] as List<dynamic>;
      final maxTemps = daily['temperature_2m_max'] as List<dynamic>;
      final minTemps = daily['temperature_2m_min'] as List<dynamic>;
      final codes = daily['weather_code'] as List<dynamic>;
      final precips = daily['precipitation_probability_max'] as List<dynamic>;

      final forecast = <DayForecast>[];
      for (var i = 0; i < times.length; i++) {
        final dt = DateTime.parse(times[i] as String);
        forecast.add(DayForecast(
          dayLabel: _shortWeekday(dt.weekday),
          weatherCode: (codes[i] as num).toInt(),
          tempMax: (maxTemps[i] as num).toDouble(),
          tempMin: (minTemps[i] as num).toDouble(),
          precipProbability:
              precips[i] != null ? (precips[i] as num).toInt() : 0,
        ));
      }

      _weatherText = '${temp.round()}$unitLabel $condition';
      _forecast = forecast;
      _loading = false;
      notifyListeners();
    } catch (_) {
      // Silently fail — don't crash the panel
      _loading = false;
      notifyListeners();
    } finally {
      _fetchInFlight = false;
    }
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}

class Weather extends StatefulWidget {
  const Weather({super.key});

  @override
  WeatherState createState() => WeatherState();
}

class WeatherState extends State<Weather> with PopupHost<Weather> {
  final WeatherStore _store = WeatherStore.instance;

  @override
  void initState() {
    super.initState();
    _store.acquire();
  }

  @override
  void dispose() {
    _store.release();
    closePopup();
    super.dispose();
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
      preferredConstraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
      child: ThemeProvider(
        child: WeatherForecastPopup(
          forecast: _store.forecast,
          unitLabel: _store.unitLabel,
          weatherCondition: _weatherCondition,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        if (_store.loading) {
          // The 16x16 box is kept around the 14px loader: this sits in a
          // panel row and the placeholder must not be narrower than the
          // reading that replaces it, or the modules beside it shuffle
          // sideways when it lands.
          return SizedBox(
            width: 16,
            height: 16,
            child: Center(
              child: LoadingIndicator(
                color: ThemeScope.of(context).foreground,
                size: 14,
              ),
            ),
          );
        }

        if (_store.weatherText.isEmpty) return const SizedBox.shrink();

        final theme = ThemeScope.of(context);
        final text = Text(
          _store.weatherText,
          style: TextStyle(fontSize: 16, color: theme.foreground),
        );

        if (_store.forecast.isEmpty) return text;

        return BarButton(
          active: isPopupOpen,
          onTapDown: (_) => _togglePopup(context),
          child: text,
        );
      },
    );
  }
}

String _shortWeekday(int weekday) {
  const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return labels[(weekday - 1).clamp(0, 6)];
}

String _weatherCondition(int code) {
    switch (code) {
      case 0:
        return '☀️';
      case 1:
        return '🌤️';
      case 2:
        return '⛅';
      case 3:
        return '☁️';
      case 45:
      case 48:
        return '🌫️';
      case 51:
      case 53:
      case 55:
        return '🌦️';
      case 61:
      case 63:
      case 65:
        return '🌧️';
      case 66:
      case 67:
        return '🌧️';
      case 71:
      case 73:
      case 75:
      case 77:
        return '❄️';
      case 80:
      case 81:
      case 82:
        return '🌧️';
      case 85:
      case 86:
        return '🌨️';
      case 95:
        return '⛈️';
      case 96:
      case 99:
        return '⛈️';
      default:
        return '';
    }
  }

class WeatherForecastPopup extends StatelessWidget {
  const WeatherForecastPopup({
    super.key,
    required this.forecast,
    required this.unitLabel,
    required this.weatherCondition,
  });

  final List<DayForecast> forecast;
  final String unitLabel;
  final String Function(int) weatherCondition;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    // A Table rather than a column of Rows, because the popup is sized to its
    // content and MainAxisAlignment.spaceBetween — what these rows used to use
    // to line their columns up — means nothing without a bounded width.
    // IntrinsicColumnWidth sizes each of the four columns to its widest cell and
    // keeps them aligned across every row, which is what spaceBetween was only
    // approximating, and it replaces the hand-rolled SizedBox(width: 32) that
    // used to stand in for a day-label column. With no flex column the table
    // shrink-wraps, so the card ends up as wide as its widest day.
    Widget cell(Widget child, {EdgeInsets? padding}) => Padding(
          padding: padding ?? const EdgeInsets.symmetric(vertical: 4),
          child: child,
        );

    final rows = forecast.map((day) {
      return TableRow(
        children: [
          cell(Text(day.dayLabel,
              style: const TextStyle(fontWeight: FontWeight.w600))),
          cell(
            Text(weatherCondition(day.weatherCode)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          cell(Text(
            '${day.tempMax.round()}° / ${day.tempMin.round()}°',
            style: TextStyle(color: theme.popupForeground),
          )),
          cell(
            Text(
              '💧${day.precipProbability}%',
              style: TextStyle(
                  color: theme.popupForeground.withValues(alpha: 0.7),
                  fontSize: 12),
            ),
            padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
          ),
        ],
      );
    }).toList();

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(color: theme.popupForeground, fontSize: 13),
        child: PopupBounceIn(
          child: PopupCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '7-Day Forecast',
                  style: TextStyle(
                    color: theme.popupForeground,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Table(
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: rows,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final Module weatherModule = Module.simple<WeatherConfig>(
  configKey: 'weather',
  fromMap: (map) {
    final config = WeatherConfig.fromMap(map);
    // The store, not the widget, owns the config: polling continues across
    // widget rebuilds, and every bar instance shares the one fetcher.
    WeatherStore.instance.configure(config);
    return config;
  },
  builder: (context, config) => const Weather(),
);
