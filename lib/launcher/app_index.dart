import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/launcher/app_search.dart';

/// The process-wide list of installed applications, kept warm for the launcher.
///
/// `loadInstalledApps()` is thousands of FFI round-trips on the UI isolate: a
/// `g_app_info_get_all` walk plus, per entry, the id, name, icon, categories,
/// keywords, and actions, each with a UTF-8 decode. That is invisible behind a
/// deliberate mouse click (which is why the dock's app directory just calls it
/// in `initState`), but the launcher has to paint the instant the shortcut
/// fires, so the cost is paid once at start-up instead.
///
/// Same singleton-`ChangeNotifier` shape as `OsdStore`/`TrayStore`.
///
/// The entries here are deliberately *not* shared with
/// `modules/app_directory.dart`: that widget unrefs its own list in `dispose`,
/// and unref'ing pointers this index still holds would make the next launch a
/// use-after-free. Two lists of the same `GAppInfo*`s is a few hundred extra
/// refs, which is nothing.
class AppIndex extends ChangeNotifier {
  AppIndex._();

  static final AppIndex instance = AppIndex._();

  @visibleForTesting
  factory AppIndex.forTesting() => AppIndex._();

  List<AppEntry> _apps = const [];
  List<SearchableApp> _searchable = const [];
  _AppInfoMonitor? _monitor;
  bool _refreshDeferred = false;
  bool _inUse = false;

  /// Every installed application that should be shown, sorted by name.
  List<AppEntry> get apps => _apps;

  /// The same list with its searchable text pre-folded, for [rankApps].
  List<SearchableApp> get searchable => _searchable;

  /// Builds the index and starts watching for applications being installed or
  /// removed. Safe to call more than once.
  void start() {
    if (_apps.isEmpty) _rebuild();
    // A missing GAppInfoMonitor just means the index is only as fresh as the
    // last rebuild; nothing else changes.
    _monitor ??= _AppInfoMonitor(_onApplicationsChanged);
  }

  /// Marks the index as being read from — while this is true a refresh is
  /// deferred, because the launcher's rows hold `GAppInfo*`s that a rebuild
  /// would unref out from under them.
  void acquire() => _inUse = true;

  /// Releases the read lock taken by [acquire] and applies any refresh that
  /// arrived meanwhile.
  void release() {
    _inUse = false;
    if (_refreshDeferred) {
      _refreshDeferred = false;
      _rebuild();
      notifyListeners();
    }
  }

  void _onApplicationsChanged() {
    if (_inUse) {
      _refreshDeferred = true;
      return;
    }
    _rebuild();
    notifyListeners();
  }

  void _rebuild() {
    final previous = _apps;
    try {
      _apps = loadInstalledApps();
    } catch (error) {
      debugPrint('app-index: could not enumerate applications: $error');
      return;
    }
    _searchable = [for (final app in _apps) SearchableApp(app)];
    // Only once nothing points at the old list.
    disposeAppEntries(previous);
  }
}

/// Builds the index at start-up. Called from `main()` beside the other
/// `start*Service` calls; the first read then costs nothing.
void startAppIndexService() => AppIndex.instance.start();

// ---------------------------------------------------------------------------
// GAppInfoMonitor
// ---------------------------------------------------------------------------

final ffi.DynamicLibrary _process = ffi.DynamicLibrary.process();

typedef _GAppInfoMonitorGetC = ffi.Pointer<ffi.Void> Function();
typedef _GAppInfoMonitorGetDart = ffi.Pointer<ffi.Void> Function();

typedef _GSignalConnectDataC = ffi.Uint64 Function(
  ffi.Pointer<ffi.Void> instance,
  ffi.Pointer<Utf8> detailedSignal,
  ffi.Pointer<ffi.Void> handler,
  ffi.Pointer<ffi.Void> data,
  ffi.Pointer<ffi.Void> destroyData,
  ffi.Uint32 connectFlags,
);
typedef _GSignalConnectDataDart = int Function(
  ffi.Pointer<ffi.Void> instance,
  ffi.Pointer<Utf8> detailedSignal,
  ffi.Pointer<ffi.Void> handler,
  ffi.Pointer<ffi.Void> data,
  ffi.Pointer<ffi.Void> destroyData,
  int connectFlags,
);

/// Watches GIO for applications being installed or removed.
///
/// Same shape as [MonitorWatcher]: symbols come from the running process (GIO
/// is already linked in), the callback is `isolateLocal` because GLib invokes
/// it on the thread-default main context — which, since `g_app_info_monitor_get`
/// runs on the platform thread, is the GTK main loop.
class _AppInfoMonitor {
  _AppInfoMonitor(this.onChanged) {
    try {
      final monitorGet =
          _process.lookupFunction<_GAppInfoMonitorGetC, _GAppInfoMonitorGetDart>(
              'g_app_info_monitor_get');
      final signalConnect =
          _process.lookupFunction<_GSignalConnectDataC, _GSignalConnectDataDart>(
              'g_signal_connect_data');

      final monitor = monitorGet();
      if (monitor.address == 0) return;

      // void handler(GAppInfoMonitor*, gpointer user_data)
      _callback = ffi.NativeCallable<
          ffi.Void Function(ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Void>)>.isolateLocal(_onSignal);

      _signalName = 'changed'.toNativeUtf8();
      signalConnect(
        monitor,
        _signalName!,
        _callback!.nativeFunction.cast(),
        ffi.nullptr,
        ffi.nullptr,
        0,
      );
    } catch (error) {
      // No GAppInfoMonitor on this build — the index simply stops being live.
      debugPrint('app-index: no live application monitoring: $error');
      dispose();
    }
  }

  final void Function() onChanged;

  ffi.NativeCallable<
      ffi.Void Function(
          ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)>? _callback;
  ffi.Pointer<Utf8>? _signalName;

  void _onSignal(ffi.Pointer<ffi.Void> monitor, ffi.Pointer<ffi.Void> userData) {
    onChanged();
  }

  void dispose() {
    _callback?.close();
    _callback = null;
    final name = _signalName;
    if (name != null) malloc.free(name);
    _signalName = null;
  }
}
