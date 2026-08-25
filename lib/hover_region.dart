import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A hover state, and the tap that goes with it, without the ceremony.
///
/// The shell has no Material, so before this primitive every hover-highlight
/// row and button was its own `StatefulWidget` carrying `bool _hovered`, a
/// `MouseRegion`, and two `setState` calls — about thirty classes existed for
/// nothing else. `HoverRegion` owns that bool and hands it to [builder].
///
/// It owns the `GestureDetector` as well, at [HitTestBehavior.opaque], and
/// **that half is the load-bearing one**. A `GestureDetector` with no
/// `behavior:` is `deferToChild`, and nearly everything a control is built from
/// answers `hitTestSelf == false`: `Padding`, `Align`, `ConstrainedBox`,
/// `ClipRRect`, `Row`/`Column`/`Stack`, `RenderImage`, and a `Container` with
/// neither `color:` nor `decoration:`. So in
/// `Container(width: 26, height: 26, alignment: center, child: FaIcon(size: 11))`
/// the only render object left accepting a hit is the glyph's own
/// `RenderParagraph` — the button hovered and cursored over 26 square and fired
/// over about 11. Emitting the detector here, around [builder]'s result, makes
/// the hover box and the tap box the same rect by construction: a
/// `GestureDetector` is a proxy box with no layout effect, so its rect is
/// [builder]'s rect is the `MouseRegion`'s rect.
///
/// The `builder`-only form (hover with no tap) emits no detector at all. An
/// unconditional opaque box would start swallowing hits meant for a `Stack`
/// sibling underneath, since `RenderStack.hitTestChildren` stops at the first
/// child that accepts.
///
/// The cursor defaults to a pointer because nearly every hoverable surface in
/// the shell is clickable; pass [cursor] for the exceptions.
class HoverRegion extends StatefulWidget {
  const HoverRegion({
    super.key,
    this.cursor = SystemMouseCursors.click,
    this.disabledCursor = SystemMouseCursors.basic,
    this.enabled = true,
    this.onEnter,
    this.onExit,
    this.onTap,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
    this.onSecondaryTapDown,
    required this.builder,
  });

  /// The cursor while [enabled].
  final MouseCursor cursor;

  /// The cursor while not [enabled]. Only reached when [enabled] is false, so a
  /// `builder`-only region keeps the pointer it has always had.
  final MouseCursor disabledCursor;

  /// Whether the gestures fire. False drops every callback and switches to
  /// [disabledCursor] — but the region **still absorbs the pointer**, which is
  /// what a disabled button has always done (its `Container(decoration:)` was
  /// hit-testable whether or not `onTap` was null). `hovered` still flips; call
  /// sites that dim on hover already spell `hovered && canTap`.
  final bool enabled;

  final VoidCallback? onEnter;
  final VoidCallback? onExit;

  /// Tap on release. The default for anything that is not a popup toggle.
  final VoidCallback? onTap;

  /// Tap on press. **Not interchangeable with [onTap].** Every popup toggle in
  /// the shell opens on tap-*down*, because `PopupDismissArea`'s ancestor
  /// `Listener` fires before any descendant recognizer and the coordinator's
  /// reopen guard is armed and consumed inside that one pointer-down (see the
  /// Dismissal section of CLAUDE.md). Moving one of those to [onTap] moves the
  /// open a full press-and-release later, outside the guard's window.
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final VoidCallback? onTapCancel;

  /// Right-click. The reopen guard is armed on the primary button only, so a
  /// secondary press is always free to open a context menu.
  final GestureTapDownCallback? onSecondaryTapDown;

  final Widget Function(BuildContext context, bool hovered) builder;

  bool get _tappable =>
      onTap != null ||
      onTapDown != null ||
      onTapUp != null ||
      onTapCancel != null ||
      onSecondaryTapDown != null;

  @override
  State<HoverRegion> createState() => _HoverRegionState();
}

class _HoverRegionState extends State<HoverRegion> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    Widget child = widget.builder(context, _hovered);

    if (widget._tappable) {
      final on = widget.enabled;
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: on ? widget.onTap : null,
        onTapDown: on ? widget.onTapDown : null,
        onTapUp: on ? widget.onTapUp : null,
        onTapCancel: on ? widget.onTapCancel : null,
        onSecondaryTapDown: on ? widget.onSecondaryTapDown : null,
        child: child,
      );
    }

    return MouseRegion(
      cursor: widget.enabled ? widget.cursor : widget.disabledCursor,
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onEnter?.call();
      },
      onExit: (_) {
        setState(() => _hovered = false);
        widget.onExit?.call();
      },
      child: child,
    );
  }
}
