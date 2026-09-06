import 'dart:async';
import 'dart:io' show pid;

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:graceful_shell/dbus_menu.dart';
import 'package:graceful_shell/dbus_service_object.dart';

/// StatusNotifierItem (SNI) system-tray support.
///
/// This file makes the shell act as both a `StatusNotifierWatcher` (the registry
/// every tray application looks for) and a `StatusNotifierHost` (the consumer
/// that displays the items). Registered items are tracked, their
/// icon/title/status/menu properties kept live via the item's change signals, and
/// the current set published through [TrayStore].
///
/// Mirrors the server pattern in `notification_service.dart` and the remote
/// object tracking pattern in `modules/media_player.dart`.

const String _watcherInterface = 'org.kde.StatusNotifierWatcher';
const String _watcherPath = '/StatusNotifierWatcher';
const String _itemInterface = 'org.kde.StatusNotifierItem';

/// Session bus client shared by the watcher and the UI helper functions
/// ([fetchTrayMenu], [activateTrayItem], [sendTrayMenuClick]). Set once by
/// [startStatusNotifierService].
DBusClient? _sessionClient;

/// A tray icon delivered as raw ARGB32 pixels (SNI `IconPixmap`, `a(iiay)`).
///
/// The bytes are in network byte order (big-endian ARGB per pixel); the UI
/// converts them to RGBA when building a Flutter image.
class TrayIconPixmap {
  const TrayIconPixmap(this.width, this.height, this.bytes);
  final int width;
  final int height;
  final Uint8List bytes;
}

/// Immutable snapshot of one registered StatusNotifierItem.
class TrayItem {
  const TrayItem({
    required this.busName,
    required this.objectPath,
    required this.id,
    required this.title,
    required this.status,
    required this.iconName,
    required this.iconPixmap,
    required this.tooltip,
    required this.menuPath,
    required this.itemIsMenu,
  });

  /// D-Bus name owning the item; also this item's identity key.
  final String busName;

  /// Object path of the `org.kde.StatusNotifierItem` object.
  final DBusObjectPath objectPath;

  /// Application-provided `Id` (stable across restarts; used for `hidden_items`).
  final String id;

  /// Human-readable title (`Title`), used as a tooltip fallback / hidden match.
  final String title;

  /// `Passive`, `Active`, or `NeedsAttention`.
  final String status;

  /// Themed icon name (`IconName`), or empty when only a pixmap is provided.
  final String iconName;

  /// Raw pixmap icon (`IconPixmap`), or null when a name is provided.
  final TrayIconPixmap? iconPixmap;

  /// Tooltip title text, if any.
  final String tooltip;

  /// Object path of the item's `com.canonical.dbusmenu` menu, if it has one.
  final DBusObjectPath? menuPath;

  /// When true the item prefers to show its menu on activation.
  final bool itemIsMenu;

  TrayItem copyWith({
    String? id,
    String? title,
    String? status,
    String? iconName,
    TrayIconPixmap? iconPixmap,
    bool clearPixmap = false,
    String? tooltip,
    DBusObjectPath? menuPath,
    bool? itemIsMenu,
  }) {
    return TrayItem(
      busName: busName,
      objectPath: objectPath,
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
      iconName: iconName ?? this.iconName,
      iconPixmap: clearPixmap ? null : (iconPixmap ?? this.iconPixmap),
      tooltip: tooltip ?? this.tooltip,
      menuPath: menuPath ?? this.menuPath,
      itemIsMenu: itemIsMenu ?? this.itemIsMenu,
    );
  }
}

/// Singleton [ChangeNotifier] holding the current tray items, consumed by the
/// system-tray panel widget.
class TrayStore extends ChangeNotifier {
  static final TrayStore instance = TrayStore._();
  TrayStore._();

  // Insertion order is preserved so icons keep a stable position.
  final Map<String, TrayItem> _items = {};

  List<TrayItem> get items => List.unmodifiable(_items.values);

  void upsert(TrayItem item) {
    _items[item.busName] = item;
    notifyListeners();
  }

  TrayItem? get(String busName) => _items[busName];

  void remove(String busName) {
    if (_items.remove(busName) != null) notifyListeners();
  }
}

/// Tracks a single registered item: reads its properties and keeps the
/// [TrayStore] entry live by subscribing to the item's change signals.
class _ItemTracker {
  _ItemTracker(DBusClient client,
      {required this.busName, required DBusObjectPath objectPath})
      : _object =
            DBusRemoteObject(client, name: busName, path: objectPath),
        _objectPath = objectPath;

  final String busName;
  final DBusObjectPath _objectPath;
  final DBusRemoteObject _object;
  final List<StreamSubscription<DBusSignal>> _subs = [];

  Future<void> start() async {
    Map<String, DBusValue> props;
    try {
      props = await _object.getAllProperties(_itemInterface);
    } catch (_) {
      // Item vanished before we could read it.
      return;
    }
    TrayStore.instance.upsert(_buildItem(props));

    // The SNI signals carry no useful payload for our purposes, so each just
    // triggers a re-read of the relevant properties.
    for (final signal in const [
      'NewIcon',
      'NewTitle',
      'NewToolTip',
      'NewStatus',
    ]) {
      _subs.add(DBusRemoteObjectSignalStream(
        object: _object,
        interface: _itemInterface,
        name: signal,
      ).listen((_) => _refresh()));
    }
  }

  Future<void> _refresh() async {
    Map<String, DBusValue> props;
    try {
      props = await _object.getAllProperties(_itemInterface);
    } catch (_) {
      return;
    }
    if (TrayStore.instance.get(busName) == null) return;
    TrayStore.instance.upsert(_buildItem(props));
  }

  TrayItem _buildItem(Map<String, DBusValue> props) {
    String str(String key, [String fallback = '']) =>
        props.containsKey(key) ? props[key]!.asString() : fallback;

    DBusObjectPath? menuPath;
    if (props.containsKey('Menu')) {
      try {
        menuPath = props['Menu']!.asObjectPath();
      } catch (_) {}
    }

    return TrayItem(
      busName: busName,
      objectPath: _objectPath,
      id: str('Id'),
      title: str('Title'),
      status: str('Status', 'Active'),
      iconName: str('IconName'),
      iconPixmap: _parsePixmap(props['IconPixmap']),
      tooltip: _parseTooltip(props['ToolTip']),
      menuPath: menuPath,
      itemIsMenu:
          props.containsKey('ItemIsMenu') ? props['ItemIsMenu']!.asBoolean() : false,
    );
  }

  /// Picks the largest pixmap from an `a(iiay)` array.
  static TrayIconPixmap? _parsePixmap(DBusValue? value) {
    if (value == null) return null;
    try {
      final entries = value.asArray();
      TrayIconPixmap? best;
      for (final entry in entries) {
        final parts = entry.asStruct();
        final width = parts[0].asInt32();
        final height = parts[1].asInt32();
        if (width <= 0 || height <= 0) continue;
        if (best != null && width * height <= best.width * best.height) continue;
        final bytes = Uint8List.fromList(parts[2].asByteArray().toList());
        if (bytes.length < width * height * 4) continue;
        best = TrayIconPixmap(width, height, bytes);
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  /// Tooltip signature is `(sa(iiay)ss)` — (icon-name, icon-pixmaps, title,
  /// body). We only surface the title (index 2).
  static String _parseTooltip(DBusValue? value) {
    if (value == null) return '';
    try {
      final parts = value.asStruct();
      if (parts.length >= 3) return parts[2].asString();
    } catch (_) {}
    return '';
  }

  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
  }
}

/// Active item trackers, keyed by the owning bus name. Shared between watcher
/// mode (we own the watcher name) and host-consumer mode (another watcher owns
/// it and we read from it), so the panel shows items either way.
final Map<String, _ItemTracker> _trackers = {};

/// Parses a StatusNotifierItem service string into (busName, objectPath).
///
/// Registrations and watcher item lists come in several shapes: a bare bus name
/// (item at `/StatusNotifierItem`), the KDE `busName/path` form, the GNOME
/// `busName@path` form, or an object path alone (the bus name is then [sender]).
(String, DBusObjectPath) _parseService(String service, String? sender) {
  String busName;
  String path;
  final atIndex = service.indexOf('@');
  if (service.startsWith('/')) {
    busName = sender ?? '';
    path = service;
  } else if (atIndex >= 0) {
    busName = service.substring(0, atIndex);
    path = service.substring(atIndex + 1);
  } else if (service.contains('/')) {
    final idx = service.indexOf('/');
    busName = service.substring(0, idx);
    path = service.substring(idx);
  } else {
    busName = service.isNotEmpty ? service : (sender ?? '');
    path = '/StatusNotifierItem';
  }
  if (!path.startsWith('/')) path = '/StatusNotifierItem';
  return (busName, DBusObjectPath(path));
}

/// Starts tracking an item if not already tracked. Returns true if newly added.
Future<bool> _upsertTracker(
    DBusClient client, String busName, DBusObjectPath path) async {
  if (busName.isEmpty || _trackers.containsKey(busName)) return false;
  final tracker = _ItemTracker(client, busName: busName, objectPath: path);
  _trackers[busName] = tracker;
  await tracker.start();
  return true;
}

/// Stops tracking an item and drops it from the store. Returns true if removed.
bool _removeTracker(String busName) {
  final tracker = _trackers.remove(busName);
  if (tracker == null) return false;
  tracker.dispose();
  TrayStore.instance.remove(busName);
  return true;
}

/// Consumes an existing `org.kde.StatusNotifierWatcher` (e.g. gnome-shell's)
/// as a host: registers as a host, loads the already-registered items, and
/// tracks additions/removals via the watcher's signals.
Future<void> _startHostConsumer(DBusClient client, String hostName) async {
  final watcher = DBusRemoteObject(client,
      name: _watcherInterface, path: DBusObjectPath(_watcherPath));

  // Drop items whose owning connection disappears.
  client.nameOwnerChanged.listen((event) {
    if (event.newOwner == null || event.newOwner!.isEmpty) {
      _removeTracker(event.name);
    }
  });

  // Subscribe before the initial read so nothing registered in between is lost.
  DBusRemoteObjectSignalStream(
    object: watcher,
    interface: _watcherInterface,
    name: 'StatusNotifierItemRegistered',
    signature: DBusSignature('s'),
  ).listen((signal) {
    final (busName, path) = _parseService(signal.values[0].asString(), null);
    _upsertTracker(client, busName, path);
  });
  DBusRemoteObjectSignalStream(
    object: watcher,
    interface: _watcherInterface,
    name: 'StatusNotifierItemUnregistered',
    signature: DBusSignature('s'),
  ).listen((signal) {
    final (busName, _) = _parseService(signal.values[0].asString(), null);
    _removeTracker(busName);
  });

  // Announce ourselves so apps that gate on a host being present show icons.
  try {
    await watcher.callMethod(
      _watcherInterface,
      'RegisterStatusNotifierHost',
      [DBusString(hostName)],
      replySignature: DBusSignature(''),
    );
  } catch (_) {}

  // Load items already registered with the watcher.
  try {
    final value = await watcher.getProperty(
        _watcherInterface, 'RegisteredStatusNotifierItems',
        signature: DBusSignature('as'));
    for (final service in value.asStringArray()) {
      final (busName, path) = _parseService(service, null);
      await _upsertTracker(client, busName, path);
    }
  } catch (_) {}
}

/// D-Bus object implementing `org.kde.StatusNotifierWatcher`.
class StatusNotifierWatcher extends DBusServiceObject {
  StatusNotifierWatcher(this._client)
      : super(DBusObjectPath(_watcherPath));

  final DBusClient _client;

  /// Full service strings as registered, exposed via the
  /// `RegisteredStatusNotifierItems` property.
  final List<String> _registeredServices = [];
  bool _hostRegistered = false;
  StreamSubscription<DBusNameOwnerChangedEvent>? _nameOwnerSub;

  Future<void> init() async {
    _nameOwnerSub = _client.nameOwnerChanged.listen(_onNameOwnerChanged);
  }

  @override
  late final List<DBusServiceInterface> interfaces = [
    DBusServiceInterface(
      _watcherInterface,
      methods: {
        'RegisterStatusNotifierItem': DBusServiceMethod(_registerItem, args: [
          DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_,
              name: 'service'),
        ]),
        'RegisterStatusNotifierHost': DBusServiceMethod(_registerHost, args: [
          DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_,
              name: 'service'),
        ]),
      },
      properties: {
        'RegisteredStatusNotifierItems': DBusServiceProperty(
            DBusSignature('as'), () => DBusArray.string(_registeredServices)),
        'IsStatusNotifierHostRegistered': DBusServiceProperty(
            DBusSignature('b'), () => DBusBoolean(_hostRegistered)),
        'ProtocolVersion':
            DBusServiceProperty(DBusSignature('i'), () => const DBusInt32(0)),
      },
      signals: [
        DBusIntrospectSignal('StatusNotifierItemRegistered', args: [
          DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.out),
        ]),
        DBusIntrospectSignal('StatusNotifierItemUnregistered', args: [
          DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.out),
        ]),
        DBusIntrospectSignal('StatusNotifierHostRegistered'),
      ],
      onError: (call, error) => DBusMethodErrorResponse.invalidArgs(),
    ),
  ];

  Future<DBusMethodResponse> _registerItem(DBusMethodCall methodCall) async {
    if (methodCall.values.isEmpty) {
      return DBusMethodErrorResponse.invalidArgs();
    }
    final service = methodCall.values[0].asString();
    final (busName, objectPath) = _parseService(service, methodCall.sender);
    if (busName.isEmpty) return DBusMethodErrorResponse.invalidArgs();

    final added = await _upsertTracker(_client, busName, objectPath);
    if (added) {
      _registeredServices.add(service);
      await emitSignal(_watcherInterface, 'StatusNotifierItemRegistered',
          [DBusString(service)]);
      await emitPropertiesChanged(_watcherInterface, changedProperties: {
        'RegisteredStatusNotifierItems':
            DBusArray.string(_registeredServices),
      });
    }
    return DBusMethodSuccessResponse([]);
  }

  Future<DBusMethodResponse> _registerHost(DBusMethodCall methodCall) async {
    if (!_hostRegistered) {
      _hostRegistered = true;
      await emitSignal(
          _watcherInterface, 'StatusNotifierHostRegistered', []);
      await emitPropertiesChanged(_watcherInterface, changedProperties: {
        'IsStatusNotifierHostRegistered': const DBusBoolean(true),
      });
    }
    return DBusMethodSuccessResponse([]);
  }

  void _onNameOwnerChanged(DBusNameOwnerChangedEvent event) {
    // An owner leaving with an empty new owner means the service disappeared.
    if (event.newOwner != null && event.newOwner!.isNotEmpty) return;
    if (!_removeTracker(event.name)) return;
    _registeredServices
        .removeWhere((s) => _parseService(s, null).$1 == event.name);
    emitSignal(_watcherInterface, 'StatusNotifierItemUnregistered',
        [DBusString(event.name)]);
    emitPropertiesChanged(_watcherInterface, changedProperties: {
      'RegisteredStatusNotifierItems': DBusArray.string(_registeredServices),
    });
  }

  void dispose() {
    _nameOwnerSub?.cancel();
    for (final tracker in _trackers.values) {
      tracker.dispose();
    }
    _trackers.clear();
  }
}


/// Starts system-tray support on the session bus.
///
/// With no `org.kde.StatusNotifierWatcher` yet, the shell becomes the watcher and
/// its own host. Another watcher already owning the name is not even a decline —
/// the shell attaches to it as a host and mirrors its registered items, so the
/// tray works either way. Genuine errors — an unreachable bus, a name request
/// that errored, an export failure — throw, and `ShellServices.run` records the
/// service as failed. A flaky *foreign* watcher stays soft inside
/// [_startHostConsumer]: the shell has yielded, and still listens for
/// registrations.
Future<void> startStatusNotifierService() async {
  final client = DBusClient.session();
  try {
    _sessionClient = client;

    final hostName = 'org.kde.StatusNotifierHost-$pid';
    await client
        .requestName(hostName, flags: {DBusRequestNameFlag.doNotQueue});

    final reply = await client.requestName(_watcherInterface,
        flags: {DBusRequestNameFlag.doNotQueue});

    if (reply == DBusRequestNameReply.primaryOwner ||
        reply == DBusRequestNameReply.alreadyOwner) {
      // We own the watcher name — act as the watcher and our own host.
      final watcher = StatusNotifierWatcher(client);
      await watcher.init();
      await client.registerObject(watcher);
      await watcher.handleMethodCall(DBusMethodCall(
        sender: hostName,
        interface: _watcherInterface,
        name: 'RegisterStatusNotifierHost',
        values: [DBusString(hostName)],
      ));
    } else {
      // Another watcher owns the name — consume it as a host.
      await _startHostConsumer(client, hostName);
    }
  } catch (_) {
    _sessionClient = null;
    unawaited(client.close());
    rethrow;
  }
}

/// Fetches the dbusmenu layout for [item], or null if it has no menu.
Future<MenuNode?> fetchTrayMenu(TrayItem item) async {
  final client = _sessionClient;
  final menuPath = item.menuPath;
  if (client == null || menuPath == null) return null;
  final menu =
      DBusMenuClient(client, busName: item.busName, path: menuPath);
  return menu.fetchLayout();
}

/// Reports a click on menu entry [id] of [item]'s menu.
Future<void> sendTrayMenuClick(TrayItem item, int id) async {
  final client = _sessionClient;
  final menuPath = item.menuPath;
  if (client == null || menuPath == null) return;
  final menu =
      DBusMenuClient(client, busName: item.busName, path: menuPath);
  await menu.clickItem(id);
}

/// Left-click activation fallback for items without a menu (SNI `Activate`).
Future<void> activateTrayItem(TrayItem item) async {
  final client = _sessionClient;
  if (client == null) return;
  try {
    final obj = DBusRemoteObject(client,
        name: item.busName, path: item.objectPath);
    await obj.callMethod(
      _itemInterface,
      'Activate',
      [const DBusInt32(0), const DBusInt32(0)],
      replySignature: DBusSignature(''),
      noReplyExpected: true,
    );
  } catch (_) {
    // Item may not implement Activate; nothing else to do.
  }
}
