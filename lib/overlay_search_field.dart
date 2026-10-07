// The search input the shell's full-screen overlays type into.
//
// Extracted from the launcher's own private copy when the emoji picker wanted the
// same control: the settings library's "a control the library lacks gets added to
// the library" rule applied one layer out, because the mouse wiring below is
// thirty lines of `RenderEditable` handling a second hand-rolled copy would have
// got subtly wrong.
library;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/editable_text_mouse.dart';
import 'package:moonswing/theme/tokens.dart';

/// A raw [EditableText] (there is no Material `TextField` in this tree) with an
/// autofocus and a hint drawn behind it.
///
/// Mouse selection is [EditableTextMouseSelection]'s.
///
/// The owner supplies the controller and focus node and disposes them: every
/// overlay reads the query in its own key handler, and a field that owned them
/// would be a field the handler could not see.
class OverlaySearchField extends StatefulWidget {
  const OverlaySearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.theme,
    required this.hint,
    required this.onChanged,
    this.icon = FontAwesomeIcons.magnifyingGlass,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ThemeConfig theme;

  /// Drawn behind an empty field. Says what the overlay searches, which for
  /// both of its callers is more than the obvious noun.
  final String hint;

  final ValueChanged<String> onChanged;

  /// The glyph at the leading edge.
  final FaIconData icon;

  @override
  State<OverlaySearchField> createState() => _OverlaySearchFieldState();
}

class _OverlaySearchFieldState extends State<OverlaySearchField> {
  final GlobalKey<EditableTextState> _editableKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.controlSurface,
        borderRadius: BorderRadius.circular(ShellRadii.card),
        border: Border.all(color: theme.divider, width: 1),
      ),
      child: Row(
        children: [
          FaIcon(widget.icon, size: 14, color: theme.muted),
          const SizedBox(width: 10),
          Expanded(
            child: EditableTextMouseSelection(
              editableKey: _editableKey,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.controller,
                    builder: (context, value, _) => value.text.isEmpty
                        ? Text(
                            widget.hint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.muted,
                              fontSize: ShellFontSizes.field,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  EditableText(
                    key: _editableKey,
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    autofocus: true,
                    // Hands pointer handling to the detector above; without
                    // this RenderEditable's own tap recogniser wins the
                    // arena and nothing but caret placement ever works.
                    rendererIgnoresPointer: true,
                    style: TextStyle(
                      fontSize: ShellFontSizes.field,
                      color: theme.popupForeground,
                      fontFamily: theme.fontFamily,
                    ),
                    // The caret is a mark to be *seen*, so it takes the
                    // accent's reading colour; the highlight below is a fill
                    // and keeps the accent itself. Swapping them over would
                    // put pale text on a pale block.
                    cursorColor: theme.accentText,
                    backgroundCursorColor: theme.divider,
                    // Selected text is drawn on the accent, which reads as an
                    // inverted block against the field's dark control surface.
                    // Flutter paints the highlight *behind* the glyphs and
                    // offers no way to recolour them, so the contrast has to
                    // come from the highlight alone.
                    selectionColor: theme.accent,
                    onChanged: widget.onChanged,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
