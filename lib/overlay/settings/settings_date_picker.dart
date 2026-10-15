// ignore_for_file: invalid_use_of_internal_member
// The date picker: a month of days on a card of its own, opened from a
// calendar button beside a date field.
//
// A *true* popup — a native window parented to whatever surface the button is
// on, through [PopupHost] — rather than a float in the root overlay the way
// [AnchoredSearchDropdown] is: the card is themed and animated as every other
// popup in the shell is, is free to open past the edge of the form that opened
// it, and closes on a click anywhere else because [PopupCoordinator] closes it,
// not because the form remembered to.
library;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:layer_shell/layer_shell.dart';

import 'package:moonswing/hover_region.dart';
import 'package:moonswing/overlay/calendar/month.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/shell_text_root.dart';
import 'package:moonswing/theme/theme_provider.dart';
import 'package:moonswing/theme/tokens.dart';

/// One day's cell in [SettingsDatePickerCard].
const double kDatePickerCellWidth = 32;
const double kDatePickerCellHeight = 28;

/// The card's padding, all round.
const double _kCardPadding = 10;

/// A month of days, one of them picked by a click.
///
/// Every month is six weeks ([buildMonthGrid]'s 42 cells) and every cell a
/// fixed size, so paging between months never changes the card's size — which
/// matters because the popup window it sits in is sized once, at map time.
class SettingsDatePickerCard extends StatefulWidget {
  const SettingsDatePickerCard({
    super.key,
    required this.selected,
    required this.today,
    required this.onPicked,
    this.weekStart = DateTime.sunday,
  });

  /// The day already chosen, or null for none. The card opens on its month,
  /// else on [today]'s.
  final DateTime? selected;

  final DateTime today;

  /// A [DateTime] weekday constant: `[calendar] week_start`.
  final int weekStart;

  /// A local-midnight day.
  final ValueChanged<DateTime> onPicked;

  @override
  State<SettingsDatePickerCard> createState() => _SettingsDatePickerCardState();
}

class _SettingsDatePickerCardState extends State<SettingsDatePickerCard> {
  late DateTime _month = addMonths(widget.selected ?? widget.today, 0);

  void _step(int delta) => setState(() => _month = addMonths(_month, delta));

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final grid = buildMonthGrid(
      _month.year,
      _month.month,
      weekStart: widget.weekStart,
    );
    final selected = switch (widget.selected) {
      final day? => dayKey(day),
      null => null,
    };
    final today = dayKey(widget.today);
    return Padding(
      padding: const EdgeInsets.all(_kCardPadding),
      child: SizedBox(
        width: 7 * kDatePickerCellWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${monthNames[_month.month - 1]} ${_month.year}',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ShellFontSizes.label,
                      fontWeight: FontWeight.w600,
                      color: theme.popupForeground,
                    ),
                  ),
                ),
                SettingsIconButton(
                  icon: FontAwesomeIcons.chevronLeft,
                  tooltip: 'Previous month',
                  onTap: () => _step(-1),
                ),
                SettingsIconButton(
                  icon: FontAwesomeIcons.chevronRight,
                  tooltip: 'Next month',
                  onTap: () => _step(1),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  SizedBox(
                    width: kDatePickerCellWidth,
                    child: Center(
                      child: Text(
                        weekdayInitials[(widget.weekStart + i) % 7],
                        style: TextStyle(
                          fontSize: ShellFontSizes.caption,
                          fontWeight: FontWeight.w600,
                          color: theme.popupForeground.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (var week = 0; week < 6; week++)
              Row(
                children: [
                  for (var weekday = 0; weekday < 7; weekday++)
                    _DayCell(
                      day: grid.days[week * 7 + weekday],
                      inMonth: grid.isInMonth(week * 7 + weekday),
                      isToday: grid.days[week * 7 + weekday] == today,
                      isSelected: grid.days[week * 7 + weekday] == selected,
                      onTap: widget.onPicked,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final Color foreground;
    if (isSelected) {
      foreground = kOnAccent;
    } else if (isToday) {
      foreground = theme.accentText;
    } else {
      foreground = theme.popupForeground.withValues(
        alpha: inMonth ? 0.9 : 0.35,
      );
    }
    // Built once and handed to the hover builder, so a hover repaints the
    // cell's fill without re-shaping its number.
    final number = Text(
      '${day.day}',
      style: TextStyle(
        fontSize: ShellFontSizes.body,
        color: foreground,
        fontWeight: isToday || isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
    return RepaintBoundary(
      child: HoverRegion(
        onTap: () => onTap(day),
        // The tap box is the whole cell; the margin is inset painting.
        builder: (context, hovered) => SizedBox(
          width: kDatePickerCellWidth,
          height: kDatePickerCellHeight,
          child: Container(
            margin: const EdgeInsets.all(1.5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.accent
                  : hovered
                  ? theme.surfaceHover
                  : null,
              borderRadius: BorderRadius.circular(ShellRadii.control),
              border: isToday && !isSelected
                  ? Border.all(color: theme.accent, width: 1.5)
                  : null,
            ),
            child: number,
          ),
        ),
      ),
    );
  }
}

/// The calendar button beside a date field, opening a [SettingsDatePickerCard]
/// in a popup anchored under it.
///
/// It owns the popup and nothing else: the field stays the value, so a date can
/// still be typed, and a pick is handed to [onPicked] for the caller to write
/// into it. The popup closes on a pick, on a second click of the button (the
/// coordinator's reopen guard), on a click anywhere else in the window's
/// [PopupDismissArea], and when the button goes away.
class SettingsDatePickerButton extends StatefulWidget {
  const SettingsDatePickerButton({
    super.key,
    required this.selected,
    required this.today,
    required this.onPicked,
    this.weekStart = DateTime.sunday,
    this.tooltip = 'Pick a date',
  });

  /// What the field holds now, or null when it is empty or not a date.
  final DateTime? selected;

  final DateTime today;
  final ValueChanged<DateTime> onPicked;
  final int weekStart;
  final String tooltip;

  @override
  State<SettingsDatePickerButton> createState() =>
      _SettingsDatePickerButtonState();
}

class _SettingsDatePickerButtonState extends State<SettingsDatePickerButton>
    with PopupHost<SettingsDatePickerButton> {
  @override
  void dispose() {
    closePopup();
    super.dispose();
  }

  void _toggle(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }
    final button = popupAnchorRect(context);
    openPopup(
      context,
      // The button's rect grown a few pixels top and bottom, so the card stands
      // off it by the same gap whether it opens below or is flipped above.
      anchorRect: Rect.fromLTRB(
        button.left,
        button.top - 4,
        button.right,
        button.bottom + 4,
      ),
      parentAnchor: WindowPositionerAnchor.bottomLeft,
      childAnchor: WindowPositionerAnchor.topLeft,
      constraintAdjustment: const WindowPositionerConstraintAdjustment(
        flipY: true,
        slideX: true,
      ),
      // Loose: the card's fixed cells give it its size.
      preferredConstraints: const BoxConstraints(maxWidth: 360, maxHeight: 360),
      // Its own view, so its own theme, live, and its own text root — nothing
      // above the popup's content supplies either.
      child: ThemeProvider(
        child: Builder(
          builder: (context) {
            final theme = ThemeScope.of(context);
            return ShellTextRoot(
              style: TextStyle(
                color: theme.popupForeground,
                fontSize: ShellFontSizes.body,
              ),
              // Opaque, for the reason forms are: it opens over the fields of
              // the form that opened it.
              child: OpaquePopupScope(
                child: PopupCard(
                  child: SettingsDatePickerCard(
                    selected: widget.selected,
                    today: widget.today,
                    weekStart: widget.weekStart,
                    onPicked: (day) {
                      closePopup();
                      widget.onPicked(day);
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return SettingsTooltip(
      message: widget.tooltip,
      child: HoverRegion(
        // On the press, as every popup toggle is: the reopen guard is armed and
        // consumed inside the one pointer-down.
        onTapDown: (_) => _toggle(context),
        builder: (context, hovered) => Container(
          width: ShellSizes.iconButton + 6,
          height: ShellSizes.iconButton + 6,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered ? theme.surfaceHover : theme.controlSurface,
            borderRadius: BorderRadius.circular(ShellRadii.control),
          ),
          child: FaIcon(
            FontAwesomeIcons.calendarDays,
            size: 13,
            color: hovered
                ? theme.accentText
                : theme.popupForeground.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}
