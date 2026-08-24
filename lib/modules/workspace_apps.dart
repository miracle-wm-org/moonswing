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

  factory WorkspacesConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const WorkspacesConfig();
    return WorkspacesConfig(
      showAppIcons: map.boolOr('show_app_icons', true),
      iconSize: map.intOr('icon_size', 14, min: 8, max: 64),
      maxIcons: map.intOr('max_icons', 4, min: 1, max: 16),
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
///
/// Deliberately not `ContainerNode.isWindow`, which the library defines as
/// `window != null` — that is the *X11* window id, so under a Wayland
/// compositor it is null for very nearly everything on screen.
String? containerAppId(ContainerNode node) =>
    _nonEmpty(node.appId) ??
    _nonEmpty(node.windowProperties.className) ??
    _nonEmpty(node.windowProperties.instance);

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;

/// Walks a `GET_TREE` reply into one [WorkspaceApps] per workspace.
///
/// The traversal is `miracle.dart`'s own (`BaseNode.workspaces`, which is
/// `walk().whereType()`, and `descendants`, which covers tiled and floating
/// children alike), so nothing here has to know the shape of the tree.
List<WorkspaceApps> collectWorkspaceApps(BaseNode tree) => [
      for (final workspace in tree.workspaces)
        WorkspaceApps(
          output: workspace.output,
          num: workspace.num,
          name: workspace.name,
          // A set, because two Firefox windows are one icon; it is a
          // LinkedHashSet, so tree order survives.
          appIds: <String>{
            for (final node in workspace.descendants.whereType<ContainerNode>())
              ?containerAppId(node),
          }.toList(),
        ),
    ];

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

/// Whether [event] can have changed which applications are on which workspace.
///
/// The filter is the point of the event-driven design rather than an
/// optimisation on top of it: `window` fires on every focus change, so an
/// unfiltered listener would re-read the whole window tree on each alt-tab.
/// The switch over [WindowChange] is exhaustive so that a change miracle.dart
/// grows later forces a decision here rather than being silently ignored.
@visibleForTesting
bool wakesWorkspaceApps(Event event) => switch (event) {
      // A workspace being created, emptied, renamed, moved to another output,
      // or switched to.
      WorkspaceEvent() => true,
      // miracle never says *which* output changed, and a removed one has its
      // workspaces re-homed onto another with no workspace event of its own —
      // which is exactly what `MiracleManager.outputsRevision` used to stand in
      // for, back when this event could not be decoded.
      OutputEvent() => true,
      WindowEvent(:final change) => switch (change) {
          WindowChange.created ||
          WindowChange.closed ||
          WindowChange.moved =>
            true,
          // None of these move a window between workspaces, and `focused`
          // alone fires on every alt-tab.
          WindowChange.focused ||
          WindowChange.fullscreenMode ||
          WindowChange.floating ||
          WindowChange.marked =>
            false,
          // A change this package does not model yet: re-read rather than go
          // quietly stale.
          WindowChange.unknown => true,
        },
      _ => false,
    };

/// The window tree, reduced to "which applications are on which workspace",
/// for every bar on the machine.
///
/// Same singleton-`ChangeNotifier` shape as `OsdStore`/`TrayStore`, with
/// `SystemStatsStore`'s lease rule: the `GET_TREE` round-trip runs only while
/// at least one workspace row is on screen *and* has its icons switched on, so
/// a two-monitor setup shares one reader and a shell with the feature off pays
/// nothing at all.
///
/// **It is driven by events, and never by a timer.** miracle.dart 2.0 decodes
/// `window` and `output` events (before it, every event type but `workspace`
/// threw an `UnsupportedError` from inside the socket's own data handler, which
/// tore down the stream — so this store polled instead, and `MiracleManager`
/// could not subscribe to `output` at all). [wakesWorkspaceApps] is the filter.
///
/// Three things a change here has to keep true:
///
/// - **A fetch that arrives mid-flight is coalesced, not dropped.** With no
///   timer behind this, a discarded refetch leaves the row stale until the next
///   unrelated event — and opening three windows in a burst is three events
///   over one round-trip.
/// - **A read that finds nothing new must not notify.** Every panel on every
///   monitor listens, so re-laying every bar to redraw identical icons is the
///   cost this would otherwise impose. [_publish] compares a signature.
/// - **A tree that will not parse costs the icons, never the row.** That is an
///   adornment failing, and the workspace buttons must still render and still
///   switch.
class WorkspaceAppsStore extends ChangeNotifier {
  WorkspaceAppsStore._();

  static final WorkspaceAppsStore instance = WorkspaceAppsStore._();

  @visibleForTesting
  factory WorkspaceAppsStore.forTesting() => WorkspaceAppsStore._();

  WorkspaceTreeSource? _source;
  StreamSubscription<Event>? _events;
  int _leases = 0;

  /// A `GET_TREE` is a socket round-trip; a request that lands while one is
  /// still in flight sets [_fetchQueued] rather than starting a second.
  bool _fetchInFlight = false;
  bool _fetchQueued = false;

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
    _events = source.events.listen(
      (event) {
        if (wakesWorkspaceApps(event)) unawaited(_fetch());
      },
      // miracle.dart 2.0 reports an undecodable payload as a stream error
      // rather than killing the stream; an event we cannot read is one refetch
      // we do not make, and nothing more.
      onError: (Object error) =>
          debugPrint('workspaces: undecodable IPC event: $error'),
    );
    if (_leases > 0) unawaited(_fetch());
  }

  /// Takes a lease. The first one reads immediately, so a bar never waits for
  /// the user to move a window before its icons appear.
  void acquire() {
    _leases++;
    if (_leases == 1) {
      AppIndex.instance.addListener(_onApplicationsChanged);
      unawaited(_fetch());
    }
  }

  void release() {
    if (_leases > 0) _leases--;
    if (_leases == 0) AppIndex.instance.removeListener(_onApplicationsChanged);
  }

  /// An install or a removal can change what an `app_id` resolves to, and the
  /// cache is keyed on the `app_id` alone.
  void _onApplicationsChanged() => _icons.clear();

  Future<void> _fetch() async {
    if (_fetchInFlight) {
      _fetchQueued = true;
      return;
    }
    _fetchInFlight = true;
    try {
      do {
        _fetchQueued = false;
        final source = _source;
        // The lease is checked *before* the round-trip as well as after it: the
        // event listener is attached whether or not anybody is drawing icons,
        // and a shell with `show_app_icons = false` must open no GET_TREE.
        if (source == null || _leases == 0) return;
        try {
          final tree = await source.getTree();
          // A release, or a reconnect, can land while the round-trip is in
          // flight.
          if (_leases == 0 || !identical(_source?.token, source.token)) return;
          _publish(collectWorkspaceApps(tree));
        } catch (error) {
          debugPrint('workspaces: could not read the window tree: $error');
        }
      } while (_fetchQueued);
    } finally {
      _fetchInFlight = false;
      _fetchQueued = false;
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
