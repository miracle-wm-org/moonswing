// Closing the shell's transient surfaces when the user focuses something that
// is not the shell.
//
// The rest of the popup stack cannot see this happen, for three separate
// reasons:
//
//  * The Linux popup controller takes no `gdk_seat_grab`, so the compositor
//    never sends `popup_done`. `lib/popup.dart`'s `GRACEFUL_SHELL_POPUP_GRAB`
//    is the experiment in taking one by hand — and even if it works it reaches
//    only the bar popups, never the overlays, which are layer surfaces with no
//    popup role at all. So this file stays either way.
//  * A panel's own focus never changes. `LayershellWindowController` does
//    notify on `notify::is-active`, but on Wayland GTK takes `is-active` from
//    `wl_keyboard.enter`/`leave`, and a panel is `LayerShellKeyboardMode.none`
//    — so it is never active and never transitions.
//  * `ext-foreign-toplevel-list-v1` carries no state — not focus, not
//    minimisation.
//
// So `PopupDismissArea` catches a click on a panel or the desktop, and nothing
// in that stack catches a click on an ordinary application window.
//
// What *is* visible is the consequence of that click: miracle emits a `window`
// event with `change: focus` when the compositor focuses an application
// window, on the one IPC connection the shell already subscribes to for the
// workspace row (`MiracleManager`). This turns that event into the dismissal
// nobody else can ask for. A shell not connected to miracle keeps exactly the
// behaviour it had before — there is no surface on which "popups will not
// auto-close" could be read, so this degrades quietly rather than visibly.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:miracle/miracle.dart';

import 'package:graceful_shell/miracle_manager.dart';
import 'package:graceful_shell/popup_coordinator.dart';

/// How long focus changes the shell asked for itself go unread.
///
/// Not a `ShellDurations` token: every one of those is animation timing, and
/// what this bounds is a socket round trip — `activateWindow` reads `GET_TREE`
/// before it sends the focus command, so the event it causes is two round trips
/// away. Generous, because the only cost of being generous is one external
/// focus change going unnoticed inside a second of an Alt+Tab; and bounded at
/// all because a guard that did not expire would be a popup that stops closing
/// for the rest of the session.
const Duration _selfFocusWindow = Duration(seconds: 1);

/// Whether [event] means focus moved to something that is not the shell.
///
/// Spelled out arm by arm with no `default`, `wakesWorkspaceApps`'s shape and
/// for its reason: a new `WindowChange` or `WorkspaceChange` in a later
/// miracle.dart fails the build rather than landing silently classified.
bool dismissesPopupsOn(Event event) => switch (event) {
      WindowEvent(:final change) => switch (change) {
          // The one that matters: the compositor focused an application
          // window, which is the click on Firefox that nothing else can see.
          WindowChange.focused => true,
          // A window that opens without taking focus has not moved the user's
          // attention, and one that takes it emits `focus` as well — so
          // `created` here would tear a popup down for a window nobody looked
          // at. None of the rest is a focus change at all.
          WindowChange.created ||
          WindowChange.closed ||
          WindowChange.fullscreenMode ||
          WindowChange.moved ||
          WindowChange.floating ||
          WindowChange.marked ||
          WindowChange.urgent =>
            false,
          // Deliberately the opposite of `wakesWorkspaceApps`'s `unknown`: a
          // row that goes stale is cheap and re-reads on the next event, while
          // a popup torn down under the user's hand is not recoverable.
          WindowChange.unknown => false,
        },
      WorkspaceEvent(:final change) => switch (change) {
          // The half a window event cannot cover: a switch that lands on an
          // *empty* workspace focuses no window and so emits no window event,
          // and a popup left on screen there is one the user has walked away
          // from just as squarely.
          WorkspaceChange.focus => true,
          WorkspaceChange.init ||
          WorkspaceChange.empty ||
          WorkspaceChange.move ||
          WorkspaceChange.rename ||
          WorkspaceChange.reload ||
          WorkspaceChange.urgent =>
            false,
          WorkspaceChange.unknown => false,
        },
      _ => false,
    };

/// Turns miracle's focus events into [PopupCoordinator.dismissOutside].
///
/// One subscription for the machine, on the connection [MiracleManager] already
/// holds: `MiracleConnection` is a broadcast stream, so this costs a second
/// listener and no second socket. Nothing renders from it, so it is not a
/// `ChangeNotifier` and notifies nobody.
class PopupFocusDismisser {
  PopupFocusDismisser._();

  static final PopupFocusDismisser instance = PopupFocusDismisser._();

  /// A detached instance, so the filtering and the self-focus guard are
  /// testable without a compositor or a socket.
  @visibleForTesting
  factory PopupFocusDismisser.forTesting() => PopupFocusDismisser._();

  MiracleConnection? _connection;
  StreamSubscription<Event>? _events;
  Timer? _selfFocus;

  /// Points the dismisser at the shell's current Miracle connection, or at
  /// nothing.
  ///
  /// `OpenWindowStore.attach`'s shape, and for its reason: a
  /// [MiracleConnection] is single-use, so every reconnect hands the shell a
  /// different instance and identity is what tells one from the other.
  void attach(MiracleConnection? connection) {
    if (identical(connection, _connection)) return;
    _events?.cancel();
    _events = null;
    _connection = connection;
    if (connection == null) return;
    _events = connection.listen(
      handleEvent,
      // miracle.dart reports an undecodable payload as a stream error rather
      // than killing the stream; an event we cannot read is one dismissal we
      // do not make, and nothing more.
      onError: (Object error) =>
          debugPrint('popup focus: undecodable IPC event: $error'),
    );
  }

  /// The shell is about to ask miracle for a focus change: do not read the
  /// events it causes as the user leaving.
  ///
  /// `activateWindow` is the only place the shell asks, and the race it closes
  /// is the one `WindowSwitcherController.commit` already documents. `commit`
  /// hands the keyboard grab back, ends the session, then starts an *unawaited*
  /// switch whose `GET_TREE` round trip lands the focus event several turns
  /// later. A second Alt+Tab inside the first session's fade opens a new
  /// session — and the old switch's focus event would then cancel it, since the
  /// switcher's `onDismiss` is `cancel`.
  ///
  /// [PopupCoordinator.consumeReopenGuard]'s idiom — swallow the event the
  /// shell's own action caused — but a *window* rather than a one-shot, because
  /// one switch is not one event: `switchToWindowCommands` sends a `workspace`
  /// hop and a `focus` in the same payload, and both a workspace focus and a
  /// window focus come back. Consuming exactly one would leave the other to
  /// dismiss.
  ///
  /// The window's only cost is ignoring a genuine external focus change for a
  /// second after an Alt+Tab, which is a second in which the switcher was the
  /// only transient the shell had open and has already gone. Re-arming
  /// restarts it rather than stacking, so two switches in a row leave one
  /// timer.
  void expectSelfFocus() {
    _selfFocus?.cancel();
    _selfFocus = Timer(_selfFocusWindow, () => _selfFocus = null);
  }

  /// One miracle event. The listener [attach] installs, and the seam a test
  /// pushes an `Event.fromJson(…)` through — there is no fake
  /// `MiracleConnection` in the repo and this needs none.
  @visibleForTesting
  void handleEvent(Event event) {
    if (!dismissesPopupsOn(event)) return;
    // A focus change the shell asked for itself. The timer is left running:
    // one switch emits both a workspace focus and a window focus, so the
    // expectation has to outlast the first of them. See [expectSelfFocus].
    if (_selfFocus != null) return;
    // `dismissOutside`, never `dismissAll`: the first honours
    // `TransientPolicy.dismissable`, which is what leaves the screencast
    // consent picker, the file picker, the power menu and the polkit prompt
    // standing. Alt-tabbing away from a prompt that grants administrator
    // rights must not answer it.
    //
    // A null chain tip, because the focus went to something outside every
    // chain the shell owns.
    PopupCoordinator.instance.dismissOutside(null);
  }

  /// Whether a focus change the shell asked for is still expected. Tests only.
  @visibleForTesting
  bool get expectingSelfFocus => _selfFocus != null;

  @visibleForTesting
  void disposeForTesting() {
    _events?.cancel();
    _events = null;
    _connection = null;
    _selfFocus?.cancel();
    _selfFocus = null;
  }
}

/// Points the shared dismisser at the shell's Miracle connection, and keeps it
/// current.
///
/// Not a `ShellService`, `startKeybindService`'s reason: there is nothing to
/// await, and a machine that cannot reach a compositor must not settle a
/// start-up task `failed` over a dismissal nobody has noticed the absence of.
/// The manager is listened to rather than read once, because the shell may
/// start before miracle is up and the connection is re-established later.
void startPopupFocusDismissService(MiracleManager miracle) {
  final dismisser = PopupFocusDismisser.instance;
  dismisser.attach(miracle.connection);
  miracle.addListener(() => dismisser.attach(miracle.connection));
}
