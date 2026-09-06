// The weather reading for the whole shell.
//
// The singleton-`ChangeNotifier`-with-leases shape of `MprisStore` and
// `SystemStatsStore`: the HTTP requests exist only while some widget holds a
// lease, so two monitors with a bar module each and a desktop widget besides
// share one poller rather than hitting the APIs five times per interval.
//
// Flutter-free apart from `ChangeNotifier`, so the bar module and the desktop
// widget can both consume it and neither owns it.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/weather/weather_api.dart';
import 'package:graceful_shell/weather/weather_condition.dart';
import 'package:graceful_shell/weather/weather_config.dart';

class WeatherStore extends ChangeNotifier {
  WeatherStore._({WeatherClient? client})
      : _client = client ?? const OpenMeteoClient();

  static final WeatherStore instance = WeatherStore._();

  /// A detached store with an injected client, so a widget test can take a real
  /// lease without a network behind it. Offline in the same sense
  /// `MprisStore.forTesting` is: nothing here opens a socket unless [client]
  /// does.
  @visibleForTesting
  factory WeatherStore.forTesting({
    required WeatherClient client,
    WeatherConfig config = const WeatherConfig(),
  }) {
    final store = WeatherStore._(client: client);
    store._config = config;
    return store;
  }

  final WeatherClient _client;

  WeatherConfig _config = const WeatherConfig();
  WeatherConfig get config => _config;

  /// Applies [config]; the module's `fromMap` pushes it here.
  ///
  /// A cadence change while leased restarts the timer; a change of *unit or
  /// location* refetches, because both change what the reading says and waiting
  /// out the interval reads as the setting not working.
  void configure(WeatherConfig config) {
    final previous = _config;
    if (previous == config) return;
    _config = config;
    if (_timer == null) return;

    if (config.refreshMinutes != previous.refreshMinutes) {
      _stopTimer();
      _startTimer();
    }
    final refetch = config.unit != previous.unit ||
        config.latitude != previous.latitude ||
        config.longitude != previous.longitude;
    if (refetch) {
      // The place is resolved per fetch, so dropping the cached one is all it
      // takes for an automatic location to be looked up again.
      _resolved = null;
      _loading = true;
      notifyListeners();
      unawaited(refresh());
    }
  }

  TemperatureUnit get unit => _config.temperatureUnit;

  /// The degree suffix — `°F` or `°C`.
  String get unitLabel => unit.label;

  // --- published state -----------------------------------------------------

  WeatherReading? _current;
  WeatherReading? get current => _current;

  List<DayForecast> _forecast = const [];
  List<DayForecast> get forecast => List.unmodifiable(_forecast);

  WeatherPlace? _place;

  /// The place the reading on screen is for, once one has landed. Null before
  /// the first successful fetch — which for an automatic location is the only
  /// moment the shell does not know where it is.
  WeatherPlace? get place => _place;

  /// True until the first fetch settles, one way or the other. The bar shows a
  /// fixed-size loader in its place so the modules beside it do not shuffle
  /// when the reading lands.
  bool _loading = true;
  bool get loading => _loading;

  /// Why there is no reading, or empty when there is one.
  ///
  /// A visible state rather than a silent one, the rule
  /// `NotificationDaemonStatus` documents: an empty bar module is
  /// indistinguishable from one the user never enabled.
  String _error = '';
  String get error => _error;

  bool get hasReading => _current != null;

  /// The current condition, or null before the first reading.
  WeatherCondition? get condition => _current?.condition;

  /// `72°F` — the temperature alone, which is what a narrow bar shows beside
  /// the icon.
  String get temperatureText {
    final reading = _current;
    if (reading == null) return '';
    return '${reading.temperature.round()}${unit.label}';
  }

  /// The last time a fetch succeeded, for a "stale" hint.
  DateTime? _updatedAt;
  DateTime? get updatedAt => _updatedAt;

  // --- polling -------------------------------------------------------------

  int _leases = 0;
  Timer? _timer;

  /// A tick arriving while the previous fetch is still in flight is dropped,
  /// not queued behind it.
  bool _fetchInFlight = false;

  /// The resolved automatic location, kept between fetches so the IP lookup is
  /// one request per shell rather than one per refresh.
  WeatherPlace? _resolved;

  /// The lookup in flight, so two callers wanting the location at once make one
  /// request. There are two of them now — [refresh] and [resolvePlace] — and
  /// the second exists for a consumer that does not want the weather at all.
  Future<WeatherPlace>? _locating;

  /// Take a lease. The first one starts the refresh timer and fetches
  /// immediately, so the first consumer never waits a full interval.
  ///
  /// One lease level, unlike `MprisStore`'s: the desktop widget wants the same
  /// single response the bar does, and a second tier would buy a second code
  /// path and nothing else.
  void acquire() {
    _leases++;
    if (_timer == null) {
      _startTimer();
      unawaited(refresh());
    }
  }

  void release() {
    if (_leases > 0) _leases--;
    if (_leases == 0) _stopTimer();
  }

  @visibleForTesting
  int get leaseCount => _leases;

  @visibleForTesting
  bool get polling => _timer != null;

  void _startTimer() {
    _timer = Timer.periodic(
      Duration(minutes: _config.refreshMinutes),
      (_) => unawaited(refresh()),
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Where the shell thinks it is, without fetching any weather.
  ///
  /// The lunar widget needs a *location* and nothing else, and taking a weather
  /// lease for that would start a forecast poll to answer a question the config
  /// may already contain. So: the configured coordinates, then whatever a weather
  /// fetch has already resolved, then the one IP lookup — shared with [refresh]'s
  /// and cached for the life of the shell.
  ///
  /// Null rather than a throw when there is no answer: a consumer of this is by
  /// definition one that works without a location.
  Future<WeatherPlace?> resolvePlace() async {
    final configured = _config.place;
    if (configured != null) return configured;
    final known = _place ?? _resolved;
    if (known != null) return known;
    try {
      return await _locateOnce();
    } catch (e) {
      debugPrint('weather: could not resolve a location: $e');
      return null;
    }
  }

  /// The IP lookup, made at most once per shell and at most once at a time.
  Future<WeatherPlace> _locateOnce() {
    final cached = _resolved;
    if (cached != null) return Future.value(cached);
    return _locating ??= _client.locate().then(
      (place) {
        _resolved = place;
        _locating = null;
        return place;
      },
      // Cleared on the way out, or one failed lookup would be re-thrown at
      // every caller for the rest of the session.
      onError: (Object error) {
        _locating = null;
        throw error;
      },
    );
  }

  /// Fetch now. Public because both surfaces offer a retry: every failure here
  /// is recoverable without restarting the shell (the network comes back, the
  /// API stops rate-limiting) and the shell cannot detect either happening.
  Future<void> refresh() async {
    if (_fetchInFlight) return;
    _fetchInFlight = true;
    try {
      // Captured once, so the reading, the forecast and the degree suffix of
      // one fetch always agree even if the config moves mid-flight.
      final unit = this.unit;
      final configured = _config.place;
      final place = configured ?? await _locateOnce();
      final snapshot = await _client.fetch(place, unit);

      _place = snapshot.place;
      _current = snapshot.current;
      _forecast = snapshot.forecast;
      _updatedAt = DateTime.now();
      _error = '';
    } on WeatherException catch (e) {
      // A failed refresh keeps the last reading on screen: an hour-old
      // temperature is worth more than a blank card, and the error line says
      // which one the user is looking at.
      _error = e.message;
    } catch (e) {
      _error = 'Weather unavailable';
      debugPrint('weather: $e');
    } finally {
      _loading = false;
      _fetchInFlight = false;
      notifyListeners();
    }
  }

  /// Seeds a store for a widget test, with no client and no timer behind it.
  @visibleForTesting
  void seed({
    WeatherReading? current,
    List<DayForecast> forecast = const [],
    WeatherPlace? place,
    String error = '',
    bool loading = false,
  }) {
    _current = current;
    _forecast = forecast;
    _place = place;
    _error = error;
    _loading = loading;
    if (current != null) _updatedAt = DateTime.now();
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
