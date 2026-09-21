// Windowing infrastructure built on Flutter's regular (experimental) windowing
// API. Two things live here:
//   * [PopupHost] — compositor-positioned popups (xdg_popup), placed from the
//     parent-local [anchorRect] and [WindowPositioner].
//   * [LayerShellHost] — full layer-shell windows (panels/overlays/dialogs)
//     whose [LayershellWindowController] the module creates itself.
// Both register a [WindowEntry] into the [WindowRegistry] the root's
// [WindowManager] publishes, so every window in the shell is rendered by one
// mechanism in one place.

// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderView;
// BaseWindowController is the one piece of the SDK's windowing layer that
// layer_shell does not re-export; both host mixins' controllers implement it.
import 'package:flutter/src/widgets/_window.dart' show BaseWindowController;
// Only _window_linux.dart is imported directly: layer_shell re-exports the
// windowing and positioner pieces this file needs, but not the Linux-specific
// BaseWindowControllerLinux.
import 'package:flutter/src/widgets/_window_linux.dart';
import 'package:graceful_shell/native/ffi_util.dart' show gdkDisplayGetDefault;
import 'package:graceful_shell/panel_rim.dart';
import 'package:graceful_shell/popup_coordinator.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/popup_transition.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/popup_effect.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:layer_shell/layer_shell.dart';
import 'package:layer_shell/src/gtk.dart';

/// Minimum size floor applied to every popup/tooltip so a sized-to-content
/// window never collapses to a degenerate size.
const BoxConstraints kMinPopupConstraints =
    BoxConstraints(minWidth: 48, minHeight: 24);

/// Every popup is anchored to a widget in a bar that may sit near a screen edge,
/// so let the compositor translate the window along both axes to keep it
/// on-screen. Slide (rather than flip) preserves the popup's side of the bar,
/// which is what [popupAnchorsForBar]'s anchor pair encodes.
const WindowPositionerConstraintAdjustment kPopupSlide =
    WindowPositionerConstraintAdjustment(slideX: true, slideY: true);

/// Adjustment for a flyout submenu anchored to the side of its parent: flip to
/// the opposite side when the preferred one would run off-screen, and slide
/// vertically. Used for the app-directory category submenus.
const WindowPositionerConstraintAdjustment kPopupFlipX =
    WindowPositionerConstraintAdjustment(flipX: true, slideY: true);

/// Shared delegate that forwards [onWindowDestroyed] to a callback.
class PopupDelegate extends PopupWindowControllerDelegate {
  PopupDelegate({required this.onDestroyed});
  final VoidCallback onDestroyed;

  @override
  void onWindowDestroyed() {
    super.onWindowDestroyed();
    onDestroyed();
  }
}

/// Maps a panel's anchor edge to the (parentAnchor, childAnchor) pair that makes
/// a popup appear flush against the inner edge of the bar.
///
/// The popup's [anchorRect] is the triggering widget's rect in the parent
/// window's space, so only the anchor pair varies per edge.
(WindowPositionerAnchor, WindowPositionerAnchor) popupAnchorsForBar(
    String anchor) {
  switch (anchor) {
    case 'bottom':
      return (WindowPositionerAnchor.top, WindowPositionerAnchor.bottom);
    case 'left':
      return (WindowPositionerAnchor.right, WindowPositionerAnchor.left);
    case 'right':
      return (WindowPositionerAnchor.left, WindowPositionerAnchor.right);
    default: // 'top'
      return (WindowPositionerAnchor.bottom, WindowPositionerAnchor.top);
  }
}

/// The positioner offset that puts a shadowed popup's *card* where an
/// unshadowed one's window would have gone.
///
/// A popup surface is grown by [popupShadowInsets] so the shadow has room to
/// paint, which leaves the card sitting `insets` inside its own window. The
/// compositor aligns the *window's* [childAnchor] to the anchor rect, so without
/// this every menu would walk away from its button by the shadow's extent.
///
/// The halved cases are not a rounding convenience: [popupAnchorsForBar] returns
/// edge-*centred* anchors, so an asymmetric shadow would otherwise shift every
/// bar popup sideways by half the asymmetry.
Offset popupShadowAnchorOffset(
  WindowPositionerAnchor childAnchor,
  EdgeInsets insets,
) {
  final double dx;
  switch (childAnchor) {
    case WindowPositionerAnchor.left:
    case WindowPositionerAnchor.topLeft:
    case WindowPositionerAnchor.bottomLeft:
      dx = -insets.left;
    case WindowPositionerAnchor.right:
    case WindowPositionerAnchor.topRight:
    case WindowPositionerAnchor.bottomRight:
      dx = insets.right;
    case WindowPositionerAnchor.center:
    case WindowPositionerAnchor.top:
    case WindowPositionerAnchor.bottom:
      dx = (insets.right - insets.left) / 2;
  }
  final double dy;
  switch (childAnchor) {
    case WindowPositionerAnchor.top:
    case WindowPositionerAnchor.topLeft:
    case WindowPositionerAnchor.topRight:
      dy = -insets.top;
    case WindowPositionerAnchor.bottom:
    case WindowPositionerAnchor.bottomLeft:
    case WindowPositionerAnchor.bottomRight:
      dy = insets.bottom;
    case WindowPositionerAnchor.center:
    case WindowPositionerAnchor.left:
    case WindowPositionerAnchor.right:
      dy = (insets.bottom - insets.top) / 2;
  }
  return Offset(dx, dy);
}

/// The constraints a shadowed popup's *window* is given, grown from the card's.
///
/// [PopupWindowController]'s `constraints` are not layout constraints. The Linux
/// backend registers a sized-to-content view with an unbounded metrics range —
/// so they never reach Flutter's layout — and turns them into the GTK window's
/// `GDK_HINT_MIN_SIZE`/`GDK_HINT_MAX_SIZE` instead. They cap the *surface*, and
/// with a shadow the surface is the card plus [popupShadowInsets].
///
/// This is the third piece of the shadow arithmetic and the one that was
/// missing: without it GTK clamped the `gtkWindow.resize` back to the card's own
/// maximum, so every popup pinning a width with `minWidth == maxWidth` mapped a
/// window exactly as wide as its card and drew that card `insets.left` inside it
/// — off its button by half the shadow's reach and clipped on the far side. The
/// loose-constrained menus were never clamped, which is what made it look like
/// only some popups had drifted.
///
/// An infinite maximum stays infinite, and a shadowless theme's zero insets hand
/// the card's constraints straight back.
BoxConstraints popupWindowConstraints(BoxConstraints card, EdgeInsets shadow) {
  if (shadow == EdgeInsets.zero) return card;
  return BoxConstraints(
    minWidth: card.minWidth + shadow.horizontal,
    maxWidth: card.maxWidth.isFinite
        ? card.maxWidth + shadow.horizontal
        : card.maxWidth,
    minHeight: card.minHeight + shadow.vertical,
    maxHeight: card.maxHeight.isFinite
        ? card.maxHeight + shadow.vertical
        : card.maxHeight,
  );
}

/// Computes the parent-window-local anchor rect for the widget behind [context].
Rect popupAnchorRect(BuildContext context) {
  final box = context.findRenderObject() as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// [widget]'s rect grown across the panel, so a bar popup is anchored to the
/// panel's *inner edge* while staying centred on the module that opened it.
///
/// [popupAnchorsForBar] returns edge-centred anchors, so what the compositor
/// reads off this rect is a single point. Handing it the widget's own rect put
/// that point wherever the module's padding happened to end, so every popup
/// opened a couple of pixels *inside* the bar, by an amount differing per
/// module. Spanning the panel's whole cross-axis extent makes the anchor the
/// bar's own edge for every module alike, and leaves the other axis alone, which
/// keeps the popup centred on its icon.
///
/// [panel] is the panel surface's size, the space [popupAnchorRect] reports in.
/// A degenerate one falls back to [widget] rather than emitting a zero-extent
/// rect, which `xdg_positioner` rejects as a protocol error.
///
/// **The anchor edge is the panel's, flush, and the popup lands below it.** A
/// bar popup is never placed *over* its panel: the compositor puts the card on
/// the far side of the anchor edge, which is what makes an attached card read as
/// growing out of the bar. Nothing the card paints can therefore reach the bar's
/// own inner rim, and two attempts to make it — a *collar* on the card's shape
/// asking for a negative [WindowPositioner.offset], and an inset on this rect —
/// are why that is worth stating here. The bar's rim is the bar's to leave off;
/// see `PanelRimBreaks` (`panel_rim.dart`).
Rect barAnchorRect(Rect widget, Size panel, String anchor) {
  if (panel.isEmpty) return widget;
  switch (anchor) {
    case 'left':
    case 'right':
      return Rect.fromLTRB(0, widget.top, panel.width, widget.bottom);
    default: // 'top', 'bottom'
      return Rect.fromLTRB(widget.left, 0, widget.right, panel.height);
  }
}

/// [barAnchorRect] for the widget behind [context], in a panel anchored to
/// [anchor].
///
/// The panel surface's size comes from the [MediaQuery] its `View` installs,
/// which is the very space [RenderBox.localToGlobal] maps into.
/// [setPanelMargin]'s margin is native and outside the surface, so there is
/// nothing to correct for.
Rect barAnchorRectFor(BuildContext context, String anchor) {
  final box = context.findRenderObject() as RenderBox;
  return barAnchorRect(
    box.localToGlobal(Offset.zero) & box.size,
    MediaQuery.sizeOf(context),
    anchor,
  );
}

/// The positioner offset that floats a bar popup [gap] px off the panel edge it
/// is anchored to.
///
/// Keyed on the *bar's* anchor, the string [popupAnchorsForBar] takes: the popup
/// sits on the far side of that edge, so this always pushes it away from the
/// panel. Added to [popupShadowAnchorOffset] rather than folded into it — that
/// one cancels the margin the shadow added, this is the distance the theme asked
/// for.
Offset popupGapOffset(String anchor, double gap) {
  switch (anchor) {
    case 'bottom':
      return Offset(0, -gap);
    case 'left':
      return Offset(gap, 0);
    case 'right':
      return Offset(-gap, 0);
    default: // 'top'
      return Offset(0, gap);
  }
}

/// Tells the compositor not to shrink [controller]'s surface to make room for
/// other layer-shell surfaces' exclusive zones.
///
/// gtk-layer-shell defaults the zone to 0, which per wlr-layer-shell means "move
/// me so I don't occlude surfaces that reserved space" — so a full-screen
/// surface is shrunk to the gap *between* the panels. -1 means "extend me to the
/// edges I'm anchored to".
///
/// This is what makes a translucent panel show the wallpaper: without it a
/// see-through bar reveals a flat black strip. It went unnoticed while every
/// panel was opaque.
void spanFullOutput(LayershellWindowController controller) {
  controller.setExclusiveZone(-1);
}

/// Floats a panel [margin] px off each screen edge it is anchored to.
///
/// A native layer-shell margin rather than a Flutter inset because the shell has
/// no input-region support: padding inside a full-size surface would leave the
/// surface swallowing every click in the gap, where a real margin shrinks it.
///
/// The exclusive zone is deliberately untouched. Per wlr-layer-shell's
/// `set_margin`, "the exclusive zone includes the margin", so the compositor
/// already adds it; reserving `height + margin` would reserve it twice and leave
/// a dead strip no window would occupy.
void setPanelMargin(
  LayershellWindowController controller, {
  required String anchor,
  required int margin,
}) {
  for (final edge in anchorEdgesForPosition(anchor)) {
    controller.setMargin(edge, margin);
  }
  // Once the surface is mapped a margin change only queues a resize, so a live
  // theme edit would otherwise sit unsent until something else forced a frame.
  controller.tryForceCommit();
}

/// Lends [parent] keyboard focus for as long as a popup that types needs it,
/// answering the surface that was flipped — and null when none was.
///
/// A bar popup is an `xdg_popup` child of the panel's layer surface, and per
/// `set_keyboard_interactivity` the setting "is inherited by child surfaces set
/// by the get_popup request" — so a panel at [LayerShellKeyboardMode.none], which
/// every panel now is, hands that down and an `EditableText` in one of its
/// popups never sees a key event.
///
/// The panel is not simply left `onDemand`, because a bar that can take focus
/// takes it on every click anywhere on it. Borrowing only while a popup with a
/// field is open costs that popup's opening click and nothing else.
///
/// Answers null — changing nothing — when the parent is already `onDemand` or is
/// not a layer surface at all. Only a borrow that actually flipped the surface is
/// given back, so `none` is never sent to a surface that wanted `onDemand`.
LayershellWindowController? _borrowPopupKeyboard(BaseWindowController? parent) {
  if (parent is! LayershellWindowController) return null;
  if (parent.isDestroyed) return null;
  if (parent.keyboardMode != LayerShellKeyboardMode.none) return null;
  parent.setKeyboardMode(LayerShellKeyboardMode.onDemand);
  // A keyboard-mode change on a mapped surface only queues a resize, so without
  // this it would sit unsent until something else forced a frame — and the field
  // would come up unable to type into. [setPanelMargin]'s rule.
  parent.tryForceCommit();
  return parent;
}

/// Gives back what [_borrowPopupKeyboard] took.
///
/// Guarded on [LayershellWindowController.isDestroyed] rather than assumed live:
/// a monitor unplugged while its app directory is open destroys the panel before
/// the module closes its popup, and every getter on a destroyed controller
/// throws.
void _returnPopupKeyboard(LayershellWindowController? parent) {
  if (parent == null || parent.isDestroyed) return;
  parent.setKeyboardMode(LayerShellKeyboardMode.none);
  parent.tryForceCommit();
}

/// Carries the [TransientHandle] of the popup a subtree is rendered inside.
///
/// This is what makes nesting work without a call site passing a parent.
/// [PopupHost.openPopup] wraps every popup's content in one, so a module opening
/// a popup from *inside* another popup's content resolves its parent from
/// `context` — the walk that already finds [WindowScope] and [WindowRegistry].
class TransientScope extends InheritedWidget {
  const TransientScope({
    super.key,
    required this.handle,
    required super.child,
  });

  final TransientHandle handle;

  /// The enclosing popup's handle, or null in a panel or the desktop surface.
  ///
  /// Deliberately not a `dependOnInheritedWidgetOfExactType`: this is read from
  /// tap handlers rather than `build`, so there is nothing to rebuild.
  static TransientHandle? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<TransientScope>()
      ?.handle;

  @override
  bool updateShouldNotify(TransientScope oldWidget) => false;
}

/// Dismisses every open transient surface when a pointer goes down on [child].
///
/// Wrapped around the two surfaces that cover real screen area and are not
/// themselves transient — a panel and the desktop surface — because nothing else
/// can tell us the user clicked elsewhere: the Linux popup controller takes no
/// `gdk_seat_grab`, so the compositor never sends `popup_done`, and a panel's
/// own focus never changes — it is [LayerShellKeyboardMode.none], so GTK's
/// `is-active` (which the controller *does* notify on) is permanently false
/// and never transitions.
///
/// Translucent, so a click on a panel's empty space dismisses too. It still
/// cannot catch a click on an ordinary application window — nothing available
/// to the shell can — but the *focus change* that click causes is reported by
/// miracle, and `lib/popup_focus_dismiss.dart` dismisses on that. So the click
/// is invisible and its consequence is not, which leaves this the only thing
/// that notices a click on a shell surface and the only one that can arm the
/// reopen guard.
class PopupDismissArea extends StatelessWidget {
  const PopupDismissArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) =>
          PopupCoordinator.instance.dismissFromPointerDown(event),
      child: child,
    );
  }
}

/// Whether [State.setState] may still be called from here.
///
/// [State.mounted] is not that test on its own. Every module that owns a popup
/// closes it from its own `dispose()`, and `State.mounted` stays true for the
/// whole of `dispose()` — the framework clears `state._element` only after it
/// returns — while the *element* was made defunct before the call. A `setState`
/// from there is a `markNeedsBuild` on a dead element, which asserts in debug and
/// queues an unbuildable build in release. [BuildContext.mounted] is the
/// element's own liveness, so the pair answers "still in the tree" for both the
/// ordinary close and the teardown one.
extension on State {
  bool get _canRebuild => mounted && context.mounted;
}

/// Unmaps a native window without destroying it, so a close still *looks*
/// instant while [WindowTeardown] waits out the frames the destroy needs.
///
/// gtk-layer-shell's [GtkWidget] wrapper binds realize/show/destroy but not
/// hide; this belongs upstream in `layer_shell` on the next pin bump.
@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'gtk_widget_hide')
external void _gtkWidgetHide(ffi.Pointer<ffi.NativeType> widget);

// ---------------------------------------------------------------------------
// Spike: the popup grab (`GRACEFUL_SHELL_POPUP_GRAB`)
// ---------------------------------------------------------------------------
//
// Off unless the environment asks for it. Everything below is an experiment
// with one question to answer, and the answer is on the wire, not in the UI:
// **does an `xdg_popup` grab reach Mir, and does Mir send `popup_done` when the
// user clicks an unrelated window?** If it does, this is a better mechanism for
// bar popups than `lib/popup_focus_dismiss.dart`'s IPC route, because the
// compositor is telling the shell rather than the shell inferring it — and it
// would work on a compositor that is not miracle.
//
// Why the grab is missing in the first place: `PopupWindowControllerLinux`
// creates a `GTK_WINDOW_POPUP`, realizes it, sets it transient for the parent
// and places it with `gdk_window_move_to_rect` — and never calls
// `gdk_seat_grab`. GDK3 emits `xdg_popup.grab` in exactly one place, when it
// creates the popup, gated on finding a grab seat on the popup or its
// transient-for chain; with no seat grab there is no request, so no
// `popup_done` and no compositor-driven dismissal. That is a gap in Flutter's
// Linux windowing API rather than anything this shell did.
//
// What is *not* expected to change, and why this does not replace anything:
//
// * Mir deliberately withholds keyboard focus from a grabbing popup — the
//   `AbstractShell` HACK citing mir#2324 says Weston and others disobey
//   xdg-shell here because focusing menus breaks Qt submenus. So
//   [_borrowPopupKeyboard] stays exactly as necessary as it is today, and
//   equally, opening a bar popup will *not* steal focus from whatever the user
//   is typing in. The protocol's "the top most grabbing popup will always have
//   keyboard focus" does not describe this compositor.
// * `LayerShellHost`'s windows are layer surfaces with no popup role at all, so
//   the overlays can never receive `popup_done`. The IPC dismisser stays
//   regardless of how this turns out.
//
// The known failure mode to look for *first* is not a popup that fails to
// close, but one that never opens: Mir's `add_grabbing_popup` closes and hides
// a grabbing popup immediately when its toplevel is not the compositor's
// current popup-parent, which miracle sets from pointer handling. A popup
// opened from a keyboard shortcut, or while an application window is focused,
// may therefore appear and vanish in the same frame.
//
// Formally this is out of spec: `xdg_popup.grab` requires an `xdg_toplevel` or
// another grabbing popup as the parent, and a layer surface is neither — so
// whatever happens here is compositor-defined, which is why it is a spike and
// not a patch.

/// How the popup grab spike is configured, or null when it is off.
///
/// `GRACEFUL_SHELL_POPUP_GRAB=1` grabs pointer *and* keyboard, which is what a
/// GTK menu grab is and the likeliest to make GDK take the popup-grab path.
/// `=pointer` grabs the pointing devices only — worth a second run, because if
/// that still puts `grab` on the wire it is the narrower thing to ask for.
/// Anything else, or unset, leaves the spike off entirely.
final _PopupGrabMode? _kPopupGrabMode = () {
  final value = Platform.environment['GRACEFUL_SHELL_POPUP_GRAB'];
  return switch (value) {
    '1' || 'all' => _PopupGrabMode.all,
    'pointer' => _PopupGrabMode.pointer,
    _ => null,
  };
}();

enum _PopupGrabMode {
  /// `GDK_SEAT_CAPABILITY_ALL`.
  all(0xF),

  /// `GDK_SEAT_CAPABILITY_ALL_POINTING` — pointer, touch and tablet stylus.
  pointer(0x7);

  const _PopupGrabMode(this.capabilities);

  /// The `GdkSeatCapabilities` bitmask this mode asks for.
  final int capabilities;
}

// GdkWindow* gtk_widget_get_window(GtkWidget*) — the popup's GdkWindow, valid
// only once the widget is realized (which the SDK's constructor does before it
// returns). layer_shell's GtkWidget wrapper binds no GdkWindow accessor at all.
@ffi.Native<ffi.Pointer<ffi.NativeType> Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'gtk_widget_get_window')
external ffi.Pointer<ffi.NativeType> _gtkWidgetGetWindow(
    ffi.Pointer<ffi.NativeType> widget);

// GdkSeat* gdk_display_get_default_seat(GdkDisplay*)
@ffi.Native<ffi.Pointer<ffi.NativeType> Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'gdk_display_get_default_seat')
external ffi.Pointer<ffi.NativeType> _gdkDisplayGetDefaultSeat(
    ffi.Pointer<ffi.NativeType> display);

// GdkGrabStatus gdk_seat_grab(GdkSeat*, GdkWindow*, GdkSeatCapabilities,
//     gboolean owner_events, GdkCursor*, const GdkEvent*,
//     GdkSeatGrabPrepareFunc, gpointer)
@ffi.Native<
    ffi.Int Function(
      ffi.Pointer<ffi.NativeType>,
      ffi.Pointer<ffi.NativeType>,
      ffi.Uint32,
      ffi.Int32,
      ffi.Pointer<ffi.NativeType>,
      ffi.Pointer<ffi.NativeType>,
      ffi.Pointer<ffi.NativeType>,
      ffi.Pointer<ffi.NativeType>,
    )>(symbol: 'gdk_seat_grab')
external int _gdkSeatGrab(
  ffi.Pointer<ffi.NativeType> seat,
  ffi.Pointer<ffi.NativeType> window,
  int capabilities,
  int ownerEvents,
  ffi.Pointer<ffi.NativeType> cursor,
  ffi.Pointer<ffi.NativeType> event,
  ffi.Pointer<ffi.NativeType> prepareFunc,
  ffi.Pointer<ffi.NativeType> prepareFuncData,
);

// void gdk_seat_ungrab(GdkSeat*)
@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'gdk_seat_ungrab')
external void _gdkSeatUngrab(ffi.Pointer<ffi.NativeType> seat);

/// `GDK_GRAB_ALREADY_GRABBED` — see [_takePopupGrab] for why it is special.
const int _kGrabAlreadyGrabbed = 1;

/// `GdkGrabStatus`, for the log line — a non-success status is the first thing
/// worth knowing when no `grab` appears on the wire.
const List<String> _kGrabStatusNames = <String>[
  'success',
  'already-grabbed',
  'invalid-time',
  'not-viewable',
  'frozen',
  'failed',
];

/// Takes a seat grab on a popup that has been realized but **not yet mapped**,
/// and answers the seat so [_releasePopupGrab] can give it back.
///
/// The timing is the whole of this. GDK reads the grab seat when it creates the
/// `xdg_popup`, which happens when the window is shown — and the SDK shows it
/// from the engine's first-frame callback, after the constructor has returned.
/// So the only moment that works is between construction and that first frame,
/// which is where [PopupHost.openPopup] already reaches into the native window
/// to make it transparent. Grabbing after the map would be too late for GDK and
/// an `invalid_grab` protocol error if it were not.
///
/// Answers null on anything unexpected — a missing symbol, no display, a
/// refused grab — because a spike that cannot arm itself must still leave a
/// working popup behind.
ffi.Pointer<ffi.NativeType>? _takePopupGrab(
  ffi.Pointer<ffi.Void> windowHandle,
  _PopupGrabMode mode,
) {
  try {
    final gdkWindow = _gtkWidgetGetWindow(windowHandle.cast());
    if (gdkWindow == ffi.nullptr) {
      debugPrint('popup grab: the popup has no GdkWindow yet; not grabbing');
      return null;
    }
    final display = gdkDisplayGetDefault();
    if (display == ffi.nullptr) return null;
    final seat = _gdkDisplayGetDefaultSeat(display.cast());
    if (seat == ffi.nullptr) return null;
    final status = _gdkSeatGrab(
      seat,
      gdkWindow,
      mode.capabilities,
      // owner_events: the popup's own widgets keep getting their events, which
      // is the "owner-events" grab xdg-shell describes.
      1,
      ffi.nullptr,
      ffi.nullptr,
      ffi.nullptr,
      ffi.nullptr,
    );
    final name = status >= 0 && status < _kGrabStatusNames.length
        ? _kGrabStatusNames[status]
        : '$status';
    debugPrint('popup grab: gdk_seat_grab(${mode.name}) -> $name');
    // Answered even on most non-success statuses, deliberately: GDK records the
    // grab seat on the window separately from what it returns here, so a
    // refusal does not prove `xdg_popup.grab` will not go out — the wire trace
    // is the authority on that — and holding the seat is what makes us hand it
    // back rather than leak it.
    //
    // `already-grabbed` is the exception, because there the grab belongs to
    // somebody else and ungrabbing would take *theirs* down. Nothing in the
    // shell holds a GTK grab today, so this should never be seen; if it is, it
    // is a finding rather than something to work around.
    if (status == _kGrabAlreadyGrabbed) return null;
    return seat;
  } catch (error) {
    debugPrint('popup grab: could not grab the seat: $error');
    return null;
  }
}

/// Gives back what [_takePopupGrab] took.
void _releasePopupGrab(ffi.Pointer<ffi.NativeType>? seat) {
  if (seat == null) return;
  try {
    _gdkSeatUngrab(seat);
  } catch (error) {
    debugPrint('popup grab: could not ungrab the seat: $error');
  }
}

/// Destroys a native window only once Flutter has let go of its view, and one
/// frame after that.
///
/// `gtk_widget_destroy` on a window whose Flutter view is still live aborts the
/// process. The GTK destroy cascade disposes the embedder's per-view renderer,
/// whose `frame_mutex` the *raster* thread holds while it composites, and
/// `g_mutex_clear` on a held mutex is a glib `abort()`. The same abort answers a
/// *second* destroy, because `gtk_widget_destroy` goes through
/// `g_object_run_dispose`, which re-runs dispose on an already-disposed widget.
///
/// Upstream defends against neither: `PopupWindowControllerLinux.destroy` calls
/// `gtk_widget_destroy` *before* it unregisters the view. A single
/// `addPostFrameCallback` hop is not enough either — it assumes the rebuild that
/// drops the view happened in the frame it landed after. Under the dock, whose
/// tooltips open and close a surface per hover, that assumption fails.
///
/// The probe and callbacks are injected so the loop is a plain widget test
/// (`test/popup_teardown_test.dart`).
class WindowTeardown {
  WindowTeardown({
    required this.viewAttached,
    required this.destroy,
    this.hide,
    this.maxFrames = 8,
  });

  /// Whether Flutter is still rendering into the window's view.
  final bool Function() viewAttached;

  /// Tears the native window down. Called exactly once.
  final VoidCallback destroy;

  /// Unmaps the surface immediately, if it can be. Called at most once, before
  /// any frame is waited on.
  final VoidCallback? hide;

  /// Frames to wait before destroying anyway.
  ///
  /// A window nobody ever detaches would otherwise leak on every close, which is
  /// worse than the residual race — and a view can legitimately outlive its
  /// owner's expectations.
  final int maxFrames;

  bool _started = false;
  bool _done = false;
  bool _detached = false;
  int _frames = 0;

  /// Whether [destroy] has run.
  bool get isDone => _done;

  void start() {
    if (_started) return;
    _started = true;
    hide?.call();
    _scheduleFrame();
  }

  void _scheduleFrame() {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback(_onFrame);
    // addPostFrameCallback does not request a frame of its own, and a shell
    // with nothing animating produces none — the callback would never run.
    binding.scheduleFrame();
  }

  void _onFrame(Duration _) {
    if (_done) return;
    _frames++;
    if (viewAttached()) {
      if (_frames >= maxFrames) {
        debugPrint('WindowTeardown: view still attached after $_frames frames; '
            'destroying anyway');
        _finish();
        return;
      }
      _scheduleFrame();
      return;
    }
    // Detach is observed on the platform thread; the raster thread may still be
    // presenting the last frame that carried this view. One more frame is the
    // only wait Dart can express for that.
    if (_detached) {
      _finish();
      return;
    }
    _detached = true;
    _scheduleFrame();
  }

  void _finish() {
    _done = true;
    destroy();
  }
}

/// Whether the framework still holds a render tree for [view].
///
/// The framework's own view of it: the engine only drops the view when the
/// window is destroyed, which is the thing being waited for, so
/// `platformDispatcher.views` would never answer no.
bool viewIsAttached(FlutterView view) => WidgetsBinding.instance.renderViews
    .any((RenderView rv) => identical(rv.flutterView, view));

/// Starts a [WindowTeardown] for [controller]'s window.
///
/// [hide] unmaps the surface up front so the close is visually immediate; pass
/// false where an unmap would show something that must stay covered (the lock
/// screen, whose surfaces hide the desktop).
void destroyWindowWhenDetached(
  BaseWindowController controller, {
  bool hide = true,
}) {
  if (controller.isDestroyed) return;
  final FlutterView view = controller.rootView;
  WindowTeardown(
    viewAttached: () => viewIsAttached(view),
    hide: hide ? () => _hideWindowOf(controller) : null,
    // destroy() is idempotent in both controller implementations, so a
    // compositor-initiated destroy arriving mid-wait costs nothing.
    destroy: controller.destroy,
  ).start();
}

void _hideWindowOf(BaseWindowController controller) {
  // windowHandle throws once the controller is destroyed, and hiding a freed
  // GtkWidget is the same class of bug this file exists to close.
  if (controller.isDestroyed) return;
  final native = controller as BaseWindowControllerLinux;
  _gtkWidgetHide(native.windowHandle.cast());
}

/// [child] under a [PopupAttachScope], or [child] itself when [edge] is null.
///
/// A floating popup builds exactly the tree it built before attaching existed —
/// no extra element, and no extra inherited lookup for the cards inside it.
Widget _maybeAttached(String? edge, Widget child) =>
    edge == null ? child : PopupAttachScope(edge: edge, child: child);

/// How long past its own animation a popup's exit is given before the window is
/// torn down anyway.
///
/// [PopupTransition] normally answers well inside this. The timer is for the
/// cases where it never will: a window whose view was dropped before the
/// transition built, a host disposed mid-animation, a compositor that took the
/// surface away. A popup leaked on every close is worse than one that disappears
/// a moment early.
const Duration _kPopupExitGrace = Duration(milliseconds: 250);

/// The deadline for an exit lasting [exit].
///
/// Measured off the exit the theme actually plays rather than fixed, or a theme
/// with a long `popup_animation_duration` would have every popup cut off partway
/// out by the very timer that exists for the popups that never animate at all.
Duration _popupExitTimeout(Duration exit) => exit + _kPopupExitGrace;

/// A popup the host has let go of but that is still on screen, playing its exit
/// animation.
///
/// The host drops every reference the instant [PopupHost.closePopup] is called —
/// `isPopupOpen` answers false and a fresh popup may open in the same turn, which
/// `dock.dart`, `app_directory.dart` and `desktop_surface.dart` rely on.
/// Everything still owed to the outgoing window lives here until [finish] pays
/// it: the [WindowEntry], the native window, and the opener's `onClosed`.
///
/// The coordinator handle is **not** among them — it is released synchronously in
/// [PopupHost.closePopup]. A handle left registered through the exit is one
/// `dismissOutside` would find when the next popup opens, and its `onDismiss` is
/// the host's `closePopup`: what that would close is the *new* popup, in the
/// same gesture that asked for it.
class _ClosingPopup {
  _ClosingPopup({
    required this.controller,
    required this.registry,
    required this.entry,
    required this.onClosed,
    required this.closing,
    required this.timeout,
    required this.onFinished,
  });

  final PopupWindowController controller;
  final WindowRegistry? registry;
  final WindowEntry entry;
  final VoidCallback? onClosed;

  /// The flag [PopupTransition] watches. Deliberately never disposed: the
  /// transition removes its listener from `dispose`, which runs a frame *after*
  /// [finish] drops the entry, and a `ValueNotifier` throws when a listener is
  /// removed from a disposed one.
  final ValueNotifier<bool> closing;

  /// How long [beginExit] waits before finishing the close itself. Snapshotted
  /// from the theme at open, with the effect — see [_popupExitTimeout].
  final Duration timeout;

  final void Function(_ClosingPopup) onFinished;

  Timer? _fallback;
  bool _done = false;

  /// Asks the card to animate out; [finish] runs when it reports back, or when
  /// [timeout] runs out, whichever is first.
  void beginExit() {
    _fallback = Timer(timeout, finish);
    closing.value = true;
  }

  void finish() {
    if (_done) return;
    _done = true;
    _fallback?.cancel();
    _fallback = null;
    registry?.unregister(entry);
    // The unregister above only drops the view on the *next* frame's rebuild,
    // and destroying the window before that aborts the process — see
    // [WindowTeardown], which waits for the detach rather than assuming it.
    destroyWindowWhenDetached(controller);
    // The host decides whether [onClosed] is still owed — see
    // [PopupHost._dropOutgoing].
    onFinished(this);
  }
}

/// Mixin for [State] classes that own a single popup window.
///
/// Encapsulates the controller/view lifecycle and WindowRegistry registration so
/// each module only computes its anchor geometry and calls [openPopup] — plus
/// the [PopupTransition] the card is wrapped in and the [_ClosingPopup] that
/// outlives the close.
mixin PopupHost<T extends StatefulWidget> on State<T> {
  PopupWindowController? _popupController;
  WindowRegistry? _registry;
  WindowEntry? _entry;
  VoidCallback? _onClosed;
  TransientHandle? _handle;

  /// The panel surface this host borrowed keyboard focus from, and null when it
  /// borrowed none — which is every popup but the one or two carrying a text
  /// field. Held rather than re-derived at close time because the closing
  /// popup's own `context` is gone by then, and because only the surface this
  /// host actually flipped may be flipped back.
  LayershellWindowController? _keyboardLender;

  /// The seat this host's popup grabbed, and null when it grabbed none — which
  /// is every popup unless `GRACEFUL_SHELL_POPUP_GRAB` is set. Held for
  /// [_keyboardLender]'s reason: only a grab this host actually took may be
  /// given back.
  ffi.Pointer<ffi.NativeType>? _grabbedSeat;

  /// The flag the open popup's [PopupTransition] watches, handed to its
  /// [_ClosingPopup] when the popup is closed.
  ValueNotifier<bool>? _closing;

  /// Whether the open popup's effect has an exit to play. False for
  /// [PopupEffect.none], and forced false when the compositor destroys the
  /// window under us.
  bool _exitAnimates = false;

  /// The deadline the open popup's [_ClosingPopup] will be given, snapshotted
  /// with the effect at open for the same reason: a theme edited while a popup
  /// is open must not shorten the exit of a card already playing one.
  Duration _exitTimeout = _popupExitTimeout(ShellDurations.popupOut);

  /// Popups this host has closed that are still on screen, animating out.
  ///
  /// Normally at most one, but a host that closes and immediately reopens (the
  /// dock's tooltip giving way to its menu) can have the outgoing card still
  /// fading while the new one arrives, and a host disposed mid-animation has to
  /// finish them all.
  final List<_ClosingPopup> _outgoing = <_ClosingPopup>[];

  /// The panel whose rim this host's open popup is breaking, if any.
  ///
  /// Held rather than re-derived, because [closePopup] runs from `dispose` as
  /// well and a defunct element cannot be asked for its view.
  Object? _rimBreakPanel;

  /// Records how much of [view]'s inner rim this popup's mouth covers.
  ///
  /// The card is centred on its module and the window is the card plus its
  /// surface margin, so the mouth starts one leading inset into the window and
  /// runs the card's own extent — widened by the flare, which bows the card
  /// outward exactly where it meets the bar. See [attachedMouthRange] for the
  /// slide the compositor may apply and that this has to predict.
  void _publishRimBreak({
    required Object view,
    required Size panel,
    required Size window,
    required Rect anchor,
    required String edge,
    required EdgeInsets insets,
    required double flare,
  }) {
    final vertical = edge == 'left' || edge == 'right';
    final windowExtent = vertical ? window.height : window.width;
    final leading = vertical ? insets.top : insets.left;
    final trailing = vertical ? insets.bottom : insets.right;
    final cardExtent = windowExtent - leading - trailing;
    if (cardExtent <= 0) return;
    _rimBreakPanel = view;
    PanelRimBreaks.instance.set(
      view,
      attachedMouthRange(
        anchorCentre: vertical ? anchor.center.dy : anchor.center.dx,
        windowExtent: windowExtent,
        leadingInset: leading,
        cardExtent: cardExtent,
        flare: flare < 0 ? 0 : flare,
        panelExtent: vertical ? panel.height : panel.width,
      ),
    );
  }

  /// Whether a popup is currently open.
  ///
  /// A popup animating *out* is not open: the host has let go of it and a new one
  /// may open over it in the same turn. Every close-then-reopen call site depends
  /// on that being true synchronously.
  bool get isPopupOpen => _popupController != null;

  /// Opens a popup anchored to the triggering widget, choosing the anchor pair
  /// from the panel's [BarScope] edge. This is the common case; use [openPopup]
  /// directly only when custom anchor geometry is needed. A no-op if one is
  /// already open — call [closePopup] first.
  ///
  /// [attach] governs the card's *shape* alone. Every bar popup is anchored to
  /// the panel edge, pushed off it by `popup_gap`, and kept from painting its
  /// shadow over the bar; one that declines to attach simply keeps all four
  /// corners and its whole rim. The hover tooltips pass false — a label that
  /// appears under the pointer reads as a floating card, not as furniture.
  ///
  /// [effect] overrides the theme's `popup_animation` for this popup alone. The
  /// dock is the one caller that passes it: its hover labels and unpin menu
  /// belong to a strip the pointer sweeps across, where a card that animates on
  /// every button it passes is the shell twitching rather than responding.
  void openBarPopup(
    BuildContext context, {
    required Widget child,
    required BoxConstraints preferredConstraints,
    TransientPolicy policy = TransientPolicy.menu,
    Object? ownerKey,
    bool attach = true,
    PopupEffect? effect,
    bool needsKeyboard = false,
  }) {
    final barAnchor = BarScope.of(context);
    final (parentAnchor, childAnchor) = popupAnchorsForBar(barAnchor);
    openPopup(
      context,
      child: child,
      preferredConstraints: preferredConstraints,
      anchorRect: barAnchorRectFor(context, barAnchor),
      parentAnchor: parentAnchor,
      childAnchor: childAnchor,
      policy: policy,
      ownerKey: ownerKey,
      barAnchor: barAnchor,
      attach: attach,
      effect: effect,
      needsKeyboard: needsKeyboard,
    );
  }

  void openPopup(
    BuildContext context, {
    required Widget child,
    required BoxConstraints preferredConstraints,
    required Rect anchorRect,
    required WindowPositionerAnchor parentAnchor,
    required WindowPositionerAnchor childAnchor,
    WindowPositionerConstraintAdjustment constraintAdjustment = kPopupSlide,
    VoidCallback? onClosed,
    TransientPolicy policy = TransientPolicy.menu,
    Object? ownerKey,
    String? barAnchor,
    bool attach = true,
    PopupEffect? effect,
    bool needsKeyboard = false,
  }) {
    if (isPopupOpen) return;
    // Identity for the reopen guard, defaulting to the host State because one
    // State owns one popup. A host that opens a *different* popup per trigger —
    // the tray, whose one State serves every icon — passes something finer, or
    // clicking the second icon would be mistaken for re-clicking the first.
    final owner = ownerKey ?? this;
    // The click that opened this is the same one that just dismissed our own
    // popup from [PopupDismissArea], which runs first: a [Listener] sits above
    // every recognizer on the hit-test path. Without this the toggle would close
    // and immediately reopen, and no bar popup could be dismissed by its own icon.
    if (PopupCoordinator.instance.consumeReopenGuard(owner)) return;
    _onClosed = onClosed;
    final parentController = WindowScope.of(context);
    // Before the popup is created, so the surface is already `onDemand` when
    // the compositor reads the parent's interactivity for the new child.
    if (needsKeyboard) {
      _keyboardLender = _borrowPopupKeyboard(parentController);
    }
    final constraints = preferredConstraints.enforce(kMinPopupConstraints);
    // Snapshotted at open, the discipline [constraints] has and for its reason:
    // GTK3 resolves gdk_window_move_to_rect exactly once at map time, so neither
    // the surface's size nor its placement can be revised afterwards. A theme
    // edit while a popup is open therefore restyles the card — PopupCard reads
    // the scope live — without resizing the window it sits in.
    final theme = ThemeScope.of(context);
    // Attached is a shape and the theme's gap is its switch: at any gap at all
    // the card is free-floating, and a join flare would be reaching for a bar
    // that is no longer there.
    final attachEdge =
        barAnchor != null && attach && theme.popupGap <= 0 ? barAnchor : null;
    // Snapshotted with the rest of the theme, for a reason of its own: the
    // entrance and the exit have to be the same effect, and a theme edited while
    // a popup is open would otherwise close it with an animation that is not the
    // reverse of the one it opened with.
    final resolvedEffect = effect ?? theme.popupEffect;
    final resolvedDuration = theme.popupInDuration;
    // The panel this popup is attached to, and its extent, for the break in its
    // rim — snapshotted here for the same reason everything else is, and read
    // from the *module's* context, which is inside the panel's own view.
    final panelView = attachEdge == null ? null : View.maybeOf(context);
    final panelSize = attachEdge == null ? null : MediaQuery.sizeOf(context);
    final closing = _closing = ValueNotifier<bool>(false);
    _exitAnimates = resolvedEffect.animates;
    _exitTimeout = _popupExitTimeout(theme.popupOutDuration);
    // Both terms are margin outside the card that the surface has to carry, or
    // the compositor clips what should have been painted there — the shadow's
    // reach, and an attached card's flare, which bows out past its own box on the
    // two sides that meet the bar.
    final surfaceInsets = popupSurfaceInsets(
      popupShadowInsets(theme, attachEdge: barAnchor),
      popupAttachInsets(theme, attachEdge: attachEdge),
    );
    PopupWindowController? thisController;
    _popupController = thisController = PopupWindowController(
      parent: parentController,
      anchorRect: anchorRect,
      positioner: WindowPositioner(
        parentAnchor: parentAnchor,
        childAnchor: childAnchor,
        // Two terms. The first cancels the margin the shadow adds, so the card
        // lands where an unshadowed popup's window would have; the second is the
        // distance off the panel edge the theme asked for. They compose without
        // interfering, because on the joined edge the inset has already been
        // clamped to the gap: the first contributes `gap - min(reach, gap)`
        // there, so the sum is the gap exactly.
        offset: popupShadowAnchorOffset(childAnchor, surfaceInsets) +
            (barAnchor == null
                ? Offset.zero
                : popupGapOffset(barAnchor, theme.popupGap)),
        constraintAdjustment: constraintAdjustment,
      ),
      // The *window's* constraints, not the card's: these become GTK geometry
      // hints capping the surface, which the shadow and the flare have just
      // grown. See [popupWindowConstraints] — the [ConstrainedBox] below still
      // holds the card to what the call site asked for.
      constraints: popupWindowConstraints(constraints, surfaceInsets),
      delegate: PopupDelegate(onDestroyed: () {
        if (_popupController == thisController) {
          // The compositor has already taken the surface away, so there is
          // nothing left to animate: asking for an exit would keep a dead window
          // registered for the length of one. Set on the field rather than passed
          // as an argument because `closePopup` is what modules override
          // (`dock.dart`), and that override has to keep running.
          _exitAnimates = false;
          closePopup();
        } else {
          // An outgoing card whose window the compositor destroyed mid-exit.
          _finishOutgoing(thisController!);
        }
      }),
    );
    // The popup surface defaults to opaque black (fl_view_renderer paints the
    // view background unless it is exactly #00000000), so make it transparent the
    // way LayershellWindowController does for panels.
    // BaseWindowControllerLinux, not WindowControllerLinux: the latter is the
    // *regular*-window controller, and a popup's only implements the base
    // interface. Casting to the wrong one compiles and then throws on the first
    // popup opened.
    final native = thisController as BaseWindowControllerLinux;
    final gtkWindow = GtkWindow.fromHandle(native.windowHandle);
    gtkWindow.setAppPaintable(true);
    FlView.fromHandle(native.flutterViewHandle).setBackgroundColor('#00000000');
    // The spike, and the one moment it can happen: realized by the SDK's
    // constructor above, not yet shown — the engine's first-frame callback is
    // what maps it, and GDK reads the grab seat as it creates the `xdg_popup`.
    // See [_takePopupGrab].
    final grabMode = _kPopupGrabMode;
    if (grabMode != null) {
      _grabbedSeat = _takePopupGrab(native.windowHandle, grabMode);
    }
    // A sized-to-content popup has to be told its size before it maps, or it is
    // positioned as though it were some other size.
    //
    // PopupWindowControllerLinux resolves the placement exactly once, from its
    // constructor, and GTK3 does not set the positioner's reactive flag — so
    // `gdk_window_move_to_rect` is evaluated against whatever size the window has
    // at map time and never revisited. The window maps from the engine's
    // first-frame callback, but fl_view_renderer only applies the content size
    // when it *presents* a frame, which is after that. So the popup maps at GTK's
    // default 200x200 and shrinks afterwards, having been placed as 200x200.
    //
    // That matters because [popupAnchorsForBar] returns edge-*centred* anchors:
    // a wrong width offsets the popup by half the error, and a 128-wide menu
    // placed as though it were 200 lands 36px to the side of its button.
    //
    // This was invisible while every call site passed `BoxConstraints.tightFor`.
    // A post-frame callback runs after the frame that laid the content out but
    // before it is presented — the last moment the size can reach GTK.
    final contentKey = GlobalKey();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (thisController!.isDestroyed) return;
      final size = contentKey.currentContext?.size;
      if (size == null) return;
      gtkWindow.resize(size.width.ceil(), size.height.ceil());
      // The same measurement answers the panel's other question: how much of
      // its inner rim this card's mouth covers, so it can leave that stretch
      // unpainted. It has to be here rather than at open, because the mouth is
      // as wide as the card and the card has only just laid out.
      if (attachEdge != null &&
          panelView != null &&
          panelSize != null &&
          // Still this host's open popup: one closed inside the frame it opened
          // in has already cleared its break, and re-publishing here would leave
          // a gap in the bar with nothing left to close it.
          _popupController == thisController) {
        _publishRimBreak(
          view: panelView,
          panel: panelSize,
          window: size,
          anchor: anchorRect,
          edge: attachEdge,
          insets: surfaceInsets,
          flare: theme.popupAttachRadius,
        );
      }
    });
    // The root's registry, reached the way any descendant reaches it. A popup
    // opened from inside another popup's content finds the same one, because that
    // content is built under the root manager too.
    _registry = WindowRegistry.of(context);
    // Registered before the surface maps, so whatever this displaces is already
    // on its way out. The parent comes from the context: null in a panel, and the
    // enclosing popup's handle when a popup opens from inside another's content.
    final handle = _handle = PopupCoordinator.instance.open(
      owner: owner,
      parent: TransientScope.maybeOf(context),
      policy: policy,
      onDismiss: closePopup,
    );
    // The content is laid out directly under the popup's View, so the
    // ConstrainedBox at the bottom of this tree is what gives a sized-to-content
    // window its size: tight constraints make the content fill the popup exactly,
    // loose ones are floored at [kMinPopupConstraints].
    _entry = WindowEntry(
      controller: _popupController!,
      builder: (_) => TransientScope(
        handle: handle,
        // Inside the TransientScope and above everything the call site built,
        // because it is the card — three or four levels down, in a view of its
        // own — that reads it. Absent entirely for a floating popup, so nothing
        // outside a bar pays an element for this.
        child: _maybeAttached(
          attachEdge,
          // A card on its way out accepts nothing. Its surface stays mapped for
          // the length of the exit and the Listener below sits above the
          // animation, so without this a click on a fading popup would run
          // `dismissFromPointerDown` under a handle the coordinator has already
          // forgotten — dismissing everything *else* open, including a popup the
          // same gesture may have just opened. The Listener subtree is passed
          // through as `child`, so the flip costs one rebuild here.
          ValueListenableBuilder<bool>(
            valueListenable: closing,
            // `subtree` rather than `child`: the call site's own `child`
            // parameter is still in scope down at the ConstrainedBox, and two
            // different widgets under one name in one expression is a trap.
            builder: (context, isClosing, subtree) =>
                IgnorePointer(ignoring: isClosing, child: subtree),
            // The popup renders into its own FlutterView, so the panel's
            // [PopupDismissArea] never sees a click that lands in here — hence
            // this Listener, which spares this popup's chain and dismisses
            // everything else.
            //
            // It also covers the shadow's margin, because the shell has no
            // input-region support and the margin is part of this surface: a
            // click there neither dismisses the popup nor reaches what is
            // underneath. Same class of problem [setPanelMargin] documents, and
            // the reason the margin is kept to the shadow's actual reach rather
            // than padded generously.
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) => PopupCoordinator.instance
                  .dismissFromPointerDown(event, within: handle),
              // Keyed so the post-frame callback above can measure what the
              // content actually laid out to and hand that size to GTK.
              //
              // The shadow margin goes *outside* the ConstrainedBox, which is
              // the whole trick: a BoxShadow paints past its box and the
              // surface clips at its edge, so the window has to be the card
              // plus the shadow's reach. Padding the inside instead would
              // shrink the content — and the popups that pin a width by
              // passing minWidth == maxWidth (the app directory's list and
              // flyout, the sound slider, which has no intrinsic length) would
              // silently narrow rather than the window widening.
              child: Padding(
                key: contentKey,
                padding: surfaceInsets,
                // The one place a popup's animation is spelled. It used to be
                // the call site's job — fifteen of them wrapped their own card
                // in `PopupBounceIn` — which made it something a new popup
                // could forget, and left no way at all to play an exit: the
                // host is what knows the popup is closing, and the card is
                // what can animate. Inside the padding, so the card travels
                // within the margin the shadow already claimed rather than
                // against the surface's clip; outside the ConstrainedBox, so
                // the transform cannot reach the size the window was mapped
                // at.
                child: PopupTransition(
                  effect: resolvedEffect,
                  duration: resolvedDuration,
                  edge: barAnchor,
                  closing: closing,
                  onClosed: () => _finishOutgoing(thisController!),
                  child: ConstrainedBox(constraints: constraints, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _registry!.register(_entry!);
    setState(() {});
  }

  /// Closes the current popup, if any.
  ///
  /// Under an animated `popup_animation` this *starts* the close rather than
  /// completing it. The host lets go of the popup here and now — `isPopupOpen`
  /// answers false immediately, so the several call sites that close one popup
  /// and open another in the same gesture still work — while the window itself
  /// stays mapped, playing the entrance backwards, until its [PopupTransition]
  /// reports that it has finished. Only then is the [WindowEntry]
  /// dropped, the native window destroyed, and the opener's `onClosed` called;
  /// see [_ClosingPopup], which owns all of that, and [_dropOutgoing] for the
  /// one case in which `onClosed` is *not* owed. The coordinator handle is the
  /// exception to the deferral and is released here and now — [_ClosingPopup]
  /// says why.
  ///
  /// With [PopupEffect.none] — and whenever the compositor has already taken
  /// the window away — every one of those happens synchronously, exactly as it
  /// did before there was an exit animation at all.
  void closePopup() {
    final ctrl = _popupController;
    if (ctrl == null) return;
    // Synchronously, before anything else in this turn: several call sites
    // close one popup and open another in the same gesture, and a clear that
    // ran after the new one had published would take its break away again.
    final rimPanel = _rimBreakPanel;
    if (rimPanel != null) {
      _rimBreakPanel = null;
      PanelRimBreaks.instance.clear(rimPanel);
    }
    final record = _ClosingPopup(
      controller: ctrl,
      registry: _registry,
      entry: _entry!,
      onClosed: _onClosed,
      closing: _closing!,
      timeout: _exitTimeout,
      onFinished: _dropOutgoing,
    );
    final animate = _exitAnimates;
    // Given back now rather than at the end of the exit, for the coordinator
    // handle's reason below: the card is [IgnorePointer]ed and on its way out, so
    // nothing is being typed into it, and holding the panel's focus for the
    // length of an animation is holding it from the window underneath.
    _returnPopupKeyboard(_keyboardLender);
    _keyboardLender = null;
    // Given back here and not at the end of the exit, for the same reason: a
    // pointer grab held through a 112ms fade is held from the window
    // underneath, and the card is [IgnorePointer]ed on its way out anyway.
    _releasePopupGrab(_grabbedSeat);
    _grabbedSeat = null;
    // Released now rather than at the end of the exit: see [_ClosingPopup].
    PopupCoordinator.instance.close(_handle);
    _popupController = null;
    _registry = null;
    _entry = null;
    _handle = null;
    _onClosed = null;
    _closing = null;
    _exitAnimates = false;
    _exitTimeout = _popupExitTimeout(ShellDurations.popupOut);
    _outgoing.add(record);
    // Before the teardown, so a host that rebuilds on `isPopupOpen` has already
    // dropped its pressed state by the time `onClosed` runs.
    if (_canRebuild) setState(() {});
    if (animate) {
      record.beginExit();
    } else {
      record.finish();
    }
  }

  /// Completes the exit of whichever outgoing popup owns [controller].
  void _finishOutgoing(PopupWindowController controller) {
    for (final record in List<_ClosingPopup>.from(_outgoing)) {
      if (identical(record.controller, controller)) record.finish();
    }
  }

  void _dropOutgoing(_ClosingPopup record) {
    _outgoing.remove(record);
    if (_canRebuild) setState(() {});
    // `onClosed` fires once per open — at the end of the exit rather than at
    // its start, because "closed" is what it has always meant — but never over
    // a popup this host has opened since. Every caller uses it to put back
    // state the *open* menu was holding (the desktop's Open-with `GAppInfo`
    // handlers, the app directory's hold on its category flyout), and both of
    // those are single fields shared by whatever menu is current. A close
    // followed by a re-open in the same gesture is the shape both of them are
    // built around, so answering for the outgoing menu after its successor has
    // arrived would release the *successor's* handlers and close the flyout it
    // is sitting in. The successor's own `onClosed` is what answers for it.
    if (_popupController == null) record.onClosed?.call();
  }

  @override
  void dispose() {
    // Normally already given back by [closePopup]; this covers the host disposed
    // with its popup still open, so a monitor unplugged mid-rename cannot leave a
    // surface holding focus.
    _returnPopupKeyboard(_keyboardLender);
    _keyboardLender = null;
    _releasePopupGrab(_grabbedSeat);
    _grabbedSeat = null;
    // Modules close their popup from their own `dispose`, which runs before this:
    // what is left is a card animating out on behalf of a host that no longer
    // exists. Finish it now rather than leaving a timer and a registered window
    // behind — a deterministic teardown is worth more than the last few frames.
    for (final record in List<_ClosingPopup>.from(_outgoing)) {
      record.finish();
    }
    // Belt and braces: a host torn down without its module having closed its
    // popup would otherwise leave a gap in that panel's rim with nothing left
    // to close it.
    final rimPanel = _rimBreakPanel;
    if (rimPanel != null) {
      _rimBreakPanel = null;
      PanelRimBreaks.instance.clear(rimPanel);
    }
    super.dispose();
  }
}

/// Mixin for [State] classes that own a single full layer-shell window (a panel,
/// overlay, or dialog) whose surface they configure themselves.
///
/// The module creates the [LayershellWindowController] with its own layer/anchor
/// parameters and hands it to [openLayerWindow]; this mixin owns the
/// [WindowRegistry] registration and teardown.
mixin LayerShellHost<T extends StatefulWidget> on State<T> {
  LayershellWindowController? _lsController;
  WindowRegistry? _lsRegistry;
  WindowEntry? _lsEntry;
  TransientHandle? _lsHandle;

  /// Whether a layer-shell window is currently open.
  bool get isLayerWindowOpen => _lsController != null;

  /// Registers [controller] (already created by the caller with its
  /// layer/anchor params) into the root's [WindowRegistry], rendering [child].
  ///
  /// If a window is already open this is a no-op — call [closeLayerWindow]
  /// first.
  /// [onDismissRequested] is what the [PopupCoordinator] calls when something
  /// else needs this window gone. Windows with an exit animation pass the
  /// callback that *starts* it — the coordinator must never call
  /// [closeLayerWindow] itself, or a panel that should slide out would vanish.
  void openLayerWindow(
    BuildContext context, {
    required LayershellWindowController controller,
    required Widget child,
    TransientPolicy policy = TransientPolicy.menu,
    VoidCallback? onDismissRequested,
  }) {
    if (isLayerWindowOpen) return;
    _lsController = controller;
    _lsRegistry = WindowRegistry.of(context);
    _lsHandle = PopupCoordinator.instance.open(
      owner: this,
      parent: TransientScope.maybeOf(context),
      policy: policy,
      onDismiss: onDismissRequested ?? closeLayerWindow,
    );
    _lsEntry = WindowEntry(controller: controller, builder: (_) => child);
    _lsRegistry!.register(_lsEntry!);
    setState(() {});
  }

  /// Unregisters and destroys the current layer-shell window, if any.
  void closeLayerWindow() {
    PopupCoordinator.instance.close(_lsHandle);
    _lsHandle = null;
    if (_lsEntry != null) {
      _lsRegistry?.unregister(_lsEntry!);
      _lsEntry = null;
    }
    _lsRegistry = null;
    final ctrl = _lsController;
    _lsController = null;
    // Never synchronously: the view is still mounted in this very turn, so
    // destroying here is the abort [WindowTeardown] documents, with none of the
    // frame of grace the popup path at least had.
    if (ctrl != null) destroyWindowWhenDetached(ctrl);
    if (_canRebuild) setState(() {});
  }
}

/// Text label rendered inside a hover tooltip popup.
///
/// Popup content is built in its own window, outside the panel's [ThemeScope],
/// so callers must wrap this in a `ThemeProvider` — which is also what keeps a
/// tooltip still on screen in step with a theme change.
class TooltipLabel extends StatelessWidget {
  const TooltipLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      // The background is the theme's, at the alpha the theme chose. This used to
      // force .withAlpha(100) on top of it, which under a translucent theme
      // compounded into the least legible surface in the shell.
      child: PopupCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Center(
          child: Text(
            text,
            style: TextStyle(color: theme.popupForeground, fontSize: 12),
          ),
        ),
      ),
    );
  }
}
