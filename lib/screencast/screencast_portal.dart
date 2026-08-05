import 'dart:async';

import 'package:dbus/dbus.dart';

import 'pick_types.dart';
import 'screencast_log.dart';

/// The xdg-desktop-portal ScreenCast *backend* (`impl` side): xdg-desktop-portal
/// itself is the only D-Bus peer, forwarding app requests here and handling
/// `OpenPipeWireRemote` on its own — this backend only chooses sources and
/// returns PipeWire node ids.
///
/// Object model per the portal backend contract:
/// - [ScreenCastPortalBackend] at `/org/freedesktop/portal/desktop`.
/// - A [PortalSession] exported at each `session_handle` path the frontend
///   supplies (Close method, Closed signal).
/// - A [PortalRequest] exported at the `handle` path for the duration of
///   `Start`, so the frontend can cancel a pick that's still on screen.
///
/// Modeled on `StatusNotifierWatcher` (`lib/status_notifier_service.dart`):
/// interface-checked `handleMethodCall`, property overrides, and
/// `nameOwnerChanged` peer-death tracking.

const String screenCastInterface = 'org.freedesktop.impl.portal.ScreenCast';
const String sessionInterface = 'org.freedesktop.impl.portal.Session';
const String requestInterface = 'org.freedesktop.impl.portal.Request';

/// `AvailableSourceTypes` bits.
const int sourceTypeMonitor = 1;
const int sourceTypeWindow = 2;

/// `AvailableCursorModes` bits. METADATA (4) is deliberately not offered.
const int cursorModeHidden = 1;
const int cursorModeEmbedded = 2;

/// Portal response codes.
const int _responseSuccess = 0;
const int _responseCancelled = 1;
const int _responseError = 2;

/// One PipeWire stream in a `Start` response.
class PortalStreamInfo {
  const PortalStreamInfo({
    required this.nodeId,
    required this.sourceType,
    required this.width,
    required this.height,
    this.x,
    this.y,
  });

  final int nodeId;
  final int sourceType;
  final int width;
  final int height;
  final int? x;
  final int? y;
}

/// A running cast (all streams for one session).
abstract class ActiveCast {
  List<PortalStreamInfo> get streams;

  void stop();
}

/// What the portal needs from the capture/PipeWire machinery — a seam so
/// `test/screencast_portal_test.dart` can drive the backend with fakes.
abstract class ScreencastEngine {
  /// Bitmask of [sourceTypeMonitor] | [sourceTypeWindow].
  int get availableSourceTypes;

  /// Shows the picker; null means cancelled.
  Future<PickResult?> pick(PickRequest request);

  /// Cancels an in-flight [pick] (frontend closed the Request).
  void cancelPick();

  /// Builds capture sessions + PipeWire streams for the picked sources and
  /// resolves once every node id is known. [onStopped] fires later if any
  /// underlying source goes away (session must close).
  Future<ActiveCast> startCast(
    PickResult picked, {
    required bool paintCursors,
    required void Function() onStopped,
  });
}

class _SessionState {
  _SessionState(this.object, this.frontend);

  final PortalSession object;

  /// The frontend's unique bus name (`:1.x`) — sessions die with it.
  final String frontend;

  int types = sourceTypeMonitor;
  bool multiple = false;
  int cursorMode = cursorModeHidden;
  bool started = false;
  ActiveCast? cast;
}

class ScreenCastPortalBackend extends DBusObject {
  ScreenCastPortalBackend(this._client, this._engine)
      : super(DBusObjectPath('/org/freedesktop/portal/desktop'));

  final DBusClient _client;
  final ScreencastEngine _engine;
  final Map<String, _SessionState> _sessions = {};
  StreamSubscription<DBusNameOwnerChangedEvent>? _nameOwnerSub;

  Future<void> init() async {
    _nameOwnerSub = _client.nameOwnerChanged.listen(_onNameOwnerChanged);
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != screenCastInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    try {
      switch (methodCall.name) {
        case 'CreateSession':
          return await _createSession(methodCall);
        case 'SelectSources':
          return await _selectSources(methodCall);
        case 'Start':
          return await _start(methodCall);
        default:
          return DBusMethodErrorResponse.unknownMethod();
      }
    } catch (e) {
      screencastLog('ScreenCast portal ${methodCall.name} failed: $e');
      return _result(_responseError);
    }
  }

  static DBusMethodResponse _result(int response,
          [Map<String, DBusValue> results = const {}]) =>
      DBusMethodSuccessResponse(
          [DBusUint32(response), DBusDict.stringVariant(results)]);

  Future<DBusMethodResponse> _createSession(DBusMethodCall call) async {
    final values = call.values;
    if (values.length < 4 || values[1] is! DBusObjectPath) {
      return DBusMethodErrorResponse.invalidArgs();
    }
    final sessionHandle = (values[1] as DBusObjectPath).value;
    if (_sessions.containsKey(sessionHandle)) return _result(_responseError);

    final object = PortalSession(DBusObjectPath(sessionHandle), this);
    // The sender is xdg-desktop-portal's unique name; sessions die with it.
    // An unsigned message can't happen on a bus connection, but an empty
    // string here would only mean "never matched by nameOwnerChanged".
    final state = _SessionState(object, call.sender ?? '');
    _sessions[sessionHandle] = state;
    await _client.registerObject(object);
    screencastLog('ScreenCast session created: $sessionHandle '
        '(app "${_appId(values)}")');
    return _result(_responseSuccess);
  }

  Future<DBusMethodResponse> _selectSources(DBusMethodCall call) async {
    final values = call.values;
    if (values.length < 4 || values[1] is! DBusObjectPath) {
      return DBusMethodErrorResponse.invalidArgs();
    }
    final state = _sessions[(values[1] as DBusObjectPath).value];
    if (state == null || state.started) return _result(_responseError);

    final options = values[3] is DBusDict
        ? (values[3] as DBusDict).asStringVariantDict()
        : <String, DBusValue>{};
    // Type-test, never cast: a malformed option falls back to its default.
    final types = options['types'];
    if (types is DBusUint32) {
      state.types = types.value & _engine.availableSourceTypes;
      if (state.types == 0) state.types = sourceTypeMonitor;
    }
    final multiple = options['multiple'];
    if (multiple is DBusBoolean) state.multiple = multiple.value;
    final cursorMode = options['cursor_mode'];
    if (cursorMode is DBusUint32) state.cursorMode = cursorMode.value;
    return _result(_responseSuccess);
  }

  Future<DBusMethodResponse> _start(DBusMethodCall call) async {
    final values = call.values;
    if (values.length < 5 ||
        values[0] is! DBusObjectPath ||
        values[1] is! DBusObjectPath) {
      return DBusMethodErrorResponse.invalidArgs();
    }
    final handlePath = values[0] as DBusObjectPath;
    final sessionHandle = (values[1] as DBusObjectPath).value;
    final state = _sessions[sessionHandle];
    if (state == null || state.started) return _result(_responseError);
    state.started = true;

    // Export the Request object so the frontend can cancel mid-pick.
    final request = PortalRequest(handlePath, _engine.cancelPick);
    await _client.registerObject(request);
    PickResult? picked;
    try {
      picked = await _engine.pick(PickRequest(
        appId: _appId(values),
        monitors: state.types & sourceTypeMonitor != 0,
        windows: state.types & sourceTypeWindow != 0,
        multiple: state.multiple,
      ));
    } finally {
      await _client.unregisterObject(request);
    }

    if (picked == null || picked.sources.isEmpty) {
      state.started = false; // xdg-desktop-portal closes the session anyway
      return _result(_responseCancelled);
    }

    final ActiveCast cast;
    try {
      cast = await _engine
          .startCast(
            picked,
            paintCursors: state.cursorMode == cursorModeEmbedded,
            onStopped: () => _closeFromBackend(sessionHandle),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      screencastLog('ScreenCast Start failed: $e');
      return _result(_responseError);
    }
    state.cast = cast;

    return _result(_responseSuccess, {
      'streams': DBusArray(DBusSignature('(ua{sv})'), [
        for (final s in cast.streams)
          DBusStruct([
            DBusUint32(s.nodeId),
            DBusDict.stringVariant({
              if (s.x != null && s.y != null)
                'position': DBusStruct([DBusInt32(s.x!), DBusInt32(s.y!)]),
              'size': DBusStruct([DBusInt32(s.width), DBusInt32(s.height)]),
              'source_type': DBusUint32(s.sourceType),
            }),
          ]),
      ]),
    });
  }

  static String _appId(List<DBusValue> values) =>
      values[2] is DBusString ? (values[2] as DBusString).value : '';

  /// `Session.Close` from the frontend: app stopped sharing or died.
  Future<void> closeSession(PortalSession session) async {
    final entry = _sessions.entries
        .where((e) => identical(e.value.object, session))
        .firstOrNull;
    if (entry == null) return;
    await _teardown(entry.key, emitClosed: false);
  }

  /// Backend-initiated close (source vanished, capture connection died).
  void _closeFromBackend(String sessionHandle) {
    _teardown(sessionHandle, emitClosed: true);
  }

  Future<void> _teardown(String sessionHandle,
      {required bool emitClosed}) async {
    final state = _sessions.remove(sessionHandle);
    if (state == null) return;
    state.cast?.stop();
    state.cast = null;
    if (emitClosed) {
      try {
        await state.object.emitSignal(sessionInterface, 'Closed');
      } catch (_) {}
    }
    try {
      await _client.unregisterObject(state.object);
    } catch (_) {}
    screencastLog('ScreenCast session closed: $sessionHandle');
  }

  void _onNameOwnerChanged(DBusNameOwnerChangedEvent event) {
    if (event.newOwner != null && event.newOwner!.isNotEmpty) return;
    final dead = _sessions.entries
        .where((e) => e.value.frontend == event.name)
        .map((e) => e.key)
        .toList();
    for (final handle in dead) {
      _teardown(handle, emitClosed: false);
    }
  }

  /// Shell shutdown / capture connection lost.
  Future<void> closeAllSessions() async {
    for (final handle in _sessions.keys.toList()) {
      await _teardown(handle, emitClosed: true);
    }
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != screenCastInterface) {
      return DBusMethodErrorResponse.unknownProperty();
    }
    switch (name) {
      case 'version':
        // Version 2: before restore/persist (4+) and virtual monitors (5) —
        // the frontend won't send options this backend doesn't understand.
        return DBusGetPropertyResponse(const DBusUint32(2));
      case 'AvailableSourceTypes':
        return DBusGetPropertyResponse(
            DBusUint32(_engine.availableSourceTypes));
      case 'AvailableCursorModes':
        return DBusGetPropertyResponse(
            const DBusUint32(cursorModeHidden | cursorModeEmbedded));
      default:
        return DBusMethodErrorResponse.unknownProperty();
    }
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != screenCastInterface) {
      return DBusGetAllPropertiesResponse({});
    }
    return DBusGetAllPropertiesResponse({
      'version': const DBusUint32(2),
      'AvailableSourceTypes': DBusUint32(_engine.availableSourceTypes),
      'AvailableCursorModes':
          const DBusUint32(cursorModeHidden | cursorModeEmbedded),
    });
  }

  @override
  List<DBusIntrospectInterface> introspect() {
    DBusIntrospectArgument arg(String signature, DBusArgumentDirection dir,
            String name) =>
        DBusIntrospectArgument(DBusSignature(signature), dir, name: name);
    final inArg = DBusArgumentDirection.in_;
    final outArg = DBusArgumentDirection.out;
    return [
      DBusIntrospectInterface(
        screenCastInterface,
        methods: [
          DBusIntrospectMethod('CreateSession', args: [
            arg('o', inArg, 'handle'),
            arg('o', inArg, 'session_handle'),
            arg('s', inArg, 'app_id'),
            arg('a{sv}', inArg, 'options'),
            arg('u', outArg, 'response'),
            arg('a{sv}', outArg, 'results'),
          ]),
          DBusIntrospectMethod('SelectSources', args: [
            arg('o', inArg, 'handle'),
            arg('o', inArg, 'session_handle'),
            arg('s', inArg, 'app_id'),
            arg('a{sv}', inArg, 'options'),
            arg('u', outArg, 'response'),
            arg('a{sv}', outArg, 'results'),
          ]),
          DBusIntrospectMethod('Start', args: [
            arg('o', inArg, 'handle'),
            arg('o', inArg, 'session_handle'),
            arg('s', inArg, 'app_id'),
            arg('s', inArg, 'parent_window'),
            arg('a{sv}', inArg, 'options'),
            arg('u', outArg, 'response'),
            arg('a{sv}', outArg, 'results'),
          ]),
        ],
        properties: [
          DBusIntrospectProperty('version', DBusSignature('u'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('AvailableSourceTypes', DBusSignature('u'),
              access: DBusPropertyAccess.read),
          DBusIntrospectProperty('AvailableCursorModes', DBusSignature('u'),
              access: DBusPropertyAccess.read),
        ],
      ),
    ];
  }

  Future<void> dispose() async {
    await _nameOwnerSub?.cancel();
    await closeAllSessions();
  }
}

/// `org.freedesktop.impl.portal.Session` — one per session handle.
class PortalSession extends DBusObject {
  PortalSession(super.path, this._backend);

  final ScreenCastPortalBackend _backend;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != sessionInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    if (methodCall.name != 'Close') {
      return DBusMethodErrorResponse.unknownMethod();
    }
    await _backend.closeSession(this);
    return DBusMethodSuccessResponse([]);
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface == sessionInterface && name == 'version') {
      return DBusGetPropertyResponse(const DBusUint32(1));
    }
    return DBusMethodErrorResponse.unknownProperty();
  }

  @override
  List<DBusIntrospectInterface> introspect() => [
        DBusIntrospectInterface(
          sessionInterface,
          methods: [DBusIntrospectMethod('Close')],
          signals: [DBusIntrospectSignal('Closed')],
          properties: [
            DBusIntrospectProperty('version', DBusSignature('u'),
                access: DBusPropertyAccess.read),
          ],
        ),
      ];
}

/// `org.freedesktop.impl.portal.Request` — exported for the duration of a
/// `Start` call; `Close` cancels the pick, resolving `Start` with response 1.
class PortalRequest extends DBusObject {
  PortalRequest(super.path, this._onClose);

  final void Function() _onClose;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != requestInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    if (methodCall.name != 'Close') {
      return DBusMethodErrorResponse.unknownMethod();
    }
    _onClose();
    return DBusMethodSuccessResponse([]);
  }

  @override
  List<DBusIntrospectInterface> introspect() => [
        DBusIntrospectInterface(
          requestInterface,
          methods: [DBusIntrospectMethod('Close')],
        ),
      ];
}
