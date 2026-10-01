// The CalDAV calendars' events the shell shows, for the whole shell.
//
// `GoogleCalendarStore`'s shape, for the same reasons: one poller for the
// machine however many surfaces show events and none while nothing does, a
// lease names the window of time its holder shows, and the store fetches the
// span covering every live window — one `calendar-query` per calendar per
// interval.
//
// Every signed-in account is read. `[caldav] calendars` names calendars by
// collection URL, which is unique across servers, so one list serves every
// account; each is read through the account it was found on.
//
// **Each calendar is fetched on its own and fails on its own**, and keeps its
// last good answer on screen through a failed refresh with the reason beside
// it, named — one server being down costs that server's events and nobody
// else's. Nothing is notified unless something a surface renders has moved.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/accounts/calendar_event_source.dart';
import 'package:moonswing/caldav/caldav_account_store.dart';
import 'package:moonswing/caldav/caldav_client.dart';
import 'package:moonswing/caldav/caldav_config.dart';
import 'package:moonswing/caldav/caldav_events.dart';
import 'package:moonswing/google/google_api.dart';

/// A consumer's hold on the store: a window of time it wants events for.
class CalDavCalendarLease {
  CalDavCalendarLease._(this._store, this._from, this._to);

  final CalDavCalendarStore _store;
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

/// One calendar to read, and the account to read it through.
typedef CalDavCalendarJob = ({CalDavAccount account, Uri url, String name});

/// The events of the chosen CalDAV calendars, and the poll behind them.
class CalDavCalendarStore extends ChangeNotifier
    implements CalendarEventSource {
  CalDavCalendarStore._({
    CalDavAccountStore? accounts,
    bool autoTimers = true,
    this.zone,
  }) : _accounts = accounts ?? CalDavAccountStore.instance,
       _autoTimers = autoTimers {
    _accounts.addListener(_onAccounts);
    _accountsSignature = _signatureOfAccounts();
  }

  static final CalDavCalendarStore instance = CalDavCalendarStore._();

  /// A detached store over [accounts]. [autoTimers] false leaves out the
  /// refresh timer, which a widget test's end-of-test check would trip on.
  @visibleForTesting
  factory CalDavCalendarStore.forTesting({
    required CalDavAccountStore accounts,
    CalDavConfig config = const CalDavConfig(),
    bool autoTimers = false,
    ZoneConverter? zone,
  }) {
    final store = CalDavCalendarStore._(
      accounts: accounts,
      autoTimers: autoTimers,
      zone: zone,
    );
    store._config = config;
    return store;
  }

  final CalDavAccountStore _accounts;
  final bool _autoTimers;

  /// How a time written with a `TZID` becomes local time. Set at start-up to
  /// the IANA database's; null reads every such time as local.
  ZoneConverter? zone;

  CalDavAccountStore get accounts => _accounts;

  // --- configuration -------------------------------------------------------

  CalDavConfig _config = const CalDavConfig();
  CalDavConfig get config => _config;

  /// Whether there is anything to show: an account, a calendar chosen, and
  /// the events switched on.
  bool get active =>
      _config.showInCalendar &&
      _config.calendars.isNotEmpty &&
      _accounts.signedIn;

  /// Applies [config]. A change to which calendars are read refetches, since
  /// waiting out an interval reads as the setting not working; a cadence
  /// change re-arms the timer.
  void configure(CalDavConfig config) {
    final previous = _config;
    if (previous == config) return;
    _config = config;
    if (!listEquals(previous.calendars, config.calendars)) {
      _fetched = null;
      // A calendar switched off goes at once, not at the next answer.
      _byCalendar.removeWhere((url, _) => !config.shows(url));
      _rebuildEvents();
      _errors = const [];
      if (_leases.isNotEmpty) unawaited(refresh());
      _publish();
    } else if (previous.refreshMinutes != config.refreshMinutes) {
      if (_leases.isNotEmpty) _armTimer();
    }
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
      ..sort(compareEventsForDay);
  }

  @override
  bool hasEventsOn(DateTime day) {
    final midnight = DateTime(day.year, day.month, day.day);
    return _events.any((e) => !e.cancelled && e.overlapsDay(midnight));
  }

  /// A CalDAV event's calendar is its collection's URL.
  @override
  bool owns(GoogleEvent event) => event.calendarId.startsWith('http');

  /// The calendar [event] was read from, while its account still lists it.
  CalDavCollection? calendarOf(GoogleEvent event) {
    for (final a in _accounts.accounts) {
      if (a.id != event.account) continue;
      for (final c in a.calendars) {
        if (c.url.toString() == event.calendarId) return c;
      }
    }
    return null;
  }

  @override
  String? colorOf(GoogleEvent event) => event.color ?? calendarOf(event)?.color;

  @override
  String calendarLabelOf(GoogleEvent event) {
    final name = calendarOf(event)?.name ?? event.calendarId;
    final account = _accounts.accountWithId(event.account);
    return _accounts.accounts.length > 1 && account != null
        ? '$name · ${account.label}'
        : name;
  }

  bool _loading = false;

  @override
  bool get loading => _loading;

  List<String> _errors = const [];

  /// Why calendars failed on the last fetch, one line per calendar.
  List<String> get errors => _errors;

  @override
  String get error => _errors.join('\n');

  /// The span the last *successful* fetch answered for.
  ({DateTime from, DateTime to})? _fetched;

  /// Whether the last successful fetch answered for all of [from]–[to] with
  /// the calendars now configured.
  bool covers(DateTime from, DateTime to) {
    final fetched = _fetched;
    return fetched != null &&
        !fetched.from.isAfter(from) &&
        !fetched.to.isBefore(to);
  }

  String get _signature {
    final buffer = StringBuffer()
      ..write(_accountsSignature)
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

  String _accountsSignature = '';

  /// What of the accounts decides what is read and how it is drawn: who they
  /// are, how they sign in, and the calendars' names and colours.
  String _signatureOfAccounts() {
    final buffer = StringBuffer();
    for (final a in _accounts.accounts) {
      buffer
        ..write(a.id)
        ..write('\u0000')
        ..write(a.password.hashCode)
        ..write(a.trustedCertificate);
      for (final c in a.calendars) {
        buffer
          ..write(',')
          ..write(c.url)
          ..write(c.name)
          ..write(c.color);
      }
      buffer.write('\n');
    }
    return buffer.toString();
  }

  void _onAccounts() {
    final signature = _signatureOfAccounts();
    if (signature == _accountsSignature) return;
    _accountsSignature = signature;
    final live = {for (final job in plan()) job.url};
    // Nothing of an account that has gone stays on screen.
    _byCalendar.removeWhere((url, _) => !live.contains(url));
    _rebuildEvents();
    _fetched = null;
    if (!_accounts.signedIn) {
      _stopTimer();
      _errors = const [];
      _loading = false;
    } else if (_leases.isNotEmpty) {
      unawaited(refresh());
    }
    _publish();
  }

  // --- leases --------------------------------------------------------------

  final List<CalDavCalendarLease> _leases = [];

  /// Takes a lease on [from]–[to]. The first lease, or one the last fetch does
  /// not cover, fetches straight away. Never notifies synchronously, since it
  /// runs inside the acquirer's `initState`.
  CalDavCalendarLease acquire(DateTime from, DateTime to) {
    final lease = CalDavCalendarLease._(this, from, to);
    _leases.add(lease);
    scheduleMicrotask(_windowsChanged);
    return lease;
  }

  void _release(CalDavCalendarLease lease) {
    _leases.remove(lease);
    if (_leases.isEmpty) _stopTimer();
  }

  @visibleForTesting
  int get leaseCount => _leases.length;

  @visibleForTesting
  bool get polling => _timer != null;

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
    if (wanted == null || !_accounts.signedIn) return;
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

  /// The last good answer per calendar, so one that fails keeps its events on
  /// screen while the others move on.
  final Map<Uri, List<GoogleEvent>> _byCalendar = {};

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

  /// Which calendars are read, and through which account: every chosen one an
  /// account lists, in account order, then any chosen URL no list holds —
  /// typed into `config.toml` by hand, or gone from the server — through the
  /// account on its server, so a readable one shows and one that is gone
  /// says so by name.
  @visibleForTesting
  List<CalDavCalendarJob> plan() {
    final selected = _config.calendars;
    if (selected.isEmpty) return const [];
    final claimed = <String>{};
    final jobs = <CalDavCalendarJob>[];
    for (final a in _accounts.accounts) {
      for (final c in a.eventCalendars) {
        final url = c.url.toString();
        if (!selected.contains(url) || !claimed.add(url)) continue;
        jobs.add((account: a, url: c.url, name: c.name));
      }
    }
    for (final url in selected) {
      if (claimed.contains(url)) continue;
      final parsed = calDavServerUri(url);
      final account = parsed == null ? null : _accounts.accountOf(parsed);
      if (parsed == null || account == null) continue;
      jobs.add((account: account, url: parsed, name: url));
    }
    return jobs;
  }

  /// Fetches the leased span now. Public because a failure offers a retry: a
  /// network comes back and the shell cannot see it happen.
  @override
  Future<void> refresh() async {
    final wanted = _wanted;
    if (wanted == null || !_accounts.signedIn) return;
    if (_fetchInFlight) {
      // A window moved mid-fetch: fetch again once this one lands.
      _refetch = true;
      return;
    }
    _fetchInFlight = true;
    if (_fetched == null && _events.isEmpty) _loading = true;
    _publish();
    final config = _config;
    final accounts = _accountsSignature;
    try {
      final jobs = plan();
      final results = await Future.wait([
        for (final job in jobs) _fetchOne(job, wanted.from, wanted.to),
      ]);
      // Answered for a question since changed: the next fetch is the one.
      if (config != _config || accounts != _accountsSignature) {
        _refetch = true;
      } else {
        final errors = <String>[];
        final live = <Uri>{};
        for (var i = 0; i < jobs.length; i++) {
          final job = jobs[i];
          live.add(job.url);
          final result = results[i];
          if (result.events case final events?) {
            _byCalendar[job.url] = events;
          } else {
            errors.add(
              jobs.length > 1 ? '${job.name}: ${result.error}' : result.error!,
            );
          }
        }
        _byCalendar.removeWhere((url, _) => !live.contains(url));
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
      } else if (_leases.isNotEmpty && _accounts.signedIn) {
        _armTimer();
      }
    }
  }

  Future<({List<GoogleEvent>? events, String? error})> _fetchOne(
    CalDavCalendarJob job,
    DateTime from,
    DateTime to,
  ) async {
    try {
      final resources = await _accounts
          .clientFor(job.account)
          .listEvents(job.url, from: from, to: to);
      return (
        events: [
          for (final r in resources)
            ...eventsFromICalendar(
              r.data,
              calendarId: job.url.toString(),
              account: job.account.id,
              from: from,
              to: to,
              zone: zone,
            ),
        ],
        error: null,
      );
    } on CalDavException catch (e) {
      return (events: null, error: e.message);
    } catch (e) {
      debugPrint('caldav: calendar fetch failed: $e');
      return (events: null, error: 'Could not read the calendar');
    }
  }

  @override
  void dispose() {
    _stopTimer();
    _accounts.removeListener(_onAccounts);
    super.dispose();
  }
}
