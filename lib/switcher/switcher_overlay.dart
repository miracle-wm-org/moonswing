// The Alt+Tab surface: every open window as an icon, five to a row, with the
// full title of the highlighted one written underneath.
//
// One of these is drawn on every output, because a switcher on the display the
// user is not looking at is a switcher they have to go and find. Only one of
// them takes the keyboard ([takesKeyboard]) — that is where Alt coming back up
// is read, and two layer surfaces both asking for exclusive focus is not a
// thing the protocol defines an answer for.
//
// The title goes under the *grid* rather than under its own icon on purpose. A
// window's title is a sentence — "Inbox (12) — user@example.com — Mozilla
// Thunderbird" — and a label that wide under a 112px cell would either wrap the
// grid into a different shape for every window or be cut down to the part that
// says nothing. Under the grid it has the whole card to be read in, and the
// highlight is what says which icon it belongs to.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/config.dart' show ThemeConfig;
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/modules/workspace_apps.dart'
    show WorkspaceAppsStore;
import 'package:graceful_shell/overlay_fade_scaffold.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/switcher/open_window.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// The drawn icon. Large enough to be recognised at a glance from across a
/// 4K screen, which is the whole job of this surface.
const double kSwitcherIconSize = 64;

/// One cell: the icon with room around it for the selection fill.
const double kSwitcherCellWidth = 112;
const double kSwitcherCellHeight = 96;

/// How much of the output the grid may take before it scrolls. The rest is
/// backdrop and the title line, and a card that reaches the edges of the
/// screen stops reading as a card.
const double kSwitcherMaxGridFraction = 0.6;

/// The modifier keys a switcher shortcut can be held on.
///
/// Both sides of each, and the side-less synonyms with them: the trigger the
/// shell registers uses the *generic* modifier bits, so either Alt is the same
/// gesture — and a surface that takes focus with a key already down may only
/// ever learn about it through the modifier state, which is reported under the
/// synonym.
///
/// `final`, not `const`: [LogicalKeyboardKey] overrides `==`, and a constant
/// set has to canonicalize on primitive equality. A top-level `final` is
/// lazily initialized, so it still costs nothing until the first Alt+Tab.
final Set<LogicalKeyboardKey> kSwitcherModifiers = {
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
};

/// How many lines of title the card reserves, filled or not, so it does not
/// change height as the selection moves from a one-line name to a three-line
/// one.
const int kSwitcherTitleLines = 2;

/// The height that many lines need at [size].
///
/// Computed from the ambient [TextScaler] rather than written down, the rule
/// anything deciding a layout from text obeys: `font_size` moves the whole
/// `ShellFontSizes` scale, and a box fixed at the unscaled height would clip
/// the title on every theme that enlarges the type.
double switcherTitleHeight(
  TextScaler scaler, {
  double size = ShellFontSizes.label,
}) => scaler.scale(size) * 1.35 * kSwitcherTitleLines;

class WindowSwitcherOverlay extends StatefulWidget {
  const WindowSwitcherOverlay({
    super.key,
    required this.windows,
    required this.selection,
    required this.closingNotifier,
    required this.onClosed,
    required this.onSelect,
    required this.onCommit,
    required this.onCancel,
    this.takesKeyboard = false,
    this.available = true,
  });

  /// The session's windows, in the order they are drawn. Fixed for the life of
  /// the session — see [WindowSwitcherController].
  final List<OpenWindow> windows;

  /// Which one is highlighted. Listened to per cell rather than read, so a
  /// press of Tab repaints two cells instead of the whole output.
  final ValueListenable<int> selection;

  /// Flipped by the owner to start the exit animation; [onClosed] follows.
  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  /// The pointer picked a cell.
  final ValueChanged<int> onSelect;

  /// Switch to the highlighted window (Alt released, or a click on a cell).
  final VoidCallback onCommit;

  /// Switch to nothing (Escape, or a click on the backdrop).
  final VoidCallback onCancel;

  /// Whether this is the surface that holds keyboard focus. Exactly one of the
  /// switcher's windows has it.
  final bool takesKeyboard;

  /// Whether the shell could read the window list at all. False is a machine
  /// with no compositor connection, which is a different sentence from "you
  /// have nothing open".
  final bool available;

  @override
  State<WindowSwitcherOverlay> createState() => _WindowSwitcherOverlayState();
}

class _WindowSwitcherOverlayState extends State<WindowSwitcherOverlay> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.selection.addListener(_onSelectionChanged);
    // The list can open already scrolled — the previously-used window is the
    // second cell, but a click from the pointer can land anywhere.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelection());
  }

  @override
  void didUpdateWidget(WindowSwitcherOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.selection, widget.selection)) {
      oldWidget.selection.removeListener(_onSelectionChanged);
      widget.selection.addListener(_onSelectionChanged);
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onSelectionChanged() => _revealSelection();

  /// Scrolls the least that brings the highlighted row into view.
  ///
  /// Guarded on `hasClients` twice over: the first frame has not attached the
  /// controller yet, and a grid short enough not to scroll has no position to
  /// move either.
  void _revealSelection() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    final offset = switcherScrollOffset(
      row: switcherRowOf(widget.selection.value),
      rowExtent: kSwitcherCellHeight,
      viewportExtent: position.viewportDimension,
      offset: position.pixels,
      rowCount: switcherRowCount(widget.windows.length),
    );
    if ((offset - position.pixels).abs() < 0.5) return;
    _scroll.animateTo(
      offset,
      duration: ShellDurations.fast,
      curve: Curves.easeOut,
    );
  }

  /// The keyboard, on the one surface that has it.
  ///
  /// **Alt coming up is the commit**, and it is the only thing here that has
  /// to work: the Tab presses never arrive (the compositor consumes what its
  /// own trigger matched), so this handler exists for the release and for the
  /// ways out a mouse-less user would otherwise not have.
  ///
  /// What counts as the release is *any* modifier coming up that leaves none
  /// held, rather than Alt by name: the shortcut is configurable, and reading
  /// the set is also what lets go of Alt+Shift+Tab correctly — releasing Shift
  /// is not releasing the gesture.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.escape:
          widget.onCancel();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.numpadEnter:
        case LogicalKeyboardKey.space:
          widget.onCommit();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowRight:
          _move(1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowLeft:
          _move(-1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          _move(kSwitcherColumns);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _move(-kSwitcherColumns);
          return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyUpEvent) return KeyEventResult.ignored;
    if (!kSwitcherModifiers.contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    // A modifier came up and none is left down. Deliberately not "Alt came
    // up": the shortcut is configurable, so what ends the gesture is whatever
    // modifier the user is holding, and `switch_windows = "super+tab"` has to
    // end on Super. Reading the set rather than the key is also what makes
    // Alt+Shift+Tab work — letting Shift go is not letting go.
    if (_anyModifierDown) return KeyEventResult.ignored;
    widget.onCommit();
    return KeyEventResult.handled;
  }

  bool get _anyModifierDown {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    for (final key in kSwitcherModifiers) {
      if (pressed.contains(key)) return true;
    }
    return false;
  }

  void _move(int delta) {
    if (widget.windows.isEmpty) return;
    widget.onSelect(
      cycleIndex(widget.selection.value, delta, widget.windows.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // Its own text root, like every other full-screen overlay: the window
    // chrome supplies one, but a widget test pumping this on its own must not
    // have to, and every `Text` below needs a `Directionality` in release too.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: theme.fontFamily,
          fontSize: ShellFontSizes.body,
          color: theme.popupForeground,
          decoration: TextDecoration.none,
          fontWeight: FontWeight.normal,
        ),
        child: Focus(
          autofocus: widget.takesKeyboard,
          canRequestFocus: widget.takesKeyboard,
          onKeyEvent: widget.takesKeyboard ? _onKey : null,
          child: FadeOverlayScaffold(
            closing: widget.closingNotifier,
            onClosed: widget.onClosed,
            // The shell has no input-region support, so this surface swallows
            // every click on the monitor. Without dismiss-on-backdrop a
            // switcher opened by a stray Alt+Tab would have to be answered
            // from the keyboard, on whichever screen took focus.
            onBackdropTap: widget.onCancel,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: GestureDetector(
                // The card is not the backdrop: a click in the gap between two
                // icons must not cancel the switch.
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: PopupCard(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: _card(context, theme),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, ThemeConfig theme) {
    if (widget.windows.isEmpty) return _empty(theme);

    final columns = widget.windows.length < kSwitcherColumns
        ? widget.windows.length
        : kSwitcherColumns;
    final rows = switcherRowCount(widget.windows.length);
    // The output, not the card: this surface spans the whole of one screen, so
    // its MediaQuery is the display the grid has to fit on.
    final maxGrid =
        MediaQuery.sizeOf(context).height * kSwitcherMaxGridFraction;
    final gridHeight = rows * kSwitcherCellHeight;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: columns * kSwitcherCellWidth,
          height: gridHeight < maxGrid ? gridHeight : maxGrid,
          child: ListView.builder(
            controller: _scroll,
            // Fixed, so the scroll arithmetic above is the same arithmetic the
            // viewport uses, and so a long list costs no per-row layout.
            itemExtent: kSwitcherCellHeight,
            // The default 250px is two and a half rows of cache either side of
            // a grid that is rarely taller than that; one row is enough to
            // keep a cycle from building as it scrolls.
            cacheExtent: kSwitcherCellHeight,
            physics: const ClampingScrollPhysics(),
            itemCount: rows,
            itemBuilder: (context, row) => _row(row),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: switcherTitleHeight(MediaQuery.textScalerOf(context)),
          width: columns * kSwitcherCellWidth,
          child: Center(
            child: ValueListenableBuilder<int>(
              valueListenable: widget.selection,
              builder: (context, selected, _) {
                final window = selected >= 0 && selected < widget.windows.length
                    ? widget.windows[selected]
                    : null;
                return Text(
                  window?.label ?? '',
                  textAlign: TextAlign.center,
                  maxLines: kSwitcherTitleLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.label,
                    color: theme.popupForeground,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// One row of the grid, centred in it: the last row of a list that does not
  /// divide by five is short, and a short row hanging off the left edge reads
  /// as a rendering fault rather than as the end of the list.
  Widget _row(int row) {
    final first = row * kSwitcherColumns;
    final last = (first + kSwitcherColumns) < widget.windows.length
        ? first + kSwitcherColumns
        : widget.windows.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = first; index < last; index++)
          _SwitcherCell(
            key: ValueKey(widget.windows[index].identifier),
            window: widget.windows[index],
            index: index,
            selection: widget.selection,
            onTap: () {
              widget.onSelect(index);
              widget.onCommit();
            },
          ),
      ],
    );
  }

  Widget _empty(ThemeConfig theme) => SizedBox(
    width: kSwitcherCellWidth * 3,
    height: kSwitcherCellHeight,
    child: Center(
      child: Text(
        widget.available
            ? 'No open windows'
            : 'The shell cannot read the window list',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: ShellFontSizes.label,
          color: theme.muted,
        ),
      ),
    ),
  );
}

/// One window: its icon, in a box that fills when it is the selected one.
///
/// A [RepaintBoundary] each, because a switcher surface has no boundary of its
/// own and cycling moves the highlight several times a second — without one,
/// every press of Tab re-records the picture for the whole output, on every
/// monitor.
class _SwitcherCell extends StatelessWidget {
  const _SwitcherCell({
    super.key,
    required this.window,
    required this.index,
    required this.selection,
    required this.onTap,
  });

  final OpenWindow window;
  final int index;
  final ValueListenable<int> selection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // Memoised in the store — a miss is a GIO lookup, and this runs per icon
    // per build. The same resolver the workspace row's icons come from, so an
    // `app_id` that draws as Firefox in the bar draws as Firefox here.
    final icon = WorkspaceAppsStore.instance.iconFor(window.appId);
    final image = AppIconImage(
      iconName: icon.iconName,
      name: icon.name.isNotEmpty ? icon.name : window.label,
      size: kSwitcherIconSize.round(),
      foreground: theme.popupForeground,
    );
    return RepaintBoundary(
      child: HoverRegion(
        onTap: onTap,
        builder: (context, hovered) => ValueListenableBuilder<int>(
          valueListenable: selection,
          // The icon is handed in rather than rebuilt: it is an
          // `XdgIcon`/`Image`, and a selection change must not re-resolve or
          // re-decode one per cell per press.
          child: image,
          builder: (context, selected, child) {
            final isSelected = selected == index;
            // The cell is exactly one grid slot wide however it is decorated —
            // a margin would widen the row and push the last column past the
            // card the grid was sized to.
            return SizedBox(
              width: kSwitcherCellWidth,
              height: kSwitcherCellHeight,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ShellRadii.card),
                    color: isSelected
                        ? theme.accent.withValues(alpha: 0.22)
                        : (hovered ? theme.surfaceHover : null),
                    border: isSelected
                        ? Border.all(color: theme.accent, width: 2)
                        : null,
                  ),
                  child: Center(child: child),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
