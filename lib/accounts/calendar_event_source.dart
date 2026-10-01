// What the Calendar tab reads events through, whichever account they came
// from: a Google account's calendars (`GoogleCalendarStore`) or a CalDAV
// server's (`CalDavCalendarStore`), and [MergedCalendarEvents], which is both
// at once.
//
// Each source is its own store with its own leases, poll and errors, because
// the two fail for different reasons and neither may take the other's events
// off the screen. The merge holds no state: it answers every question by
// asking the sources, and listening to it is listening to them.

import 'package:flutter/foundation.dart';

import 'package:moonswing/google/google_api.dart';

/// A store of events the Calendar tab draws.
abstract interface class CalendarEventSource implements Listenable {
  /// The events on the local day [day], all-day ones first, then by start.
  /// Cancelled ones are left out.
  List<GoogleEvent> eventsOn(DateTime day);

  /// Whether the local day [day] has any event.
  bool hasEventsOn(DateTime day);

  /// Whether [event] came from this source.
  bool owns(GoogleEvent event);

  /// `#rrggbb` to draw [event] in, or null for the theme's accent.
  String? colorOf(GoogleEvent event);

  /// The calendar [event] is on, as its details name it — with the account
  /// beside it when there is more than one to tell apart.
  String calendarLabelOf(GoogleEvent event);

  /// True while a fetch is in flight with nothing yet on screen.
  bool get loading;

  /// Why calendars failed on the last fetch, one line per calendar, or empty.
  String get error;

  /// Fetches again now.
  Future<void> refresh();
}

/// All-day (and multi-day) events first, then by start, then the longer
/// first, so a day's bars read in the order a calendar lists them.
int compareEventsForDay(GoogleEvent a, GoogleEvent b) {
  if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
  final byStart = a.start.compareTo(b.start);
  if (byStart != 0) return byStart;
  return b.end.compareTo(a.end);
}

/// Several sources read as one.
///
/// Compared by its sources, so a tab that builds a fresh one per frame hands
/// its views an equal object and a `StoreSelector` keeps its subscription.
@immutable
class MergedCalendarEvents implements CalendarEventSource {
  MergedCalendarEvents(List<CalendarEventSource> sources)
    : sources = List.unmodifiable(sources),
      _listenable = Listenable.merge(sources);

  final List<CalendarEventSource> sources;
  final Listenable _listenable;

  @override
  void addListener(VoidCallback listener) => _listenable.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _listenable.removeListener(listener);

  @override
  List<GoogleEvent> eventsOn(DateTime day) {
    if (sources.length == 1) return sources.single.eventsOn(day);
    return [for (final s in sources) ...s.eventsOn(day)]
      ..sort(compareEventsForDay);
  }

  @override
  bool hasEventsOn(DateTime day) => sources.any((s) => s.hasEventsOn(day));

  CalendarEventSource? _ownerOf(GoogleEvent event) {
    for (final s in sources) {
      if (s.owns(event)) return s;
    }
    return null;
  }

  @override
  bool owns(GoogleEvent event) => _ownerOf(event) != null;

  @override
  String? colorOf(GoogleEvent event) => _ownerOf(event)?.colorOf(event);

  @override
  String calendarLabelOf(GoogleEvent event) =>
      _ownerOf(event)?.calendarLabelOf(event) ?? event.calendarId;

  @override
  bool get loading => sources.any((s) => s.loading);

  @override
  String get error => [
    for (final s in sources)
      if (s.error.isNotEmpty) s.error,
  ].join('\n');

  @override
  Future<void> refresh() => Future.wait([for (final s in sources) s.refresh()]);

  @override
  bool operator ==(Object other) =>
      other is MergedCalendarEvents && listEquals(other.sources, sources);

  @override
  int get hashCode => Object.hashAll(sources);
}
