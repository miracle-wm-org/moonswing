import 'package:flutter/widgets.dart';

/// A hover state without the ceremony.
///
/// The shell has no Material, so before this primitive every hover-highlight
/// row and button was its own `StatefulWidget` carrying `bool _hovered`, a
/// `MouseRegion`, and two `setState` calls — about thirty classes existed for
/// nothing else. `HoverRegion` owns that bool and hands it to [builder].
///
/// The cursor defaults to a pointer because nearly every hoverable surface in
/// the shell is clickable; pass [cursor] for the exceptions.
class HoverRegion extends StatefulWidget {
  const HoverRegion({
    super.key,
    this.cursor = SystemMouseCursors.click,
    this.onEnter,
    this.onExit,
    required this.builder,
  });

  final MouseCursor cursor;
  final VoidCallback? onEnter;
  final VoidCallback? onExit;
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<HoverRegion> createState() => _HoverRegionState();
}

class _HoverRegionState extends State<HoverRegion> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onEnter?.call();
      },
      onExit: (_) {
        setState(() => _hovered = false);
        widget.onExit?.call();
      },
      child: widget.builder(context, _hovered),
    );
  }
}
