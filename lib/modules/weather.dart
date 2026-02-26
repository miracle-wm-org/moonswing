import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/widgets.dart';
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

class Weather extends StatefulWidget {
  const Weather({super.key, required this.config});

  final WeatherConfig config;

  @override
  WeatherState createState() => WeatherState();
}

class WeatherState extends State<Weather> {
  String _weatherText = '';
  bool _loading = true;
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

      // Fetch weather from Open-Meteo
      final unitParam = _unit == TemperatureUnit.fahrenheit
          ? '&temperature_unit=fahrenheit'
          : '';
      final weatherResponse =
          await http.get(Uri.parse('https://api.open-meteo.com/v1/forecast'
              '?latitude=$lat&longitude=$lon'
              '&current=temperature_2m,weather_code'
              '$unitParam'));
      if (weatherResponse.statusCode != 200) return;

      final weather = jsonDecode(weatherResponse.body);
      final current = weather['current'];
      final temp = current['temperature_2m'];
      final code = current['weather_code'] as int;
      final condition = _weatherCondition(code);
      final unitLabel = _unit == TemperatureUnit.fahrenheit ? '°F' : '°C';

      if (!mounted) return;
      setState(() {
        _weatherText = '${temp.round()}$unitLabel $condition';
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

    return Text(
      _weatherText,
      style: TextStyle(fontSize: 16, color: ThemeScope.of(context).foreground),
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
        style: TextStyle(
            fontSize: 14, color: ThemeScope.of(context).foreground),
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
