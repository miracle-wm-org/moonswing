// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/overlay/calendar/calendar_store.dart';
import 'package:graceful_shell/overlay/calendar/event.dart';
import 'package:graceful_shell/overlay/calendar/month.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';

/// Width of the agenda column. The month grid takes whatever is left.
const double _kAgendaWidth = 300;

/// The Calendar tab of the overlay: a month grid on the left, and on the right
/// either the selected day's agenda or the pane for connecting an account.
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  _CalendarTabState createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  final CalendarStore _store = CalendarStore.instance;

  late DateTime _visibleMonth;
  late DateTime _selectedDay;

  /// The consent URL, while a sign-in is waiting on the browser. Shown so the
  /// user can copy it if xdg-open could not reach a browser.
  Uri? _consentUrl;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _selectedDay = dayKey(today);
    _visibleMonth = DateTime(today.year, today.month, 1);

    // The tab is built (though not painted) as soon as the overlay opens, since
    // it sits in an IndexedStack — so this prefetches while the user may still
    // be looking at the settings tab. ensureMonth coalesces, so it is cheap.
    _store.ensureMonth(_visibleMonth);
  }

  void _goToMonth(DateTime month) {
    setState(() => _visibleMonth = DateTime(month.year, month.month, 1));
    _store.ensureMonth(_visibleMonth);
  }

  void _goToToday() {
    final today = DateTime.now();
    setState(() {
      _selectedDay = dayKey(today);
      _visibleMonth = DateTime(today.year, today.month, 1);
    });
    _store.ensureMonth(_visibleMonth);
  }

  Future<void> _connect() async {
    setState(() => _consentUrl = null);
    await _store.connect(
      'google',
      onUrl: (url) {
        if (mounted) setState(() => _consentUrl = url);
      },
    );
    if (mounted) setState(() => _consentUrl = null);
  }

  Future<void> _cancelConnect() async {
    await _store.cancelConnect('google');
    if (mounted) setState(() => _consentUrl = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _MonthPane(
                visibleMonth: _visibleMonth,
                selectedDay: _selectedDay,
                weekStart: _store.config.weekStart,
                hasEvents: _store.hasEvents,
                onMonthChanged: _goToMonth,
                onDaySelected: (day) => setState(() => _selectedDay = day),
                onToday: _goToToday,
              ),
            ),
            Container(width: 1, color: theme.divider),
            SizedBox(
              width: _kAgendaWidth,
              child: _store.hasConnectedAccount
                  ? _AgendaPane(
                      day: _selectedDay,
                      events: _store.eventsOn(_selectedDay),
                      store: _store,
                    )
                  : _ConnectPane(
                      store: _store,
                      consentUrl: _consentUrl,
                      onConnect: _connect,
                      onCancel: _cancelConnect,
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Month grid
// ---------------------------------------------------------------------------

class _MonthPane extends StatelessWidget {
  const _MonthPane({
    required this.visibleMonth,
    required this.selectedDay,
    required this.weekStart,
    required this.hasEvents,
    required this.onMonthChanged,
    required this.onDaySelected,
    required this.onToday,
  });

  final DateTime visibleMonth;
  final DateTime selectedDay;
  final int weekStart;
  final bool Function(DateTime) hasEvents;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final grid = buildMonthGrid(
      visibleMonth.year,
      visibleMonth.month,
      weekStart: weekStart,
    );
    final today = dayKey(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MonthHeader(
            month: visibleMonth,
            onPrevious: () => onMonthChanged(addMonths(visibleMonth, -1)),
            onNext: () => onMonthChanged(addMonths(visibleMonth, 1)),
            onToday: onToday,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      weekdayInitials[(weekStart + i) % 7],
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground.withValues(alpha: 0.45),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Column(
              children: [
                for (var week = 0; week < 6; week++)
                  Expanded(
                    child: Row(
                      children: [
                        for (var weekday = 0; weekday < 7; weekday++)
                          Builder(builder: (context) {
                            final index = week * 7 + weekday;
                            final day = grid.days[index];
                            return Expanded(
                              child: _DayCell(
                                day: day,
                                inMonth: grid.isInMonth(index),
                                isToday: day == today,
                                isSelected: day == selectedDay,
                                hasEvents: hasEvents(day),
                                onTap: () => onDaySelected(day),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Row(
      children: [
        Text(
          '${monthNames[month.month - 1]} ${month.year}',
          style: TextStyle(
            fontSize: 18,
            fontFamily: theme.fontFamily,
            color: theme.popupForeground,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        _TodayButton(onTap: onToday),
        const SizedBox(width: 4),
        SettingsIconButton(
          icon: FontAwesomeIcons.chevronLeft,
          size: 12,
          onTap: onPrevious,
        ),
        SettingsIconButton(
          icon: FontAwesomeIcons.chevronRight,
          size: 12,
          onTap: onNext,
        ),
      ],
    );
  }
}

class _TodayButton extends StatefulWidget {
  const _TodayButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_TodayButton> createState() => _TodayButtonState();
}

class _TodayButtonState extends State<_TodayButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered ? theme.surfaceHover : theme.controlSurface,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Today',
            style: TextStyle(
              fontSize: 12,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayCell extends StatefulWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.hasEvents,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final bool hasEvents;
  final VoidCallback onTap;

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    final Color background;
    if (widget.isSelected) {
      background = theme.accent;
    } else if (_hovered) {
      background = theme.surfaceHover;
    } else {
      background = const Color(0x00000000);
    }

    // Days spilling in from the neighbouring months stay legible but recede.
    var foreground = widget.isSelected
        ? theme.popupForeground
        : theme.popupForeground.withValues(alpha: widget.inMonth ? 0.9 : 0.35);
    if (widget.isToday && !widget.isSelected) foreground = theme.accent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: widget.isToday && !widget.isSelected
                ? Border.all(color: theme.accent, width: 1.5)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${widget.day.day}',
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: theme.fontFamily,
                  color: foreground,
                  fontWeight: widget.isToday || widget.isSelected
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 3),
              // A dot rather than a count: the agenda has the detail, and the
              // grid only needs to answer "is anything happening that day".
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.hasEvents
                      ? (widget.isSelected
                          ? theme.popupForeground
                          : theme.accent)
                      : const Color(0x00000000),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Agenda
// ---------------------------------------------------------------------------

class _AgendaPane extends StatelessWidget {
  const _AgendaPane({
    required this.day,
    required this.events,
    required this.store,
  });

  final DateTime day;
  final List<CalendarEvent> events;
  final CalendarStore store;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Text(
            _formatDayHeading(day),
            style: TextStyle(
              fontSize: 14,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (store.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: _ErrorBanner(
              message: store.error!,
              onRetry: () => store.ensureMonth(day, force: true),
            ),
          ),
        Expanded(
          child: events.isEmpty
              ? Center(
                  child: Text(
                    store.state == CalendarSyncState.loading
                        ? 'Loading…'
                        : 'No events',
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground.withValues(alpha: 0.4),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  itemCount: events.length,
                  itemBuilder: (context, i) => _EventTile(event: events[i]),
                ),
        ),
        Container(height: 1, color: theme.divider),
        _AccountFooter(store: store, day: day),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final accent = event.color ?? theme.accent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 34,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatEventTime(event),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground.withValues(alpha: 0.5),
                  ),
                ),
                if (event.location != null && event.location!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      event.location!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountFooter extends StatelessWidget {
  const _AccountFooter({required this.store, required this.day});

  final CalendarStore store;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final account = store.google?.account;
    final loading = store.state == CalendarSyncState.loading;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
      child: Row(
        children: [
          FaIcon(
            FontAwesomeIcons.google,
            size: 11,
            color: theme.popupForeground.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              account?.email ?? 'Connected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.5),
              ),
            ),
          ),
          SettingsIconButton(
            icon: loading
                ? FontAwesomeIcons.hourglassHalf
                : FontAwesomeIcons.arrowsRotate,
            size: 11,
            onTap: () {
              if (!loading) store.ensureMonth(day, force: true);
            },
          ),
          SettingsIconButton(
            icon: FontAwesomeIcons.rightFromBracket,
            size: 11,
            onTap: () => store.disconnect('google'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connect
// ---------------------------------------------------------------------------

/// Shown in place of the agenda until an account is connected. The month grid
/// beside it stays fully usable, so the calendar is worth opening even for
/// someone who never signs in.
class _ConnectPane extends StatelessWidget {
  const _ConnectPane({
    required this.store,
    required this.consentUrl,
    required this.onConnect,
    required this.onCancel,
  });

  final CalendarStore store;
  final Uri? consentUrl;
  final VoidCallback onConnect;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final connecting = store.state == CalendarSyncState.connecting;
    final google = store.config.google ?? const GoogleOAuthConfig();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Google Calendar',
            style: TextStyle(
              fontSize: 14,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (store.error != null) ...[
            _ErrorBanner(message: store.error!, onRetry: onConnect),
            const SizedBox(height: 12),
          ],
          if (connecting)
            _ConnectingBody(consentUrl: consentUrl, onCancel: onCancel)
          else ...[
            const SettingsHint(
              'Connect an account to see your events here. Graceful Shell uses '
              'your own Google OAuth client, so create a "Desktop app" client in '
              'the Google Cloud Console, enable the Calendar API, and paste its '
              'credentials below.',
            ),
            const SizedBox(height: 8),
            const SettingsSubLabel('Client ID'),
            SettingsTextField(
              initial: google.clientId,
              onChanged: (v) => ConfigStore.instance
                  .set(['calendar', 'google', 'client_id'], v.trim()),
            ),
            const SettingsSubLabel('Client secret'),
            SettingsTextField(
              initial: google.clientSecret,
              onChanged: (v) => ConfigStore.instance
                  .set(['calendar', 'google', 'client_secret'], v.trim()),
            ),
            const SizedBox(height: 16),
            _PrimaryButton(
              label: 'Connect Google Calendar',
              // The store's provider is what actually knows whether the
              // credentials are usable, so ask it rather than re-checking here.
              enabled: store.google?.isConfigured ?? false,
              onTap: onConnect,
            ),
            if (!(store.google?.isConfigured ?? false))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SettingsHint('Enter both fields to enable connecting.'),
              ),
          ],
        ],
      ),
    );
  }
}

class _ConnectingBody extends StatelessWidget {
  const _ConnectingBody({required this.consentUrl, required this.onCancel});

  final Uri? consentUrl;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Waiting for your browser…',
          style: TextStyle(
            fontSize: 13,
            fontFamily: theme.fontFamily,
            color: theme.popupForeground.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 8),
        const SettingsHint(
          'Approve the request in the browser tab that opened. If no tab '
          'opened, copy this link into a browser.',
        ),
        if (consentUrl != null) ...[
          const SizedBox(height: 10),
          _CopyLinkRow(url: consentUrl!),
        ],
        const SizedBox(height: 16),
        _PrimaryButton(label: 'Cancel', enabled: true, onTap: onCancel),
      ],
    );
  }
}

class _CopyLinkRow extends StatefulWidget {
  const _CopyLinkRow({required this.url});

  final Uri url;

  @override
  State<_CopyLinkRow> createState() => _CopyLinkRowState();
}

class _CopyLinkRowState extends State<_CopyLinkRow> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: theme.controlSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.url.toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.6),
              ),
            ),
          ),
          SettingsIconButton(
            icon: _copied ? FontAwesomeIcons.check : FontAwesomeIcons.copy,
            size: 11,
            onTap: () async {
              await Clipboard.setData(
                ClipboardData(text: widget.url.toString()),
              );
              if (mounted) setState(() => _copied = true);
            },
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final enabled = widget.enabled;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: enabled ? widget.onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled
                ? theme.accent.withValues(alpha: _hovered ? 1.0 : 0.85)
                : theme.controlSurface,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground
                  .withValues(alpha: enabled ? 1.0 : 0.35),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.85),
              ),
            ),
          ),
          SettingsIconButton(
            icon: FontAwesomeIcons.arrowsRotate,
            size: 11,
            onTap: onRetry,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

const List<String> _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _formatDayHeading(DateTime day) {
  final weekday = _weekdayNames[day.weekday - 1];
  return '$weekday, ${monthNames[day.month - 1]} ${day.day}';
}

String _formatEventTime(CalendarEvent event) {
  if (event.allDay) return 'All day';
  return '${_formatClock(event.start)} – ${_formatClock(event.end)}';
}

String _formatClock(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
