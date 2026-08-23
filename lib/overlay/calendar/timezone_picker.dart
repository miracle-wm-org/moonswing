import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/overlay/calendar/time_zones.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/search_list.dart';

const double kTimeZonePickerWidth = 260;
const double kTimeZonePickerMaxHeight = 320;

/// The height of one row in the zone list. Fixed, so scrolling the highlight
/// into view is arithmetic instead of a measurement.
const double kTimeZoneRowHeight = 34;

/// The "+" that adds a world clock, and the searchable list it opens.
///
/// [zones] is supplied by the caller rather than read from the database here,
/// so widget tests pass a handful of names and never load the IANA tables.
///
/// A thin wrapper over [AnchoredSearchDropdown], which owns the root-overlay
/// float, the filter field, and the keyboard navigation; only the trigger,
/// the [rankTimeZones] ranking, and the city/region row live here. It does
/// not need the root-owned overlay *window* that `showAppChooser` uses: the
/// calendar tab already sits inside `SettingsOverlay`'s own `Overlay`, with
/// `DefaultTextEditingShortcuts` above it, which is what makes an
/// [EditableText] in an inserted entry work at all.
class TimeZonePickerButton extends StatelessWidget {
  const TimeZonePickerButton({
    super.key,
    required this.zones,
    required this.existing,
    required this.onSelected,
  });

  final List<TimeZoneName> zones;

  /// Zone names already on the list. Those rows are shown with a check and
  /// selecting one still fires — a zone vanishing from the picker would read
  /// as a missing zone, not as one already added.
  final Set<String> existing;

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return AnchoredSearchDropdown<TimeZoneName>(
      width: kTimeZonePickerWidth,
      maxHeight: kTimeZonePickerMaxHeight,
      rowHeight: kTimeZoneRowHeight,
      emptyText: 'No matching time zone',
      // Anchored on the right: the button sits at the right edge of a narrow
      // column, so the card has to grow leftwards into the panel.
      alignRight: true,
      filter: (query) => rankTimeZones(zones, query),
      onSelected: (zone) => onSelected(zone.name),
      itemBuilder: (context, zone, highlighted) {
        final theme = ThemeScope.of(context);
        final added = existing.contains(zone.name);
        final alpha = added ? 0.45 : 1.0;
        return Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    zone.city,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: theme.fontFamily,
                      color:
                          (highlighted ? theme.accent : theme.popupForeground)
                              .withValues(alpha: alpha),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    zone.region,
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: theme.fontFamily,
                      color:
                          theme.popupForeground.withValues(alpha: 0.45 * alpha),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (added)
              FaIcon(
                FontAwesomeIcons.check,
                size: 10,
                color: theme.popupForeground.withValues(alpha: 0.5),
              ),
          ],
        );
      },
      triggerBuilder: (context, open, toggle) => SettingsIconButton(
        icon: FontAwesomeIcons.plus,
        size: 11,
        onTap: toggle,
      ),
    );
  }
}
