// The Moon, for the whole shell: one clock, one location lookup, one set of
// numbers, however many surfaces are drawing them.
//
// `WeatherStore`'s shape, down to the lease rule — a singleton `ChangeNotifier`
// whose ticker runs only while something is on screen — with two differences
// that follow from the Moon not being on the far end of a network:
//
// - **There is no loading state and no failure state.** The phase is
//   arithmetic over the current time, so [reading] can always answer and the
//   widget never has an empty frame to fill. The only thing that can be missing
//   is the *location*, and all that costs is the rise and set times.
// - **The location is borrowed, never asked for twice.** It comes from
//   `WeatherStore.resolvePlace()`, which answers from `[modules.weather]`'s
//   coordinates when the user has picked a place, from whatever a weather fetch
//   has already resolved when they have not, and only then makes an IP lookup —
//   one per shell, shared with the weather's own. A lunar widget on a machine
//   whose weather is configured therefore opens no socket at all.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/moon/moon_facts.dart';
import 'package:graceful_shell/moon/moon_phase.dart';
import 'package:graceful_shell/weather/weather_api.dart';
import 'package:graceful_shell/weather/weather_store.dart';

/// How often the numbers are recomputed while something is watching.
///
/// A minute, because that is the resolution of every time this feature prints.
/// The work is a few hundred multiply-adds and no I/O whatsoever, and a tick
/// that finds nothing new does not notify — see [_publish].
const Duration kMoonTickInterval = Duration(minutes: 1);

class MoonStore extends ChangeNotifier {
  MoonStore._({WeatherStore? weather, DateTime Function()? clock})
      : _weather = weather ?? WeatherStore.instance,
        _clock = clock ?? DateTime.now;

  static final MoonStore instance = MoonStore._();

  /// A detached store for tests. [weather] is required rather than defaulting
  /// to the singleton for the reason `WeatherStore.forTesting` exists at all:
  /// the real one carries an `OpenMeteoClient`, and a test that reached it
  /// would make an IP lookup from the test runner.
  @visibleForTesting
  factory MoonStore.forTesting({
    required WeatherStore weather,
    DateTime Function()? clock,
  }) =>
      MoonStore._(weather: weather, clock: clock);

  final WeatherStore _weather;
  final DateTime Function() _clock;

  // --- published state -----------------------------------------------------

  MoonReading? _reading;

  /// The current reading, computed on first read and refreshed on every tick.
  ///
  /// Never null and never stale by more than [kMoonTickInterval]: a consumer
  /// with no lease still gets a correct answer, it just does not get told when
  /// it changes.
  MoonReading get reading => _reading ??= _compute();

  List<MoonFact>? _facts;

  /// [reading]'s consequences, derived once per reading.
  ///
  /// Here rather than in the widget's `build` for the reason `_WeatherSkyState`
  /// caches its field: a desktop widget's `build` runs on every frame of a drag
  /// and of a resize, and this one costs two more evaluations of the whole
  /// ephemeris (`moon_facts.dart` reads the Moon's ecliptic latitude at both
  /// upcoming syzygies) on top of a dozen strings and a sort. None of it can
  /// move between two frames of the same reading, so none of it should be paid
  /// twice — and the store is the one thing that knows when the reading moved.
  List<MoonFact> get facts => _facts ??= moonFacts(reading);

  MoonTimes? _times;

  /// Tonight's moonrise and moonset, or null while the shell does not know
  /// where the user is.
  MoonTimes? get times => _times;

  WeatherPlace? _place;

  /// The place the rise and set times are for.
  WeatherPlace? get place => _place;

  /// The coordinates `[modules.weather]` carried at the last tick.
  ///
  /// Watched rather than waited for: `WeatherStore.configure` only notifies
  /// while the weather itself is polling, so on a machine with no weather
  /// module or widget on screen — which this widget is perfectly usable
  /// without — a location picked in settings would otherwise not reach the
  /// Moon until the next restart.
  WeatherPlace? _configuredPlace;

  bool _locating = true;

  /// Whether the shell is still working out where it is. False once the
  /// question has been answered *or* given up on, so a surface can tell
  /// "looking" from "there is no location and there will not be one".
  bool get locating => _locating;

  /// Whether the rise/set half of the widget has something to show.
  bool get hasLocation => _place != null;

  // --- leasing -------------------------------------------------------------

  int _leases = 0;
  Timer? _timer;
  bool _disposed = false;

  /// The local date [_times] was computed for, so a tick does not redo the
  /// twelve-hundred-odd trigonometric terms a rise/set scan costs while it is
  /// still the same day.
  DateTime? _timesDay;

  void acquire() {
    _leases++;
    if (_timer != null) return;
    _weather.addListener(_onWeatherChanged);
    _timer = Timer.periodic(kMoonTickInterval, (_) => _tick());
    _configuredPlace = _weather.config.place;
    unawaited(_syncPlace());
    // Silent: this runs inside the acquiring widget's `initState`, which builds
    // from the fresh state a moment later anyway, and a synchronous
    // `notifyListeners` from there would be a `setState` on any *other*
    // surface already holding a lease — during a build, which is an assertion.
    _tick(notify: false);
  }

  void release() {
    if (_leases > 0) _leases--;
    if (_leases > 0) return;
    _timer?.cancel();
    _timer = null;
    _weather.removeListener(_onWeatherChanged);
  }

  @visibleForTesting
  int get leaseCount => _leases;

  @visibleForTesting
  bool get ticking => _timer != null;

  /// Recompute now. Public for the same reason `WeatherStore.refresh` is: a
  /// surface that has just been given a location wants the times without
  /// waiting out the tick.
  void refresh() => _tick();

  // --- the work ------------------------------------------------------------

  MoonReading _compute() {
    final place = _place;
    return computeMoonReading(
      at: _clock(),
      latitude: place?.latitude,
      longitude: place?.longitude,
    );
  }

  void _tick({bool notify = true}) {
    final configured = _weather.config.place;
    if (configured != _configuredPlace) {
      _configuredPlace = configured;
      // Resolves to the new coordinates, or back to an IP lookup if the user
      // cleared them. It ticks again when it lands.
      unawaited(_syncPlace());
    }

    final now = _clock();
    _reading = computeMoonReading(
      at: now,
      latitude: _place?.latitude,
      longitude: _place?.longitude,
    );
    _facts = null;

    final place = _place;
    if (place == null) {
      _times = null;
      _timesDay = null;
    } else {
      final today = DateTime(now.year, now.month, now.day);
      if (_timesDay != today || _times == null) {
        _times = moonTimesFor(
          day: now,
          latitude: place.latitude,
          longitude: place.longitude,
        );
        _timesDay = today;
      }
    }
    _publish(notify: notify);
  }

  /// The last published state, as the values the surfaces actually draw.
  String? _published;

  /// Notify only when something a reader can see has moved.
  ///
  /// Every desktop surface on the machine listens to this, and most minutes
  /// change nothing on the card: the illumination moves by a tenth of a percent
  /// an hour and the rise time is fixed for the day. This is the `_publish`
  /// discipline `WorkspaceAppsStore` states — a store watched by every monitor
  /// must not re-lay them all to redraw an identical row.
  void _publish({bool notify = true}) {
    final current = reading;
    // Every entry is something a surface draws, which is the whole of the rule
    // and what the altitude and `isUp` used to break: no card in the shell
    // renders either, and both move continuously, so they could only ever add
    // wake-ups. What is left that moves every minute is the distance, and that
    // one is genuinely printed to the kilometre.
    //
    // The next principal phase is here as the *phase* rather than as its
    // instant, which is the same test one Newton search cheaper — the instant
    // changes exactly when the Moon crosses a quadrant of elongation, and so
    // does which phase is next. That is what keeps `_publish` off
    // `MoonReading`'s lazy getters, so a tick costs one position evaluation
    // rather than fifty.
    final signature = [
      current.phase.index,
      current.illuminationPercent,
      current.distanceKm.round(),
      current.nextPrincipalPhase.index,
      _times?.rise?.millisecondsSinceEpoch,
      _times?.set?.millisecondsSinceEpoch,
      _place?.name,
      _locating,
    ].join('|');
    if (signature == _published) return;
    _published = signature;
    if (notify && !_disposed) notifyListeners();
  }

  void _onWeatherChanged() => unawaited(_syncPlace());

  /// Adopt whatever location the weather layer can give us.
  Future<void> _syncPlace() async {
    final resolved = await _weather.resolvePlace();
    if (_disposed) return;
    _locating = false;
    if (resolved == _place) {
      _publish();
      return;
    }
    _place = resolved;
    // A new location is a new horizon: the cached rise and set are for the old
    // one and must not survive into the next tick.
    _times = null;
    _timesDay = null;
    _tick();
  }

  /// Seeds a store for a widget test: a fixed place and a fixed instant, with
  /// no timer and no weather lookup behind either.
  @visibleForTesting
  void seed({WeatherPlace? place, bool locating = false}) {
    _place = place;
    _locating = locating;
    _times = null;
    _timesDay = null;
    _tick();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _weather.removeListener(_onWeatherChanged);
    super.dispose();
  }
}
