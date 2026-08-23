// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/root_modal.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/search_list.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// Themed form controls shared by the panels inside the settings overlay.
///
/// Extracted from `shell.dart` when the calendar tab needed the same section
/// headers, rows, text fields, and icon buttons: two copies of this styling
/// would drift apart the first time the theme changed.

// ---------------------------------------------------------------------------
// Layout helpers
// ---------------------------------------------------------------------------

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.label,
    required this.children,
  });

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionLabel(label),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontFamily: theme.fontFamily,
        color: theme.popupForeground.withValues(alpha: 0.5),
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
  }
}

class SettingsSubLabel extends StatelessWidget {
  const SettingsSubLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontFamily: theme.fontFamily,
          color: theme.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class SettingsHint extends StatelessWidget {
  const SettingsHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontFamily: theme.fontFamily,
        color: theme.popupForeground.withValues(alpha: 0.5),
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    required this.control,
    this.alignTop = false,
  });

  final String label;
  final Widget control;
  final bool alignTop;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: alignTop
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: alignTop ? 10 : 0),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

class SettingsToggle extends StatefulWidget {
  const SettingsToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  _SettingsToggleState createState() => _SettingsToggleState();
}

class _SettingsToggleState extends State<SettingsToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final color = widget.value ? theme.accent : theme.divider;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onChanged(!widget.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 24,
          decoration: BoxDecoration(
            color: _hovered ? color.withValues(alpha: 0.8) : color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeInOut,
                left: widget.value ? 22 : 2,
                top: 2,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsSegmented extends StatelessWidget {
  const SettingsSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        for (final o in options)
          SettingsOptionButton(
            label: '${o[0].toUpperCase()}${o.substring(1)}',
            selected: o == value,
            onTap: () => onChanged(o),
          ),
      ],
    );
  }
}

class SettingsOptionButton extends StatefulWidget {
  const SettingsOptionButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  _SettingsOptionButtonState createState() => _SettingsOptionButtonState();
}

class _SettingsOptionButtonState extends State<SettingsOptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final Color bg;
    if (widget.selected) {
      bg = theme.accent;
    } else if (_hovered) {
      bg = theme.surfaceHover;
    } else {
      bg = theme.controlSurface;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.selected ? theme.accent : theme.divider,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontFamily: theme.fontFamily,
              color: widget.selected
                  ? const Color(0xFFFFFFFF)
                  : theme.popupForeground,
            ),
          ),
        ),
      ),
    );
  }
}

/// A stretch-to-fit action button: accent-filled when [primary], quiet
/// otherwise. Shows a [LoadingIndicator] and refuses taps while [loading] or
/// not [enabled].
///
/// Extracted from the `_ActionButton` clones in the audio and display panes
/// (display's carried the superset: the [enabled] flag and the theme font).
class SettingsActionButton extends StatelessWidget {
  const SettingsActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.loading = false,
    this.enabled = true,
    this.compact = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool loading;
  final bool enabled;

  /// The dense inline form used beside a list row (the bluetooth pane's
  /// Connect/Disconnect): tighter padding and the secondary font size, sized
  /// to its label rather than stretched under a form.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final canTap = enabled && !loading;
    return HoverRegion(
      cursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (context, hovered) {
        final Color bg;
        if (primary) {
          bg = hovered && canTap
              ? theme.accent.withValues(alpha: 0.85)
              : canTap
                  ? theme.accent
                  : theme.accent.withValues(alpha: 0.4);
        } else {
          bg = hovered && canTap ? theme.surfaceHover : theme.divider;
        }
        return GestureDetector(
          onTap: canTap ? onTap : null,
          child: Container(
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                : const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(ShellRadii.control),
            ),
            child: Center(
              child: loading
                  ? const LoadingIndicator(size: 14)
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: compact
                            ? ShellFontSizes.secondary
                            : ShellFontSizes.body,
                        fontFamily: theme.fontFamily,
                        color: primary ? kOnAccent : theme.popupForeground,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// A small accent-tinted pill marking a list row's state — "Connected" on the
/// network and bluetooth device lists.
///
/// Extracted from the `_ConnectedBadge` clones in the network and bluetooth
/// panes, identical but for the network one carrying the theme font (the
/// superset). The label is a parameter because the state a row wants to
/// announce is not always "Connected".
class SettingsBadge extends StatelessWidget {
  const SettingsBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.accent, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: ShellFontSizes.caption,
          fontFamily: theme.fontFamily,
          color: theme.accent,
        ),
      ),
    );
  }
}

/// A quiet refresh affordance: a rotate-arrows icon beside its [label],
/// transparent at rest with a hover fill. The default label is "Scan"; the
/// error states pass "Retry".
///
/// Extracted from the `_RescanButton` clones in the network and bluetooth
/// panes, identical but for the network one carrying the theme font (the
/// superset). Not folded into [SettingsIconButton]: this is a labelled pill
/// with a hover-filled background, not a bare icon, and it carries no spin
/// state — both panes rebuild into a full-body loader while scanning.
class SettingsRescanButton extends StatelessWidget {
  const SettingsRescanButton({super.key, required this.onTap, this.label = 'Scan'});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      builder: (context, hovered) {
        final theme = ThemeScope.of(context);
        return GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: hovered ? theme.surfaceHover : null,
              borderRadius: BorderRadius.circular(ShellRadii.control),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaIcon(
                  FontAwesomeIcons.arrowsRotate,
                  size: 11,
                  color: theme.popupForeground.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One row of a [SettingsDropdown]: the [value] it stands for, the [label]
/// shown for it, and an optional dim [detail] tag after the label (the display
/// pane marks its preferred mode this way).
class SettingsDropdownItem<T> {
  const SettingsDropdownItem({
    required this.value,
    required this.label,
    this.detail,
  });

  final T value;
  final String label;
  final String? detail;
}

/// Inline-expanding dropdown: a bordered trigger showing the selected item's
/// label and, while open, a scrollable list of the items pushed into the
/// layout below it — not floated over it, so it needs no Overlay and cannot
/// be clipped by a nested Navigator's. Selecting an item reports it through
/// [onSelected] and closes the list; a [selected] value no item carries shows
/// an em dash.
///
/// Extracted from the `_AudioDropdown`/`_ModeDropdown` clones in the audio
/// and display panes. For a searchable list that floats in the root overlay
/// instead, see [SettingsFontField] / `AnchoredSearchDropdown`.
class SettingsDropdown<T> extends StatefulWidget {
  const SettingsDropdown({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<SettingsDropdownItem<T>> items;
  final T? selected;
  final ValueChanged<T> onSelected;

  @override
  State<SettingsDropdown<T>> createState() => _SettingsDropdownState<T>();
}

class _SettingsDropdownState<T> extends State<SettingsDropdown<T>> {
  bool _open = false;

  String get _selectedLabel {
    for (final item in widget.items) {
      if (item.value == widget.selected) return item.label;
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTrigger(),
        if (_open)
          Container(
            margin: const EdgeInsets.only(top: 2),
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: theme.controlSurface,
              border: Border.all(color: theme.divider),
              borderRadius: BorderRadius.circular(ShellRadii.control),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.items.length,
              itemBuilder: (_, i) => _buildItem(widget.items[i]),
            ),
          ),
      ],
    );
  }

  Widget _buildTrigger() {
    return HoverRegion(
      builder: (context, hovered) {
        final theme = ThemeScope.of(context);
        return GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: hovered ? theme.surfaceHover : theme.controlSurface,
              borderRadius: BorderRadius.circular(ShellRadii.control),
              border: Border.all(color: theme.divider),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedLabel,
                    style: TextStyle(
                      fontSize: ShellFontSizes.body,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                FaIcon(
                  _open
                      ? FontAwesomeIcons.chevronUp
                      : FontAwesomeIcons.chevronDown,
                  size: 10,
                  color: theme.popupForeground.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildItem(SettingsDropdownItem<T> item) {
    final selected = item.value == widget.selected;
    final detail = item.detail;
    return HoverRegion(
      builder: (context, hovered) {
        final theme = ThemeScope.of(context);
        final Color bg;
        if (selected) {
          bg = theme.accent.withValues(alpha: 0.15);
        } else if (hovered) {
          bg = theme.surfaceHover;
        } else {
          bg = const Color(0x00000000);
        }
        return GestureDetector(
          onTap: () {
            widget.onSelected(item.value);
            setState(() => _open = false);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: bg,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: ShellFontSizes.body,
                      fontFamily: theme.fontFamily,
                      color: selected ? theme.accent : theme.popupForeground,
                    ),
                  ),
                ),
                if (detail != null)
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground.withValues(alpha: 0.4),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Bordered single-line text input backed by [EditableText] (the codebase does
/// not use Material). Seeds its controller once from [initial]; subsequent
/// parent rebuilds do not clobber in-progress edits.
class SettingsTextField extends StatefulWidget {
  const SettingsTextField({
    super.key,
    required this.initial,
    required this.onChanged,
    this.width,
    this.inputFormatters,
  });

  final String initial;
  final ValueChanged<String> onChanged;
  final double? width;
  final List<TextInputFormatter>? inputFormatters;

  @override
  _SettingsTextFieldState createState() => _SettingsTextFieldState();
}

class _SettingsTextFieldState extends State<SettingsTextField> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _focusNode.addListener(
      () => setState(() => _focused = _focusNode.hasFocus),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      width: widget.width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.popupBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _focused ? theme.accent : theme.divider,
          width: 1,
        ),
      ),
      child: EditableText(
        controller: _controller,
        focusNode: _focusNode,
        style: TextStyle(
          fontSize: 13,
          color: theme.popupForeground,
          fontFamily: theme.fontFamily,
        ),
        cursorColor: theme.accent,
        backgroundCursorColor: theme.divider,
        inputFormatters: widget.inputFormatters,
        onChanged: (v) => widget.onChanged(v),
      ),
    );
  }
}

class SettingsNumberField extends StatelessWidget {
  const SettingsNumberField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.isInt,
    this.allowNegative = false,
  });

  final num value;
  final bool isInt;

  /// Whether a minus sign may be typed.
  ///
  /// Off by default because most settings here are a length or a count that
  /// cannot be negative, and the filter is the only thing stopping one. The
  /// shadow offsets and spread are the exception: CSS casts a shadow up and to
  /// the left with negative values, and shrinks one before blurring. A lone
  /// `-` mid-typing parses to null, which the handler below already ignores.
  final bool allowNegative;

  final ValueChanged<num> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsTextField(
      width: 90,
      initial: isInt ? '${value.toInt()}' : _trimDouble(value.toDouble()),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          isInt
              ? (allowNegative ? RegExp(r'[-0-9]') : RegExp(r'[0-9]'))
              : (allowNegative ? RegExp(r'[-0-9.]') : RegExp(r'[0-9.]')),
        ),
      ],
      onChanged: (text) {
        if (text.isEmpty) return;
        if (isInt) {
          final v = int.tryParse(text);
          if (v != null) onChanged(v);
        } else {
          final v = double.tryParse(text);
          if (v != null) onChanged(v);
        }
      },
    );
  }

  static String _trimDouble(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(1);
    return '$v';
  }
}

/// Parses a `#RRGGBB` / `#AARRGGBB` hex string (`#` optional) into a color.
Color? parseHexColor(String hex) {
  final s = hex.startsWith('#') ? hex.substring(1) : hex;
  if (s.length != 6 && s.length != 8) return null;
  final value = int.tryParse(s.length == 6 ? 'FF$s' : s, radix: 16);
  return value != null ? Color(value) : null;
}

class SettingsIconButton extends StatefulWidget {
  const SettingsIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 12,
  });

  final FaIconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  _SettingsIconButtonState createState() => _SettingsIconButtonState();
}

class _SettingsIconButtonState extends State<SettingsIconButton> {
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
          width: 26,
          height: 26,
          alignment: Alignment.center,
          child: FaIcon(
            widget.icon,
            size: widget.size,
            color: _hovered
                ? theme.accent
                : theme.popupForeground.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Font picker
// ---------------------------------------------------------------------------

/// The height of one row in the font list. Fixed, so the popup can scroll
/// straight to the selected family by arithmetic instead of measuring.
const double _kFontRowHeight = 30;

/// A dropdown of installed font families, each row drawn in its own face.
///
/// [fonts] is supplied by the caller (see `theme/font_catalog.dart`) rather than
/// read here, so widget tests pass a list of three and never fork `fc-list`.
///
/// A thin wrapper over [AnchoredSearchDropdown], which owns the root-overlay
/// float, the filter field, and the keyboard navigation; only the trigger,
/// the ranking, and the rendered-in-its-own-face row live here.
class SettingsFontField extends StatelessWidget {
  const SettingsFontField({
    super.key,
    required this.value,
    required this.fonts,
    required this.onChanged,
    this.locked = false,
    this.onLockedTap,
    this.width = 180,
  });

  final String value;
  final List<String> fonts;
  final ValueChanged<String> onChanged;

  /// Dims the control and routes taps to [onLockedTap] instead of opening the
  /// list. The theme editor uses this for the shipped, read-only themes.
  final bool locked;
  final VoidCallback? onLockedTap;

  final double width;

  @override
  Widget build(BuildContext context) {
    return AnchoredSearchDropdown<String>(
      // Switching themes replaces the value under an open list; leaving it up
      // would let the next click write the old theme's pick into the new one.
      closeKey: value,
      rowHeight: _kFontRowHeight,
      emptyText: 'No matching font',
      filter: (query) {
        final q = query.trim().toLowerCase();
        return q.isEmpty
            ? fonts
            : fonts
                .where((f) => f.toLowerCase().contains(q))
                .toList(growable: false);
      },
      // Open highlighted-and-scrolled to the current family rather than at
      // the top of a few hundred rows.
      initialHighlight: (items) => items.indexOf(value),
      onSelected: onChanged,
      itemBuilder: (context, family, highlighted) {
        final theme = ThemeScope.of(context);
        return Text(
          family,
          // The point of the row: what the family actually looks like.
          style: TextStyle(
            fontSize: 13,
            fontFamily: family,
            color: highlighted ? theme.accent : theme.popupForeground,
          ),
          overflow: TextOverflow.ellipsis,
        );
      },
      triggerBuilder: (context, open, toggle) {
        final theme = ThemeScope.of(context);
        return Opacity(
          opacity: locked ? 0.45 : 1.0,
          child: HoverRegion(
            builder: (context, hovered) => GestureDetector(
              onTap: locked ? (onLockedTap ?? () {}) : toggle,
              child: Container(
                width: width,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: hovered ? theme.surfaceHover : theme.controlSurface,
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: open ? theme.accent : theme.divider),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        // Drawn in the family it names, so the trigger
                        // previews the choice as well as reporting it.
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: value,
                          color: theme.popupForeground,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    FaIcon(
                      open
                          ? FontAwesomeIcons.chevronUp
                          : FontAwesomeIcons.chevronDown,
                      size: 10,
                      color: theme.popupForeground.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Colour picker
// ---------------------------------------------------------------------------
//
// Moved here from `shell.dart` when the theme editor stopped being the only
// consumer — same reasoning as the controls above.

/// Formats a color back to the config's hex form: `#RRGGBB` when fully opaque,
/// otherwise `#AARRGGBB`.
String formatHexColor(Color c) {
  final argb = c.toARGB32();
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  final a = (argb >> 24) & 0xFF;
  if (a == 0xFF) return '#$rgb';
  return '#${a.toRadixString(16).padLeft(2, '0').toUpperCase()}$rgb';
}

/// A color swatch + hex text field. Clicking the swatch opens a visual color
/// picker ([SettingsColorPicker]) floated over the settings window.
class SettingsColorField extends StatefulWidget {
  const SettingsColorField({
    super.key,
    required this.initial,
    required this.onChanged,
    this.locked = false,
    this.onLockedTap,
  });

  final String initial;
  final ValueChanged<String> onChanged;

  /// Dims the field and routes taps to [onLockedTap] instead of opening the
  /// picker. The theme editor uses this for the shipped, read-only themes.
  final bool locked;
  final VoidCallback? onLockedTap;

  @override
  ColorFieldState createState() => ColorFieldState();
}

class ColorFieldState extends State<SettingsColorField> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  final _link = LayerLink();
  // The picker floats in the root overlay (not a nearby OverlayPortal target)
  // so a nested Navigator's clipped Overlay can't cut it off. See _open().
  OverlayEntry? _pickerEntry;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _focusNode.addListener(
      () => setState(() => _focused = _focusNode.hasFocus),
    );
  }

  @override
  void didUpdateWidget(SettingsColorField old) {
    super.didUpdateWidget(old);
    // Unlike the other controls, this one is re-seeded: switching themes
    // replaces every value under it, and a swatch still showing the previous
    // theme's colour would be a lie.
    //
    // "Did this change come from me?" is answered on the parsed colours, not on
    // the strings: what comes back has been through ThemeConfig.formatColor,
    // whose spelling need not match ours byte for byte, and a re-spelling of
    // the colour we just wrote is not somebody else re-seeding the field. When
    // it was a string compare, every drag inside the picker closed the picker.
    final incoming = parseHexColor(widget.initial);
    final mine = parseHexColor(_controller.text);
    final same = incoming != null && mine != null
        ? incoming == mine
        : widget.initial == _controller.text;
    if (widget.initial != old.initial && !same) {
      _controller.text = widget.initial;
      _close();
    }
  }

  @override
  void dispose() {
    _close();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggle() {
    if (widget.locked) {
      widget.onLockedTap?.call();
      return;
    }
    if (_pickerEntry != null) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    if (_pickerEntry != null) return;
    // Insert into the root overlay so the picker can extend past the settings
    // content pane (whose nested Navigator Overlay would otherwise clip it).
    final entry = OverlayEntry(builder: (context) => _buildPicker());
    _pickerEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  void _close() {
    _pickerEntry?.remove();
    _pickerEntry = null;
  }

  void _apply(Color color) {
    final hex = formatHexColor(color);
    _controller.value = TextEditingValue(
      text: hex,
      selection: TextSelection.collapsed(offset: hex.length),
    );
    setState(() {});
    widget.onChanged(hex);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final swatch = parseHexColor(_controller.text);
    return Opacity(
      opacity: widget.locked ? 0.45 : 1.0,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CompositedTransformTarget(
            link: _link,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _toggle,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: swatch ?? const Color(0x00000000),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: theme.divider),
                  ),
                  child: swatch == null
                      ? FaIcon(
                          FontAwesomeIcons.question,
                          size: 10,
                          color: theme.popupForeground.withValues(alpha: 0.4),
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 110,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.popupBackground,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _focused ? theme.accent : theme.divider,
                width: 1,
              ),
            ),
            // Read-only on the main page: the value is edited through the color
            // picker popup, not typed here.
            child: EditableText(
              controller: _controller,
              focusNode: _focusNode,
              readOnly: true,
              style: TextStyle(
                fontSize: 13,
                color: theme.popupForeground,
                fontFamily: theme.fontFamily,
              ),
              cursorColor: theme.accent,
              backgroundCursorColor: theme.divider,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPicker() {
    return Stack(
      children: [
        // Dismiss when tapping outside the popup.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),
          // The card's own chrome — its padding, border, and the gaps between
          // the sliders — is Padding and DecoratedBox, neither of which
          // hit-tests itself, so a click there used to fall through the Stack
          // to the barrier above and dismiss. A Listener rather than a
          // GestureDetector: it takes the card out of the barrier's hit path
          // without joining the gesture arena, leaving the tap/pan recognizers
          // inside _draggable untouched.
          child: Listener(
            behavior: HitTestBehavior.opaque,
            child: SettingsColorPicker(
              initial:
                  parseHexColor(_controller.text) ?? const Color(0xFF000000),
              onChanged: _apply,
            ),
          ),
        ),
      ],
    );
  }
}

/// Visual HSV color picker: a draggable saturation/value square, hue and alpha
/// sliders, and a manual hex entry. Emits every change through [onChanged].
class SettingsColorPicker extends StatefulWidget {
  const SettingsColorPicker({required this.initial, required this.onChanged});

  final Color initial;
  final ValueChanged<Color> onChanged;

  @override
  State<SettingsColorPicker> createState() => ColorPickerPopupState();
}

class ColorPickerPopupState extends State<SettingsColorPicker> {
  static const double _w = 200;
  static const double _squareH = 150;
  static const double _sliderH = 14;

  late HSVColor _hsv;
  late final TextEditingController _hexController;
  final _hexFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hexController = TextEditingController(
      text: formatHexColor(widget.initial),
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  /// Applies a new HSV value, optionally syncing the hex field text (skipped
  /// while the user is typing into that field).
  void _set(HSVColor hsv, {bool syncHex = true}) {
    _hsv = hsv;
    final color = hsv.toColor();
    if (syncHex) {
      final hex = formatHexColor(color);
      if (_hexController.text != hex) {
        _hexController.value = TextEditingValue(
          text: hex,
          selection: TextSelection.collapsed(offset: hex.length),
        );
      }
    }
    setState(() {});
    widget.onChanged(color);
  }

  void _onHex(String text) {
    final c = parseHexColor(text);
    if (c != null) _set(HSVColor.fromColor(c), syncHex: false);
  }

  /// A fixed-size region that reports the pointer position (down + drag) as
  /// normalized (0..1) coordinates.
  Widget _draggable({
    required double width,
    required double height,
    required ValueChanged<Offset> onChange,
    required Widget child,
  }) {
    void handle(Offset local) {
      onChange(
        Offset(
          (local.dx / width).clamp(0.0, 1.0),
          (local.dy / height).clamp(0.0, 1.0),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => handle(d.localPosition),
      onPanDown: (d) => handle(d.localPosition),
      onPanUpdate: (d) => handle(d.localPosition),
      child: SizedBox(width: width, height: height, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final color = _hsv.toColor();
    return PopupBounceIn(
      child: Container(
        width: _w + 24,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.popupBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.accent, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Saturation / value square.
            _draggable(
              width: _w,
              height: _squareH,
              onChange: (n) =>
                  _set(_hsv.withSaturation(n.dx).withValue(1 - n.dy)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CustomPaint(
                  painter: _SVPainter(_hsv.hue),
                  foregroundPainter: _SVCursorPainter(
                    saturation: _hsv.saturation,
                    value: _hsv.value,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Hue slider.
            _draggable(
              width: _w,
              height: _sliderH,
              onChange: (n) =>
                  _set(_hsv.withHue((n.dx * 360).clamp(0.0, 360.0))),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_sliderH / 2),
                child: CustomPaint(
                  painter: _HuePainter(),
                  foregroundPainter: _ThumbPainter(_hsv.hue / 360),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Alpha slider.
            _draggable(
              width: _w,
              height: _sliderH,
              onChange: (n) => _set(_hsv.withAlpha(n.dx)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_sliderH / 2),
                child: CustomPaint(
                  painter: _AlphaPainter(_hsv.withAlpha(1).toColor()),
                  foregroundPainter: _ThumbPainter(_hsv.alpha),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Manual hex entry.
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: theme.divider),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.workspaceBackground,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: theme.divider),
                    ),
                    child: EditableText(
                      controller: _hexController,
                      focusNode: _hexFocus,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.popupForeground,
                        fontFamily: theme.fontFamily,
                      ),
                      cursorColor: theme.accent,
                      backgroundCursorColor: theme.divider,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[#0-9a-fA-F]'),
                        ),
                      ],
                      onChanged: _onHex,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the saturation (x) / value (y) gradient field for a given [hue].
class _SVPainter extends CustomPainter {
  _SVPainter(this.hue);

  final double hue;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [const Color(0xFFFFFFFF), hueColor],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SVPainter old) => old.hue != hue;
}

/// Draws the ring cursor over the saturation/value square.
class _SVCursorPainter extends CustomPainter {
  _SVCursorPainter({required this.saturation, required this.value});

  final double saturation;
  final double value;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final c = Offset(saturation * size.width, (1 - value) * size.height);
    canvas.drawCircle(
      c,
      6,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      c,
      7.5,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x88000000),
    );
  }

  @override
  bool shouldRepaint(_SVCursorPainter old) =>
      old.saturation != saturation || old.value != value;
}

/// Paints the full hue spectrum bar.
class _HuePainter extends CustomPainter {
  @override
  void paint(ui.Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => false;
}

/// Paints the alpha slider: a checkerboard behind a transparent→opaque gradient
/// of the current [color].
class _AlphaPainter extends CustomPainter {
  _AlphaPainter(this.color);

  final Color color;

  @override
  void paint(ui.Canvas canvas, Size size) {
    const cell = 5.0;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, ui.Paint()..color = const Color(0xFFCCCCCC));
    final dark = ui.Paint()..color = const Color(0xFF888888);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        if (((x ~/ cell) + (y ~/ cell)) % 2 == 0) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
        }
      }
    }
    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 1)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_AlphaPainter old) => old.color != color;
}

/// Draws the round thumb for the hue/alpha sliders at normalized position [t].
class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.t);

  final double t;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final r = size.height / 2;
    final x = (t.clamp(0.0, 1.0) * size.width).clamp(r, size.width - r);
    final center = Offset(x, size.height / 2);
    canvas.drawCircle(
      center,
      r - 1,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      center,
      r,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x66000000),
    );
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// Confirmation
// ---------------------------------------------------------------------------

/// A modal "are you sure?" card for a destructive settings action.
///
/// A scrim plus a [PopupCard] rather than a Material dialog, which the shell
/// does not use anywhere; this is the same shape as `KillConfirm` in
/// `overlay/system/kill_confirm.dart`, generalized so the settings panes do not
/// grow a third hand-rolled copy. The one thing it does not take from the theme
/// is its rim: the accent border marks a destructive action, so it overrides
/// `popup_border` rather than following it.
///
/// [warning] is a second paragraph for a consequence the user cannot see from
/// the row they clicked — removing the last panel, say. Null when there is
/// none, so the card does not carry an empty line.
class SettingsConfirmCard extends StatelessWidget {
  const SettingsConfirmCard({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.warning,
  });

  final String title;
  final String message;
  final String? warning;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final warning = this.warning;
    return Focus(
      autofocus: true,
      // Escape cancels, matching the power menu's confirmation
      // (`modules/system.dart`). The card is modal, so nothing below it is
      // competing for the key.
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          // Tapping the scrim cancels, which is the least surprising thing a
          // click outside a confirmation can do.
          Positioned.fill(
            child: GestureDetector(
              onTap: onCancel,
              child: Container(color: const Color(0x99000000)),
            ),
          ),
          Center(
            child: SizedBox(
              width: 380,
              child: PopupCard(
                border: Border.all(color: theme.accent, width: 1.5),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontFamily: theme.fontFamily,
                        fontWeight: FontWeight.w600,
                        color: theme.popupForeground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: theme.fontFamily,
                        height: 1.4,
                        color: theme.popupForeground.withValues(alpha: 0.7),
                      ),
                    ),
                    if (warning != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          warning,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: theme.fontFamily,
                            height: 1.4,
                            color: theme.popupForeground.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SettingsOptionButton(
                          label: 'Cancel',
                          selected: false,
                          onTap: onCancel,
                        ),
                        const SizedBox(width: 8),
                        SettingsOptionButton(
                          label: confirmLabel,
                          selected: true,
                          onTap: onConfirm,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a [SettingsConfirmCard] in the nearest *root* [Overlay], resolving to
/// true if the user confirmed and false if they cancelled or dismissed it.
///
/// The root overlay for the same reason [SettingsColorField]'s picker uses one:
/// the Shell settings pane is a nested `Navigator`, and a scrim inserted into
/// its overlay — or built into a scrolled section — would cover the pane's
/// content while leaving the sidebar and header live. Cloned from
/// `showAppChooser` in `desktop/app_chooser.dart`.
Future<bool> showSettingsConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? warning,
}) {
  return showRootModal<bool>(
    context,
    (close) => SettingsConfirmCard(
      title: title,
      message: message,
      warning: warning,
      confirmLabel: confirmLabel,
      onCancel: () => close(false),
      onConfirm: () => close(true),
    ),
  );
}

/// Editable ordered list of strings. When [suggestions] is provided, new items
/// are added from a dropdown of those values; otherwise a free-form text field
/// is shown. Existing items can be reordered and removed.
class SettingsStringListEditor extends StatefulWidget {
  const SettingsStringListEditor({
    super.key,
    required this.items,
    required this.onChanged,
    this.suggestions,
    this.addHint,
    this.width = 260,
  });

  final List<String> items;
  final ValueChanged<List<String>> onChanged;
  final List<String>? suggestions;
  final String? addHint;

  /// Fixed editor width. Pass `null` to stretch to the parent's width (used on
  /// the Panels page, where the list sits full-width under its label).
  final double? width;

  @override
  State<SettingsStringListEditor> createState() =>
      _SettingsStringListEditorState();
}

class _SettingsStringListEditorState extends State<SettingsStringListEditor> {
  final _addController = TextEditingController();
  final _addFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _addFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _addController.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  void _emit(List<String> list) => widget.onChanged(list);

  void _add(String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    _emit([...widget.items, v]);
  }

  void _removeAt(int i) {
    final list = [...widget.items]..removeAt(i);
    _emit(list);
  }

  void _move(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= widget.items.length) return;
    final list = [...widget.items];
    final tmp = list[i];
    list[i] = list[j];
    list[j] = tmp;
    _emit(list);
  }

  @override
  Widget build(BuildContext context) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.items.length; i++)
          _row(context, i, widget.items[i]),
        const SizedBox(height: 6),
        _buildAdder(context),
      ],
    );
    final width = widget.width;
    return width == null ? column : SizedBox(width: width, child: column);
  }

  Widget _row(BuildContext context, int i, String item) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        decoration: BoxDecoration(
          color: theme.controlSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground,
                ),
              ),
            ),
            SettingsIconButton(
              icon: FontAwesomeIcons.chevronUp,
              size: 10,
              onTap: () => _move(i, -1),
            ),
            SettingsIconButton(
              icon: FontAwesomeIcons.chevronDown,
              size: 10,
              onTap: () => _move(i, 1),
            ),
            SettingsIconButton(
              icon: FontAwesomeIcons.xmark,
              size: 12,
              onTap: () => _removeAt(i),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdder(BuildContext context) {
    final suggestions = widget.suggestions;
    if (suggestions != null) {
      return _AddDropdown(
        options: suggestions,
        onSelected: _add,
      );
    }
    final theme = ThemeScope.of(context);
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.popupBackground,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: _addFocus.hasFocus ? theme.accent : theme.divider),
            ),
            child: Stack(
              children: [
                if (_addController.text.isEmpty)
                  Text(
                    widget.addHint ?? 'add…',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.popupForeground.withValues(alpha: 0.35),
                      fontFamily: theme.fontFamily,
                    ),
                  ),
                EditableText(
                  controller: _addController,
                  focusNode: _addFocus,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.popupForeground,
                    fontFamily: theme.fontFamily,
                  ),
                  cursorColor: theme.accent,
                  backgroundCursorColor: theme.divider,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (v) {
                    _add(v);
                    _addController.clear();
                    setState(() {});
                    _addFocus.requestFocus();
                  },
                ),
              ],
            ),
          ),
        ),
        SettingsIconButton(
          icon: FontAwesomeIcons.plus,
          onTap: () {
            _add(_addController.text);
            _addController.clear();
            setState(() {});
          },
        ),
      ],
    );
  }
}

/// A dropdown that expands to a list of [options] and reports the chosen value.
class _AddDropdown extends StatefulWidget {
  const _AddDropdown({required this.options, required this.onSelected});

  final List<String> options;
  final ValueChanged<String> onSelected;

  @override
  State<_AddDropdown> createState() => _AddDropdownState();
}

class _AddDropdownState extends State<_AddDropdown> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsAddButton(
          label: _open ? 'Close' : 'Add module',
          onTap: () => setState(() => _open = !_open),
        ),
        if (_open)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: theme.controlSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.divider),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final o in widget.options)
                    _DropdownItem(
                      label: o,
                      onTap: () {
                        widget.onSelected(o);
                        setState(() => _open = false);
                      },
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DropdownItem extends StatefulWidget {
  const _DropdownItem({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_DropdownItem> createState() => _DropdownItemState();
}

class _DropdownItemState extends State<_DropdownItem> {
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
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: _hovered ? theme.surfaceHover : const Color(0x00000000),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground,
            ),
          ),
        ),
      ),
    );
  }
}

/// A plus-labelled button for appending to a collection: the string-list
/// editor's dropdown toggle, and the Background and Desktop sections' add
/// actions.
class SettingsAddButton extends StatefulWidget {
  const SettingsAddButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<SettingsAddButton> createState() => _SettingsAddButtonState();
}

class _SettingsAddButtonState extends State<SettingsAddButton> {
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered ? theme.surfaceHover : theme.controlSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(FontAwesomeIcons.plus,
                  size: 11,
                  color: _hovered ? theme.popupForeground : theme.accent),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
