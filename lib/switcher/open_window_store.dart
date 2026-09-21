// The list of open windows the switcher cycles through, and the recency order
// it cycles them in.
//
// The list is `ext_foreign_toplevel_list_v1`, read off the one
// [CaptureConnection] in the process rather than a second one of its own —
// the same handles the screencast window picker is built from. Nothing here
// polls: the compositor sends a `toplevel` event when a window opens and a
// `closed` when it goes, and `CaptureHost` fans those out.
//
// Recency is the half the protocol has no answer for. `ext-foreign-toplevel-
// list-v1` reports no state at all — not focus, not minimisation, not the
// workspace — so the order comes from miracle's `window` events, which are
// already on the shell's one IPC connection for the workspace row. A shell not
// connected to miracle still switches; it just offers the compositor's order
// rather than the one the user's own last few windows would suggest.
//
// The singleton-`ChangeNotifier` shape, and the store rules with it: one
// connection for the machine, and a read that finds nothing new must not
// notify — every overlay surface on every monitor listens.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:miracle/miracle.dart';

import 'package:graceful_shell/capture/toplevel_match.dart';
import 'package:graceful_shell/miracle_manager.dart';
import 'package:graceful_shell/modules/workspace_apps.dart' show containerAppId;
import 'package:graceful_shell/screencast/capture_host.dart';
import 'package:graceful_shell/switcher/open_window.dart';

class OpenWindowStore extends ChangeNotifier {
  OpenWindowStore._();

  static final OpenWindowStore instance = OpenWindowStore._();

  /// A detached store, so the ordering and the event filtering are testable
  /// without a compositor or a socket.
  @visibleForTesting
  factory OpenWindowStore.forTesting() => OpenWindowStore._();

  List<OpenWindow> _windows = const [];
  String _signature = '';
  List<String> _recent = const [];

  MiracleConnection? _connection;
  StreamSubscription<Event>? _events;
  bool _started = false;

  /// Every open window, most recently focused first.
  ///
  /// The order is recomputed on read rather than stored, because the two
  /// inputs move independently: a focus change reorders without changing the
  /// set, and a window opening changes the set without reordering it.
  List<OpenWindow> get windows => orderByRecency(_windows, _recent);

  /// Whether the shell has a compositor connection to read the list from at
  /// all. False on a machine with no libwayland or no display, which is the
  /// same thing that costs the screenshot and recorder modules their targets —
  /// the switcher says so rather than showing an empty grid, because "nothing
  /// is open" and "nothing can be read" are not the same answer.
  bool get available => CaptureHost.current != null;

  /// Opens the capture connection, takes the initial burst of toplevels and
  /// starts listening for more. Safe to call more than once.
  ///
  /// Called once at start-up rather than on the first Alt+Tab: connecting does
  /// two synchronous round-trips, and paying for those inside the keystroke
  /// that is meant to put a switcher on screen is a switcher that arrives
  /// late. It is also what lets the recency order start accumulating from
  /// login rather than from the first time the user reaches for it.
  void start() {
    if (_started) return;
    _started = true;
    CaptureHost.addToplevelsChangedListener(_refresh);
    CaptureHost.addDiedListener(_onConnectionDied);
    CaptureHost.connect();
    _refresh();
  }

  /// Points the store at the shell's current Miracle connection, or at nothing.
  ///
  /// `WorkspaceAppsStore.attach`'s shape, and for the same reason: a
  /// [MiracleConnection] is single-use, so every reconnect hands the shell a
  /// different instance and identity is what tells one from the other.
  void attach(MiracleConnection? connection) {
    if (identical(connection, _connection)) return;
    _events?.cancel();
    _events = null;
    _connection = connection;
    if (connection == null) return;
    _events = connection.listen(
      (event) {
        if (event case WindowEvent(
          change: WindowChange.focused,
          :final container,
        )) {
          _onFocused(container);
        }
      },
      // miracle.dart reports an undecodable payload as a stream error rather
      // than killing the stream; an event we cannot read is one reordering we
      // do not make, and nothing more.
      onError: (Object error) =>
          debugPrint('switcher: undecodable IPC event: $error'),
    );
  }

  /// The connection the switcher's commit runs against.
  MiracleConnection? get connection => _connection;

  /// [windows], having reconnected first if the compositor connection was lost.
  ///
  /// What the switcher reads when it opens, and the only place the connect is
  /// allowed to happen inside a keystroke: `CaptureHost` clears its memoised
  /// failure when a connection dies, so this is where a compositor restart is
  /// recovered from. It costs two round trips once, against a switcher that
  /// would otherwise be empty for the rest of the session.
  List<OpenWindow> read() {
    if (CaptureHost.current == null) _refresh();
    return windows;
  }

  /// Re-reads the toplevel list off the capture connection.
  ///
  /// Connecting here as well as in [start] is what makes a compositor restart
  /// cost one list rather than the rest of the session: `CaptureHost` clears
  /// its memoised failure when the connection dies, so the next read is the
  /// reconnect.
  void _refresh() {
    final connection = CaptureHost.current ?? CaptureHost.connect();
    final next = <OpenWindow>[
      for (final toplevel in connection?.toplevels ?? const [])
        if (toplevel.identifier.isNotEmpty)
          OpenWindow(
            identifier: toplevel.identifier,
            appId: toplevel.appId,
            title: toplevel.title,
          ),
    ];
    _publish(next);
  }

  void _publish(List<OpenWindow> next) {
    final signature = openWindowSignature(next);
    // The `done` event fires on every retitle, which for a browser is every
    // tab switch — and the overlay is full-screen on every output, so a
    // notification that changes nothing costs a repaint of every one of them.
    if (signature == _signature) return;
    _signature = signature;
    _windows = next;
    notifyListeners();
  }

  void _onConnectionDied() {
    // The handles are gone with the connection; keeping them would offer the
    // user a list of windows nothing can be done with.
    _publish(const []);
  }

  /// miracle says [container] took focus. Moves the toplevel that is it to the
  /// front of the recency order.
  ///
  /// Best effort by construction — the join is on what the window calls itself
  /// (`capture/toplevel_match.dart`), and an ambiguous one is declined. A focus
  /// change that cannot be attributed leaves the order as it was, which is
  /// exactly what a shell with no IPC connection has all the time.
  void _onFocused(ContainerNode container) {
    final identifier = _identifierFor(container);
    if (identifier == null) return;
    final next = promoteRecent(_recent, identifier);
    if (identical(next, _recent)) return;
    _recent = next;
    // Deliberately no notify: nothing on screen is reading the order while it
    // moves. The switcher takes its list at the moment it opens — the order
    // must not shuffle under a user who is halfway through cycling it — so the
    // only read that matters is the next Alt+Tab.
  }

  String? _identifierFor(ContainerNode container) {
    final appId = containerAppId(container);
    if (appId == null && container.name.isEmpty) return null;
    return matchOpenWindow(
      _windows,
      appId: appId ?? '',
      title: container.name,
    );
  }

  /// Seeds the list directly. Tests only: everything else arrives over Wayland.
  @visibleForTesting
  void setWindowsForTesting(List<OpenWindow> windows) => _publish(windows);

  /// Records a focus for [identifier]. Tests only.
  @visibleForTesting
  void promoteForTesting(String identifier) =>
      _recent = promoteRecent(_recent, identifier);

  @override
  void dispose() {
    CaptureHost.removeToplevelsChangedListener(_refresh);
    CaptureHost.removeDiedListener(_onConnectionDied);
    _events?.cancel();
    _events = null;
    _connection = null;
    super.dispose();
  }
}

/// The identifier of the one window in [windows] that is `appId`/`title`, or
/// null when no single one is.
///
/// [matchToplevel] over [OpenWindow]s rather than over the capture stack's own
/// descriptors, so the switcher and the window picker cannot drift apart about
/// what counts as a match.
String? matchOpenWindow(
  List<OpenWindow> windows, {
  required String appId,
  required String title,
}) =>
    matchToplevel(
      [for (final window in windows) window.descriptor],
      appId: appId,
      title: title,
    );

/// Points the shared store at the compositor and at the shell's Miracle
/// connection, and keeps the second of those current.
///
/// Not a `ShellService`, `startKeybindService`'s reason: there is nothing to
/// await, and a machine with no compositor must not settle a start-up task
/// `failed` over a switcher nobody has pressed Alt+Tab on. The manager is
/// listened to rather than read once, because the shell may start before
/// miracle is up and the connection is re-established later.
void startWindowSwitcherService(MiracleManager miracle) {
  final store = OpenWindowStore.instance;
  store.start();
  store.attach(miracle.connection);
  miracle.addListener(() => store.attach(miracle.connection));
}
