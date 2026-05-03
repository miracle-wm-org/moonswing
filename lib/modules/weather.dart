// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:flutter/src/widgets/_window_positioner.dart';
import 'package:graceful_shell/layer_shell.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:http/http.dart' as http;

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
      unit: map['unit'] as String? ?? 'fahrenheit',
      refreshMinutes: map['refresh_minutes'] as int? ?? 10,
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

class Weather extends StatefulWidget {
  const Weather({super.key, required this.config});

  final WeatherConfig config;

  @override
  WeatherState createState() => WeatherState();
}

class WeatherState extends State<Weather> with PopupHost<Weather> {
  String _weatherText = '';
  bool _loading = true;
  bool _hovered = false;
  List<DayForecast> _forecast = [];
  Timer? _refreshTimer;

  TemperatureUnit get _unit => widget.config.unit == 'celsius'
      ? TemperatureUnit.celsius
      : TemperatureUnit.fahrenheit;

  @override
  void initState() {
    super.initState();
    _fetchWeather();
    _refreshTimer =
        Timer.periodic(Duration(minutes: widget.config.refreshMinutes), (_) {
      _fetchWeather();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    closePopup();
    super.dispose();
  }

  Future<void> _fetchWeather() async {
    try {
      // Get location from IP
      final geoResponse = await http.get(Uri.parse('https://ipapi.co/json/'));
      if (geoResponse.statusCode != 200) return;

      final geo = jsonDecode(geoResponse.body);
      final lat = geo['latitude'];
      final lon = geo['longitude'];

      // Fetch current weather + 7-day daily forecast from Open-Meteo
      final unitParam = _unit == TemperatureUnit.fahrenheit
          ? '&temperature_unit=fahrenheit'
          : '';
      final weatherResponse =
          await http.get(Uri.parse('https://api.open-meteo.com/v1/forecast'
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
      final unitLabel = _unit == TemperatureUnit.fahrenheit ? '°F' : '°C';

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
          precipProbability: precips[i] != null ? (precips[i] as num).toInt() : 0,
        ));
      }

      if (!mounted) return;
      setState(() {
        _weatherText = '${temp.round()}$unitLabel $condition';
        _forecast = forecast;
        _loading = false;
      });
    } catch (_) {
      // Silently fail — don't crash the panel
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  static String _shortWeekday(int weekday) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[(weekday - 1).clamp(0, 6)];
  }

  static String _weatherCondition(int code) {
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

  void _togglePopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }

    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final flutterView = View.of(context);
    final dpr = flutterView.devicePixelRatio;
    final barLogicalWidth = flutterView.physicalSize.width / dpr;
    final barLogicalHeight = flutterView.physicalSize.height / dpr;

    final anchor = BarScope.of(context).anchor;
    final theme = ThemeScope.of(context);
    final unitLabel = _unit == TemperatureUnit.fahrenheit ? '°F' : '°C';

    final Rect anchorRect;
    final WindowPositionerAnchor parentAnchor;
    final WindowPositionerAnchor childAnchor;

    switch (anchor) {
      case 'bottom':
        final screenH = getScreenSize().height;
        anchorRect =
            Rect.fromLTWH(offset.dx, screenH - barLogicalHeight, size.width, 0);
        parentAnchor = WindowPositionerAnchor.top;
        childAnchor = WindowPositionerAnchor.bottom;
      case 'left':
        anchorRect = Rect.fromLTWH(0, offset.dy, barLogicalWidth, size.height);
        parentAnchor = WindowPositionerAnchor.right;
        childAnchor = WindowPositionerAnchor.left;
      case 'right':
        final screenW = getScreenSize().width;
        anchorRect = Rect.fromLTWH(
            screenW - barLogicalWidth, offset.dy, barLogicalWidth, 0);
        parentAnchor = WindowPositionerAnchor.left;
        childAnchor = WindowPositionerAnchor.right;
      default: // 'top'
        anchorRect = Rect.fromLTWH(offset.dx, 0, size.width, 0);
        parentAnchor = WindowPositionerAnchor.bottom;
        childAnchor = WindowPositionerAnchor.top;
    }

    openPopup(
      context,
      anchorRect: anchorRect,
      parentAnchor: parentAnchor,
      childAnchor: childAnchor,
      preferredConstraints: const BoxConstraints.tightFor(width: 260, height: 300),
      child: ThemeScope(
        theme: theme,
        child: _WeatherForecastPopup(
          forecast: _forecast,
          unitLabel: unitLabel,
          weatherCondition: _weatherCondition,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: _Spinner(),
      );
    }

    if (_weatherText.isEmpty) return const SizedBox.shrink();

    final theme = ThemeScope.of(context);
    final isActive = _hovered || isPopupOpen;
    final text = Text(
      _weatherText,
      style: TextStyle(fontSize: 16, color: theme.foreground),
    );

    if (_forecast.isEmpty) return text;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => _togglePopup(context),
        child: Container(
          decoration: BoxDecoration(
            color: isActive ? const Color(0x28FFFFFF) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: text,
        ),
      ),
    );
  }
}

class _WeatherForecastPopup extends StatelessWidget {
  const _WeatherForecastPopup({
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

    final rows = forecast.map((day) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 32,
              child: Text(day.dayLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(weatherCondition(day.weatherCode)),
            Text(
              '${day.tempMax.round()}° / ${day.tempMin.round()}°',
              style: TextStyle(color: theme.popupForeground),
            ),
            Text(
              '💧${day.precipProbability}%',
              style: TextStyle(
                  color: theme.popupForeground.withValues(alpha: 0.7),
                  fontSize: 12),
            ),
          ],
        ),
      );
    }).toList();

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(color: theme.popupForeground, fontSize: 13),
        child: PopupBounceIn(
          child: Container(
            color: theme.popupBackground,
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
                ...rows,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Spinner extends StatefulWidget {
  const _Spinner();

  @override
  _SpinnerState createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * pi,
          child: child,
        );
      },
      child: Text(
        '◐',
        style:
            TextStyle(fontSize: 14, color: ThemeScope.of(context).foreground),
      ),
    );
  }
}

class WeatherModule extends Module {
  WeatherConfig _config = const WeatherConfig();

  @override
  String get configKey => 'weather';

  @override
  void loadConfig(Map<String, dynamic>? map) {
    _config = WeatherConfig.fromMap(map);
  }

  @override
  WidgetBuilder get builder => (context) => Weather(config: _config);
}
