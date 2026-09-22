import 'dart:async';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import 'config_store.dart';
import 'dbus_service_object.dart';

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
    this.read = false,
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

  /// Whether the user has acknowledged this one.
  ///
  /// Read is not the same claim as dismissed, and the panel needs both: a
  /// dismissal takes the notification off the list, while marking it read
  /// leaves it there to be read again and only stops the shell *asking* — the
  /// bell's bubble, the floating card and the chime all hang off
  /// [NotificationStore.unreadCount] rather than off the list's length.
  ///
  /// A notification arrives unread, and a replacement arrives unread again: an
  /// application that rewrites a notification has said something new under an
  /// id it happens to be reusing.
  final bool read;

  NotificationItem copyWith({
    int? id,
    String? appName,
    String? summary,
    String? body,
    List<String>? actions,
    int? expireTimeout,
    DateTime? arrivedAt,
    bool? read,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      appName: appName ?? this.appName,
      summary: summary ?? this.summary,
      body: body ?? this.body,
      actions: actions ?? this.actions,
      expireTimeout: expireTimeout ?? this.expireTimeout,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      read: read ?? this.read,
    );
  }
}

/// Whether the shell actually owns `org.freedesktop.Notifications`.
///
/// Deliberately separate from the `ShellService.notifications` `ServiceStatus`.
/// That one answers "should I show a spinner?", for which a decline and a success
/// are the same answer. This one answers "are notifications working?", where they
/// are emphatically not: the name went to somebody else, so every notification on
/// this machine is delivered somewhere the shell cannot see. The UI needs both,
/// which is why neither can be spelled in terms of the other.
enum NotificationDaemonStatus {
  /// The name request has not been answered yet.
  starting,

  /// The shell owns the name and is receiving notifications.
  running,

  /// The shell does not own the name — another daemon holds it, or the request
  /// itself errored. Nothing will arrive until a retry wins the name.
  unavailable,
}

/// Where the silenced flag lives in `config.toml`.
///
/// A key of the shell's own config rather than state that dies with the
/// process: silencing is a decision the user made about their machine, and a
/// shell that quietly started interrupting them again after a restart would be
/// the one failure mode a "do not disturb" switch may not have.
const List<String> kNotificationSilencedPath = ['notifications', 'silenced'];

/// Singleton ChangeNotifier that holds the current list of notifications.
class NotificationStore extends ChangeNotifier {
  static final NotificationStore instance = NotificationStore._();
  NotificationStore._();

  final List<NotificationItem> _items = [];
  List<NotificationItem> get items => List.unmodifiable(_items);

  /// How many of [items] the user has not acknowledged yet.
  ///
  /// The number every attention-seeking surface renders, and the one the chime
  /// fires on: the bell's bubble, the floating card, and whether that card's
  /// window exists at all. The panel's own header still counts the list, because
  /// a panel that said "nothing waiting" over four cards would be lying.
  int get unreadCount {
    var count = 0;
    for (final item in _items) {
      if (!item.read) count++;
    }
    return count;
  }

  /// Whether anything is still asking for attention.
  bool get hasUnread => _items.any((item) => !item.read);

  /// Marks everything on the list acknowledged — the panel's check-all button.
  ///
  /// Deliberately *not* what opening the panel does. Reading a notification is
  /// something the user does, not something a window being mapped does for
  /// them, and a panel that silently cleared the count as it slid in would
  /// leave a user who opened it by accident with no way of knowing what had
  /// arrived. Nothing is removed: the list is still there to be read, and
  /// [dismissAll] is the button that empties it.
  ///
  /// A no-op when nothing moves, so a second press costs no notification.
  void markAllRead() {
    var moved = false;
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].read) continue;
      _items[i] = _items[i].copyWith(read: true);
      moved = true;
    }
    if (moved) notifyListeners();
  }

  /// Marks one item acknowledged. A no-op for an id that is not on the list or
  /// is already read.
  void markRead(int id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index == -1 || _items[index].read) return;
    _items[index] = _items[index].copyWith(read: true);
    notifyListeners();
  }

  int _nextId = 1;
  final Map<int, Timer> _expireTimers = {};
  void Function(int id, String actionKey)? _onActionInvoked;

  NotificationDaemonStatus _daemonStatus = NotificationDaemonStatus.starting;
  String? _daemonReason;
  bool _daemonRetrying = false;

  /// Whether the shell owns the notification bus name — see
  /// [NotificationDaemonStatus].
  NotificationDaemonStatus get daemonStatus => _daemonStatus;

  /// True when notifications are broken and the user should be told so.
  bool get daemonUnavailable =>
      _daemonStatus == NotificationDaemonStatus.unavailable;

  /// One sentence on *why*, for the banner. Null unless [daemonUnavailable].
  String? get daemonReason => _daemonReason;

  /// True while [retryDaemon] is in flight, so the button can show a loader
  /// instead of inviting a second attempt on top of the first.
  bool get daemonRetrying => _daemonRetrying;

  ConfigStore? _resolvedConfig;
  bool _configResolved = false;

  /// The config the silenced flag is persisted through, or null.
  ///
  /// Resolved lazily, `KeyboardStore`'s rule and its two reasons:
  /// `ConfigStore.instance` throws before `initShared()`, and a module built
  /// alone in a widget test has no `main()` behind it. With no shared store the
  /// flag is whatever this process set and nothing is written, which is exactly
  /// what a test wants.
  ConfigStore? get _config {
    if (_configResolved) return _resolvedConfig;
    _configResolved = true;
    try {
      _resolvedConfig = ConfigStore.instance;
    } catch (_) {
      _resolvedConfig = null;
    }
    return _resolvedConfig;
  }

  /// Null until first read, then the flag; see [silenced].
  bool? _silenced;

  /// Whether the shell is silencing notifications — "do not disturb".
  ///
  /// Silencing is about *interruption*, never about delivery. The daemon keeps
  /// accepting `Notify` calls and the panel keeps filling up, so nothing is
  /// lost and the user reads it when they choose; what stops is the shell
  /// calling them away from what they are doing — the bell's shake and the
  /// floating badge that puts itself in the corner of every output.
  ///
  /// Read through the config on first use rather than in the constructor: this
  /// singleton is built the first time anything touches it, which is before
  /// `ConfigStore.initShared()` has run.
  bool get silenced =>
      _silenced ??= _config?.get<bool>(kNotificationSilencedPath) ?? false;

  /// Sets the flag and persists it. A no-op when nothing moves, so a rebuild
  /// that re-asserts the current state costs no write and no notification.
  void setSilenced(bool value) {
    if (silenced == value) return;
    _silenced = value;
    _config?.set(kNotificationSilencedPath, value);
    notifyListeners();
  }

  /// What the bell's right-click and the panel's switch both do.
  void toggleSilenced() => setSilenced(!silenced);

  /// Puts the silenced flag back to what a fresh process has, optionally bound
  /// to [configStore]. For tests, which share this singleton across cases.
  @visibleForTesting
  void resetSilencedState({ConfigStore? configStore}) {
    _silenced = null;
    _resolvedConfig = configStore;
    _configResolved = configStore != null;
    notifyListeners();
  }

  /// The attempt [retryDaemon] re-runs, defaulting to the real thing.
  ///
  /// Injectable so the retry path is a plain unit test: [startNotificationService]
  /// opens a session bus connection, which no test may depend on being there.
  @visibleForTesting
  Future<void> Function() daemonStarter = startNotificationService;

  /// Records that the shell owns the name. Called by
  /// [startNotificationService] once the request has been won.
  void reportDaemonRunning() {
    if (_daemonStatus == NotificationDaemonStatus.running &&
        _daemonReason == null) {
      return;
    }
    _daemonStatus = NotificationDaemonStatus.running;
    _daemonReason = null;
    notifyListeners();
  }

  /// Records that the shell does *not* own the name, with the sentence the
  /// banner shows. Both the graceful decline and a genuine error land here —
  /// the distinction matters to `ShellServices`, not to the user, for whom
  /// notifications are equally gone either way.
  void reportDaemonUnavailable(String reason) {
    if (_daemonStatus == NotificationDaemonStatus.unavailable &&
        _daemonReason == reason) {
      return;
    }
    _daemonStatus = NotificationDaemonStatus.unavailable;
    _daemonReason = reason;
    notifyListeners();
  }

  /// Puts the daemon state back to what a fresh process has. For tests, which
  /// share this singleton across cases.
  @visibleForTesting
  void resetDaemonState() {
    _daemonStatus = NotificationDaemonStatus.starting;
    _daemonReason = null;
    _daemonRetrying = false;
    daemonStarter = startNotificationService;
    notifyListeners();
  }

  /// Re-runs the name request behind the panel's Retry button.
  ///
  /// Failures are swallowed rather than rethrown: [daemonStarter] has already
  /// recorded the reason by the time it throws, and the rethrow exists for
  /// `ShellServices.run`, which is long gone by the time a user clicks Retry.
  Future<void> retryDaemon() async {
    if (_daemonRetrying) return;
    if (_daemonStatus == NotificationDaemonStatus.running) return;
    _daemonRetrying = true;
    notifyListeners();
    try {
      await daemonStarter();
    } catch (error) {
      reportDaemonUnavailable('$error');
    } finally {
      _daemonRetrying = false;
      notifyListeners();
    }
  }

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

  /// How many notifications have arrived that the chime must not answer.
  ///
  /// Monotonic, never reset, and read as a *delta* by
  /// `NotificationSoundStore`: the chime fires on [unreadCount] going up, and
  /// this is what says how much of that rise was the shell announcing
  /// something it has already made its own noise about. A timer finishing is
  /// the case — it rings its own alarm and then posts this list a line saying
  /// which timer it was, and answering that with the arrival chime as well
  /// would be two sounds a frame apart for one event.
  ///
  /// A counter rather than a flag on [NotificationItem] because the chime
  /// never sees the item: it listens to this store and compares counts, which
  /// is what keeps it out of the list's internals.
  int get chimelessArrivals => _chimelessArrivals;
  int _chimelessArrivals = 0;

  /// Adds a new notification or replaces an existing one when [item.id]
  /// matches an existing entry. Returns the assigned id.
  ///
  /// [chime] false marks the arrival as one the shell has already sounded for
  /// — see [chimelessArrivals]. It is for the shell's *own* posts only: a
  /// notification arriving over D-Bus is somebody else's, and the user's chime
  /// setting is the only thing that decides whether it is heard.
  int addOrReplace(NotificationItem item, {bool chime = true}) {
    if (!chime) _chimelessArrivals++;
    final existingIndex = _items.indexWhere((n) => n.id == item.id);

    if (existingIndex != -1) {
      _expireTimers.remove(_items[existingIndex].id)?.cancel();
      // The incoming item wins whole, its `read` flag included: an application
      // that rewrote a notification under an id it is reusing has said
      // something the user has not seen. See [NotificationItem.read].
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
class NotificationServer extends DBusServiceObject {
  NotificationServer()
      : super(DBusObjectPath('/org/freedesktop/Notifications'));

  static const _interface = 'org.freedesktop.Notifications';

  final NotificationStore _store = NotificationStore.instance;

  @override
  late final List<DBusServiceInterface> interfaces = [
    DBusServiceInterface(
      _interface,
      methods: {
        'GetCapabilities':
            DBusServiceMethod((call) async => _handleGetCapabilities()),
        'GetServerInformation':
            DBusServiceMethod((call) async => _handleGetServerInformation()),
        'Notify': DBusServiceMethod((call) async => _handleNotify(call.values)),
        'CloseNotification':
            DBusServiceMethod((call) => _handleCloseNotification(call.values)),
      },
      signals: [
        DBusIntrospectSignal('NotificationClosed'),
        DBusIntrospectSignal('ActionInvoked'),
      ],
      onError: (call, error) => DBusMethodErrorResponse.invalidArgs(),
    ),
  ];

  DBusMethodResponse _handleGetCapabilities() {
    return DBusMethodSuccessResponse([
      DBusArray.string(['body', 'actions', 'body-markup']),
    ]);
  }

  DBusMethodResponse _handleGetServerInformation() {
    return DBusMethodSuccessResponse([
      const DBusString('moonswing'),
      const DBusString('moonswing'),
      const DBusString('1.0'),
      const DBusString('1.2'),
    ]);
  }

  DBusMethodResponse _handleNotify(List<DBusValue> values) {
    // D-Bus Notify signature: susssasa{sv}i
    if (values.length < 8) return DBusMethodErrorResponse.invalidArgs();

    final appName = (values[0] as DBusString).value;
    final replacesId = (values[1] as DBusUint32).value;
    // values[2] = app_icon (ignored)
    final summary = (values[3] as DBusString).value;
    final body = (values[4] as DBusString).value;
    final actions = (values[5] as DBusArray)
        .children
        .map((v) => (v as DBusString).value)
        .toList();
    // values[6] = hints a{sv} (ignored)
    final expireMs = (values[7] as DBusInt32).value;

    // Reuse replacesId if it refers to an existing notification.
    final int assignedId;
    if (replacesId != 0 && _store.items.any((n) => n.id == replacesId)) {
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
      _interface,
      'NotificationClosed',
      [DBusUint32(id), const DBusUint32(3)], // reason 3 = closed by call
    );
    return DBusMethodSuccessResponse([]);
  }

  /// Emits the ActionInvoked signal. Called by [NotificationStore] via the
  /// callback wired up in [startNotificationService].
  Future<void> emitActionInvoked(int id, String actionKey) async {
    await emitSignal(
      _interface,
      'ActionInvoked',
      [DBusUint32(id), DBusString(actionKey)],
    );
  }
}

/// Registers this shell as the FreeDesktop notification daemon on the session bus.
///
/// Another daemon already owning `org.freedesktop.Notifications` is a graceful
/// decline — the shell yields, logs, returns and keeps working without
/// notifications. Anything else — an unreachable bus, an export or name request
/// that errored — throws, and `ShellServices.run` records the service as failed.
///
/// Both outcomes are *also* recorded on [NotificationStore] as a
/// [NotificationDaemonStatus], which is not a duplicate: the decline settles
/// `ShellService.notifications` at `ServiceStatus.ready`, correctly, but "nothing
/// left to wait for" and "notifications work" are different claims and only the
/// second is what the bell tells the user.
///
/// This function is also the retry: [NotificationStore.retryDaemon] re-runs it.
/// Every failing path closes its own client first, so a second attempt starts
/// from a clean connection, and a run that has already won the name is never
/// re-entered.
Future<void> startNotificationService() async {
  final store = NotificationStore.instance;
  final client = DBusClient.session();
  try {
    final server = NotificationServer();

    // Export before requesting the name, so a call arriving the instant the
    // name is granted already finds the object.
    await client.registerObject(server);

    final reply = await client.requestName('org.freedesktop.Notifications',
        flags: {DBusRequestNameFlag.doNotQueue});
    if (reply != DBusRequestNameReply.primaryOwner &&
        reply != DBusRequestNameReply.alreadyOwner) {
      debugPrint('Notification daemon already running; '
          'the shell yields and will not show notifications');
      await client.close();
      store.reportDaemonUnavailable(
        'Another notification daemon already owns '
        'org.freedesktop.Notifications, so the shell is not receiving '
        'notifications.',
      );
      return;
    }

    // Only the daemon that owns the name emits ActionInvoked, so this is wired
    // after the name is won — never toward a client the decline path closed.
    store.setActionInvokedCallback(
      (id, actionKey) => server.emitActionInvoked(id, actionKey),
    );
    store.reportDaemonRunning();
  } catch (error) {
    unawaited(client.close());
    store.reportDaemonUnavailable(
      'The shell could not register as the notification daemon: $error',
    );
    rethrow;
  }
}
