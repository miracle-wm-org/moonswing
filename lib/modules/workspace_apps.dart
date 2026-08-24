// What is open on each workspace, for the workspace row's app icons.
//
// The bar module ([modules/workspaces.dart]) renders this; nothing here imports
// Flutter beyond `ChangeNotifier`, so the tree walk and the identity matching
// are plain unit tests.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/config_reader.dart';
import 'package:graceful_shell/launcher/app_index.dart';
import 'package:miracle/miracle.dart';

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

class WorkspacesConfig {
  const WorkspacesConfig({
    this.showAppIcons = true,
    this.iconSize = 14,
    this.maxIcons = 4,
    this.pollSeconds = 3,
  });

  /// Whether each workspace button carries the icons of the applications open
  /// on it. On by default.
  ///
  /// The buttons then size to their contents, so a workspace holding three
  /// windows is wider than an empty one — see `_WorkspaceButton`, whose square
  /// 16px box became a *minimum* for this.
  final bool showAppIcons;

  /// Rendered icon width/height, in logical pixels.
  final int iconSize;

  /// How many icons one button shows before collapsing the rest into a `+N`.
  /// Without a cap a workspace with a dozen windows takes the whole bar.
  final int maxIcons;

  /// Cadence of the window-tree poll, in seconds.
  ///
  /// A poll, rather than an event subscription, because `miracle.dart`'s
  /// `Event.fromJson` throws `UnsupportedError` for every event type but
  /// `workspace` — see [WorkspaceAppsStore]. Only paid while
  /// [showAppIcons] is on and a bar is on screen.
  final int pollSeconds;

  factory WorkspacesConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const WorkspacesConfig();
    return WorkspacesConfig(
      showAppIcons: map.boolOr('show_app_icons', true),
      iconSize: map.intOr('icon_size', 14, min: 8, max: 64),
      maxIcons: map.intOr('max_icons', 4, min: 1, max: 16),
      pollSeconds: map.intOr('poll_seconds', 3, min: 1, max: 60),
    );
  }
}

// ---------------------------------------------------------------------------
// The tree walk (pure)
// ---------------------------------------------------------------------------

/// The applications open on one workspace of the window tree.
///
/// Identity is carried three ways because [WorkspaceResult] — what the row
/// actually renders — spells it differently from [WorkspaceNode]: `num` and
/// `name` are both nullable there and both non-null here.
@immutable
class WorkspaceApps {
  const WorkspaceApps({
    required this.output,
    required this.num,
    required this.name,
    required this.appIds,
  });

  final String output;
  final int num;
  final String name;

  /// The distinct `app_id`s on the workspace, in tree order.
  ///
  /// Distinct rather than one per window: this is a bar dot, and two Firefox
  /// windows saying "Firefox" twice costs the width of an icon to say nothing.
  final List<String> appIds;
}

/// The `app_id` of [node], or null when it is a split container rather than a
/// window.
///
/// XWayland toplevels carry no `app_id` at all; `window_properties` is where
/// their WM class arrives, and it is the same string `StartupWMClass=` names.
String? containerAppId(ContainerNode node) {
  final appId = node.appId;
  if (appId != null && appId.isNotEmpty) return appId;
  for (final key in const ['class', 'instance']) {
    final value = node.windowProperties[key];
    if (value is String && value.isNotEmpty) return value;
  }
  return null;
}

/// Walks a `GET_TREE` reply into one [WorkspaceApps] per workspace.
List<WorkspaceApps> collectWorkspaceApps(BaseNode tree) {
  final result = <WorkspaceApps>[];

  void collect(BaseNode node, List<String> into) {
    if (node is! ContainerNode) return;
    final appId = containerAppId(node);
    if (appId != null && !into.contains(appId)) into.add(appId);
    // A window is a leaf in practice, but descending unconditionally is what
    // makes a nested split under a floating container reachable.
    for (final child in node.nodes) {
      collect(child, into);
    }
    for (final child in node.floatingNodes) {
      collect(child, into);
    }
  }

  void descend(BaseNode node) {
    switch (node) {
      case WorkspaceNode():
        final appIds = <String>[];
        for (final child in node.nodes) {
          collect(child, appIds);
        }
        for (final child in node.floatingNodes) {
          collect(child, appIds);
        }
        result.add(WorkspaceApps(
          output: node.output,
          num: node.num,
          name: node.name,
          appIds: appIds,
        ));
      case RootNode():
        node.nodes.forEach(descend);
      case OutputNode():
        node.nodes.forEach(descend);
      case ContainerNode():
        break;
    }
  }

  descend(tree);
  return result;
}

/// The `app_id`s on the workspace [workspace] names, or empty.
///
/// Two passes, so a name match on the right output always beats a number
/// match: miracle reports a named workspace's `num` as a placeholder, and
/// several of those on one output would otherwise collide.
List<String> appIdsForWorkspace(
  List<WorkspaceApps> apps,
  WorkspaceResult workspace,
) {
  final name = workspace.name;
  if (name != null && name.isNotEmpty) {
    for (final entry in apps) {
      if (entry.output == workspace.output && entry.name == name) {
        return entry.appIds;
      }
    }
  }
  final number = workspace.num;
  if (number != null) {
    for (final entry in apps) {
      if (entry.output == workspace.output && entry.num == number) {
        return entry.appIds;
      }
    }
  }
  return const [];
}

// ---------------------------------------------------------------------------
// Store
// ---------------------------------------------------------------------------

/// What [WorkspaceAppsStore] needs from a Miracle connection, behind a seam a
/// test can satisfy without a socket.
///
/// [token] is the identity the store compares on, because a
/// [MiracleConnection] is single-use and every reconnect hands the bars a
/// different instance.
@immutable
class WorkspaceTreeSource {
  const WorkspaceTreeSource({
    required this.token,
    required this.getTree,
    required this.events,
  });

  factory WorkspaceTreeSource.of(MiracleConnection connection) =>
      WorkspaceTreeSource(
        token: connection,
        getTree: connection.getTree,
        // MiracleConnection *is* the event stream.
        events: connection,
      );

  final Object token;
  final Future<BaseNode> Function() getTree;
  final Stream<Event> events;
}

/// The window tree, reduced to "which applications are on which workspace",
/// for every bar on the machine.
///
/// Same singleton-`ChangeNotifier` shape as `OsdStore`/`TrayStore`, with
/// `SystemStatsStore`'s lease rule: the `GET_TREE` round-trip runs only while
/// at least one workspace row is on screen *and* has its icons switched on, so
/// a two-monitor setup shares one poller and a shell with the feature off pays
/// nothing at all.
///
/// **It polls, and that is forced rather than chosen.** The obvious source is
/// `SubscriptionType.window`, and it is unusable: `miracle.dart`'s
/// `Event.fromJson` throws `UnsupportedError` for every type but `workspace`,
/// from inside the socket's own data handler — which skips the `_buffer.clear()`
/// after it, so the same message re-parses and re-throws on every subsequent
/// read and the shell's one IPC connection is wedged for good. (This is the
/// same reason `MiracleManager` documents for not subscribing to
/// `SubscriptionType.output`.) The workspace events the shell *does* subscribe
/// to are still used — they cover a workspace appearing, emptying or being
/// switched to, which is most of what moves — and the timer covers the rest: a
/// window opening on a workspace that already had one emits nothing.
///
/// Two things a change here has to keep true:
///
/// - **A poll that finds nothing new must not notify.** This wakes on a timer,
///   and every panel on every monitor listens; re-laying every bar every few
///   seconds to redraw the same icons is the cost this store would otherwise
///   impose on an idle machine. [_publish] compares a signature and returns.
/// - **A tree that will not parse costs the icons, never the row.**
///   `miracle.dart`'s node parsers cast their fields unconditionally, so one
///   unexpected node type takes the whole reply down. That is an adornment
///   failing, and the workspace buttons must still render and still switch.
class WorkspaceAppsStore extends ChangeNotifier {
  WorkspaceAppsStore._();

  static final WorkspaceAppsStore instance = WorkspaceAppsStore._();

  @visibleForTesting
  factory WorkspaceAppsStore.forTesting() => WorkspaceAppsStore._();

  WorkspacesConfig _config = const WorkspacesConfig();
  WorkspaceTreeSource? _source;
  StreamSubscription<Event>? _events;
  Timer? _timer;
  int _leases = 0;

  /// A `GET_TREE` is a socket round-trip; a tick that arrives while the last
  /// one is still in flight is dropped, not queued behind it.
  bool _fetchInFlight = false;

  List<WorkspaceApps> _apps = const [];
  String _signature = '';

  final _AppIconCache _icons = _AppIconCache();

  /// Whether anything is holding a lease — the bar reads this to tell "no
  /// windows" from "not asked yet".
  bool get active => _leases > 0;

  List<WorkspaceApps> get apps => _apps;

  /// The `app_id`s on [workspace], or empty.
  List<String> appIdsFor(WorkspaceResult workspace) =>
      appIdsForWorkspace(_apps, workspace);

  /// How [appId] should be drawn. Memoised, because this runs per icon per
  /// build and each miss is a GIO lookup.
  WorkspaceAppIcon iconFor(String appId) => _icons.lookup(appId);

  /// Applies [config]; the module widget pushes it from `initState`. A cadence
  /// change while leased restarts the timer at the new interval.
  void configure(WorkspacesConfig config) {
    final cadenceChanged = config.pollSeconds != _config.pollSeconds;
    _config = config;
    if (cadenceChanged && _timer != null) {
      _stopTimer();
      _startTimer();
    }
  }

  /// Points the store at the shell's current Miracle connection, or at nothing.
  void attach(MiracleConnection? connection) => attachSource(
      connection == null ? null : WorkspaceTreeSource.of(connection));

  @visibleForTesting
  void attachSource(WorkspaceTreeSource? source) {
    if (identical(source?.token, _source?.token)) return;

    _events?.cancel();
    _events = null;
    _source = source;
    // Cleared without notifying: `attachSource` is reached from the module's
    // `didChangeDependencies`, which runs during build, and a notify from
    // there is a `setState` in the build phase.
    _apps = const [];
    _signature = '';

    if (source == null) return;
    _events = source.events.listen((event) {
      // The shell subscribes to workspace events already; they cover a
      // workspace appearing, emptying, or being switched to.
      if (event is EventWorkspace) unawaited(_fetch());
    });
    if (_leases > 0) unawaited(_fetch());
  }

  /// Takes a lease. The first one starts the poll and fetches immediately, so
  /// a bar never waits an interval for its first set of icons.
  void acquire() {
    _leases++;
    if (_timer == null) {
      AppIndex.instance.addListener(_onApplicationsChanged);
      _startTimer();
      unawaited(_fetch());
    }
  }

  void release() {
    if (_leases > 0) _leases--;
    if (_leases == 0) {
      AppIndex.instance.removeListener(_onApplicationsChanged);
      _stopTimer();
    }
  }

  /// An install or a removal can change what an `app_id` resolves to, and the
  /// cache is keyed on the `app_id` alone.
  void _onApplicationsChanged() => _icons.clear();

  void _startTimer() {
    _timer = Timer.periodic(
      Duration(seconds: _config.pollSeconds),
      (_) => unawaited(_fetch()),
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _fetch() async {
    final source = _source;
    // The lease is checked *before* the round-trip as well as after it: this is
    // reached from the workspace-event listener, which is attached whether or
    // not anybody is drawing icons, and a shell with `show_app_icons = false`
    // must open no GET_TREE at all.
    if (source == null || _leases == 0 || _fetchInFlight) return;
    _fetchInFlight = true;
    try {
      final tree = await source.getTree();
      // A release, or a reconnect, can land while the round-trip is in flight.
      if (_leases == 0 || !identical(_source?.token, source.token)) return;
      _publish(collectWorkspaceApps(tree));
    } catch (error) {
      debugPrint('workspaces: could not read the window tree: $error');
    } finally {
      _fetchInFlight = false;
    }
  }

  void _publish(List<WorkspaceApps> apps) {
    final signature = apps
        .map((a) => '${a.output}\u0000${a.num}\u0000${a.name}'
            '\u0000${a.appIds.join('\u0001')}')
        .join('\u0002');
    if (signature == _signature) return;
    _signature = signature;
    _apps = apps;
    notifyListeners();
  }

  @override
  void dispose() {
    _events?.cancel();
    if (_leases > 0) AppIndex.instance.removeListener(_onApplicationsChanged);
    _leases = 0;
    _stopTimer();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// app_id -> icon
// ---------------------------------------------------------------------------

/// How one `app_id` is drawn: a GIO icon name for [AppIconImage], and the
/// display name behind its first-letter fallback.
@immutable
class WorkspaceAppIcon {
  const WorkspaceAppIcon({required this.iconName, required this.name});

  final String iconName;
  final String name;
}

/// Resolves compositor `app_id`s to installed applications, once each.
///
/// Deliberately keeps *strings*, never the [AppEntry] they came from: an entry
/// out of [AppIndex] holds a `GAppInfo*` the index unrefs on its next rebuild,
/// and one out of [loadAppById] is ours to dispose. Copying the two fields the
/// row draws makes both lifetimes somebody else's problem.
class _AppIconCache {
  final Map<String, WorkspaceAppIcon> _entries = {};

  void clear() => _entries.clear();

  WorkspaceAppIcon lookup(String appId) =>
      _entries[appId] ??= _resolve(appId);

  WorkspaceAppIcon _resolve(String appId) {
    // A Wayland `app_id` is usually the desktop-file id verbatim, and often
    // differs only in case.
    final direct = _byDesktopId(appId) ??
        (appId == appId.toLowerCase() ? null : _byDesktopId(appId.toLowerCase()));
    if (direct != null) return direct;

    final indexed = _byIndex(appId);
    if (indexed != null) return indexed;

    // Unresolved is not the same as unrenderable: icon themes name a great
    // many icons exactly as the app_id, so hand it to XdgIcon anyway and let
    // AppIconImage's first-letter fallback answer if it is not there either.
    return WorkspaceAppIcon(iconName: appId, name: appId);
  }

  WorkspaceAppIcon? _byDesktopId(String id) {
    try {
      final entry = loadAppById(id);
      if (entry == null) return null;
      final icon =
          WorkspaceAppIcon(iconName: entry.iconName, name: entry.name);
      // Read and released in the same breath — nothing outlives this call.
      disposeAppEntries([entry]);
      return icon;
    } catch (_) {
      // No GLib in this process (flutter_tester links none).
      return null;
    }
  }

  WorkspaceAppIcon? _byIndex(String appId) {
    final wanted = appId.toLowerCase();
    try {
      final apps = AppIndex.instance.apps;
      // `StartupWMClass=` is the entry declaring this very mapping, so it wins
      // outright over any spelling heuristic.
      for (final entry in apps) {
        if (entry.startupWmClass.isNotEmpty &&
            entry.startupWmClass.toLowerCase() == wanted) {
          return WorkspaceAppIcon(iconName: entry.iconName, name: entry.name);
        }
      }
      final tail = _lastSegment(wanted);
      for (final entry in apps) {
        final id = entry.id.toLowerCase();
        if (id == wanted || _lastSegment(id) == tail) {
          return WorkspaceAppIcon(iconName: entry.iconName, name: entry.name);
        }
      }
    } catch (_) {
      // Same as above: an index that could not be built is simply empty.
    }
    return null;
  }

  /// `org.gnome.nautilus` -> `nautilus`; anything undotted is its own tail.
  static String _lastSegment(String id) {
    final dot = id.lastIndexOf('.');
    return dot < 0 || dot == id.length - 1 ? id : id.substring(dot + 1);
  }
}
