// The Alt+Tab session: what is open, which one is highlighted, and what letting
// go of Alt does.
//
// The controller shape the rest of the shell's overlays use — a singleton
// `ChangeNotifier` a global shortcut pokes and the root watches — with one
// thing none of the others has: a *held* gesture. Every other shortcut in the
// shell is a toggle, so the compositor's `begin` is the whole story. Alt+Tab is
// three separate signals, and each arrives by a different route:
//
//  * **The first press** comes from the compositor's input trigger, because no
//    shell surface has focus when the user reaches for it.
//  * **Every press after it** comes from the trigger too, and has to: Mir
//    *consumes* the key events a trigger matched, so the Tab presses never
//    reach the overlay however much focus it holds
//    (`src/server/frontend_wayland/wl_seat.cpp`, `ConsumedKeyTracker`).
//  * **Letting go of Alt** is the one signal the trigger cannot give. Its `end`
//    event fires when the *combination* stops being held, which is the moment
//    Tab comes back up — with Alt still down and the user still choosing. So
//    the release is read off the keyboard by the overlay, which is why its
//    surface takes keyboard focus at all.
//
// The window list is snapshotted when the session opens and not read again.
// A window opening or being retitled while the user is mid-cycle must not
// renumber the grid under them — the index they are on is the promise the
// highlight is making.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/switcher/open_window.dart';
import 'package:graceful_shell/switcher/open_window_store.dart';
import 'package:graceful_shell/switcher/window_activation.dart';

class WindowSwitcherController extends ChangeNotifier {
  WindowSwitcherController._();

  static final WindowSwitcherController instance = WindowSwitcherController._();

  /// A detached controller, so a widget test can drive the overlay without the
  /// singleton's compositor connection.
  @visibleForTesting
  factory WindowSwitcherController.forTesting({
    List<OpenWindow> Function()? readWindows,
    Future<void> Function(OpenWindow window, List<OpenWindow> all)? activate,
  }) {
    final controller = WindowSwitcherController._();
    if (readWindows != null) controller._readWindows = readWindows;
    if (activate != null) controller._activate = activate;
    return controller;
  }

  List<OpenWindow> Function() _readWindows =
      () => OpenWindowStore.instance.read();

  Future<void> Function(OpenWindow window, List<OpenWindow> all) _activate =
      (window, all) =>
          activateWindow(OpenWindowStore.instance.connection, window, all);

  bool _open = false;
  List<OpenWindow> _windows = const [];

  /// Which icon is highlighted.
  ///
  /// A [ValueNotifier] rather than a field behind [notifyListeners] because
  /// cycling is the thing this does most and an overlay surface has no repaint
  /// boundary of its own: every cell listens to this one value and repaints
  /// itself, instead of the card rebuilding on every press of Tab.
  final ValueNotifier<int> selection = ValueNotifier<int>(0);

  /// Whether a switcher session is running. The root creates its surfaces off
  /// this, and tears them down when it goes false.
  bool get isOpen => _open;

  /// The windows this session is cycling, in the order they are drawn.
  List<OpenWindow> get windows => _windows;

  /// The window [commit] would switch to, or null when there is none.
  OpenWindow? get selected {
    final index = selection.value;
    if (index < 0 || index >= _windows.length) return null;
    return _windows[index];
  }

  /// Alt+Tab (forward) or Alt+Shift+Tab (backward) fired.
  ///
  /// The first press opens the session *and* moves: the window the user wants
  /// is almost never the one they are already in, so landing on the previous
  /// window is what makes a tap-and-release the "go back" gesture it is
  /// everywhere else. Later presses only move.
  void cycle({required bool forward}) {
    final delta = forward ? 1 : -1;
    if (!_open) {
      _windows = List.unmodifiable(_readWindows());
      _open = true;
      // The list is most-recently-focused first, so index 0 is the window the
      // user is already in. One step from there is the previous one.
      selection.value = cycleIndex(0, delta, _windows.length);
      notifyListeners();
      return;
    }
    selection.value = cycleIndex(selection.value, delta, _windows.length);
  }

  /// The pointer moved the selection — a hover or a click on a cell.
  void select(int index) {
    if (!_open || index < 0 || index >= _windows.length) return;
    selection.value = index;
  }

  /// Alt came back up: switch to whatever is highlighted and end the session.
  ///
  /// The switch is started here and not awaited. The overlay is already on its
  /// way out and the IPC round trip is two commands over a socket; holding the
  /// surfaces up until it answers would make every switch look slower than the
  /// compositor actually is.
  void commit() {
    if (!_open) return;
    final window = selected;
    final all = _windows;
    _close();
    if (window != null) unawaited(_activate(window, all));
  }

  /// Escape, or a click on the backdrop: end the session and switch to nothing.
  void cancel() {
    if (!_open) return;
    _close();
  }

  /// Ends the session, leaving [windows] and [selection] exactly as they were.
  ///
  /// Deliberately: the overlay outlives the session by however long its exit
  /// animation lasts, and clearing either here would empty the grid — or jump
  /// the highlight back to the first cell — in the frames the user is watching
  /// it leave. The next [cycle] is what resets them, which is also the only
  /// moment a fresh list is honest.
  void _close() {
    _open = false;
    notifyListeners();
  }

  @override
  void dispose() {
    selection.dispose();
    super.dispose();
  }
}
