// What a dock button does between being asked to open an application and that
// application putting a window on screen.
//
// Two halves. A dock icon opens on a *double* click, so a stray click while the
// pointer crosses the bar — or the first half of a gesture that was meant to be
// a drag — launches nothing ([DockDoubleClick]). And once it has launched, the
// icon carries a spinner until the window shows up ([DockLaunchStore],
// [DockLaunchIndicator]), because an application that takes three seconds to
// start otherwise looks exactly like a click that did nothing — which is what
// sends the user back for the second, duplicate launch.
//
// "Shows up" is read off the compositor's toplevel list — the same
// `ext-foreign-toplevel-list-v1` handles the window switcher is built from — so
// nothing here polls: the compositor says when a window opens, and a one-shot
// timer per launch is the bound for an application that never says anything
// recognisable.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/widgets.dart';

import 'package:moonswing/app_info.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/switcher/open_window.dart';
import 'package:moonswing/switcher/open_window_store.dart';

// --- Double click (pure) ----------------------------------------------------

/// Tells a double click from two single ones.
///
/// Hand-rolled rather than a `GestureDetector.onDoubleTap`, because the dock
/// button's detector also carries the pan that drags it: a mouse wins the pan
/// arena after a single pixel, so a double-tap recognizer would lose every
/// click that wobbled — and a click that never passed the drag threshold
/// reaches the button through `onPanEnd`, where no tap recognizer is listening.
/// Both paths report here instead.
///
/// The interval is derived from the wall clock at each click rather than timed,
/// so nothing is scheduled between them; a clock that steps backwards between
/// two clicks makes the second a first.
class DockDoubleClick {
  DockDoubleClick({
    this.timeout = kDoubleTapTimeout,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// The longest gap between two clicks that still makes them one gesture —
  /// Flutter's own double-tap window by default.
  final Duration timeout;

  final DateTime Function() _now;
  DateTime? _first;

  /// Records a click. True when it completes a double click, after which the
  /// next click starts a new one — a triple click opens once, not twice.
  bool click() {
    final now = _now();
    final first = _first;
    if (first != null) {
      final gap = now.difference(first);
      if (!gap.isNegative && gap <= timeout) {
        _first = null;
        return true;
      }
    }
    _first = now;
    return false;
  }

  /// Forgets a half-finished double click — a drag began, or the pointer left.
  void reset() => _first = null;
}

// --- Window matching (pure) -------------------------------------------------

/// Whether [window] is one of the application whose desktop entry is
/// [desktopId] (an [AppEntry.id]) and whose `StartupWMClass=` is
/// [startupWmClass].
///
/// The compositor knows a window by its `app_id`, the dock knows an
/// application by its desktop file, and the two are spelled the same far more
/// often than they are spelled identically. So, case-insensitively: the
/// declared window class wins outright; then the id itself; then the last
/// reverse-DNS segment of either (`org.gnome.Nautilus` → `nautilus`); then a
/// snap's `<snap>_<app>` id against either half (`firefox_firefox` →
/// `firefox`).
bool windowBelongsToApp(
  OpenWindow window, {
  required String desktopId,
  String startupWmClass = '',
}) {
  final appId = window.appId.toLowerCase();
  if (appId.isEmpty) return false;
  if (startupWmClass.isNotEmpty && startupWmClass.toLowerCase() == appId) {
    return true;
  }
  final id = desktopId.toLowerCase();
  if (id.isEmpty) return false;
  final names = _spellings(id);
  return names.contains(appId) || names.contains(_lastSegment(appId));
}

Set<String> _spellings(String id) {
  final names = {id, _lastSegment(id)};
  for (final name in [...names]) {
    final underscore = name.indexOf('_');
    if (underscore > 0 && underscore < name.length - 1) {
      names
        ..add(name.substring(0, underscore))
        ..add(name.substring(underscore + 1));
    }
  }
  return names;
}

/// `org.gnome.nautilus` → `nautilus`; anything undotted is its own tail.
String _lastSegment(String id) {
  final dot = id.lastIndexOf('.');
  return dot < 0 || dot == id.length - 1 ? id : id.substring(dot + 1);
}

// --- The store --------------------------------------------------------------

/// How long a launch may show its spinner while no window it can be matched to
/// has appeared. An application that never opens one — or opens one under an
/// `app_id` nothing about its desktop file predicts — stops spinning here.
const Duration kDockLaunchTimeout = Duration(seconds: 20);

/// The bound when the application already had a window open at launch.
///
/// A single-instance application asked to start again often only raises the
/// window it has, which adds nothing to the toplevel list — so there is
/// nothing to wait for beyond the moment it takes to do that.
const Duration kDockRelaunchTimeout = Duration(seconds: 4);

/// The bound when the shell cannot read the compositor's window list at all
/// (no libwayland, or no `ext-foreign-toplevel-list-v1`). Long enough to show
/// that the click took, short enough not to claim a wait it cannot observe.
const Duration kDockBlindLaunchTimeout = Duration(seconds: 3);

/// Where the store reads the compositor's windows from. [OpenWindowStore] in
/// the shell; a hand-fed one in tests.
abstract class DockWindowSource implements Listenable {
  /// Every open window, in any order.
  List<OpenWindow> get windows;

  /// Whether [windows] reflects the compositor at all.
  bool get available;

  /// Starts reading the list, if nothing has yet. Safe to call repeatedly.
  void ensureStarted();
}

class _OpenWindowSource implements DockWindowSource {
  const _OpenWindowSource();

  OpenWindowStore get _store => OpenWindowStore.instance;

  @override
  List<OpenWindow> get windows => _store.windows;

  @override
  bool get available => _store.available;

  // The switcher starts the store only on miracle with its shortcuts bound,
  // and the dock runs on any compositor — so the dock starts it itself, on its
  // first launch rather than at start-up: a shell nobody launches anything
  // from holds no capture connection for it.
  @override
  void ensureStarted() => _store.start();

  @override
  void addListener(VoidCallback listener) => _store.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _store.removeListener(listener);
}

class _PendingLaunch {
  _PendingLaunch({
    required this.desktopId,
    required this.startupWmClass,
    required this.before,
    required this.timer,
  });

  final String desktopId;
  final String startupWmClass;

  /// The identifiers of every window open when the launch went out; only a
  /// window outside this set can be the one it opened.
  final Set<String> before;

  final Timer timer;

  bool owns(OpenWindow window) => windowBelongsToApp(
        window,
        desktopId: desktopId,
        startupWmClass: startupWmClass,
      );
}

/// Which dock applications are starting, for the machine.
///
/// One store rather than state in each dock, because there is a dock per panel
/// per monitor and a launch from one of them is the same launch on all: every
/// copy of the icon spins, and every copy refuses a second launch until the
/// first has landed. Each application gets its own [ValueListenable], so a
/// launch rebuilds that application's icons and nothing else on the bar.
///
/// The window list is listened to only while a launch is pending, and each
/// launch holds one one-shot timer — an idle dock wakes for none of this.
class DockLaunchStore {
  DockLaunchStore._({
    required DockWindowSource windows,
    required bool Function(AppEntry entry) launch,
  })  : _windows = windows,
        _launch = launch;

  static final DockLaunchStore instance = DockLaunchStore._(
    windows: const _OpenWindowSource(),
    launch: (entry) => launchApp(entry.appInfo),
  );

  /// A store over a hand-fed window list and a fake launcher.
  @visibleForTesting
  factory DockLaunchStore.forTesting({
    required DockWindowSource windows,
    bool Function(AppEntry entry)? launch,
  }) =>
      DockLaunchStore._(windows: windows, launch: launch ?? (_) => true);

  final DockWindowSource _windows;
  final bool Function(AppEntry entry) _launch;

  final Map<String, ValueNotifier<bool>> _flags = {};
  final Map<String, _PendingLaunch> _pending = {};
  bool _listening = false;

  /// Whether the application whose desktop entry is [desktopId] is starting.
  ValueListenable<bool> launchingOf(String desktopId) =>
      _flags.putIfAbsent(desktopId, () => ValueNotifier<bool>(false));

  bool isLaunching(String desktopId) => _pending.containsKey(desktopId);

  /// Launches [entry], unless it is already starting.
  ///
  /// Returns whether a launch went out. A second request while the first is
  /// still pending is declined — that request is almost always the user asking
  /// again because nothing seemed to happen, which is the duplicate window the
  /// spinner is there to prevent.
  bool launch(AppEntry entry) {
    final id = entry.id;
    if (_pending.containsKey(id)) return false;

    // Started, and the list taken, *before* the launch goes out: a fast
    // application can map its window inside the spawn, and a window already
    // in `before` could never end the wait.
    _windows.ensureStarted();
    final available = _windows.available;
    final open = available ? _windows.windows : const <OpenWindow>[];

    if (!_launch(entry)) return false;

    final wmClass = entry.startupWmClass;
    final alreadyRunning = open.any(
      (w) => windowBelongsToApp(w, desktopId: id, startupWmClass: wmClass),
    );
    final bound = !available
        ? kDockBlindLaunchTimeout
        : alreadyRunning
            ? kDockRelaunchTimeout
            : kDockLaunchTimeout;

    _pending[id] = _PendingLaunch(
      desktopId: id,
      startupWmClass: wmClass,
      before: {for (final w in open) w.identifier},
      timer: Timer(bound, () => _finish(id)),
    );
    _setListening();
    (launchingOf(id) as ValueNotifier<bool>).value = true;
    return true;
  }

  void _onWindowsChanged() {
    if (_pending.isEmpty) return;
    final windows = _windows.windows;
    final landed = <String>{};
    final unclaimed = <OpenWindow>[];
    for (final window in windows) {
      var claimed = false;
      for (final launch in _pending.values) {
        if (launch.before.contains(window.identifier)) continue;
        if (launch.owns(window)) {
          landed.add(launch.desktopId);
          claimed = true;
        }
      }
      final isNew = _pending.values.any(
        (launch) => !launch.before.contains(window.identifier),
      );
      if (!claimed && isNew) unclaimed.add(window);
    }
    // A new window nothing matched — an XWayland window with no `app_id`, or
    // one spelled unlike its desktop file — is taken as the launch's when
    // exactly one launch is waiting, since there is nothing else it could be
    // the answer to. With two waiting it is nobody's, and the timers decide.
    if (landed.isEmpty && unclaimed.isNotEmpty && _pending.length == 1) {
      landed.add(_pending.keys.single);
    }
    for (final id in landed) {
      _finish(id);
    }
  }

  void _finish(String desktopId) {
    final launch = _pending.remove(desktopId);
    if (launch == null) return;
    launch.timer.cancel();
    _setListening();
    _flags[desktopId]?.value = false;
  }

  void _setListening() {
    final want = _pending.isNotEmpty;
    if (want == _listening) return;
    _listening = want;
    if (want) {
      _windows.addListener(_onWindowsChanged);
    } else {
      _windows.removeListener(_onWindowsChanged);
    }
  }

  @visibleForTesting
  void dispose() {
    for (final launch in _pending.values) {
      launch.timer.cancel();
    }
    _pending.clear();
    _setListening();
    for (final flag in _flags.values) {
      flag.dispose();
    }
    _flags.clear();
  }
}

// --- The indicator ----------------------------------------------------------

/// A dock icon, dimmed and ringed by a spinning arc while its application is
/// starting.
///
/// The same shape at rest and while launching — an [Opacity] that is a no-op
/// at 1.0, and a [Stack] whose first child never moves — so the icon below is
/// never remounted (and its image never reloaded) by a launch starting or
/// ending. The spinner, and the ticker behind it, exist only while [launching].
///
/// The ring sits in the button's padding, just outside the icon, on a
/// repaint boundary of its own: it turns every frame, and the icon under it
/// must not be re-recorded for that.
class DockLaunchIndicator extends StatelessWidget {
  const DockLaunchIndicator({
    super.key,
    required this.launching,
    required this.child,
  });

  final bool launching;
  final Widget child;

  /// How far the ring reaches past the icon — inside the dock button's 4px
  /// padding, so it is drawn on the button's own surface.
  static const double ringOutset = 3;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Opacity(opacity: launching ? 0.4 : 1, child: child),
        if (launching)
          const Positioned(
            left: -ringOutset,
            top: -ringOutset,
            right: -ringOutset,
            bottom: -ringOutset,
            child: IgnorePointer(
              child: RepaintBoundary(child: DockLaunchSpinner()),
            ),
          ),
      ],
    );
  }
}

/// The ring itself: a faint full track and a bright arc chasing round it, in
/// the theme's accent.
class DockLaunchSpinner extends StatefulWidget {
  const DockLaunchSpinner({super.key});

  /// One turn of the arc.
  static const Duration period = Duration(milliseconds: 850);

  @override
  State<DockLaunchSpinner> createState() => _DockLaunchSpinnerState();
}

class _DockLaunchSpinnerState extends State<DockLaunchSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: DockLaunchSpinner.period,
  )..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = ThemeScope.of(context).accent;
    return CustomPaint(
      painter: _SpinnerPainter(turn: _turn, color: accent),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({required this.turn, required this.color})
      : super(repaint: turn);

  final Animation<double> turn;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    if (side <= 0) return;
    final stroke = math.max(2.0, side * 0.09);
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side - stroke,
      height: side - stroke,
    );
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color.withValues(alpha: color.a * 0.25),
    );
    // The arc breathes as it turns — a quarter at its shortest, two-thirds at
    // its longest — which is what reads as "working" rather than as a ring
    // that happens to be rotating.
    final t = turn.value;
    final sweep = math.pi * 2 * (0.25 + 0.42 * (0.5 - 0.5 * math.cos(t * 2 * math.pi)));
    canvas.drawArc(
      rect,
      t * math.pi * 2 - math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_SpinnerPainter old) =>
      old.color != color || old.turn != turn;
}
