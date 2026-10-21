import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/desktop/desktop_menu.dart';
import 'package:moonswing/overlay/sticky_notes/sticky_layout.dart';
import 'package:moonswing/overlay/sticky_notes/sticky_note.dart';
import 'package:moonswing/overlay_fade_scaffold.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_store.dart';

/// The overview's sticky notes: every note in the todo database, drawn around
/// the panel on the overview's own window.
///
/// A note's place is kept from the panel's centre, so the layout here is
/// driven by the same offset the panel's is and a drag of the panel moves the
/// notes with a relayout and no rebuild. Like the panel, a note is placed by
/// layout and never by a transform, so it is hit where it is drawn.
///
/// The layer itself answers no hits — a click between notes reaches the panel
/// or the scrim beneath it — except while its menu is open, whose barrier
/// takes the click that closes it.
class StickyNoteLayer extends StatefulWidget {
  const StickyNoteLayer({
    super.key,
    required this.offset,
    required this.cardSizeFor,
    required this.opacity,
    this.reserved = const [],
    this.onKeyboardReleased,
    this.store,
  });

  /// The panel's offset from the centre of the output (see
  /// [FadeOverlayScaffold.offset]).
  final ValueListenable<Offset> offset;

  /// The panel's size on an output of the given size.
  final Size Function(Size surface) cardSizeFor;

  /// The overview's fade.
  final Animation<double> opacity;

  /// What a new note is never put on top of: the overview's own buttons.
  final List<Rect> reserved;

  /// A note let go of the keyboard.
  final VoidCallback? onKeyboardReleased;

  /// Tests inject one; the shell's is [TodoStore.instance].
  final TodoStore? store;

  @override
  StickyNoteLayerState createState() => StickyNoteLayerState();
}

typedef _Drag = ({String id, Offset delta});

enum _MenuPage { root, colour, size }

typedef _Menu = ({String id, Offset at, _MenuPage page});

class StickyNoteLayerState extends State<StickyNoteLayer> {
  TodoStore get _store => widget.store ?? TodoStore.instance;

  /// Newest-edited first, as the store keeps them; drawn the other way round,
  /// so the note last written in is on top.
  late List<NoteItem> _notes;

  /// The note being dragged and how far, kept out of the store until the drag
  /// ends: a write per pointer event would notify every listener the board
  /// has. A listenable so the drag relayouts and rebuilds nothing.
  final ValueNotifier<_Drag?> _drag = ValueNotifier(null);

  final ValueNotifier<_Menu?> _menu = ValueNotifier(null);

  /// The output as of the last layout.
  Size _surface = Size.zero;

  /// The note just created, which takes the keyboard as it is first built.
  String? _autofocus;

  bool _placingStrays = false;

  /// Whether a note can be added — false while the database is unreadable.
  bool get canAdd => _store.editable;

  @override
  void initState() {
    super.initState();
    _notes = _store.notes;
    _store.addListener(_onStore);
  }

  @override
  void didUpdateWidget(StickyNoteLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      (oldWidget.store ?? TodoStore.instance).removeListener(_onStore);
      _store.addListener(_onStore);
      _onStore();
    }
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    _drag.dispose();
    _menu.dispose();
    super.dispose();
  }

  /// The store notifies on every card edit as well; only a change to the notes
  /// is this layer's business.
  void _onStore() {
    final notes = _store.notes;
    if (listEquals(notes, _notes)) return;
    setState(() => _notes = notes);
    final menu = _menu.value;
    if (menu != null && !notes.any((n) => n.id == menu.id)) {
      _menu.value = null;
    }
  }

  Rect _card(Size surface) {
    final size = widget.cardSizeFor(surface);
    return placeOverlayCard(surface, size, widget.offset.value) & size;
  }

  /// Every note's rectangle on the output, oldest first.
  List<Rect> _taken(Rect card, {String? except}) => [
    ...widget.reserved,
    for (final note in _notes.reversed)
      if (note.id != except && note.placement.isPlaced)
        stickyRect(_surface, card, note.placement),
  ];

  /// Adds an empty note in the first free spot around the panel and gives it
  /// the keyboard. Returns its id, or null if the store would not take it.
  String? addNote() {
    if (_surface.isEmpty) return null;
    final card = _card(_surface);
    final place = placeNewSticky(_surface, card, _taken(card));
    final id = _store.addNote(
      body: '',
      placement: NotePlacement(dx: place.dx, dy: place.dy),
    );
    if (id == null) return null;
    setState(() => _autofocus = id);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autofocus = null);
    return id;
  }

  /// Closes the menu if one is open; whether there was one. The overview asks
  /// this before an Escape closes it.
  bool dismissMenu() {
    if (_menu.value == null) return false;
    _menu.value = null;
    return true;
  }

  /// Gives a note with no place — one restored from a backup older than
  /// sticky notes — the first free spot, after the frame that found it.
  void _placeStrays() {
    if (_placingStrays || !_notes.any((n) => !n.placement.isPlaced)) return;
    _placingStrays = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _placingStrays = false;
      if (!mounted || _surface.isEmpty) return;
      final card = _card(_surface);
      final taken = _taken(card);
      for (final note in _notes.reversed.toList()) {
        if (note.placement.isPlaced) continue;
        final place = placeNewSticky(_surface, card, taken);
        _store.restyleNote(note.id, dx: place.dx, dy: place.dy);
        taken.add(
          stickyRect(
            _surface,
            card,
            note.placement.copyWith(dx: place.dx, dy: place.dy),
          ),
        );
      }
    });
  }

  NoteItem? _note(String id) {
    for (final note in _notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  /// Where [note]'s centre would be with no clamping and no drag.
  Offset _home(NoteItem note, Rect card) =>
      card.center +
      (note.placement.isPlaced
          ? Offset(note.placement.dx!, note.placement.dy!)
          : Offset.zero);

  void _dragBy(String id, Offset delta) {
    final note = _note(id);
    if (note == null || _surface.isEmpty) return;
    final card = _card(_surface);
    final current = _drag.value;
    final so = current?.id == id ? current!.delta : Offset.zero;
    // Kept to what the clamp lets through, as the panel's drag is, so a drag
    // past the edge leaves no dead travel to undo on the way back.
    final rect = stickyRect(_surface, card, note.placement, drag: so + delta);
    _drag.value = (id: id, delta: rect.center - _home(note, card));
  }

  void _endDrag(String id) {
    final drag = _drag.value;
    final note = _note(id);
    _drag.value = null;
    if (drag == null || drag.id != id || note == null || _surface.isEmpty) {
      return;
    }
    final card = _card(_surface);
    final place = stickyPlaceOf(
      stickyRect(_surface, card, note.placement, drag: drag.delta),
      card,
    );
    _store.restyleNote(id, dx: place.dx, dy: place.dy);
  }

  void _openMenu(String id, Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    _menu.value = (id: id, at: box.globalToLocal(global), page: _MenuPage.root);
  }

  void _showPage(_MenuPage page) {
    final menu = _menu.value;
    if (menu == null) return;
    _menu.value = (id: menu.id, at: menu.at, page: page);
  }

  @override
  Widget build(BuildContext context) {
    _placeStrays();
    return LayoutBuilder(
      builder: (context, constraints) {
        _surface = constraints.biggest;
        return Stack(
          children: [
            Positioned.fill(
              child: CustomMultiChildLayout(
                delegate: _StickyLayout(
                  notes: _notes,
                  offset: widget.offset,
                  drag: _drag,
                  cardSizeFor: widget.cardSizeFor,
                ),
                children: [
                  for (final note in _notes.reversed)
                    LayoutId(
                      id: note.id,
                      child: StickyNote(
                        key: ValueKey(note.id),
                        note: note,
                        opacity: widget.opacity,
                        autofocus: note.id == _autofocus,
                        onChanged: (body) => _store.updateNote(
                          note.id,
                          title: note.title,
                          body: body,
                        ),
                        onDragStart: dismissMenu,
                        onDrag: (delta) => _dragBy(note.id, delta),
                        onDragEnd: () => _endDrag(note.id),
                        onMenu: (at) => _openMenu(note.id, at),
                        onKeyboardReleased: widget.onKeyboardReleased,
                      ),
                    ),
                ],
              ),
            ),
            Positioned.fill(
              child: ValueListenableBuilder<_Menu?>(
                valueListenable: _menu,
                builder: (context, menu, _) {
                  if (menu == null) return const SizedBox.shrink();
                  final note = _note(menu.id);
                  if (note == null) return const SizedBox.shrink();
                  return _StickyMenuLayer(
                    at: menu.at,
                    card: _menuCard(note, menu.page),
                    onDismiss: dismissMenu,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _menuCard(NoteItem note, _MenuPage page) {
    final placement = note.placement;
    void restyle({StickyColor? color, StickySize? size}) {
      _store.restyleNote(note.id, color: color, size: size);
      dismissMenu();
    }

    return switch (page) {
      _MenuPage.root => DesktopMenuCard(
        entries: [
          DesktopMenuEntry(
            label: 'Colour',
            icon: FontAwesomeIcons.palette,
            onTap: () => _showPage(_MenuPage.colour),
          ),
          DesktopMenuEntry(
            label: 'Text size',
            icon: FontAwesomeIcons.textHeight,
            onTap: () => _showPage(_MenuPage.size),
          ),
          DesktopMenuEntry(
            label: 'Remove note',
            icon: FontAwesomeIcons.trashCan,
            onTap: () {
              dismissMenu();
              _store.deleteNote(note.id);
            },
          ),
        ],
      ),
      _MenuPage.colour => DesktopMenuCard(
        header: 'Colour',
        onBack: () => _showPage(_MenuPage.root),
        entries: [
          for (final color in StickyColor.values)
            DesktopMenuEntry(
              label: color.label,
              icon: FontAwesomeIcons.solidSquare,
              iconColor: stickyPaper(color),
              selected: placement.color == color,
              onTap: () => restyle(color: color),
            ),
        ],
      ),
      _MenuPage.size => DesktopMenuCard(
        header: 'Text size',
        onBack: () => _showPage(_MenuPage.root),
        entries: [
          for (final size in StickySize.values)
            DesktopMenuEntry(
              label: size.label,
              selected: placement.size == size,
              onTap: () => restyle(size: size),
            ),
        ],
      ),
    };
  }
}

/// Places every note from the panel's position, which it re-reads on a move
/// of the panel or a drag of a note without anything being rebuilt.
class _StickyLayout extends MultiChildLayoutDelegate {
  _StickyLayout({
    required this.notes,
    required this.offset,
    required this.drag,
    required this.cardSizeFor,
  }) : super(relayout: Listenable.merge([offset, drag]));

  final List<NoteItem> notes;
  final ValueListenable<Offset> offset;
  final ValueListenable<_Drag?> drag;
  final Size Function(Size surface) cardSizeFor;

  @override
  void performLayout(Size size) {
    final cardSize = cardSizeFor(size);
    final card = placeOverlayCard(size, cardSize, offset.value) & cardSize;
    final dragging = drag.value;
    for (final note in notes) {
      if (!hasChild(note.id)) continue;
      final rect = stickyRect(
        size,
        card,
        note.placement,
        drag: dragging != null && dragging.id == note.id
            ? dragging.delta
            : Offset.zero,
      );
      layoutChild(note.id, BoxConstraints.tight(rect.size));
      positionChild(note.id, rect.topLeft);
    }
  }

  @override
  bool shouldRelayout(_StickyLayout oldDelegate) =>
      !identical(oldDelegate.notes, notes) ||
      oldDelegate.offset != offset ||
      oldDelegate.drag != drag ||
      oldDelegate.cardSizeFor != cardSizeFor;
}

/// A note's menu, drawn in the overview's own window as the todo board's card
/// menu is: a full-screen overlay never opens a native popup, and there is no
/// outside of this window for one to need to reach.
class _StickyMenuLayer extends StatelessWidget {
  const _StickyMenuLayer({
    required this.at,
    required this.card,
    required this.onDismiss,
  });

  final Offset at;
  final Widget card;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            onSecondaryTapDown: (_) => onDismiss(),
          ),
        ),
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _AtPointerLayout(at),
            // Absorbs clicks on the card's own chrome, which would otherwise
            // fall through to the barrier.
            child: Listener(behavior: HitTestBehavior.opaque, child: card),
          ),
        ),
      ],
    );
  }
}

/// Puts the menu's top-left corner at the pointer, slid back onto the output
/// where it would hang off its right or bottom edge.
class _AtPointerLayout extends SingleChildLayoutDelegate {
  const _AtPointerLayout(this.at);

  final Offset at;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    at.dx.clamp(0, (size.width - childSize.width).clamp(0, double.infinity)),
    at.dy.clamp(0, (size.height - childSize.height).clamp(0, double.infinity)),
  );

  @override
  bool shouldRelayout(_AtPointerLayout oldDelegate) => oldDelegate.at != at;
}
