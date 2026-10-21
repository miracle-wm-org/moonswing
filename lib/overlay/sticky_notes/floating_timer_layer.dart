import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/desktop/desktop_menu.dart';
import 'package:moonswing/overlay/sticky_notes/overview_actions.dart';
import 'package:moonswing/overlay/sticky_notes/sticky_layout.dart';
import 'package:moonswing/overlay_fade_scaffold.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/timers/timer_format.dart';
import 'package:moonswing/timers/timer_sound.dart';
import 'package:moonswing/timers/timer_store.dart';
import 'package:moonswing/timers/timer_widgets.dart';

/// A floating timer's card. Fixed, so a new one can be placed before it is
/// built and a readout changing width never moves it.
const Size kFloatingTimerSize = Size(200, 84);

/// The width of the card the timer button opens.
const double kTimerComposerWidth = 264;

/// The overview's timers and stopwatches: every entry in the [TimersStore],
/// drawn as a card floating around the panel on the overview's own window, as
/// the sticky notes are.
///
/// An entry's place is kept in the store, from the panel's centre, so it
/// follows a drag of the panel with a relayout and no rebuild, and is where it
/// was left when the overview is next opened. Nothing is persisted — the store
/// keeps nothing across a restart, places included.
///
/// The layer rebuilds only when an entry comes, goes, moves or changes state;
/// the readouts ticking four times a second rebuild each card's own content
/// and nothing else.
///
/// The layer itself answers no hits — a click between cards reaches whatever
/// is beneath it — except while its menu or composer is open, whose barrier
/// takes the click that closes it.
class FloatingTimerLayer extends StatefulWidget {
  const FloatingTimerLayer({
    super.key,
    required this.offset,
    required this.cardSizeFor,
    required this.opacity,
    this.reserved = _nothingReserved,
    this.onKeyboardReleased,
    this.onMenuOpened,
    this.store,
    this.sound,
  });

  static List<Rect> _nothingReserved() => const [];

  /// The panel's offset from the centre of the output (see
  /// [FadeOverlayScaffold.offset]).
  final ValueListenable<Offset> offset;

  /// The panel's size on an output of the given size.
  final Size Function(Size surface) cardSizeFor;

  /// The overview's fade.
  final Animation<double> opacity;

  /// What a new timer is never put on top of: the overview's own buttons and
  /// the sticky notes. Asked each time one is placed, since what is there
  /// moves.
  final List<Rect> Function() reserved;

  /// The composer let go of the keyboard — started a timer or was closed.
  final VoidCallback? onKeyboardReleased;

  /// A menu or the composer opened, so anything else's menu should close.
  final VoidCallback? onMenuOpened;

  /// Tests inject one; the shell's is [TimersStore.instance].
  final TimersStore? store;

  /// Handed to the composer, which renders the alarm's failure.
  final TimerSoundStore? sound;

  @override
  FloatingTimerLayerState createState() => FloatingTimerLayerState();
}

typedef _Drag = ({int id, Offset delta});

/// What the layer has open: an entry's menu, or — with no [id] — the
/// composer.
typedef _Menu = ({int? id, Offset at});

/// What the layer is drawn from, short of the readouts.
typedef _Shape = ({
  int id,
  ShellTimerKind kind,
  bool running,
  bool finished,
  Offset? place,
});

class FloatingTimerLayerState extends State<FloatingTimerLayer> {
  TimersStore get _store => widget.store ?? TimersStore.instance;

  /// The entries as of the last change to [_shape], oldest first, so the
  /// newest is drawn on top.
  late List<ShellTimer> _entries;
  late List<_Shape> _shape;

  /// The card being dragged and how far, kept out of the store until the drag
  /// ends. A listenable so the drag relayouts and rebuilds nothing.
  final ValueNotifier<_Drag?> _drag = ValueNotifier(null);

  final ValueNotifier<_Menu?> _menu = ValueNotifier(null);

  /// The output as of the last layout.
  Size _surface = Size.zero;

  bool _placingStrays = false;

  @override
  void initState() {
    super.initState();
    _entries = _store.entries;
    _shape = _shapeOf(_entries);
    _store.addListener(_onStore);
  }

  @override
  void didUpdateWidget(FloatingTimerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      (oldWidget.store ?? TimersStore.instance).removeListener(_onStore);
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

  List<_Shape> _shapeOf(List<ShellTimer> entries) => [
    for (final e in entries)
      (
        id: e.id,
        kind: e.kind,
        running: e.running,
        finished: e.finished,
        place: _store.placeOf(e.id),
      ),
  ];

  /// The store notifies on every tick while anything runs; only a change to
  /// what the layer lays out, or to what an open menu offers, is its business.
  void _onStore() {
    final entries = _store.entries;
    final shape = _shapeOf(entries);
    if (listEquals(shape, _shape)) return;
    setState(() {
      _entries = entries;
      _shape = shape;
    });
    final menu = _menu.value;
    if (menu?.id != null && _store.entry(menu!.id!) == null) {
      _menu.value = null;
    }
  }

  Rect _card(Size surface) {
    final size = widget.cardSizeFor(surface);
    return placeOverlayCard(surface, size, widget.offset.value) & size;
  }

  Rect _rectOf(int id, Rect card, {Offset drag = Offset.zero}) => floatRect(
    _surface,
    card,
    _store.placeOf(id),
    kFloatingTimerSize,
    drag: drag,
  );

  /// Every placed entry's rectangle on the output as of the last layout,
  /// oldest first — what anything else floating in the overview keeps clear of.
  List<Rect> get occupied {
    if (_surface.isEmpty) return const [];
    final card = _card(_surface);
    return [
      for (final e in _entries)
        if (_store.placeOf(e.id) != null) _rectOf(e.id, card),
    ];
  }

  /// Starts a stopwatch, which is placed beside the panel once it is drawn.
  int startStopwatch() => _store.startStopwatch();

  /// Opens the composer under [anchor] — the timer button's box.
  void openComposer(Rect anchor) {
    widget.onMenuOpened?.call();
    _menu.value = (id: null, at: anchor.bottomLeft + const Offset(0, 8));
  }

  /// Closes the menu or the composer if either is open; whether one was. The
  /// overview asks this before an Escape closes it.
  bool dismissMenu() {
    final menu = _menu.value;
    if (menu == null) return false;
    _menu.value = null;
    // The composer's field had the keyboard; an entry's menu never took it.
    if (menu.id == null) widget.onKeyboardReleased?.call();
    return true;
  }

  /// Gives every entry with no place yet — one just started — the first free
  /// spot around the panel, after the frame that found it.
  void _placeStrays() {
    if (_placingStrays || _entries.every((e) => _store.placeOf(e.id) != null)) {
      return;
    }
    _placingStrays = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _placingStrays = false;
      if (!mounted || _surface.isEmpty) return;
      final card = _card(_surface);
      final taken = [...widget.reserved(), ...occupied];
      for (final e in _entries) {
        if (_store.placeOf(e.id) != null) continue;
        final place = placeNewFloat(_surface, card, taken, kFloatingTimerSize);
        _store.place(e.id, Offset(place.dx, place.dy));
        taken.add(_rectOf(e.id, card));
      }
    });
  }

  /// Where [id]'s centre would be with no clamping and no drag.
  Offset _home(int id, Rect card) =>
      card.center + (_store.placeOf(id) ?? Offset.zero);

  void _dragBy(int id, Offset delta) {
    if (_surface.isEmpty) return;
    final card = _card(_surface);
    final current = _drag.value;
    final so = current?.id == id ? current!.delta : Offset.zero;
    // Kept to what the clamp lets through, as the panel's drag is, so a drag
    // past the edge leaves no dead travel to undo on the way back.
    final rect = _rectOf(id, card, drag: so + delta);
    _drag.value = (id: id, delta: rect.center - _home(id, card));
  }

  void _endDrag(int id) {
    final drag = _drag.value;
    if (drag != null && drag.id == id && !_surface.isEmpty) {
      final card = _card(_surface);
      final place = stickyPlaceOf(_rectOf(id, card, drag: drag.delta), card);
      _store.place(id, Offset(place.dx, place.dy));
    }
    _drag.value = null;
  }

  void _openMenu(int id, Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    widget.onMenuOpened?.call();
    _menu.value = (id: id, at: box.globalToLocal(global));
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
                delegate: _TimerLayout(
                  entries: _entries,
                  placeOf: _store.placeOf,
                  offset: widget.offset,
                  drag: _drag,
                  cardSizeFor: widget.cardSizeFor,
                ),
                children: [
                  for (final e in _entries)
                    LayoutId(
                      id: e.id,
                      child: FloatingTimer(
                        key: ValueKey(e.id),
                        id: e.id,
                        store: _store,
                        opacity: widget.opacity,
                        onDragStart: dismissMenu,
                        onDrag: (delta) => _dragBy(e.id, delta),
                        onDragEnd: () => _endDrag(e.id),
                        onMenu: (at) => _openMenu(e.id, at),
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
                  final id = menu.id;
                  if (id == null) {
                    return OverviewMenuLayer(
                      at: menu.at,
                      card: _composerCard(),
                      onDismiss: dismissMenu,
                    );
                  }
                  final entry = _store.entry(id);
                  if (entry == null) return const SizedBox.shrink();
                  return OverviewMenuLayer(
                    at: menu.at,
                    card: _menuCard(entry),
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

  Widget _composerCard() => SizedBox(
    width: kTimerComposerWidth,
    child: PopupCard(
      padding: const EdgeInsets.all(12),
      child: TimerComposer(
        store: _store,
        sound: widget.sound,
        autofocus: true,
        onStarted: (_) => dismissMenu(),
      ),
    ),
  );

  Widget _menuCard(ShellTimer entry) {
    void act(void Function(int id) action) {
      dismissMenu();
      action(entry.id);
    }

    return DesktopMenuCard(
      entries: [
        DesktopMenuEntry(
          // A finished countdown has nothing left to resume, so the store
          // restarts it — and the row says so.
          label: entry.finished
              ? 'Restart'
              : entry.running
              ? 'Pause'
              : 'Resume',
          icon: entry.finished
              ? FontAwesomeIcons.arrowRotateRight
              : entry.running
              ? FontAwesomeIcons.pause
              : FontAwesomeIcons.play,
          onTap: () => act(_store.toggle),
        ),
        DesktopMenuEntry(
          label: 'Reset',
          icon: FontAwesomeIcons.arrowRotateLeft,
          // Greyed rather than gone on a finished countdown, whose reset is
          // the restart above it: the menu keeps its shape.
          enabled: !entry.finished,
          onTap: () => act(_store.reset),
        ),
        DesktopMenuEntry(
          label: entry.kind == ShellTimerKind.stopwatch
              ? 'Remove stopwatch'
              : 'Remove timer',
          icon: FontAwesomeIcons.trashCan,
          onTap: () => act(_store.stop),
        ),
      ],
    );
  }
}

/// Places every card from the panel's position, which it re-reads on a move
/// of the panel or a drag of a card without anything being rebuilt.
class _TimerLayout extends MultiChildLayoutDelegate {
  _TimerLayout({
    required this.entries,
    required this.placeOf,
    required this.offset,
    required this.drag,
    required this.cardSizeFor,
  }) : super(relayout: Listenable.merge([offset, drag]));

  final List<ShellTimer> entries;
  final Offset? Function(int id) placeOf;
  final ValueListenable<Offset> offset;
  final ValueListenable<_Drag?> drag;
  final Size Function(Size surface) cardSizeFor;

  @override
  void performLayout(Size size) {
    final cardSize = cardSizeFor(size);
    final card = placeOverlayCard(size, cardSize, offset.value) & cardSize;
    final dragging = drag.value;
    for (final e in entries) {
      if (!hasChild(e.id)) continue;
      final rect = floatRect(
        size,
        card,
        placeOf(e.id),
        kFloatingTimerSize,
        drag: dragging != null && dragging.id == e.id
            ? dragging.delta
            : Offset.zero,
      );
      layoutChild(e.id, BoxConstraints.tight(rect.size));
      positionChild(e.id, rect.topLeft);
    }
  }

  @override
  bool shouldRelayout(_TimerLayout oldDelegate) =>
      !identical(oldDelegate.entries, entries) ||
      oldDelegate.placeOf != placeOf ||
      oldDelegate.offset != offset ||
      oldDelegate.drag != drag ||
      oldDelegate.cardSizeFor != cardSizeFor;
}

/// One timer or stopwatch floating in the overview: what it is, and where it
/// has got to. Dragged anywhere on it; its controls are its right-click menu.
///
/// Laid out by [FloatingTimerLayer], which owns the drag and the menu; this
/// owns only its readout, which it follows from the store itself so a tick
/// rebuilds one card and not the layer.
class FloatingTimer extends StatelessWidget {
  const FloatingTimer({
    super.key,
    required this.id,
    required this.store,
    required this.opacity,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
    required this.onMenu,
  });

  final int id;
  final TimersStore store;

  /// The overview's own fade, so a card arrives and leaves with the panel.
  final Animation<double> opacity;

  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;

  /// A secondary click, at this global position.
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    // Its own layer: the readout ticking and a drag of another card repaint
    // this card and not the output.
    return RepaintBoundary(
      child: FadeTransition(
        opacity: opacity,
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => onDragStart(),
            onPanUpdate: (details) => onDrag(details.delta),
            onPanEnd: (_) => onDragEnd(),
            onPanCancel: onDragEnd,
            onSecondaryTapDown: (details) => onMenu(details.globalPosition),
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) {
                final entry = store.entry(id);
                if (entry == null) return const SizedBox.shrink();
                return _FloatingTimerFace(entry: entry, now: store.now);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingTimerFace extends StatelessWidget {
  const _FloatingTimerFace({required this.entry, required this.now});

  final ShellTimer entry;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final Color readoutColor;
    if (entry.finished) {
      readoutColor = theme.accentText;
    } else if (entry.running) {
      readoutColor = theme.popupForeground;
    } else {
      readoutColor = theme.popupForeground.withValues(alpha: 0.55);
    }
    final quiet = theme.popupForeground.withValues(alpha: 0.6);
    return DecoratedBox(
      decoration: BoxDecoration(
        // Opaque, like the panel and the corner buttons: the card floats over
        // the scrim and whatever the compositor shows through it.
        color: opaquePopupFill(theme),
        borderRadius: BorderRadius.circular(ShellRadii.card),
        border: Border.all(
          color: entry.finished ? theme.accent : theme.divider,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FaIcon(
                  timerKindIcon(entry.kind),
                  size: 11,
                  color: entry.finished ? theme.accentText : quiet,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    timerSubtitle(entry),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ShellFontSizes.caption,
                      fontFamily: theme.fontFamily,
                      color: quiet,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            // Shrunk rather than clipped when a large `font_size` would push
            // the readout past the card, which is a fixed size.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatTimerDuration(entry.displayAt(now)),
                  style: TextStyle(
                    fontSize: 30,
                    fontFamily: theme.fontFamily,
                    color: readoutColor,
                    fontWeight: FontWeight.w600,
                    // Tabular, or the readout shuffles on every digit that
                    // changes width.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
