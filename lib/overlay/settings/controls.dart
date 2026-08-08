// ignore_for_file: library_private_types_in_public_api

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/scopes.dart';

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
  });

  final num value;
  final bool isInt;
  final ValueChanged<num> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsTextField(
      width: 90,
      initial: isInt ? '${value.toInt()}' : _trimDouble(value.toDouble()),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          isInt ? RegExp(r'[0-9]') : RegExp(r'[0-9.]'),
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
/// The list floats in the *root* overlay for the same reason
/// [SettingsColorField]'s picker does — the settings content pane is a nested
/// `Navigator` whose `Overlay` would clip it — and it carries a filter field
/// because a typical desktop has a few hundred families.
class SettingsFontField extends StatefulWidget {
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
  State<SettingsFontField> createState() => _SettingsFontFieldState();
}

class _SettingsFontFieldState extends State<SettingsFontField> {
  final _link = LayerLink();
  OverlayEntry? _entry;
  bool _hovered = false;

  @override
  void didUpdateWidget(SettingsFontField old) {
    super.didUpdateWidget(old);
    // Switching themes replaces the value under an open list; leaving it up
    // would let the next click write the old theme's pick into the new one.
    if (widget.value != old.value) _close();
  }

  @override
  void dispose() {
    // Not _close(): that repaints the trigger, and this element is on its way
    // out of the tree.
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _toggle() {
    if (widget.locked) {
      widget.onLockedTap?.call();
      return;
    }
    if (_entry != null) {
      _close();
    } else {
      _open();
    }
  }

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

  void _select(String family) {
    _close();
    widget.onChanged(family);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final open = _entry != null;
    return Opacity(
      opacity: widget.locked ? 0.45 : 1.0,
      child: CompositedTransformTarget(
        link: _link,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: _toggle,
            child: Container(
              width: widget.width,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _hovered ? theme.surfaceHover : theme.controlSurface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: open ? theme.accent : theme.divider),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.value,
                      // Drawn in the family it names, so the trigger previews
                      // the choice as well as reporting it.
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: widget.value,
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
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 6),
          child: _FontPickerPopup(
            fonts: widget.fonts,
            selected: widget.value,
            onSelected: _select,
            onDismiss: _close,
          ),
        ),
      ],
    );
  }
}

/// The floating list itself. Owns the filter text, so typing rebuilds this
/// widget rather than the [OverlayEntry] that hosts it.
class _FontPickerPopup extends StatefulWidget {
  const _FontPickerPopup({
    required this.fonts,
    required this.selected,
    required this.onSelected,
    required this.onDismiss,
  });

  final List<String> fonts;
  final String selected;
  final ValueChanged<String> onSelected;
  final VoidCallback onDismiss;

  @override
  State<_FontPickerPopup> createState() => _FontPickerPopupState();
}

class _FontPickerPopupState extends State<_FontPickerPopup> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  List<String> _filtered = const [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.fonts;
    // Open scrolled to the current family rather than at the top of a few
    // hundred rows. After the first layout, not through initialScrollOffset:
    // a list shorter than the popup has no scroll extent to spend, and the
    // overscroll leaves every row above the offset built but off-stage.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  void _revealSelected() {
    if (!mounted || !_scroll.hasClients) return;
    final index = _filtered.indexOf(widget.selected);
    if (index <= 0) return;
    final target = (index * _kFontRowHeight)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if (target > 0) _scroll.jumpTo(target);
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _filter(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.fonts
          : widget.fonts
              .where((f) => f.toLowerCase().contains(q))
              .toList(growable: false);
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Focus(
      // Nested above the search field's node, so it only sees what the editor
      // declines — Escape here, every editing key still in the field.
      onKeyEvent: _onKey,
      child: Container(
        width: 240,
        constraints: const BoxConstraints(maxHeight: 300),
        decoration: BoxDecoration(
          color: theme.popupBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                        // Enter takes the top match, so a full name can be typed
                        // without reaching for the mouse.
                        onSubmitted: (_) {
                          if (_filtered.isNotEmpty) {
                            widget.onSelected(_filtered.first);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text(
                  'No matching font',
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
                  itemExtent: _kFontRowHeight,
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final family = _filtered[i];
                    return _FontRow(
                      family: family,
                      selected: family == widget.selected,
                      onTap: () => widget.onSelected(family),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FontRow extends StatefulWidget {
  const _FontRow({
    required this.family,
    required this.selected,
    required this.onTap,
  });

  final String family;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FontRow> createState() => _FontRowState();
}

class _FontRowState extends State<_FontRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final bg = widget.selected
        ? theme.accent.withValues(alpha: 0.15)
        : _hovered
            ? theme.surfaceHover
            : const Color(0x00000000);
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
          child: Text(
            widget.family,
            // The point of the row: what the family actually looks like.
            style: TextStyle(
              fontSize: 13,
              fontFamily: widget.family,
              color: widget.selected ? theme.accent : theme.popupForeground,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
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
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  final a = (argb >> 24) & 0xFF;
  if (a == 0xFF) return '#$rgb';
  return '#${a.toRadixString(16).padLeft(2, '0')}$rgb';
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
    if (widget.initial != old.initial && widget.initial != _controller.text) {
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
          child: SettingsColorPicker(
            initial: parseHexColor(_controller.text) ?? const Color(0xFF000000),
            onChanged: _apply,
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

/// Editable ordered list of strings. When [suggestions] is provided, new items
/// are added from a dropdown of those values; otherwise a free-form text field
