import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:moonswing/editable_text_mouse.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/todo/todo_model.dart';

/// The paper a [StickyColor] names.
///
/// Fixed rather than the theme's: a sticky note is the user's own colour
/// coding, and a palette that moved with the theme would recolour every note
/// on a theme switch. Pale enough that [kStickyInk] reads on all six.
Color stickyPaper(StickyColor color) => switch (color) {
  StickyColor.yellow => const Color(0xFFFFF2A8),
  StickyColor.pink => const Color(0xFFFFC9DE),
  StickyColor.green => const Color(0xFFCDEBB4),
  StickyColor.blue => const Color(0xFFBFE3F7),
  StickyColor.purple => const Color(0xFFDCCFF2),
  StickyColor.orange => const Color(0xFFFFD3A3),
};

/// The size of the writing on a note of [size]. The paper is one size for
/// every note (`kStickySide`); this is what the note's size names.
double stickyFontSize(StickySize size) => switch (size) {
  StickySize.small => ShellFontSizes.secondary,
  StickySize.medium => ShellFontSizes.label,
  StickySize.large => ShellFontSizes.heading,
};

/// The ink every note is written in.
const Color kStickyInk = Color(0xFF2F2A22);

/// How long typing must pause before the text is written to the store. The
/// store debounces its own write as well; this one keeps a word typed from
/// reordering the notes on every key (an edit brings a note to the front).
const Duration kStickyCommitDelay = Duration(milliseconds: 600);

/// The strip along a note's top it is dragged by.
const double kStickyGripHeight = 22;

/// One sticky note: a square of paper with a grip to drag it by and a field
/// to write on.
///
/// Laid out by `StickyNoteLayer`, which owns the drag and the menu; this owns
/// only the text, which it hands back through [onChanged] after a pause in the
/// typing, when the field loses the keyboard, and when it goes away.
class StickyNote extends StatefulWidget {
  const StickyNote({
    super.key,
    required this.note,
    required this.opacity,
    required this.onChanged,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
    required this.onMenu,
    this.onKeyboardReleased,
    this.autofocus = false,
  });

  final NoteItem note;

  /// The overview's own fade, so a note arrives and leaves with the panel.
  final Animation<double> opacity;

  final ValueChanged<String> onChanged;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;

  /// A secondary click, at this global position.
  final ValueChanged<Offset> onMenu;

  /// Escape let go of the keyboard; whoever had it before should take it back,
  /// or the overview's own Escape has nobody listening.
  final VoidCallback? onKeyboardReleased;

  final bool autofocus;

  @override
  State<StickyNote> createState() => _StickyNoteState();
}

class _StickyNoteState extends State<StickyNote> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.note.body,
  );
  final FocusNode _focusNode = FocusNode();
  final GlobalKey<EditableTextState> _editableKey = GlobalKey();
  Timer? _commitTimer;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(StickyNote oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Text that changed under the note — a restore from a backup — is taken,
    // but never while the user is writing in it.
    if (!_focusNode.hasFocus &&
        _commitTimer == null &&
        widget.note.body != _controller.text) {
      _controller.text = widget.note.body;
    }
  }

  @override
  void dispose() {
    final pending = _commitTimer != null;
    _commitTimer?.cancel();
    if (pending) {
      // Not from here directly: the store notifies the layer above, which is
      // being torn down in the same pass and may not rebuild in it.
      final text = _controller.text;
      final onChanged = widget.onChanged;
      scheduleMicrotask(() => onChanged(text));
    }
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _onTyped(String _) {
    _commitTimer?.cancel();
    _commitTimer = Timer(kStickyCommitDelay, _commit);
  }

  void _commit() {
    _commitTimer?.cancel();
    _commitTimer = null;
    if (_controller.text != widget.note.body) {
      widget.onChanged(_controller.text);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !_focusNode.hasFocus) {
      return KeyEventResult.ignored;
    }
    // Escape puts the pen down rather than closing the overview: the
    // overview's listener is an ancestor, and would close on any Escape it
    // heard.
    _focusNode.unfocus();
    widget.onKeyboardReleased?.call();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final paper = stickyPaper(widget.note.placement.color);
    final style = TextStyle(
      fontFamily: theme.fontFamily,
      fontSize: stickyFontSize(widget.note.placement.size),
      height: 1.35,
      color: kStickyInk,
    );
    // Its own layer: typing, the caret's blink and a drag of another note
    // repaint this note and not the output.
    return RepaintBoundary(
      child: FadeTransition(
        opacity: widget.opacity,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (details) =>
              widget.onMenu(details.globalPosition),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: paper,
              borderRadius: BorderRadius.circular(ShellRadii.barButton),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _grip(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      onKeyEvent: _onKey,
                      child: EditableTextMouseSelection(
                        editableKey: _editableKey,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _controller,
                                  builder: (context, value, _) =>
                                      value.text.isNotEmpty
                                      ? const SizedBox.shrink()
                                      : Text(
                                          'Jot something down…',
                                          style: style.copyWith(
                                            color: kStickyInk.withValues(
                                              alpha: 0.4,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            EditableText(
                              key: _editableKey,
                              controller: _controller,
                              focusNode: _focusNode,
                              autofocus: widget.autofocus,
                              rendererIgnoresPointer: true,
                              style: style,
                              cursorColor: kStickyInk,
                              backgroundCursorColor: kStickyInk.withValues(
                                alpha: 0.2,
                              ),
                              selectionColor: kStickyInk.withValues(
                                alpha: 0.18,
                              ),
                              maxLines: null,
                              expands: true,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              onChanged: _onTyped,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _grip() => MouseRegion(
    cursor: SystemMouseCursors.move,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => widget.onDragStart(),
      onPanUpdate: (details) => widget.onDrag(details.delta),
      onPanEnd: (_) => widget.onDragEnd(),
      onPanCancel: widget.onDragEnd,
      child: SizedBox(
        height: kStickyGripHeight,
        child: Center(
          child: Container(
            width: 28,
            height: 4,
            decoration: BoxDecoration(
              color: kStickyInk.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    ),
  );
}
