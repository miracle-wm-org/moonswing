import 'dart:async';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

/// A single notification received from the FreeDesktop notification daemon
/// protocol.
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.appName,
    required this.summary,
    required this.body,
    required this.actions,
    required this.expireTimeout,
    required this.arrivedAt,
  });

  final int id;
  final String appName;
  final String summary;
  final String body;

  /// Flat list of action pairs: [key0, label0, key1, label1, ...].
  final List<String> actions;

  /// Auto-dismiss timeout in milliseconds. -1 or 0 means no auto-dismiss.
  final int expireTimeout;

  final DateTime arrivedAt;

  NotificationItem copyWith({
    int? id,
    String? appName,
    String? summary,
    String? body,
    List<String>? actions,
    int? expireTimeout,
    DateTime? arrivedAt,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      appName: appName ?? this.appName,
      summary: summary ?? this.summary,
      body: body ?? this.body,
      actions: actions ?? this.actions,
      expireTimeout: expireTimeout ?? this.expireTimeout,
      arrivedAt: arrivedAt ?? this.arrivedAt,
    );
  }
}

/// Singleton ChangeNotifier that holds the current list of notifications.
class NotificationStore extends ChangeNotifier {
  static final NotificationStore instance = NotificationStore._();
  NotificationStore._();

  final List<NotificationItem> _items = [];
  List<NotificationItem> get items => List.unmodifiable(_items);

  int _nextId = 1;
  final Map<int, Timer> _expireTimers = {};
  void Function(int id, String actionKey)? _onActionInvoked;

  /// Wired up by [startNotificationService] so the store can emit D-Bus
  /// signals when actions are invoked from the UI.
  void setActionInvokedCallback(void Function(int, String) cb) {
    _onActionInvoked = cb;
  }

  /// Returns the next available notification id (never 0).
  int allocateId() {
    final id = _nextId;
    _nextId = (_nextId % 0x7FFFFFFF) + 1;
    return id;
  }

  /// Adds a new notification or replaces an existing one when [item.id]
  /// matches an existing entry. Returns the assigned id.
  int addOrReplace(NotificationItem item) {
    final existingIndex = _items.indexWhere((n) => n.id == item.id);

    if (existingIndex != -1) {
      _expireTimers.remove(_items[existingIndex].id)?.cancel();
      _items[existingIndex] = item;
    } else {
      _items.insert(0, item);
    }

    if (item.expireTimeout > 0) {
      _expireTimers[item.id] = Timer(
        Duration(milliseconds: item.expireTimeout),
        () => dismiss(item.id),
      );
    }

    notifyListeners();
    return item.id;
  }

  void dismiss(int id) {
    _expireTimers.remove(id)?.cancel();
    _items.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  void invokeAction(int id, String actionKey) {
    _onActionInvoked?.call(id, actionKey);
    dismiss(id);
  }

  void dismissAll() {
    for (final t in _expireTimers.values) {
      t.cancel();
    }
    _expireTimers.clear();
    _items.clear();
    notifyListeners();
  }
}

/// D-Bus object that implements the org.freedesktop.Notifications interface,
/// allowing the shell to act as the system notification daemon.
class NotificationServer extends DBusObject {
  NotificationServer()
      : super(DBusObjectPath('/org/freedesktop/Notifications'));

  final NotificationStore _store = NotificationStore.instance;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    try {
      switch (methodCall.name) {
        case 'GetCapabilities':
          return _handleGetCapabilities();
        case 'GetServerInformation':
          return _handleGetServerInformation();
        case 'Notify':
          return _handleNotify(methodCall.values);
        case 'CloseNotification':
          return await _handleCloseNotification(methodCall.values);
        default:
          return DBusMethodErrorResponse.unknownMethod();
      }
    } catch (e) {
      return DBusMethodErrorResponse.invalidArgs();
    }
  }

  DBusMethodResponse _handleGetCapabilities() {
    return DBusMethodSuccessResponse([
      DBusArray.string(['body', 'actions', 'body-markup']),
    ]);
  }

  DBusMethodResponse _handleGetServerInformation() {
    return DBusMethodSuccessResponse([
      const DBusString('graceful-shell'),
      const DBusString('graceful-shell'),
      const DBusString('1.0'),
      const DBusString('1.2'),
    ]);
  }

  DBusMethodResponse _handleNotify(List<DBusValue> values) {
    // D-Bus Notify signature: susssasa{sv}i
    if (values.length < 8) return DBusMethodErrorResponse.invalidArgs();

    final appName    = (values[0] as DBusString).value;
    final replacesId = (values[1] as DBusUint32).value;
    // values[2] = app_icon (ignored)
    final summary    = (values[3] as DBusString).value;
    final body       = (values[4] as DBusString).value;
    final actions    = (values[5] as DBusArray)
        .children
        .map((v) => (v as DBusString).value)
        .toList();
    // values[6] = hints a{sv} (ignored)
    final expireMs   = (values[7] as DBusInt32).value;

    // Reuse replacesId if it refers to an existing notification.
    final int assignedId;
    if (replacesId != 0 &&
        _store.items.any((n) => n.id == replacesId)) {
      assignedId = replacesId;
    } else {
      assignedId = _store.allocateId();
    }

    final item = NotificationItem(
      id: assignedId,
      appName: appName,
      summary: summary,
      body: body,
      actions: actions,
      expireTimeout: expireMs,
      arrivedAt: DateTime.now(),
    );

    _store.addOrReplace(item);
    return DBusMethodSuccessResponse([DBusUint32(assignedId)]);
  }

  Future<DBusMethodResponse> _handleCloseNotification(
      List<DBusValue> values) async {
    if (values.isEmpty) return DBusMethodErrorResponse.invalidArgs();
    final id = (values[0] as DBusUint32).value;
    _store.dismiss(id);
    await emitSignal(
      'org.freedesktop.Notifications',
      'NotificationClosed',
      [DBusUint32(id), const DBusUint32(3)], // reason 3 = closed by call
    );
    return DBusMethodSuccessResponse([]);
  }

  /// Emits the ActionInvoked signal. Called by [NotificationStore] via the
  /// callback wired up in [startNotificationService].
  Future<void> emitActionInvoked(int id, String actionKey) async {
    await emitSignal(
      'org.freedesktop.Notifications',
      'ActionInvoked',
      [DBusUint32(id), DBusString(actionKey)],
    );
  }

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface(
        'org.freedesktop.Notifications',
        methods: [
          DBusIntrospectMethod('GetCapabilities'),
          DBusIntrospectMethod('GetServerInformation'),
          DBusIntrospectMethod('Notify'),
          DBusIntrospectMethod('CloseNotification'),
        ],
        signals: [
          DBusIntrospectSignal('NotificationClosed'),
          DBusIntrospectSignal('ActionInvoked'),
        ],
      ),
    ];
  }
}

/// Registers this shell as the FreeDesktop notification daemon on the session
/// D-Bus. If another daemon is already running, this fails silently so the
/// shell continues to work without notifications.
Future<void> startNotificationService() async {
  try {
    final client = DBusClient.session();
    final server = NotificationServer();

    NotificationStore.instance.setActionInvokedCallback(
      (id, actionKey) => server.emitActionInvoked(id, actionKey),
    );

    await client.registerObject(server);
    await client.requestName('org.freedesktop.Notifications');
  } catch (e) {
    debugPrint('Notification service unavailable: $e');
  }
}
