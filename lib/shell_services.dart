import 'dart:async';

import 'package:flutter/widgets.dart';

/// How far along one of the shell's global start-up tasks is.
enum ServiceStatus {
  /// Still running (or not started yet). A widget that needs it shows a loader.
  loading,

  /// Finished — successfully, or with nothing to do because the feature is off
  /// in `config.toml`. Either way there is nothing left to wait for.
  ready,

  /// Gave up. Every one of these services fails soft — the shell keeps running
  /// without it — so this is a reason to stop showing a spinner, not to stop.
  failed,
}

/// The shell's global start-up tasks: the things `main()` used to `await`
/// between the process starting and the first frame reaching the screen.
///
/// Every one of them is either I/O the shell cannot make faster (a D-Bus name
/// request, a socket connect, a Wayland round-trip) or a walk over the whole
/// system (the application index). None of them is needed to *paint* — panel
/// geometry comes out of `config.toml` and the palette out of `ThemeStore`, and
/// both are resolved before this list is even started.
enum ShellService {
  /// The Wayland client, the compositor's `wl_output` set, and the global
  /// shortcut registrations that ride the same registry.
  displays,

  /// The Miracle WM IPC socket.
  miracle,

  /// `org.freedesktop.Notifications` on the session bus.
  notifications,

  /// The StatusNotifierItem tray watcher and host.
  tray,

  /// PulseAudio and the backlight, which feed the on-screen indicator.
  audio,

  /// The installed-application index the launcher and choosers rank against.
  applications,

  /// The xdg-desktop-portal ScreenCast backend.
  screencast,
}

/// The one place that knows how far along the shell's start-up is.
///
/// `main()` hands each task here instead of awaiting it, so the first frame is
/// gated on nothing but reading `config.toml`. Widgets that need a task's
/// result read its [ServiceStatus] through [ShellServicesScope] and show a
/// loader while it is [ServiceStatus.loading], rather than rendering an empty
/// state that is indistinguishable from "you have none of these".
///
/// Same `ChangeNotifier` shape as the shell's stores, but deliberately *not* a
/// singleton: it is constructed in `main()` and passed down like the
/// `MiracleManager`, so a widget test can build one carrying whatever statuses
/// the case under test needs.
class ShellServices extends ChangeNotifier {
  ShellServices();

  /// A store with every service already settled at [status]. For tests, which
  /// have no `main()` behind them to start anything.
  @visibleForTesting
  factory ShellServices.settled([ServiceStatus status = ServiceStatus.ready]) {
    final services = ShellServices();
    for (final service in ShellService.values) {
      services._status[service] = status;
      services._started.add(service);
    }
    return services;
  }

  final Map<ShellService, ServiceStatus> _status = {};
  final Map<ShellService, String> _errors = {};
  final Set<ShellService> _started = {};

  ServiceStatus statusOf(ShellService service) =>
      _status[service] ?? ServiceStatus.loading;

  /// True while [service] has not settled — the condition a loader is shown on.
  bool isLoading(ShellService service) =>
      statusOf(service) == ServiceStatus.loading;

  @visibleForTesting
  bool isReady(ShellService service) =>
      statusOf(service) == ServiceStatus.ready;

  /// Why [service] failed, or null when it did not (or has not yet).
  @visibleForTesting
  String? errorOf(ShellService service) => _errors[service];

  /// Starts [task] for [service] and settles the status when it finishes.
  ///
  /// The task is started on its own event-loop turn rather than immediately or
  /// on a microtask. A task that does its work synchronously before its first
  /// `await` — the application index is thousands of FFI round-trips with no
  /// suspension point in them — would otherwise hold the isolate through every
  /// other task registered beside it, and the engine would never get a frame in
  /// edgewise. One turn each lets the cheap ones get their I/O in flight first.
  ///
  /// Never throws: these services all fail soft, so an error is recorded and
  /// printed, and the shell carries on without whatever it provided.
  void run(ShellService service, Future<void> Function() task) {
    if (_started.contains(service)) return;
    _started.add(service);
    unawaited(Future<void>(task).then(
      (_) => _settle(service, ServiceStatus.ready),
      onError: (Object error, StackTrace stack) {
        debugPrint('service: ${service.name} failed to start: $error');
        _settle(service, ServiceStatus.failed, '$error');
      },
    ));
  }

  /// Settles [service] with no work done, because the feature is disabled in
  /// `config.toml`. Nothing is waiting on it, so it is [ServiceStatus.ready]:
  /// "off" and "finished" are the same answer to "should I show a spinner?".
  void skip(ShellService service) {
    if (_started.contains(service)) return;
    _started.add(service);
    _settle(service, ServiceStatus.ready);
  }

  void _settle(ShellService service, ServiceStatus status, [String? error]) {
    _status[service] = status;
    if (error != null) _errors[service] = error;
    notifyListeners();
  }
}

/// Provides [ShellServices] to a window's widget subtree.
///
/// An [InheritedNotifier], so a widget that reads a status through it rebuilds
/// when that status settles without holding a listener of its own.
///
/// Like [ThemeScope] this is installed once per window: an `InheritedWidget`
/// cannot span FlutterViews, and the shell renders into one view per panel per
/// monitor plus a window for every popup and overlay.
class ShellServicesScope extends InheritedNotifier<ShellServices> {
  const ShellServicesScope({
    super.key,
    required ShellServices services,
    required super.child,
  }) : super(notifier: services);

  static ShellServices? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ShellServicesScope>()
      ?.notifier;

  static ShellServices of(BuildContext context) => maybeOf(context)!;

  /// Whether [service] is still starting.
  ///
  /// False when there is no scope above [context] at all, which is the right
  /// answer for a widget test that builds a module on its own: no `main()` ran,
  /// so nothing is pending and the loader would never go away.
  static bool isLoading(BuildContext context, ShellService service) =>
      maybeOf(context)?.isLoading(service) ?? false;
}
