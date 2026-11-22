import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:moonswing/native/ffi_util.dart';
import 'package:moonswing/app_info.dart';
import 'package:moonswing/launcher/app_search.dart';

/// The process-wide list of installed applications, kept warm for the launcher.
///
/// `loadInstalledApps()` is thousands of FFI round-trips: a `g_app_info_get_all`
/// walk plus, per entry, the id, name, icon, categories, keywords and actions,
/// each with a UTF-8 decode. The launcher has to paint the instant its shortcut
/// fires, so the cost is paid once at start-up — and **off the UI isolate**
/// ([loadInstalledAppsInBackground]), because on it the walk held every panel's
/// frame for as long as it took. Until the first list lands [apps] is empty and
/// `ShellService.applications` is loading, which is what the launcher and the
/// choosers show a loader on; nothing else waits for it.
///
/// The singleton-`ChangeNotifier` shape. Notifies when a list lands, the first
/// one included.
///
/// The entries here are deliberately *not* shared with
/// `modules/app_directory.dart`: that widget unrefs its own list in `dispose`,
/// and unref'ing pointers this index still holds would make the next launch a
/// use-after-free. Two lists of the same `GAppInfo*`s is a few hundred extra refs.
class AppIndex extends ChangeNotifier {
  AppIndex._(this._load);

  static final AppIndex instance = AppIndex._(loadInstalledAppsInBackground);

  /// An index over [load] instead of GIO, and with no monitor: tests drive
  /// [applicationsChanged] themselves.
  @visibleForTesting
  factory AppIndex.forTesting({
    Future<List<AppEntry>> Function()? load,
    void Function(Iterable<AppEntry>)? dispose,
  }) =>
      AppIndex._(load ?? () async => const <AppEntry>[])
        .._dispose = dispose ?? ((_) {})
        .._monitored = true;

  final Future<List<AppEntry>> Function() _load;
  void Function(Iterable<AppEntry>) _dispose = disposeAppEntries;

  List<AppEntry> _apps = const [];
  List<SearchableApp> _searchable = const [];
  _AppInfoMonitor? _monitor;
  bool _monitored = false;
  bool _loaded = false;
  bool _inUse = false;

  /// The walk in flight, if any; a change reported during it marks it stale.
  Future<void>? _loading;
  bool _stale = false;

  /// A list that landed while [acquire]d, applied on [release].
  List<AppEntry>? _parked;

  /// Every installed application that should be shown, sorted by name. Empty
  /// until the first list lands.
  List<AppEntry> get apps => _apps;

  /// The same list with its searchable text pre-folded, for [rankApps].
  List<SearchableApp> get searchable => _searchable;

  /// Builds the index and starts watching for applications being installed or
  /// removed. Completes once the first list has landed; safe to call more than
  /// once. Throws if that first walk fails, so `ShellService.applications`
  /// settles `failed` rather than "ready" over an empty list; a later walk that
  /// fails is logged and leaves the last good list in place.
  Future<void> start() {
    // A missing GAppInfoMonitor just means the index is only as fresh as the
    // last rebuild; nothing else changes. Connected on this isolate: its
    // signal is delivered on the GTK main loop, where the callback lives.
    if (!_monitored) {
      _monitored = true;
      _monitor = _AppInfoMonitor(applicationsChanged);
    }
    if (_loaded) return Future<void>.value();
    return _rebuild();
  }

  /// Marks the index as being read from — while this is true a new list is
  /// held back, because the launcher's rows hold `GAppInfo*`s that swapping
  /// would unref out from under them.
  void acquire() => _inUse = true;

  /// Releases the read lock taken by [acquire] and applies any list that
  /// arrived meanwhile.
  void release() {
    _inUse = false;
    final parked = _parked;
    _parked = null;
    if (parked != null) _swap(parked);
  }

  /// GIO reported an application installed or removed (or a default changed).
  @visibleForTesting
  void applicationsChanged() =>
      // Logged in [_walk]; the last good list stays.
      unawaited(_rebuild().catchError((Object _) {}));

  Future<void> _rebuild() {
    if (_loading != null) {
      // Whatever the walk in flight read may predate this change.
      _stale = true;
      return _loading!;
    }
    return _loading = _walk().whenComplete(() => _loading = null);
  }

  Future<void> _walk() async {
    while (true) {
      _stale = false;
      final List<AppEntry> fresh;
      try {
        fresh = await _load();
      } catch (error) {
        debugPrint('app-index: could not enumerate applications: $error');
        if (!_loaded) rethrow;
        return;
      }
      if (_stale) {
        _dispose(fresh);
        continue;
      }
      if (_inUse) {
        final previous = _parked;
        if (previous != null) _dispose(previous);
        _parked = fresh;
        return;
      }
      _swap(fresh);
      return;
    }
  }

  void _swap(List<AppEntry> fresh) {
    final previous = _apps;
    _apps = fresh;
    _searchable = [for (final app in fresh) SearchableApp(app)];
    _loaded = true;
    // Only once nothing points at the old list.
    _dispose(previous);
    notifyListeners();
  }

  @override
  void dispose() {
    _monitor?.dispose();
    super.dispose();
  }
}

/// Builds the index at start-up, off the UI isolate. Completes when the first
/// list has landed, which is what settles `ShellService.applications`.
Future<void> startAppIndexService() => AppIndex.instance.start();

// ---------------------------------------------------------------------------
// GAppInfoMonitor
// ---------------------------------------------------------------------------

typedef _GAppInfoMonitorGetC = ffi.Pointer<ffi.Void> Function();
typedef _GAppInfoMonitorGetDart = ffi.Pointer<ffi.Void> Function();

/// Watches GIO for applications being installed or removed.
///
/// [MonitorWatcher]'s shape: symbols come from the running process (GIO is
/// already linked in), and the callback is `isolateLocal` because GLib invokes it
/// on the thread-default main context — which, since `g_app_info_monitor_get`
/// runs on the platform thread, is the GTK main loop.
class _AppInfoMonitor {
  _AppInfoMonitor(this.onChanged) {
    try {
      final monitorGet = processLibrary
          .lookupFunction<_GAppInfoMonitorGetC, _GAppInfoMonitorGetDart>(
              'g_app_info_monitor_get');
      final signalConnect = gSignalConnectData;

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
