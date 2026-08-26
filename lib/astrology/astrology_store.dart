// The horoscope for the whole shell: one request, however many surfaces are
// drawing it.
//
// `WeatherStore`'s singleton-`ChangeNotifier`-with-leases shape, and it needs
// it for the same reason with more force: the desktop surface is one
// FlutterView per monitor, so without a store a two-monitor user would make two
// requests per interval against somebody else's free deployment and could watch
// the two cards disagree about their own horoscope.
//
// Four things a change here has to keep true:
//
// - **The sign is local; only the text is remote.** `zodiacReadingFor` is
//   arithmetic and cannot fail, so the card can always name the sign, draw the
//   constellation and list the attributes. A network failure costs the
//   paragraph and nothing else, which is why [zodiac] is a separate getter from
//   [reading] and why [error] never blanks the card.
// - **A failed refresh keeps the last horoscope on screen.** `WeatherStore`'s
//   rule: a reading from this morning is worth more than an empty card, and the
//   error line says which one is being looked at. Both surfaces offer a retry
//   because every failure here is recoverable without restarting the shell and
//   the shell cannot detect the recovery happening.
// - **Nothing is fetched until there is a birthday.** With no sign there is no
//   request to make, so an unconfigured widget opens no socket at all — it
//   renders the one state the user can act on instead.
// - **A config change that moves the *sign* refetches; one that moves the
//   cadence restarts the timer.** Waiting out three hours to see a period
// switch   take effect reads as the setting not working, which is
// `WeatherStore.   configure`'s note.
//
// Flutter-free apart from `ChangeNotifier`, like the other stores.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/astrology/astrology_config.dart';
import 'package:graceful_shell/astrology/horoscope_api.dart';
import 'package:graceful_shell/astrology/zodiac.dart';
import 'package:graceful_shell/config_store.dart';

class AstrologyStore extends ChangeNotifier {
  AstrologyStore._({HoroscopeClient? client})
      : _client = client ?? const HoroscopeApiClient();

  static final AstrologyStore instance = AstrologyStore._();

  /// A detached store with an injected client, so a widget test can take a real
  /// lease with no network behind it. Offline in the same sense
  /// `WeatherStore.forTesting` is: nothing here opens a socket unless [client]
  /// does.
  @visibleForTesting
  factory AstrologyStore.forTesting({
    required HoroscopeClient client,
    AstrologyConfig config = const AstrologyConfig(),
  }) {
    final store = AstrologyStore._(client: client);
    store._config = config;
    return store;
  }

  final HoroscopeClient _client;

  AstrologyConfig _config = const AstrologyConfig();
  AstrologyConfig get config => _config;

  // --- published state -----------------------------------------------------

  HoroscopeReading? _reading;

  /// The horoscope on screen, or null before the first one lands.
  HoroscopeReading? get reading => _reading;

  bool get hasReading => _reading != null;

  /// The sign the configured birthday falls in, and its cusp neighbour when the
  /// birthday is one of the two days a month that has one. Null means no
  /// birthday has been set — the card's one actionable empty state, and
  /// distinct from a failed fetch.
  ZodiacReading? get zodiac => _config.reading;

  ZodiacSign? get sign => zodiac?.sign;

  HoroscopePeriod get period => _config.horoscopePeriod;

  /// True until the first fetch settles, one way or the other, and false
  /// forever once there is something to show — a refresh over an existing
  /// horoscope is not a reason to replace the paragraph the user is reading
  /// with a spinner. `FortuneStore.loading`'s rule.
  bool _loading = false;
  bool get loading => _loading && !hasReading;

  /// Why there is no horoscope, or empty when there is one. A visible state
  /// rather than a silent one.
  String _error = '';
  String get error => _error;

  /// The last time a fetch succeeded.
  DateTime? _updatedAt;
  DateTime? get updatedAt => _updatedAt;

  // --- leasing -------------------------------------------------------------

  int _leases = 0;
  Timer? _timer;
  bool _fetchInFlight = false;
  bool _disposed = false;

  ConfigStore? _configStore;

  /// Take a lease. The first one starts the timer and fetches immediately, so
  /// the first card on screen never waits out an interval.
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
      _config.refreshInterval,
      (_) => unawaited(refresh()),
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  // --- config --------------------------------------------------------------

  /// Binds [store] and applies `[astrology]` from it, then keeps it applied.
  ///
  /// The listener reads that subtree alone and never `ConfigStore.appConfig`,
  /// whose getter rebuilds the whole typed config and re-runs `Module.loadAll`
  /// as a side effect — it fires on every keystroke anywhere in the settings
  /// UI. [configure]'s own equality check is what makes those keystrokes free.
  void start(ConfigStore store) {
    if (_configStore == null) {
      _configStore = store;
      store.addListener(_onConfigChanged);
    }
    configure(_readConfig());
  }

  AstrologyConfig _readConfig() {
    final raw = _configStore?.get<Map<String, dynamic>>(['astrology']);
    return raw != null
        ? AstrologyConfig.fromMap(raw)
        : const AstrologyConfig();
  }

  void _onConfigChanged() => configure(_readConfig());

  /// Applies [config].
  ///
  /// A change of *sign, period or server* refetches, because all three change
  /// what the paragraph on screen says. A change of cadence restarts the timer.
  /// Anything else — and an identical config, which is what nearly every notify
  /// carries — does nothing at all.
  void configure(AstrologyConfig config) {
    final previous = _config;
    if (previous == config) return;
    _config = config;

    final refetch = config.sign != previous.sign ||
        config.horoscopePeriod != previous.horoscopePeriod ||
        config.apiBase != previous.apiBase;

    if (_timer != null && config.refreshInterval != previous.refreshInterval) {
      _stopTimer();
      _startTimer();
    }

    if (refetch) {
      // The reading on screen is the *other* sign's, or the other period's, so
      // unlike a failed refresh it is not worth keeping.
      _reading = null;
      _error = '';
      _updatedAt = null;
      // Set here as well as in [refresh] so the frame between this notify and
      // that one is a loader rather than the "No horoscope yet" the card would
      // immediately replace. `WeatherStore.configure` does the same.
      _loading = true;
      if (!_disposed) notifyListeners();
      if (_timer != null) unawaited(refresh());
    } else if (!_disposed) {
      // The sign did not move but something did — the widget draws the config's
      // own values (the attribute line, the period label), so it still has to
      // hear about it.
      notifyListeners();
    }
  }

  // --- the work ------------------------------------------------------------

  /// Fetch now. Public because both the card's retry and its refresh button
  /// call it.
  ///
  /// Nothing is notified at the *start* of a fetch, which is what makes this
  /// safe to call from [acquire] — that runs inside the acquiring widget's
  /// `initState`, and a synchronous `notifyListeners` from there is a
  /// `setState` on every other surface already holding a lease, during a build.
  /// `FortuneStore.refresh` and `WeatherStore.refresh` are arranged the same
  /// way and for the same reason.
  Future<void> refresh() async {
    if (_fetchInFlight) return;

    final sign = _config.sign;
    if (sign == null) {
      // No birthday: there is no request to make. Reported as the empty state
      // rather than as an error, because nothing has failed.
      _reading = null;
      _error = '';
      _loading = false;
      if (!_disposed) notifyListeners();
      return;
    }

    _fetchInFlight = true;
    _loading = true;
    try {
      // Captured once, so the paragraph and the label under it always agree
      // even if the config moves mid-flight.
      final period = _config.horoscopePeriod;
      final reading = await _client.fetch(
        sign: sign.label,
        period: period,
        apiBase: _config.apiBase,
      );
      // Dropped rather than published when the sign moved while it was in
      // flight: it is the previous sign's horoscope, and showing it under the
      // new one's name is the one wrong answer this card can give.
      if (_config.sign == sign && _config.horoscopePeriod == period) {
        _reading = reading;
        _updatedAt = DateTime.now();
        _error = '';
      }
    } on HoroscopeException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Horoscope unavailable';
      debugPrint('astrology: $e');
    } finally {
      _loading = false;
      _fetchInFlight = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Seeds a store for a widget test, with no client and no timer behind it.
  @visibleForTesting
  void seed({
    HoroscopeReading? reading,
    String error = '',
    bool loading = false,
    AstrologyConfig? config,
  }) {
    if (config != null) _config = config;
    _reading = reading;
    _error = error;
    _loading = loading;
    if (reading != null) _updatedAt = DateTime.now();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimer();
    _configStore?.removeListener(_onConfigChanged);
    super.dispose();
  }
}

/// Applies `[astrology]` to the store and keeps it applied. Called from
/// `main()` beside the other `start*Service` functions, after
/// [ConfigStore.initShared].
///
/// Like `startSystemStatsService` this **configures without polling**: the
/// first lease — a desktop card being drawn — is what opens a socket, so a
/// machine with no astrology widget on its desktop never makes a request.
void startAstrologyService(ConfigStore config) =>
    AstrologyStore.instance.start(config);
