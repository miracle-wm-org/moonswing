// The search input the shell's full-screen overlays type into.
//
// Extracted from the launcher's own private copy when the emoji picker wanted the
// same control: the settings library's "a control the library lacks gets added to
// the library" rule applied one layer out, because the mouse wiring below is
// thirty lines of `RenderEditable` handling a second hand-rolled copy would have
// got subtly wrong.
library;

import 'package:flutter/gestures.dart'
    show
        TapDragDownDetails,
        TapDragStartDetails,
        TapDragUpDetails,
        TapDragUpdateDetails;
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// A raw [EditableText] (there is no Material `TextField` in this tree) with an
/// autofocus and a hint drawn behind it.
///
/// Mouse selection is wired up the way `TextField` does it, because a bare
/// [EditableText] cannot: [RenderEditable] carries its own plain tap recogniser
/// and sits deeper in the hit-test path than any detector wrapped around it, so it
/// wins the arena and a hand-rolled one never fires. `rendererIgnoresPointer`
/// switches that off and lets [TextSelectionGestureDetector] — which counts
/// consecutive taps rather than racing a double-tap recogniser, so single clicks
/// stay instant — own click, double-click, triple-click and drag.
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

  RenderEditable? get _renderEditable =>
      _editableKey.currentState?.renderEditable;

  void _onSingleTapUp(TapDragUpDetails details) {
    widget.focusNode.requestFocus();
    _renderEditable?.selectPositionAt(
      from: details.globalPosition,
      cause: SelectionChangedCause.tap,
    );
  }

  void _onDoubleTapDown(TapDragDownDetails details) {
    widget.focusNode.requestFocus();
    _renderEditable?.selectWordsInRange(
      from: details.globalPosition,
      cause: SelectionChangedCause.doubleTap,
    );
  }

  void _onTripleTapDown(TapDragDownDetails details) {
    widget.focusNode.requestFocus();
    // A one-line field, so "the paragraph" is the whole query.
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.controller.text.length,
    );
  }

  void _onDragSelectionStart(TapDragStartDetails details) {
    widget.focusNode.requestFocus();
    _renderEditable?.selectPositionAt(
      from: details.globalPosition,
      cause: SelectionChangedCause.drag,
    );
  }

  void _onDragSelectionUpdate(TapDragUpdateDetails details) {
    // The details report where the drag is *now* plus how far it has come, so
    // the anchor is recovered rather than remembered.
    _renderEditable?.selectPositionAt(
      from: details.globalPosition - details.offsetFromOrigin,
      to: details.globalPosition,
      cause: SelectionChangedCause.drag,
    );
  }

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
            child: MouseRegion(
              cursor: SystemMouseCursors.text,
              child: TextSelectionGestureDetector(
                behavior: HitTestBehavior.opaque,
                onSingleTapUp: _onSingleTapUp,
                onDoubleTapDown: _onDoubleTapDown,
                onTripleTapDown: _onTripleTapDown,
                onDragSelectionStart: _onDragSelectionStart,
                onDragSelectionUpdate: _onDragSelectionUpdate,
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
                      cursorColor: theme.accent,
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
          ),
        ],
      ),
    );
  }
}
