// The Google Calendar events the shell shows, for the whole shell.
//
// The singleton-with-leases shape of `GithubStore` and `WeatherStore`: one
// poller for the machine however many surfaces show events, and none at all
// while nothing does. A lease here also names a *window* — the Calendar tab
// asks for the month on screen and the todo sync for today — and the store
// fetches the span covering every live window, so two consumers are still one
// request per calendar per interval.
//
// Every signed-in account is read. `[google] calendars` names calendars by id,
// which Google keeps unique across accounts, plus `primary` for every
// account's own; each id is read through the first account whose calendar list
// holds it, so a calendar shared with two of them is read once.
//
// **Each calendar is fetched on its own and fails on its own.** One that
// answers an error — deleted, unshared, or unreachable — costs that calendar's
// events and puts its name beside the reason, never the other calendars'.
// It keeps the last good answer on screen through a failed refresh, with the
// reason beside it, and notifies only when something a surface renders has
// moved.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/accounts/calendar_event_source.dart';
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
class GoogleCalendarStore extends ChangeNotifier
    implements CalendarEventSource {
  GoogleCalendarStore._({GoogleAccountStore? account, bool autoTimers = true})
    : _account = account ?? GoogleAccountStore.instance,
      _autoTimers = autoTimers {
    _account.addListener(_onAccount);
    _accountIds = _account.accounts.map((a) => a.id).join('\n');
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

  @override
  List<GoogleEvent> eventsOn(DateTime day) {
    final midnight = DateTime(day.year, day.month, day.day);
    return _events
        .where((e) => !e.cancelled && e.overlapsDay(midnight))
        .toList()
      ..sort(compareForDay);
  }

  /// All-day (and multi-day) events first, then by start, then the longer
  /// first, so a day's bars read in the order a calendar lists them.
  static int compareForDay(GoogleEvent a, GoogleEvent b) =>
      compareEventsForDay(a, b);

  /// Whether the local day [day] has any event, for the month grid's markers.
  @override
  bool hasEventsOn(DateTime day) {
    final midnight = DateTime(day.year, day.month, day.day);
    return _events.any((e) => !e.cancelled && e.overlapsDay(midnight));
  }

  final Map<String, List<GoogleCalendar>> _calendars = {};

  /// Each account's calendar list, by account id, once read.
  List<GoogleCalendar> calendarsOf(String accountId) =>
      _calendars[accountId] ?? const [];

  /// Whether [accountId]'s calendar list has been read.
  bool hasCalendarsOf(String accountId) => _calendars.containsKey(accountId);

  /// The calendar [event] was read from, once its account's list is known.
  GoogleCalendar? calendarOf(GoogleEvent event) {
    for (final c in calendarsOf(event.account)) {
      if (event.calendarId == 'primary'
          ? c.primary
          : c.id == event.calendarId) {
        return c;
      }
    }
    return null;
  }

  /// Whether [event] was read from a Google calendar: a CalDAV event's
  /// calendar is its collection's URL, which no Google calendar id is.
  @override
  bool owns(GoogleEvent event) => !event.calendarId.startsWith('http');

  /// The calendar's name, and the account's when more than one is linked.
  @override
  String calendarLabelOf(GoogleEvent event) {
    final name = calendarOf(event)?.summary ?? event.calendarId;
    return _account.accounts.length > 1 && event.account.isNotEmpty
        ? '$name · ${event.account}'
        : name;
  }

  /// `#rrggbb` to draw [event] in: its own colour, else its calendar's. Null
  /// when neither is known, for the theme's accent.
  @override
  String? colorOf(GoogleEvent event) => event.color ?? calendarOf(event)?.color;

  bool _loading = false;

  /// True while a fetch is in flight with nothing yet on screen.
  @override
  bool get loading => _loading;

  List<String> _errors = const [];

  /// Why calendars failed on the last fetch, one line per calendar. Empty
  /// when every calendar answered.
  List<String> get errors => _errors;

  /// [errors] as one line, or empty.
  @override
  String get error => _errors.join('\n');

  final Map<String, String> _calendarsErrors = {};

  /// Why [accountId]'s calendar list could not be read, or empty.
  String calendarsErrorOf(String accountId) =>
      _calendarsErrors[accountId] ?? '';

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
      ..write(error)
      ..write('|')
      ..write(_fetched?.from)
      ..write(_fetched?.to);
    for (final e in _events) {
      buffer
        ..write('|')
        ..write(e.key)
        ..write(e.hashCode);
    }
    for (final entry in _calendars.entries) {
      buffer
        ..write('|')
        ..write(entry.key)
        ..write(_calendarsErrors[entry.key]);
      for (final c in entry.value) {
        buffer
          ..write(',')
          ..write(c.id)
          ..write(c.summary)
          ..write(c.color);
      }
    }
    for (final entry in _calendarsErrors.entries) {
      buffer
        ..write('|!')
        ..write(entry.key)
        ..write(entry.value);
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

  // --- the accounts --------------------------------------------------------

  String _accountIds = '';

  void _onAccount() {
    final ids = _account.accounts.map((a) => a.id).join('\n');
    if (ids == _accountIds) {
      _publish();
      return;
    }
    _accountIds = ids;
    final live = ids.isEmpty ? const <String>{} : ids.split('\n').toSet();
    // Nothing of an account that has gone stays on screen.
    _calendars.removeWhere((id, _) => !live.contains(id));
    _calendarsErrors.removeWhere((id, _) => !live.contains(id));
    _byCalendar.removeWhere((key, _) => !live.contains(key.account));
    _rebuildEvents();
    _fetched = null;
    if (live.isEmpty) {
      _stopTimer();
      _errors = const [];
      _loading = false;
    } else if (_leases.isNotEmpty) {
      unawaited(refresh());
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

  /// The last good answer per calendar read, so one that fails keeps its
  /// events on screen while the others move on.
  final Map<({String account, String calendar}), List<GoogleEvent>>
  _byCalendar = {};

  void _rebuildEvents() {
    final seen = <String>{};
    final events = <GoogleEvent>[
      for (final list in _byCalendar.values)
        for (final e in list)
          if (seen.add(e.key)) e,
    ]..sort((a, b) => a.start.compareTo(b.start));
    _events = List.unmodifiable(events);
  }

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

  /// Which calendar each account reads, in account order: `primary` for an
  /// account whose own calendar is selected (under either spelling), then the
  /// selected calendars its list holds that no earlier account has claimed.
  ///
  /// A selected id no list holds — typed into `config.toml` by hand, a public
  /// calendar nobody subscribed to — is asked of every account whose list
  /// could not be read, since it may be the one holding it, or else of the
  /// first account: a readable calendar then shows, and one that is gone says
  /// so by name.
  @visibleForTesting
  List<({GoogleAccount account, String calendar, String name})> plan() {
    final selected = _config.calendars;
    final claimed = <String>{};
    final jobs = <({GoogleAccount account, String calendar, String name})>[];
    final unlisted = <GoogleAccount>[];
    for (final account in _account.accounts) {
      final list = _calendars[account.id];
      if (list == null) {
        unlisted.add(account);
        if (selected.contains('primary') ||
            (account.email.isNotEmpty && selected.contains(account.email))) {
          claimed.add(account.email);
          jobs.add((
            account: account,
            calendar: 'primary',
            name: account.label,
          ));
        }
        continue;
      }
      for (final c in list) {
        final on =
            selected.contains(c.id) ||
            (c.primary && selected.contains('primary'));
        if (!on || !claimed.add(c.id)) continue;
        jobs.add((
          account: account,
          calendar: c.primary ? 'primary' : c.id,
          name: c.summary,
        ));
      }
    }
    final accounts = _account.accounts;
    for (final id in selected) {
      if (id == 'primary' || claimed.contains(id) || accounts.isEmpty) {
        continue;
      }
      for (final account in unlisted.isEmpty ? [accounts.first] : unlisted) {
        jobs.add((account: account, calendar: id, name: id));
      }
    }
    return jobs;
  }

  /// Fetches the leased span now. Public because a failure offers a retry: a
  /// network comes back and the shell cannot see it happen.
  @override
  Future<void> refresh() async {
    final wanted = _wanted;
    if (wanted == null || !_account.signedIn) return;
    if (_fetchInFlight) {
      // A window moved mid-fetch: fetch again once this one lands.
      _refetch = true;
      return;
    }
    _fetchInFlight = true;
    if (_fetched == null && _events.isEmpty) _loading = true;
    _publish();
    final config = _config;
    final accountIds = _accountIds;
    try {
      // A calendar list is what says which account holds a calendar and what
      // colour it is, so an account's is read before its first fetch.
      await Future.wait([
        for (final a in _account.accounts)
          if (!_calendars.containsKey(a.id)) _loadCalendarsOf(a),
      ]);
      final jobs = plan();
      final results = await Future.wait([
        for (final job in jobs) _fetchOne(job, wanted.from, wanted.to),
      ]);
      // Answered for a question since changed: the next fetch is the one.
      if (config != _config || accountIds != _accountIds) {
        _refetch = true;
      } else {
        final errors = <String>[];
        final live = <({String account, String calendar})>{};
        for (var i = 0; i < jobs.length; i++) {
          final job = jobs[i];
          final key = (account: job.account.id, calendar: job.calendar);
          live.add(key);
          final result = results[i];
          if (result.events case final events?) {
            _byCalendar[key] = events;
          } else {
            final named = jobs.length > 1 || _account.accounts.length > 1;
            errors.add(named ? '${job.name}: ${result.error}' : result.error!);
          }
        }
        _byCalendar.removeWhere((key, _) => !live.contains(key));
        _rebuildEvents();
        _errors = List.unmodifiable(errors);
        if (errors.isEmpty) _fetched = wanted;
      }
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

  Future<({List<GoogleEvent>? events, String? error})> _fetchOne(
    ({GoogleAccount account, String calendar, String name}) job,
    DateTime from,
    DateTime to,
  ) async {
    try {
      final events = await _account.withAccessToken(
        job.account.id,
        (token) => _account.client.listEvents(
          accessToken: token,
          calendarId: job.calendar,
          from: from,
          to: to,
        ),
      );
      return (
        events: [for (final e in events) e.withAccount(job.account.id)],
        error: null,
      );
    } on GoogleException catch (e) {
      return (events: null, error: e.message);
    } catch (e) {
      debugPrint('google: calendar fetch failed: $e');
      return (events: null, error: 'Google Calendar unavailable');
    }
  }

  final Set<String> _calendarsInFlight = {};

  /// Reads every account's calendar list, for the settings page's choice of
  /// which calendars to show. A list that changed which calendars are read
  /// refetches the events.
  Future<void> loadCalendars() async {
    String planned() =>
        [for (final j in plan()) '${j.account.id}/${j.calendar}'].join('\n');
    final before = planned();
    await Future.wait([for (final a in _account.accounts) _loadCalendarsOf(a)]);
    if (planned() != before && _leases.isNotEmpty && _account.signedIn) {
      _fetched = null;
      unawaited(refresh());
    }
  }

  Future<void> _loadCalendarsOf(GoogleAccount account) async {
    if (!_calendarsInFlight.add(account.id)) return;
    try {
      final calendars = await _account.withAccessToken(
        account.id,
        _account.client.listCalendars,
      );
      calendars.sort((a, b) {
        if (a.primary != b.primary) return a.primary ? -1 : 1;
        return a.summary.toLowerCase().compareTo(b.summary.toLowerCase());
      });
      if (_account.accounts.contains(account)) {
        _calendars[account.id] = List.unmodifiable(calendars);
        _calendarsErrors.remove(account.id);
      }
    } on GoogleException catch (e) {
      if (_account.accounts.contains(account)) {
        _calendarsErrors[account.id] = e.message;
      }
    } catch (e) {
      if (_account.accounts.contains(account)) {
        _calendarsErrors[account.id] = 'Could not read the calendar list';
      }
      debugPrint('google: calendar list failed: $e');
    } finally {
      _calendarsInFlight.remove(account.id);
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
