// The Calendar tab's account half: the selected day's Google Calendar events
// under the month, and the dot under each day that has any.
//
// Both read `GoogleCalendarStore` and nothing else. The tab owns the lease (the
// month on screen), so neither widget causes a request. The dot subscribes
// *per cell* on a bool, so a refresh that moved one day's events rebuilds that
// day's dot and none of the other forty-one cells.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/google/google_calendar_store.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/calendar/month.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The fixed height of one agenda row, so the list can be a fixed-extent
/// `ListView` rather than a `Column` that overflows on a busy day.
const double kAgendaRowExtent = 40;

/// How many rows the agenda shows before it scrolls.
const int kAgendaVisibleRows = 4;

/// The dot under a day with events. Sized and positioned by the cell.
class CalendarEventDot extends StatelessWidget {
  const CalendarEventDot({
    super.key,
    required this.store,
    required this.day,
    required this.color,
  });

  final GoogleCalendarStore store;
  final DateTime day;
  final Color color;

  @override
  Widget build(BuildContext context) => StoreSelector<bool>(
    listenable: store,
    selector: () => store.hasEventsOn(day),
    builder: (context, has) => has
        ? Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          )
        : const SizedBox(width: 4, height: 4),
  );
}

String _two(int n) => n.toString().padLeft(2, '0');

/// "10:00–10:30", "All day", or the part of a multi-day event on [day].
String agendaTimeLabel(GoogleEvent e, DateTime day) {
  if (e.allDay) return 'All day';
  final midnight = dayKey(day);
  final next = DateTime(midnight.year, midnight.month, midnight.day + 1);
  final from = e.start.isBefore(midnight) ? null : e.start;
  final to = e.end.isAfter(next) ? null : e.end;
  String at(DateTime? t) =>
      t == null ? '…' : '${_two(t.hour)}:${_two(t.minute)}';
  if (from != null && to != null && from == to) return at(from);
  return '${at(from)}–${at(to)}';
}

/// The selected day's events, the reason there are none, or a loader.
class CalendarAgenda extends StatelessWidget {
  const CalendarAgenda({
    super.key,
    required this.store,
    required this.day,
    required this.onOpen,
  });

  final GoogleCalendarStore store;
  final DateTime day;

  /// Opens a URL in the browser.
  final bool Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final events = store.eventsOn(day);
        final error = store.error;
        final Widget body;
        if (store.loading && events.isEmpty) {
          body = const Center(child: LoadingIndicator(size: 16));
        } else if (events.isEmpty && error.isEmpty) {
          body = Align(
            alignment: Alignment.centerLeft,
            child: SettingsHint(
              'Nothing on ${weekdayNames[day.weekday % 7]} '
              '${day.day} ${monthAbbrev[day.month - 1]}.',
            ),
          );
        } else {
          body = ListView.builder(
            itemCount: events.length,
            itemExtent: kAgendaRowExtent,
            scrollCacheExtent: const ScrollCacheExtent.pixels(
              kAgendaRowExtent * kAgendaVisibleRows,
            ),
            itemBuilder: (context, i) =>
                _AgendaRow(event: events[i], day: day, onOpen: onOpen),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.triangleExclamation,
                      size: 11,
                      color: kErrorColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        error,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: ShellFontSizes.secondary,
                          fontFamily: theme.fontFamily,
                          color: theme.popupForeground.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SettingsActionButton(
                      label: 'Retry',
                      compact: true,
                      onTap: store.refresh,
                    ),
                  ],
                ),
              ),
            SizedBox(
              height: kAgendaRowExtent * kAgendaVisibleRows,
              child: body,
            ),
          ],
        );
      },
    );
  }
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({
    required this.event,
    required this.day,
    required this.onOpen,
  });

  final GoogleEvent event;
  final DateTime day;
  final bool Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final page = event.htmlLink;
    final join = event.meetingLink;
    // Built outside the hover builder, so a hover repaints a decoration and
    // does not re-shape two paragraphs.
    final content = Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            agendaTimeLabel(event, day),
            maxLines: 1,
            style: TextStyle(
              fontSize: ShellFontSizes.secondary,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.6),
            ),
          ),
        ),
        Expanded(
          child: Text(
            event.summary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ShellFontSizes.body,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground,
            ),
          ),
        ),
        if (join != null) ...[
          const SizedBox(width: 8),
          SettingsActionButton(
            label: 'Join',
            primary: true,
            compact: true,
            onTap: () => onOpen(join),
          ),
        ],
      ],
    );
    return RepaintBoundary(
      child: HoverRegion(
        enabled: page != null,
        onTap: page == null ? null : () => onOpen(page),
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: hovered ? theme.surfaceHover : const Color(0x00000000),
            borderRadius: BorderRadius.circular(ShellRadii.control),
          ),
          child: content,
        ),
      ),
    );
  }
}
