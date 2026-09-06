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

/// The shell's global start-up tasks: the things `main()` used to `await` between
/// the process starting and the first frame reaching the screen.
///
/// Every one is either I/O the shell cannot make faster (a D-Bus name request, a
/// socket connect, a Wayland round-trip) or a walk over the whole system. None is
/// needed to *paint*: panel geometry comes out of `config.toml` and the palette
/// out of `ThemeStore`, both resolved before this list is started.
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

  /// The polkit authentication agent: the registration that lets anything on
  /// the desktop ask for administrator rights at all.
  polkit,

  /// The physical power button: logind's `handle-power-key` inhibitor, taken
  /// once the compositor confirms the shell owns the key.
  power,
}

/// The one place that knows how far along the shell's start-up is.
///
/// `main()` hands each task here instead of awaiting it, so the first frame is
/// gated on nothing but reading `config.toml`. Widgets that need a task's result
/// read its [ServiceStatus] through [ShellServicesScope] and show a loader while
/// it is [ServiceStatus.loading], rather than an empty state indistinguishable
/// from "you have none of these".
///
/// The `ChangeNotifier` shape of the shell's stores, but deliberately *not* a
/// singleton: it is constructed in `main()` and passed down, so a widget test can
/// build one carrying whatever statuses the case needs.
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
  /// The contract with the `start*Service` functions:
  ///
  /// * **Genuine failure throws** — an unreachable bus, a name request that
  ///   errored, an FFI load failure. This method is the catch-all: it records
  ///   [ServiceStatus.failed] with the reason and logs it, so nothing escapes to
  ///   the zone handler and the shell carries on without the service.
  /// * **A graceful decline is not a failure.** Another daemon owning the
  ///   notification or tray name is the shell *yielding* to it, and a feature
  ///   switched off has nothing to do; the task logs and returns normally,
  ///   settling [ServiceStatus.ready] — "declined" and "finished" are the same
  ///   answer to "should I show a spinner?".
  ///
  /// A service that swallows its own genuine failures makes
  /// [ServiceStatus.failed] unreachable and its loader resolve to "ready" with
  /// the feature dead, which is the lie this contract exists to prevent.
  ///
  /// The task is started on its own event-loop turn: one that works synchronously
  /// before its first `await` — the application index is thousands of FFI
  /// round-trips with no suspension point — would otherwise hold the isolate
  /// through every other task registered beside it.
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
/// An [InheritedNotifier], so a widget reading a status through it rebuilds when
/// that status settles without holding a listener of its own.
///
/// Like [ThemeScope] this is installed once per window: an `InheritedWidget`
/// cannot span FlutterViews.
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
