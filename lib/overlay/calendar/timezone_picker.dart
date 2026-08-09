import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/calendar/time_zones.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';

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
/// The list floats in the *root* overlay, the way `SettingsFontField`'s does.
/// It does not need the root-owned overlay *window* that `showAppChooser` uses:
/// the calendar tab already sits inside `SettingsOverlay`'s own `Overlay`, with
/// `DefaultTextEditingShortcuts` above it, which is what makes an
/// [EditableText] in an inserted entry work at all.
class TimeZonePickerButton extends StatefulWidget {
  const TimeZonePickerButton({
    super.key,
    required this.zones,
    required this.existing,
    required this.onSelected,
  });

  final List<TimeZoneName> zones;

  /// Zone names already on the list. Those rows are shown with a check and
  /// selecting one is a no-op, rather than being hidden — a zone vanishing from
  /// the picker reads as a missing zone, not as one already added.
  final Set<String> existing;

  final ValueChanged<String> onSelected;

  @override
  State<TimeZonePickerButton> createState() => _TimeZonePickerButtonState();
}

class _TimeZonePickerButtonState extends State<TimeZonePickerButton> {
  final _link = LayerLink();
  OverlayEntry? _entry;

  @override
  void dispose() {
    // Not _close(): that repaints the trigger, and this element is on its way
    // out of the tree.
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _toggle() => _entry != null ? _close() : _open();

  void _open() {
    if (_entry != null) return;
    final entry = OverlayEntry(builder: (_) => _buildPicker());
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    setState(() {});
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  void _select(String zone) {
    // Closed *before* the callback: an OverlayEntry does not rebuild on the
    // host's setState, so a popup left open would keep showing the stale check
    // state for the row just added.
    _close();
    widget.onSelected(zone);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: SettingsIconButton(
        icon: FontAwesomeIcons.plus,
        size: 11,
        onTap: _toggle,
      ),
    );
  }

  Widget _buildPicker() {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          // Anchored on the right: the button sits at the right edge of a
          // narrow column, so the card has to grow leftwards into the panel.
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 6),
          // Absorbs clicks on the card's own chrome, which would otherwise fall
          // through to the barrier above.
          child: Listener(
            behavior: HitTestBehavior.opaque,
            child: _TimeZonePickerPopup(
              zones: widget.zones,
              existing: widget.existing,
              onSelected: _select,
              onDismiss: _close,
            ),
          ),
        ),
      ],
    );
  }
}

/// The floating list itself. Owns the filter text, so typing rebuilds this
/// widget rather than the [OverlayEntry] that hosts it.
class _TimeZonePickerPopup extends StatefulWidget {
  const _TimeZonePickerPopup({
    required this.zones,
    required this.existing,
    required this.onSelected,
    required this.onDismiss,
  });

  final List<TimeZoneName> zones;
  final Set<String> existing;
  final ValueChanged<String> onSelected;
  final VoidCallback onDismiss;

  @override
  State<_TimeZonePickerPopup> createState() => _TimeZonePickerPopupState();
}

class _TimeZonePickerPopupState extends State<_TimeZonePickerPopup> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  late List<TimeZoneName> _filtered = rankTimeZones(widget.zones, '');
  int _highlighted = 0;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _filter(String query) {
    setState(() {
      _filtered = rankTimeZones(widget.zones, query);
      _highlighted = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _move(int delta) {
    if (_filtered.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + delta).clamp(0, _filtered.length - 1);
    });
    _revealHighlighted();
  }

  void _revealHighlighted() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final top = _highlighted * kTimeZoneRowHeight;
    final bottom = top + kTimeZoneRowHeight;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        (bottom - position.viewportDimension).clamp(0.0, position.maxScrollExtent),
      );
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        widget.onDismiss();
        // Must be handled: SettingsOverlay's KeyboardListener is an autofocused
        // ancestor that closes the *whole* overlay on Escape, and only this
        // stops the walk before it gets there.
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (_filtered.isNotEmpty) widget.onSelected(_filtered[_highlighted].name);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Focus(
      // Nested above the search field's node, so it only sees what the editor
      // declines — Escape and the arrows here, every editing key still in the
      // field.
      onKeyEvent: _onKey,
      child: Container(
        width: kTimeZonePickerWidth,
        constraints: const BoxConstraints(maxHeight: kTimeZonePickerMaxHeight),
        decoration: BoxDecoration(
          color: theme.popupBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSearchField(theme),
            if (_filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text(
                  'No matching time zone',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: theme.fontFamily,
                    color: theme.muted,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 6),
                  itemExtent: kTimeZoneRowHeight,
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final zone = _filtered[i];
                    return _TimeZoneRow(
                      zone: zone,
                      highlighted: i == _highlighted,
                      added: widget.existing.contains(zone.name),
                      onTap: () => widget.onSelected(zone.name),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: theme.controlSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.divider),
        ),
        child: Row(
          children: [
            FaIcon(
              FontAwesomeIcons.magnifyingGlass,
              size: 10,
              color: theme.popupForeground.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: EditableText(
                controller: _search,
                focusNode: _searchFocus,
                autofocus: true,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.popupForeground,
                  fontFamily: theme.fontFamily,
                ),
                cursorColor: theme.accent,
                backgroundCursorColor: theme.divider,
                onChanged: _filter,
                onSubmitted: (_) {
                  if (_filtered.isNotEmpty) {
                    widget.onSelected(_filtered[_highlighted].name);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeZoneRow extends StatefulWidget {
  const _TimeZoneRow({
    required this.zone,
    required this.highlighted,
    required this.added,
    required this.onTap,
  });

  final TimeZoneName zone;
  final bool highlighted;
  final bool added;
  final VoidCallback onTap;

  @override
  State<_TimeZoneRow> createState() => _TimeZoneRowState();
}

class _TimeZoneRowState extends State<_TimeZoneRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final bg = widget.highlighted
        ? theme.accent.withValues(alpha: 0.15)
        : _hovered
            ? theme.surfaceHover
            : const Color(0x00000000);
    final alpha = widget.added ? 0.45 : 1.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: bg,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.zone.city,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: theme.fontFamily,
                        color: (widget.highlighted
                                ? theme.accent
                                : theme.popupForeground)
                            .withValues(alpha: alpha),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.zone.region,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground
                            .withValues(alpha: 0.45 * alpha),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (widget.added)
                FaIcon(
                  FontAwesomeIcons.check,
                  size: 10,
                  color: theme.popupForeground.withValues(alpha: 0.5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
