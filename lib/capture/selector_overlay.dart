// The selection surface: a full-output layer-shell window, one per monitor,
// that the user drags a rectangle on or points at a window through.
//
// Everything it needs is a parameter — the output it is on, the snapshot of
// the windowing environment, and the two callbacks — so the whole surface is a
// widget test with no compositor and no Wayland behind it.
//
// Three things a change here has to keep true:
//
// - **There is no entrance and no exit animation, and that is deliberate.**
//   Every other overlay in the shell fades; this one is a *tool*, and a fade-in
//   is a fraction of a second in which the drag the user has already started
//   goes to a surface that is not yet listening. The exit matters more: a
//   screenshot is taken the instant this comes down, so a fade-out would put
//   a half-transparent copy of this very surface into the picture. The
//   `closing` handshake is still honoured — the root's `_OverlayWindow`
//   protocol needs it — it simply resolves on the next frame.
// - **Only the surface's own size decides an area's geometry.** A layer-shell
//   surface anchored to all four edges *is* the output, so its constraints are
//   the output's logical size, which is exactly the space [AreaCapture.crop]
//   is expressed in. Nothing about an area selection needs miracle, which is
//   what lets a screenshot work on a shell whose IPC socket is down.
// - **Window rectangles come from miracle and are mapped, not assumed.**
//   miracle reports one global logical space; this surface is laid out in its
//   own output-local one. They are usually the same scale and the mapping is
//   still done properly, because "usually" is how a fractional-scaled second
//   monitor comes to draw every highlight in the wrong place.

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

import 'selection_controller.dart';
import 'window_targets.dart';

/// The smallest drag that counts as an area rather than a mis-click.
///
/// A click with no drag is a no-op rather than a cancellation: the surface has
/// taken over the whole output, and losing the tool to a twitch of the hand
/// while reaching for the corner of a window is worse than one ignored click.
/// The ways out are Escape and the right mouse button, both of which say so on
/// the banner.
const int kMinSelectionSize = 8;

class CaptureSelectorOverlay extends StatefulWidget {
  const CaptureSelectorOverlay({
    super.key,
    required this.request,
    required this.connector,
    required this.scene,
    required this.closingNotifier,
    required this.onClosed,
    required this.onPicked,
    required this.onCancel,
  });

  final SelectionRequest request;

  /// The `wl_output.name` of the output this surface covers.
  final String connector;

  /// The windowing environment as it was when the selection started.
  final CaptureScene scene;

  /// Flipped by the owner to take the surface down; [onClosed] follows on the
  /// next frame.
  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  final void Function(CaptureTarget target) onPicked;
  final VoidCallback onCancel;

  @override
  State<CaptureSelectorOverlay> createState() => _CaptureSelectorOverlayState();
}

class _CaptureSelectorOverlayState extends State<CaptureSelectorOverlay> {
  Offset? _dragStart;
  Offset? _dragEnd;
  SelectableWindow? _hovered;
  bool _pointerInside = false;
  bool _answered = false;

  /// The surface's own size and the miracle mapping over it, cached from the
  /// last build. A tap handler cannot derive them — `context.size` is the
  /// element's box, not the output's — and both are constant for the life of
  /// the surface anyway.
  Size _surface = Size.zero;
  _OutputMapping _mapping = _OutputMapping.identity;

  @override
  void initState() {
    super.initState();
    widget.closingNotifier.addListener(_onClosing);
  }

  @override
  void dispose() {
    widget.closingNotifier.removeListener(_onClosing);
    super.dispose();
  }

  /// No exit animation to play, so the handshake resolves on the next frame —
  /// after this surface has had one more chance to stop painting, and before
  /// the shutter.
  ///
  /// The [SchedulerBinding.scheduleFrame] is load-bearing and is
  /// `WindowTeardown`'s rule over again: `addPostFrameCallback` *requests* no
  /// frame, and nothing on this surface animates — the closing notifier does
  /// not even rebuild it — so with nothing else on the machine drawing, the
  /// callback would simply never run and the selection surfaces would stay on
  /// screen for ever.
  void _onClosing() {
    if (!widget.closingNotifier.value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onClosed();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _answer(CaptureTarget target) {
    if (_answered) return;
    _answered = true;
    widget.onPicked(target);
  }

  void _cancel() {
    if (_answered) return;
    _answered = true;
    widget.onCancel();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final surface = Size(
            constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
            constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
          );
          _surface = surface;
          _mapping = _OutputMapping.of(
              widget.scene.outputFor(widget.connector), surface);
          return _buildSurface(theme, surface, _mapping);
        },
      ),
    );
  }

  Widget _buildSurface(
      ThemeConfig theme, Size surface, _OutputMapping mapping) {
    final highlight = _highlight(surface, mapping);
    final accent = widget.request.kind == CaptureKind.video
        ? kErrorColor
        : theme.accent;

    return Stack(
      fit: StackFit.expand,
      children: [
        // The dim and the rim, under everything: it is decoration, and every
        // pointer that lands on it has to reach the gesture layer below.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _SelectionPainter(
                highlight: highlight,
                dim: const Color(0x8C000000),
                rim: accent,
              ),
            ),
          ),
        ),
        Positioned.fill(child: _gestureLayer(surface)),
        if (highlight != null)
          _readout(theme, accent, highlight, surface),
        _banner(theme, accent, surface),
      ],
    );
  }

  /// The rectangle the user is about to take, in surface coordinates.
  Rect? _highlight(Size surface, _OutputMapping mapping) {
    switch (widget.request.mode) {
      case SelectionMode.area:
        final start = _dragStart;
        final end = _dragEnd;
        if (start == null || end == null) return null;
        return Rect.fromPoints(start, end)
            .intersect(Offset.zero & surface);
      case SelectionMode.window:
        final hovered = _hovered;
        if (hovered == null) return null;
        return mapping.toLocal(hovered.rect).intersect(Offset.zero & surface);
      case SelectionMode.output:
        // The whole surface lights up only once the pointer is on *this*
        // output: with two monitors both would otherwise be highlighted at
        // once, which says nothing about which one a click would take.
        return _pointerInside ? Offset.zero & surface : null;
    }
  }

  Widget _gestureLayer(Size surface) {
    switch (widget.request.mode) {
      case SelectionMode.area:
        return MouseRegion(
          cursor: SystemMouseCursors.precise,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // `down`, or the recognizer's slop is folded into the reported
            // start and the rectangle's first corner jumps away from the
            // press — the rule `desktop_grid.dart`'s rubber band states.
            dragStartBehavior: DragStartBehavior.down,
            onSecondaryTapDown: (_) => _cancel(),
            onPanDown: (details) => setState(() {
              _dragStart = details.localPosition;
              _dragEnd = details.localPosition;
            }),
            onPanUpdate: (details) =>
                setState(() => _dragEnd = details.localPosition),
            onPanEnd: (_) => _finishArea(),
            onPanCancel: () => setState(() {
              _dragStart = null;
              _dragEnd = null;
            }),
          ),
        );
      case SelectionMode.window:
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (event) => _onHover(event.localPosition),
          onExit: (_) => setState(() => _hovered = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (_) => _cancel(),
            onTapDown: (details) => _onHover(details.localPosition),
            onTap: _finishWindow,
          ),
        );
      case SelectionMode.output:
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _pointerInside = true),
          onExit: (_) => setState(() => _pointerInside = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (_) => _cancel(),
            onTap: () => _answer(OutputCapture(
              connector: widget.connector,
              outputSize: _sizeOf(surface),
            )),
          ),
        );
    }
  }

  void _onHover(Offset local) {
    final found =
        _mapping.windowAt(widget.scene.windowsOn(widget.connector), local);
    // Compared by identity of the container id, so a pointer moving inside one
    // window does not rebuild the surface on every motion event.
    if (found?.id == _hovered?.id) return;
    setState(() => _hovered = found);
  }

  void _finishArea() {
    final surface = _surface;
    final start = _dragStart;
    final end = _dragEnd;
    setState(() {
      _dragStart = null;
      _dragEnd = null;
    });
    if (start == null || end == null) return;
    final rect =
        Rect.fromPoints(start, end).intersect(Offset.zero & surface);
    final crop = CaptureRect(
      rect.left.round(),
      rect.top.round(),
      rect.width.round(),
      rect.height.round(),
    );
    if (crop.width < kMinSelectionSize || crop.height < kMinSelectionSize) {
      return; // a mis-click, not a selection — see [kMinSelectionSize]
    }
    _answer(AreaCapture(
      connector: widget.connector,
      outputSize: _sizeOf(surface),
      crop: crop,
    ));
  }

  void _finishWindow() {
    final window = _hovered;
    if (window == null) return;
    final surface = _surface;
    if (surface.isEmpty) return;
    final local =
        _mapping.toLocal(window.rect).intersect(Offset.zero & surface);
    _answer(WindowCapture(
      connector: widget.connector,
      outputSize: _sizeOf(surface),
      crop: CaptureRect(
        local.left.round(),
        local.top.round(),
        local.width.round(),
        local.height.round(),
      ),
      title: window.title,
      appId: window.appId,
    ));
  }

  CaptureSize _sizeOf(Size surface) =>
      CaptureSize(surface.width.round(), surface.height.round());

  /// The label riding on the current highlight: the pixel size of an area, the
  /// title of a window, the connector of a screen.
  Widget _readout(
      ThemeConfig theme, Color accent, Rect highlight, Size surface) {
    final text = switch (widget.request.mode) {
      SelectionMode.area =>
        '${highlight.width.round()} x ${highlight.height.round()}',
      SelectionMode.window => _hovered?.title.isNotEmpty == true
          ? _hovered!.title
          : (_hovered?.appId ?? ''),
      SelectionMode.output => widget.connector,
    };
    if (text.isEmpty) return const SizedBox.shrink();

    // Above the rectangle where there is room, inside its top edge where there
    // is not — a label clipped off the top of the screen is a label that only
    // ever shows for selections made near the bottom.
    const gap = 8.0;
    const labelHeight = 26.0;
    final above = highlight.top - labelHeight - gap;
    final top = above >= 0 ? above : highlight.top + gap;
    return Positioned(
      left: highlight.left
          .clamp(0.0, (surface.width - 40).clamp(0.0, double.infinity)),
      top: top.clamp(
          0.0, (surface.height - labelHeight).clamp(0.0, double.infinity)),
      child: ConstrainedBox(
        // A window title is arbitrary text and the readout rides on the
        // selection, so it is kept to a share of the surface rather than
        // allowed to run off the far edge of it.
        constraints: BoxConstraints(maxWidth: surface.width * 0.6),
        child: _Pill(
          theme: theme,
          accent: accent,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ShellFontSizes.secondary,
              fontWeight: FontWeight.w600,
              color: theme.popupForeground,
            ),
          ),
        ),
      ),
    );
  }

  Widget _banner(ThemeConfig theme, Color accent, Size surface) {
    final mode = widget.request.mode;
    final needsMiracle =
        mode == SelectionMode.window && widget.scene.windowsOn(widget.connector).isEmpty;
    final text = needsMiracle
        ? 'No windows to select on ${widget.connector}'
        : '${widget.request.kind.label}: ${mode.instruction}';
    return Positioned(
      top: 24,
      left: 0,
      right: 0,
      // Never a pointer target: it sits over the middle of the output, which
      // is exactly where an area drag starts and where a window is clicked.
      child: IgnorePointer(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _Pill(
              theme: theme,
              accent: accent,
              large: true,
              icon: widget.request.kind == CaptureKind.video
                  ? FontAwesomeIcons.video
                  : FontAwesomeIcons.camera,
              // Two lines rather than one long one: the way out of a surface
              // that has taken the whole screen has to be legible, and putting
              // it after the instruction on one line is what made the banner
              // wider than a rotated display.
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      fontFamily: theme.fontFamily,
                      fontSize: ShellFontSizes.body,
                      fontWeight: FontWeight.w600,
                      color: theme.popupForeground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Esc or right-click to cancel',
                    style: TextStyle(
                      fontFamily: theme.fontFamily,
                      fontSize: ShellFontSizes.caption,
                      color: theme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The mapping between miracle's one global logical space and this surface's
/// output-local one.
///
/// [ScreenOutput] null — miracle not connected, or an output it does not know
/// — gives the identity mapping over an empty window list, which is what makes
/// area and screen selection work with the IPC socket down.
class _OutputMapping {
  const _OutputMapping({
    required this.originX,
    required this.originY,
    required this.scaleX,
    required this.scaleY,
  });

  static const _OutputMapping identity =
      _OutputMapping(originX: 0, originY: 0, scaleX: 1, scaleY: 1);

  factory _OutputMapping.of(ScreenOutput? output, Size surface) {
    if (output == null || output.rect.isEmpty || surface.isEmpty) {
      return identity;
    }
    return _OutputMapping(
      originX: output.rect.x.toDouble(),
      originY: output.rect.y.toDouble(),
      scaleX: surface.width / output.rect.width,
      scaleY: surface.height / output.rect.height,
    );
  }

  final double originX;
  final double originY;
  final double scaleX;
  final double scaleY;

  /// A global logical rectangle in this surface's coordinates.
  Rect toLocal(CaptureRect rect) => Rect.fromLTWH(
        (rect.x - originX) * scaleX,
        (rect.y - originY) * scaleY,
        rect.width * scaleX,
        rect.height * scaleY,
      );

  /// The frontmost of [windows] under the surface point [local].
  SelectableWindow? windowAt(List<SelectableWindow> windows, Offset local) {
    if (scaleX == 0 || scaleY == 0) return null;
    final globalX = (local.dx / scaleX + originX).round();
    final globalY = (local.dy / scaleY + originY).round();
    for (var i = windows.length - 1; i >= 0; i--) {
      if (windows[i].rect.contains(globalX, globalY)) return windows[i];
    }
    return null;
  }
}

/// The dim over everything but the selection, and the rim around it.
///
/// Four rectangles rather than a `saveLayer` with `BlendMode.clear`: this
/// repaints on every pointer move of a drag, and a full-output offscreen layer
/// per motion event is the one thing a surface covering the whole screen must
/// not do.
class _SelectionPainter extends CustomPainter {
  const _SelectionPainter({
    required this.highlight,
    required this.dim,
    required this.rim,
  });

  final Rect? highlight;
  final Color dim;
  final Color rim;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = dim;
    final area = highlight;
    if (area == null || area.isEmpty) {
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, area.top), paint);
    canvas.drawRect(Rect.fromLTRB(0, area.bottom, size.width, size.height), paint);
    canvas.drawRect(Rect.fromLTRB(0, area.top, area.left, area.bottom), paint);
    canvas.drawRect(
        Rect.fromLTRB(area.right, area.top, size.width, area.bottom), paint);
    canvas.drawRect(
      area.deflate(0.75),
      Paint()
        ..color = rim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SelectionPainter old) =>
      old.highlight != highlight || old.dim != dim || old.rim != rim;
}

/// The banner and the readout are the same chip at two sizes.
///
/// Its content is [Flexible] and wraps, which is not decoration: the banner's
/// line is a sentence and a surface is as wide as whatever display it is on —
/// a rotated panel is 1080 logical pixels across and a small laptop less than
/// that. Left rigid it overflows, which on this surface means the instruction
/// for the tool the user is holding is the thing that is clipped.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.theme,
    required this.accent,
    required this.child,
    this.icon,
    this.large = false,
  });

  final ThemeConfig theme;
  final Color accent;
  final Widget child;
  final FaIconData? icon;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 16 : 8,
        vertical: large ? 10 : 4,
      ),
      decoration: BoxDecoration(
        color: theme.popupBackground,
        borderRadius:
            BorderRadius.circular(large ? ShellRadii.card : ShellRadii.control),
        border: Border.all(color: accent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            FaIcon(icon!, size: ShellFontSizes.label, color: accent),
            const SizedBox(width: 10),
          ],
          Flexible(child: child),
        ],
      ),
    );
  }
}
