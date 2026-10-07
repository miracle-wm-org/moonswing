// Mouse selection for the shell's raw `EditableText`s.
//
// There is no Material `TextField` in this tree, and a bare [EditableText]
// cannot be selected with the mouse: [RenderEditable] carries its own plain tap
// recogniser and sits deeper in the hit-test path than any detector wrapped
// around it, so it wins the arena and a hand-rolled one never fires. What it
// does on its own is place the caret, and nothing else — no drag, no double
// click. `rendererIgnoresPointer` switches that recogniser off, and this widget
// takes over with a [TextSelectionGestureDetector], which counts consecutive
// taps rather than racing a double-tap recogniser, so a single click stays
// instant.
//
// Extracted from `OverlaySearchField` when `SettingsTextField` turned out to
// have the bare form — every settings field and the todo editor's could not be
// selected — because thirty lines of `RenderEditable` handling copied a second
// time is the copy that gets subtly wrong.
library;

import 'package:flutter/gestures.dart'
    show
        TapDragDownDetails,
        TapDragEndDetails,
        TapDragStartDetails,
        TapDragUpDetails,
        TapDragUpdateDetails;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Click, Shift+click, double click, triple click and drag for the
/// [EditableText] under [editableKey], which must be built with
/// `rendererIgnoresPointer: true` somewhere inside [child].
///
/// A triple click selects the line in a multi-line field and everything in a
/// one-line one. Every selection goes through
/// [EditableTextState.userUpdateTextEditingValue], so a drag past the edge of a
/// field that scrolls brings the end it is dragging into view.
class EditableTextMouseSelection extends StatefulWidget {
  const EditableTextMouseSelection({
    super.key,
    required this.editableKey,
    required this.child,
  });

  final GlobalKey<EditableTextState> editableKey;
  final Widget child;

  @override
  State<EditableTextMouseSelection> createState() =>
      _EditableTextMouseSelectionState();
}

class _EditableTextMouseSelectionState
    extends State<EditableTextMouseSelection> {
  /// Where the drag in progress started, as a text offset rather than a point:
  /// a field that scrolls under the drag moves the text away from any point
  /// remembered on screen.
  int? _dragAnchor;

  EditableTextState? get _editable => widget.editableKey.currentState;

  bool get _shiftHeld => HardwareKeyboard.instance.isShiftPressed;

  /// The text position under [global], or null while there is no field.
  TextPosition? _positionAt(Offset global) =>
      _editable?.renderEditable.getPositionForPoint(global);

  void _select(TextSelection selection, SelectionChangedCause cause) {
    final editable = _editable;
    if (editable == null) return;
    editable.widget.focusNode.requestFocus();
    editable.userUpdateTextEditingValue(
      editable.textEditingValue.copyWith(selection: selection),
      cause,
    );
  }

  /// The anchor a Shift+click or Shift+drag extends from: the current
  /// selection's base, if there is one.
  int? _extendFrom() {
    final editable = _editable;
    if (editable == null || !_shiftHeld) return null;
    if (!editable.widget.focusNode.hasFocus) return null;
    final selection = editable.textEditingValue.selection;
    return selection.isValid ? selection.baseOffset : null;
  }

  void _onSingleTapUp(TapDragUpDetails details) {
    final position = _positionAt(details.globalPosition);
    if (position == null) return;
    final base = _extendFrom();
    _select(
      base == null
          ? TextSelection.fromPosition(position)
          : TextSelection(baseOffset: base, extentOffset: position.offset),
      SelectionChangedCause.tap,
    );
  }

  void _onDoubleTapDown(TapDragDownDetails details) {
    final editable = _editable;
    if (editable == null) return;
    if (editable.widget.obscureText) {
      // The words of a password are not the user's to see, so a double
      // click takes all of it, as `TextField`'s does.
      _selectAll(SelectionChangedCause.doubleTap);
      return;
    }
    editable.widget.focusNode.requestFocus();
    editable.renderEditable.selectWordsInRange(
      from: details.globalPosition,
      cause: SelectionChangedCause.doubleTap,
    );
  }

  void _onTripleTapDown(TapDragDownDetails details) {
    final editable = _editable;
    if (editable == null) return;
    final position = _positionAt(details.globalPosition);
    if (editable.widget.maxLines == 1 || position == null) {
      _selectAll(SelectionChangedCause.tap);
      return;
    }
    _select(
      lineAround(editable.textEditingValue.text, position.offset),
      SelectionChangedCause.tap,
    );
  }

  void _selectAll(SelectionChangedCause cause) {
    final editable = _editable;
    if (editable == null) return;
    _select(
      TextSelection(
        baseOffset: 0,
        extentOffset: editable.textEditingValue.text.length,
      ),
      cause,
    );
  }

  void _onDragSelectionStart(TapDragStartDetails details) {
    final position = _positionAt(details.globalPosition);
    if (position == null) return;
    final base = _extendFrom();
    _dragAnchor = base ?? position.offset;
    _select(
      TextSelection(baseOffset: _dragAnchor!, extentOffset: position.offset),
      SelectionChangedCause.drag,
    );
  }

  void _onDragSelectionUpdate(TapDragUpdateDetails details) {
    final anchor = _dragAnchor;
    final position = _positionAt(details.globalPosition);
    if (anchor == null || position == null) return;
    _select(
      TextSelection(baseOffset: anchor, extentOffset: position.offset),
      SelectionChangedCause.drag,
    );
  }

  void _onDragSelectionEnd(TapDragEndDetails details) => _dragAnchor = null;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.text,
    child: TextSelectionGestureDetector(
      behavior: HitTestBehavior.opaque,
      onSingleTapUp: _onSingleTapUp,
      onDoubleTapDown: _onDoubleTapDown,
      onTripleTapDown: _onTripleTapDown,
      onDragSelectionStart: _onDragSelectionStart,
      onDragSelectionUpdate: _onDragSelectionUpdate,
      onDragSelectionEnd: _onDragSelectionEnd,
      child: widget.child,
    ),
  );
}

/// The line of [text] holding [offset], without its line break: what a triple
/// click selects in a multi-line field.
@visibleForTesting
TextSelection lineAround(String text, int offset) {
  final at = offset.clamp(0, text.length);
  final start = at == 0 ? 0 : text.lastIndexOf('\n', at - 1) + 1;
  final end = text.indexOf('\n', at);
  return TextSelection(
    baseOffset: start,
    extentOffset: end < 0 ? text.length : end,
  );
}
