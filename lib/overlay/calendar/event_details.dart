// One event, in full: what a click on any of the Calendar tab's bars and boxes
// opens.
//
// A card over the overlay rather than a native popup: the overlay already
// spans the output and is focused, so a modal in its root `Overlay` gets the
// keyboard (Escape closes it) and a click on the scrim for free, and nothing
// about it needs a surface of its own.
//
// The buttons are the event's ways *out* — join the call, open the event in
// Google Calendar, open what it links to — and each closes the card as it
// opens the browser, since the browser is where the user is going.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/google/google_calendar_store.dart';
import 'package:moonswing/overlay/calendar/calendar_events.dart';
import 'package:moonswing/overlay/calendar/event_layout.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/root_modal.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// Shows [event]'s details over the overlay. Resolves when the card closes.
Future<void> showEventDetails(
  BuildContext context, {
  required GoogleEvent event,
  required GoogleCalendarStore store,
  required bool Function(String url) openUrl,
}) => showRootModal<void>(
  context,
  (close) => EventDetailsCard(
    event: event,
    store: store,
    onClose: () => close(null),
    onOpen: (url) {
      openUrl(url);
      close(null);
    },
  ),
);

/// The label on the join button: "Join Google Meet", "Join Zoom Meeting".
String joinLabel(GoogleEvent e) {
  final name = e.meetingName ?? linkLabel(e.meetingLink ?? '');
  return name.isEmpty ? 'Join meeting' : 'Join $name';
}

FaIconData _iconFor(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host == 'docs.google.com' || host == 'drive.google.com') {
    return FontAwesomeIcons.googleDrive;
  }
  return FontAwesomeIcons.link;
}

class EventDetailsCard extends StatelessWidget {
  const EventDetailsCard({
    super.key,
    required this.event,
    required this.store,
    required this.onClose,
    required this.onOpen,
  });

  final GoogleEvent event;
  final GoogleCalendarStore store;
  final VoidCallback onClose;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final color = eventColor(store, event, theme);
    final calendar = store.calendarOf(event);
    final several = store.account.accounts.length > 1;
    final calendarName = calendar?.summary ?? event.calendarId;
    final join = event.meetingLink;
    final page = event.htmlLink;
    final links = event.links;
    final location = event.location;
    final description = event.description;
    // A location that is only the join link says nothing the button does not.
    final showLocation = location != null && location != join;

    final secondary = TextStyle(
      fontSize: ShellFontSizes.secondary,
      fontFamily: theme.fontFamily,
      height: 1.4,
      color: theme.popupForeground.withValues(alpha: 0.75),
    );

    Widget line(FaIconData icon, Widget child) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: FaIcon(
                icon,
                size: ShellFontSizes.secondary,
                color: theme.popupForeground.withValues(alpha: 0.55),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );

    final actions = <Widget>[
      if (join != null)
        SettingsActionButton(
          label: joinLabel(event),
          icon: FontAwesomeIcons.video,
          primary: true,
          compact: true,
          onTap: () => onOpen(join),
        ),
      if (page != null)
        SettingsActionButton(
          label: 'Open in Google Calendar',
          icon: FontAwesomeIcons.calendar,
          compact: true,
          onTap: () => onOpen(page),
        ),
      for (final link in links.take(8))
        SettingsActionButton(
          label: link.label,
          icon: _iconFor(link.url),
          compact: true,
          onTap: () => onOpen(link.url),
        ),
    ];

    final card = PopupCard(
      border: Border.all(color: theme.accent, width: 1.5),
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 10),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  event.summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.title,
                    fontFamily: theme.fontFamily,
                    fontWeight: FontWeight.w600,
                    color: theme.popupForeground,
                  ),
                ),
              ),
              SettingsIconButton(
                icon: FontAwesomeIcons.xmark,
                size: 12,
                onTap: onClose,
              ),
            ],
          ),
          line(
            FontAwesomeIcons.clock,
            Text(eventWhenLabel(event), style: secondary),
          ),
          line(
            FontAwesomeIcons.calendarDays,
            Text(
              several && event.account.isNotEmpty
                  ? '$calendarName · ${event.account}'
                  : calendarName,
              style: secondary,
            ),
          ),
          if (showLocation)
            line(
              FontAwesomeIcons.locationDot,
              Text(location, style: secondary),
            ),
          if (description != null)
            line(
              FontAwesomeIcons.alignLeft,
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(description, style: secondary),
                ),
              ),
            ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            // Each sized to its label: a compact button centres its label
            // in whatever width it is given, and a Wrap gives it all of it.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final a in actions) IntrinsicWidth(child: a)],
            ),
          ],
        ],
      ),
    );

    return Focus(
      autofocus: true,
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: Container(color: const Color(0x66000000)),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
              // Taps on the card are the card's, never the scrim's.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: card,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
