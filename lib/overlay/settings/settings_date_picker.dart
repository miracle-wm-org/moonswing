// The date picker: a month of days on a card of its own, opened from a
// calendar button beside a date field.
//
// A float in the window's root overlay, as [AnchoredSearchDropdown] is, and
// not a native popup window: see [SettingsDatePickerButton] for why.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/hover_region.dart';
import 'package:moonswing/overlay/calendar/month.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/popup_coordinator.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/shell_text_root.dart';
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

/// The gap between the calendar button and the card it opens.
const double _kPickerGap = 4;

/// The calendar button beside a date field, opening a [SettingsDatePickerCard]
/// anchored under it.
///
/// It owns the card and nothing else: the field stays the value, so a date can
/// still be typed, and a pick is handed to [onPicked] for the caller to write
/// into it. The card closes on a pick, on a click anywhere else in the window
/// (the button included, so a second click toggles it shut), when the form
/// under it scrolls, when the [PopupCoordinator] asks — Escape and the board's
/// exit, through `dismissChildren` — and when the button goes away.
///
/// **The card floats in the window's own root [Overlay], never in a popup
/// window of its own.** This button lives in the overview, a full-screen
/// overlay-layer surface, and a native popup is a separate compositor surface
/// whose stacking is the compositor's call, not the shell's: parented to a
/// surface covering the whole output, it never showed, and the button looked
/// dead. Nothing outside the window is worth reaching from a form that already
/// spans the output — the reason the board's card menu and every settings
/// dropdown float in-window too.
///
/// It is still registered with the coordinator, as a child of the
/// [TransientScope] it was opened under, so a surface that backs out one layer
/// at a time sees it as the layer above it, and a click on another surface
/// (a bar) closes it with everything else.
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

class _SettingsDatePickerButtonState extends State<SettingsDatePickerButton> {
  OverlayEntry? _entry;
  TransientHandle? _handle;

  /// The scroll position the button sits in, while the card is open. The card
  /// is placed once, at open, against where the button was; a form scrolled
  /// under it would leave it pointing at some other field.
  ScrollPosition? _hostScroll;

  @override
  void dispose() {
    _close(rebuild: false);
    super.dispose();
  }

  void _toggle() => _entry != null ? _close() : _open();

  void _open() {
    if (_entry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    final button = context.findRenderObject();
    final overlayBox = overlay.context.findRenderObject();
    if (button is! RenderBox || !button.hasSize || overlayBox is! RenderBox) {
      return;
    }
    final anchor =
        button.localToGlobal(Offset.zero, ancestor: overlayBox) & button.size;
    final entry = OverlayEntry(
      builder: (context) => _buildCard(context, anchor),
    );
    _entry = entry;
    // Registered before it shows, so whatever it displaces is already on its
    // way out — and parented to the surface it opens over, so it is not one
    // of them.
    _handle = PopupCoordinator.instance.open(
      owner: this,
      parent: TransientScope.maybeOf(context),
      onDismiss: _close,
    );
    overlay.insert(entry);
    _hostScroll = Scrollable.maybeOf(context)?.position
      ?..isScrollingNotifier.addListener(_onHostScroll);
    setState(() {});
  }

  void _onHostScroll() {
    if (_entry != null) _close();
  }

  /// Idempotent, because three things can ask: a pick, a click elsewhere, and
  /// the coordinator — whose `dismiss` arrives here as `onDismiss`.
  void _close({bool rebuild = true}) {
    _hostScroll?.isScrollingNotifier.removeListener(_onHostScroll);
    _hostScroll = null;
    final handle = _handle;
    _handle = null;
    PopupCoordinator.instance.close(handle);
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    entry.remove();
    if (rebuild && mounted) setState(() {});
  }

  Widget _buildCard(BuildContext context, Rect anchor) {
    final theme = ThemeScope.of(context);
    return Stack(
      children: [
        // A press anywhere off the card closes it, the button's own included —
        // the barrier is over the button, which is what makes a second click
        // a toggle. On the press, as every dismiss in the shell is.
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _close(),
          ),
        ),
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _DatePickerLayout(anchor),
            // Absorbs clicks on the card's own chrome, which would otherwise
            // fall through to the barrier.
            child: Listener(
              behavior: HitTestBehavior.opaque,
              child: ShellTextRoot(
                style: TextStyle(
                  color: theme.popupForeground,
                  fontSize: ShellFontSizes.body,
                ),
                // Opaque, for the reason forms are: it opens over the fields
                // of the form that opened it.
                child: OpaquePopupScope(
                  child: PopupCard(
                    child: SettingsDatePickerCard(
                      selected: widget.selected,
                      today: widget.today,
                      weekStart: widget.weekStart,
                      onPicked: (day) {
                        _close();
                        widget.onPicked(day);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return SettingsTooltip(
      message: widget.tooltip,
      child: HoverRegion(
        // On the press, as every popup toggle is. Only the open: once the card
        // is up the barrier is over this button, and it is what closes it.
        onTapDown: (_) => _toggle(),
        builder: (context, hovered) {
          final lit = hovered || _entry != null;
          return Container(
            width: ShellSizes.iconButton + 6,
            height: ShellSizes.iconButton + 6,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: lit ? theme.surfaceHover : theme.controlSurface,
              borderRadius: BorderRadius.circular(ShellRadii.control),
            ),
            child: FaIcon(
              FontAwesomeIcons.calendarDays,
              size: 13,
              color: lit
                  ? theme.accentText
                  : theme.popupForeground.withValues(alpha: 0.75),
            ),
          );
        },
      ),
    );
  }
}

/// Places the card under the button, its left edges aligned — flipped above
/// the button when it does not fit below but does above, and slid back inside
/// the window where it would hang off the side. What the native positioner's
/// `flipY` and `slideX` did, against the card's measured size.
class _DatePickerLayout extends SingleChildLayoutDelegate {
  const _DatePickerLayout(this.anchor);

  /// The button, in the overlay's coordinates.
  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = anchor.bottom + _kPickerGap;
    final above = anchor.top - _kPickerGap - childSize.height;
    final fitsBelow = below + childSize.height <= size.height;
    final y = fitsBelow || above < 0 ? below : above;
    return Offset(
      anchor.left.clamp(0, math.max(0, size.width - childSize.width)),
      y.clamp(0, math.max(0, size.height - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(_DatePickerLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}
