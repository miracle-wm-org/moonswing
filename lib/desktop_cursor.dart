import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Holds the pointer at the plain arrow over everything in [child].
///
/// A desktop's panels do not answer the pointer the way a web page does: a
/// button in a bar, a row in a tray menu or a link in a notification is clicked
/// under the same arrow the rest of the screen uses. Flutter's widgets disagree
/// — `TextSpan`s with a recognizer, `EditableText`, `SelectableRegion` and every
/// `MouseRegion(cursor:)` ask for a cursor of their own — so asking each call
/// site to pass `basic` would leave the next one free to forget.
///
/// This answers it once for a whole window instead. The mouse tracker picks the
/// cursor from the hovered annotations **in hit-test path order**, taking the
/// first that does not defer, and the path is built deepest first: a render
/// object enters itself after its children. [RenderDesktopCursor] enters itself
/// *before* them, so it is first in the path and its arrow wins over anything
/// beneath it. Hover callbacks are untouched — every `MouseRegion` below still
/// hears its own enter and exit — only the cursor stops moving.
///
/// Wraps the bars, their popups and the docked panels (the notification panel
/// and the clipboard history). The full-screen overlays keep their I-beams and
/// drag cursors: a text field or a draggable card there is the application-like
/// workspace the overview is, not a panel.
class DesktopCursor extends SingleChildRenderObjectWidget {
  const DesktopCursor({super.key, required Widget super.child});

  @override
  RenderDesktopCursor createRenderObject(BuildContext context) =>
      RenderDesktopCursor();
}

/// The render half of [DesktopCursor]: a [MouseTrackerAnnotation] that hit
/// tests itself ahead of its child.
class RenderDesktopCursor extends RenderProxyBox
    implements MouseTrackerAnnotation {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    // Ahead of the children, which is the whole trick — see [DesktopCursor].
    // Entered whether or not a child is hit, since the arrow is what an empty
    // stretch of the surface shows anyway; the return value is still the
    // child's, so nothing about which widget *takes* the click changes.
    result.add(BoxHitTestEntry(this, position));
    return hitTestChildren(result, position: position);
  }

  @override
  MouseCursor get cursor => SystemMouseCursors.basic;

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit => null;

  bool _validForMouseTracker = false;

  @override
  bool get validForMouseTracker => _validForMouseTracker;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _validForMouseTracker = true;
  }

  @override
  void detach() {
    // Before super.detach(), as RenderMouseRegion does: the tracker may be
    // asked about this annotation during the detach it is caught in.
    _validForMouseTracker = false;
    super.detach();
  }
}
