import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/overlay/calendar/event.dart';
import 'package:graceful_shell/overlay/calendar/google_provider.dart';
import 'package:graceful_shell/overlay/calendar/month.dart';
import 'package:graceful_shell/overlay/calendar/provider.dart';
import 'package:graceful_shell/overlay/calendar/token_store.dart';

enum CalendarSyncState { idle, connecting, loading, ready, error }

/// How far either side of the visible month to fetch, so the leading and
/// trailing cells of the month grid are populated too.
const Duration _kWindowPadding = Duration(days: 7);

/// Process-wide calendar state.
///
/// Same shape as [NotificationStore] and [TrayStore]: a singleton
/// [ChangeNotifier] that a start-up function populates and widgets watch with a
/// [ListenableBuilder].
class CalendarStore extends ChangeNotifier {
  CalendarStore._();

  static final CalendarStore instance = CalendarStore._();

  /// Builds a store over fake providers, so the state machine can be tested
  /// without a network or a real Google account.
  @visibleForTesting
  factory CalendarStore.forTesting(List<CalendarProvider> providers) {
    final store = CalendarStore._();
    store._providers.addAll(providers);
    return store;
  }

  final List<CalendarProvider> _providers = [];

  CalendarProvider? _providerById(String id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  CalendarConfig _config = const CalendarConfig();

  CalendarSyncState _state = CalendarSyncState.idle;
  String? _error;
  DateTime? _lastSync;

  Map<DateTime, List<CalendarEvent>> _eventsByDay = {};

  /// The month currently loaded, so [ensureMonth] can tell a page-turn from a
  /// re-open of the same month.
  DateTime? _loadedMonth;

  /// In-flight fetch, so two callers asking for the same month share one request
  /// rather than racing.
  Future<void>? _inFlight;
  DateTime? _inFlightMonth;

  Timer? _pollTimer;

  List<CalendarProvider> get providers => List.unmodifiable(_providers);

  CalendarProvider? get google => _providerById('google');

  bool get hasConnectedAccount => _providers.any((p) => p.isConnected);

  CalendarSyncState get state => _state;
  String? get error => _error;
  DateTime? get lastSync => _lastSync;

  Map<DateTime, List<CalendarEvent>> get eventsByDay =>
      Map.unmodifiable(_eventsByDay);

  List<CalendarEvent> eventsOn(DateTime day) =>
      _eventsByDay[dayKey(day)] ?? const [];

  bool hasEvents(DateTime day) => eventsOn(day).isNotEmpty;

  CalendarConfig get config => _config;

  /// Applies config, creating the providers on first call and refreshing their
  /// credentials on later ones — so entering a client ID in the settings UI
  /// takes effect without restarting the shell.
  void configure(CalendarConfig config, CalendarTokenStore tokenStore) {
    _config = config;

    final existing = google;
    if (existing is GoogleCalendarProvider) {
      existing.updateConfig(config.google ?? const GoogleOAuthConfig());
    } else {
      _providers.add(GoogleCalendarProvider(
        config: config.google ?? const GoogleOAuthConfig(),
        tokenStore: tokenStore,
      ));
    }

    _restartPollingIfConnected();
    notifyListeners();
  }

  /// Loads persisted tokens. Runs at startup, so it must not touch the network.
  Future<void> restore() async {
    for (final provider in _providers) {
      try {
        await provider.restore();
      } catch (e) {
        debugPrint('Could not restore ${provider.id} calendar: $e');
      }
    }
    _restartPollingIfConnected();
    notifyListeners();
  }

  Future<void> connect(String providerId, {void Function(Uri url)? onUrl}) async {
    final provider = _providerById(providerId);
    if (provider == null) return;

    _setState(CalendarSyncState.connecting, error: null);
    try {
      await provider.connect(onUrl: onUrl);
    } on CalendarAuthException catch (e) {
      _setState(CalendarSyncState.idle, error: e.message);
      return;
    } catch (e) {
      _setState(CalendarSyncState.idle, error: 'Could not connect: $e');
      return;
    }

    _setState(CalendarSyncState.idle, error: null);
    _restartPollingIfConnected();

    final month = _loadedMonth ?? _monthOf(DateTime.now());
    await ensureMonth(month, force: true);
  }

  Future<void> cancelConnect(String providerId) async {
    final provider = _providerById(providerId);
    if (provider is GoogleCalendarProvider) await provider.cancelConnect();
  }

  Future<void> disconnect(String providerId) async {
    final provider = _providerById(providerId);
    if (provider == null) return;

    try {
      await provider.disconnect();
    } catch (e) {
      debugPrint('Could not cleanly disconnect ${provider.id}: $e');
    }

    if (!hasConnectedAccount) {
      _eventsByDay = {};
      _loadedMonth = null;
      _lastSync = null;
      stopPolling();
    }
    _setState(CalendarSyncState.idle, error: null);
  }

  /// Loads events around [month], unless they are already loaded and fresh.
  ///
  /// Concurrent calls for the same month share one fetch: the calendar tab
  /// prefetches on open while the user may immediately page a month forward.
  Future<void> ensureMonth(DateTime month, {bool force = false}) async {
    final target = _monthOf(month);

    if (!hasConnectedAccount) {
      _loadedMonth = target;
      return;
    }

    if (_inFlight != null && _inFlightMonth == target) return _inFlight;

    if (!force && _loadedMonth == target && !_isStale) return;

    final fetch = _fetch(target);
    _inFlight = fetch;
    _inFlightMonth = target;
    try {
      await fetch;
    } finally {
      _inFlight = null;
      _inFlightMonth = null;
    }
  }

  bool get _isStale {
    final last = _lastSync;
    if (last == null) return true;
    return DateTime.now().difference(last) >=
        Duration(minutes: _config.refreshMinutes);
  }

  Future<void> _fetch(DateTime month) async {
    final from = month.subtract(_kWindowPadding);
    final to = addMonths(month, 1).add(_kWindowPadding);

    _setState(CalendarSyncState.loading, error: null);

    final events = <CalendarEvent>[];
    for (final provider in _providers) {
      if (!provider.isConnected) continue;
      try {
        events.addAll(await provider.fetchEvents(from, to));
      } on CalendarAuthException catch (e) {
        // The provider has already dropped its tokens. Fall back to the connect
        // pane rather than showing a stale agenda for an account we have lost.
        if (!hasConnectedAccount) {
          _eventsByDay = {};
          _loadedMonth = null;
          stopPolling();
        }
        _setState(CalendarSyncState.idle, error: e.message);
        return;
      } on CalendarFetchException catch (e) {
        // Transient: keep the tokens and whatever events we already have, so the
        // grid stays usable offline.
        _setState(CalendarSyncState.error, error: e.message);
        return;
      } catch (e) {
        _setState(CalendarSyncState.error, error: 'Could not load events: $e');
        return;
      }
    }

    _eventsByDay = groupByDay(events);
    _loadedMonth = month;
    _lastSync = DateTime.now();
    _setState(CalendarSyncState.ready, error: null);
  }

  void startPolling() {
    stopPolling();
    _pollTimer = Timer.periodic(
      Duration(minutes: _config.refreshMinutes),
      (_) {
        final month = _loadedMonth;
        if (month != null) ensureMonth(month, force: true);
      },
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _restartPollingIfConnected() {
    if (hasConnectedAccount) {
      startPolling();
    } else {
      stopPolling();
    }
  }

  void _setState(CalendarSyncState state, {required String? error}) {
    _state = state;
    _error = error;
    notifyListeners();
  }

  static DateTime _monthOf(DateTime d) => DateTime(d.year, d.month, 1);

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}

/// Wires up the calendar providers at startup and restores saved tokens.
///
/// Deliberately does no network I/O: an offline machine or an expired account
/// must not delay the shell coming up. The first fetch happens when the user
/// opens the calendar tab.
Future<void> startCalendarService(CalendarConfig config) async {
  final tokenStore = CalendarTokenStore();

  try {
    CalendarStore.instance.configure(config, tokenStore);
    await CalendarStore.instance.restore();
  } catch (e) {
    debugPrint('Calendar service unavailable: $e');
  }

  // The connect pane writes the OAuth client ID and secret into the ConfigStore.
  // Re-reading them here is what lets "Connect" light up the moment they are
  // entered, instead of only after a restart.
  ConfigStore.instance.addListener(() {
    final map = ConfigStore.instance.get<Map<String, dynamic>>(['calendar']);
    CalendarStore.instance.configure(CalendarConfig.fromMap(map), tokenStore);
  });
}
