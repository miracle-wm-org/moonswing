// The Google Calendar events the shell shows, for the whole shell.
//
// The singleton-with-leases shape of `GithubStore` and `WeatherStore`: one
// poller for the machine however many surfaces show events, and none at all
// while nothing does. A lease here also names a *window* — the Calendar tab
// asks for the month on screen and the todo sync for today — and the store
// fetches the span covering every live window, so two consumers are still one
// request per calendar per interval.
//
// It keeps the last good answer on screen through a failed refresh, with the
// reason beside it, and notifies only when something a surface renders has
// moved.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/google/google_account_store.dart';
import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/google/google_config.dart';

/// A consumer's hold on the store: a window of time it wants events for.
class GoogleCalendarLease {
  GoogleCalendarLease._(this._store, this._from, this._to);

  final GoogleCalendarStore _store;
  DateTime _from;
  DateTime _to;
  bool _released = false;

  DateTime get from => _from;
  DateTime get to => _to;

  /// Moves the window. A window the last fetch does not cover is fetched now.
  void update(DateTime from, DateTime to) {
    if (_released || (from == _from && to == _to)) return;
    _from = from;
    _to = to;
    // Scheduled rather than run: a window moves from inside a build, and a
    // fetch starting publishes synchronously.
    scheduleMicrotask(_store._windowsChanged);
  }

  void release() {
    if (_released) return;
    _released = true;
    _store._release(this);
  }
}

/// The events, the calendar list, and the poll behind both.
class GoogleCalendarStore extends ChangeNotifier {
  GoogleCalendarStore._({GoogleAccountStore? account, bool autoTimers = true})
    : _account = account ?? GoogleAccountStore.instance,
      _autoTimers = autoTimers {
    _account.addListener(_onAccount);
    _wasSignedIn = _account.signedIn;
  }

  static final GoogleCalendarStore instance = GoogleCalendarStore._();

  /// A detached store over [account]. [autoTimers] false leaves out the
  /// refresh timer, which a widget test's end-of-test check would trip on.
  @visibleForTesting
  factory GoogleCalendarStore.forTesting({
    required GoogleAccountStore account,
    GoogleConfig config = const GoogleConfig(),
    bool autoTimers = false,
  }) {
    final store = GoogleCalendarStore._(
      account: account,
      autoTimers: autoTimers,
    );
    store._config = config;
    return store;
  }

  final GoogleAccountStore _account;
  final bool _autoTimers;

  GoogleAccountStore get account => _account;

  // --- configuration -------------------------------------------------------

  GoogleConfig _config = const GoogleConfig();
  GoogleConfig get config => _config;

  /// Applies [config]. A change to which calendars are read refetches, since
  /// waiting out an interval reads as the setting not working; a cadence
  /// change re-arms the timer.
  void configure(GoogleConfig config) {
    final previous = _config;
    if (previous == config) return;
    _config = config;
    if (!listEquals(previous.calendars, config.calendars)) {
      _fetched = null;
      if (_leases.isNotEmpty) unawaited(refresh());
      // The list on screen answered a different question.
      _publish();
    } else if (previous.refreshMinutes != config.refreshMinutes) {
      if (_leases.isNotEmpty) _armTimer();
    }
    // Everything else in the section (showing the events at all, the todo
    // sync) is its consumers' to act on, and they rebuild on the config.
    notifyListeners();
  }

  // --- published state -----------------------------------------------------

  List<GoogleEvent> _events = const [];

  /// Every fetched occurrence, cancelled ones included, in start order.
  List<GoogleEvent> get events => _events;

  /// The events on the local day [day], all-day ones first, then by start.
  /// Cancelled ones are left out.
  List<GoogleEvent> eventsOn(DateTime day) {
    final midnight = DateTime(day.year, day.month, day.day);
    return _events
        .where((e) => !e.cancelled && e.overlapsDay(midnight))
        .toList()
      ..sort((a, b) {
        if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
        return a.start.compareTo(b.start);
      });
  }

  /// Whether the local day [day] has any event, for the month grid's markers.
  bool hasEventsOn(DateTime day) {
    final midnight = DateTime(day.year, day.month, day.day);
    return _events.any((e) => !e.cancelled && e.overlapsDay(midnight));
  }

  List<GoogleCalendar> _calendars = const [];

  /// The account's calendar list, once [loadCalendars] has answered.
  List<GoogleCalendar> get calendars => _calendars;

  bool _loading = false;

  /// True while a fetch is in flight with nothing yet on screen.
  bool get loading => _loading;

  String _error = '';

  /// Why the last fetch failed, or empty.
  String get error => _error;

  String _calendarsError = '';

  /// Why the calendar list could not be read, or empty.
  String get calendarsError => _calendarsError;

  /// The span the last *successful* fetch answered for.
  ({DateTime from, DateTime to})? _fetched;

  /// Whether the last successful fetch answered for all of [from]–[to] with the
  /// calendars now configured. The todo sync abandons cards whose events are
  /// missing, so it must know the list in hand is a whole answer rather than
  /// an absent one.
  bool covers(DateTime from, DateTime to) {
    final fetched = _fetched;
    return fetched != null &&
        !fetched.from.isAfter(from) &&
        !fetched.to.isBefore(to);
  }

  String get _signature {
    final buffer = StringBuffer()
      ..write(_account.stage.name)
      ..write('|')
      ..write(_loading)
      ..write('|')
      ..write(_error)
      ..write('|')
      ..write(_calendarsError)
      ..write('|')
      ..write(_fetched?.from)
      ..write(_fetched?.to);
    for (final e in _events) {
      buffer
        ..write('|')
        ..write(e.key)
        ..write(e.summary)
        ..write(e.start)
        ..write(e.end)
        ..write(e.cancelled)
        ..write(e.meetingLink)
        ..write(e.htmlLink);
    }
    for (final c in _calendars) {
      buffer
        ..write('|')
        ..write(c.id)
        ..write(c.summary)
        ..write(c.color);
    }
    return buffer.toString();
  }

  String _published = '';

  void _publish() {
    final signature = _signature;
    if (signature == _published) return;
    _published = signature;
    notifyListeners();
  }

  // --- the account ---------------------------------------------------------

  bool _wasSignedIn = false;

  void _onAccount() {
    final signedIn = _account.signedIn;
    if (signedIn == _wasSignedIn) return;
    _wasSignedIn = signedIn;
    if (signedIn) {
      if (_leases.isNotEmpty) unawaited(refresh());
    } else {
      // Nothing of the old account stays on screen.
      _stopTimer();
      _events = const [];
      _calendars = const [];
      _fetched = null;
      _error = '';
      _calendarsError = '';
      _loading = false;
    }
    _publish();
  }

  // --- leases --------------------------------------------------------------

  final List<GoogleCalendarLease> _leases = [];

  /// Takes a lease on [from]–[to]. The first lease, or one the last fetch does
  /// not cover, fetches straight away. Never notifies synchronously, since it
  /// runs inside the acquirer's `initState`.
  GoogleCalendarLease acquire(DateTime from, DateTime to) {
    final lease = GoogleCalendarLease._(this, from, to);
    _leases.add(lease);
    scheduleMicrotask(_windowsChanged);
    return lease;
  }

  void _release(GoogleCalendarLease lease) {
    _leases.remove(lease);
    if (_leases.isEmpty) _stopTimer();
  }

  @visibleForTesting
  int get leaseCount => _leases.length;

  @visibleForTesting
  bool get polling => _timer != null;

  /// The span covering every live window.
  ({DateTime from, DateTime to})? get _wanted {
    if (_leases.isEmpty) return null;
    var from = _leases.first.from;
    var to = _leases.first.to;
    for (final lease in _leases.skip(1)) {
      if (lease.from.isBefore(from)) from = lease.from;
      if (lease.to.isAfter(to)) to = lease.to;
    }
    return (from: from, to: to);
  }

  void _windowsChanged() {
    final wanted = _wanted;
    if (wanted == null || !_account.signedIn) return;
    if (!covers(wanted.from, wanted.to)) {
      unawaited(refresh());
    } else if (_timer == null && !_fetchInFlight) {
      _armTimer();
    }
  }

  // --- fetching ------------------------------------------------------------

  Timer? _timer;
  bool _fetchInFlight = false;
  bool _refetch = false;

  void _armTimer() {
    _timer?.cancel();
    _timer = null;
    if (!_autoTimers || _leases.isEmpty) return;
    _timer = Timer(Duration(minutes: _config.refreshMinutes), () {
      _timer = null;
      if (_leases.isNotEmpty) unawaited(refresh());
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Fetches the leased span now. Public because a failure offers a retry: a
  /// network comes back and the shell cannot see it happen.
  Future<void> refresh() async {
    final wanted = _wanted;
    if (wanted == null || !_account.signedIn) return;
    if (_fetchInFlight) {
      // A window moved mid-fetch: fetch again once this one lands.
      _refetch = true;
      return;
    }
    _fetchInFlight = true;
    if (_fetched == null) _loading = true;
    _publish();
    final calendars = _config.calendars;
    try {
      final events = <GoogleEvent>[];
      for (final id in calendars) {
        events.addAll(
          await _account.withAccessToken(
            (token) => _account.client.listEvents(
              accessToken: token,
              calendarId: id,
              from: wanted.from,
              to: wanted.to,
            ),
          ),
        );
      }
      // Answered for a question since changed: the next fetch is the one.
      if (!listEquals(calendars, _config.calendars) || !_account.signedIn) {
        _refetch = true;
      } else {
        events.sort((a, b) => a.start.compareTo(b.start));
        _events = List.unmodifiable(events);
        _fetched = wanted;
        _error = '';
      }
    } on GoogleException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Google Calendar unavailable';
      debugPrint('google: calendar fetch failed: $e');
    } finally {
      _fetchInFlight = false;
      _loading = false;
      _publish();
      if (_refetch) {
        _refetch = false;
        unawaited(refresh());
      } else if (_leases.isNotEmpty && _account.signedIn) {
        _armTimer();
      }
    }
  }

  bool _calendarsInFlight = false;

  /// Reads the account's calendar list, for the settings page's choice of
  /// which calendars to show.
  Future<void> loadCalendars() async {
    if (_calendarsInFlight || !_account.signedIn) return;
    _calendarsInFlight = true;
    try {
      final calendars = await _account.withAccessToken(
        _account.client.listCalendars,
      );
      calendars.sort((a, b) {
        if (a.primary != b.primary) return a.primary ? -1 : 1;
        return a.summary.toLowerCase().compareTo(b.summary.toLowerCase());
      });
      _calendars = List.unmodifiable(calendars);
      _calendarsError = '';
    } on GoogleException catch (e) {
      _calendarsError = e.message;
    } catch (e) {
      _calendarsError = 'Could not read the calendar list';
      debugPrint('google: calendar list failed: $e');
    } finally {
      _calendarsInFlight = false;
      _publish();
    }
  }

  @override
  void dispose() {
    _stopTimer();
    _account.removeListener(_onAccount);
    super.dispose();
  }
}
