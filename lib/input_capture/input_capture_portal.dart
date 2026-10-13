import 'dart:async';

import 'package:dbus/dbus.dart';

import '../dbus_service_object.dart';
import '../native/raw_fd_handle.dart';
import '../screencast/screencast_portal.dart' show PortalRequest;
import 'barriers.dart';
import 'capture_controller.dart';
import 'consent_types.dart';
import 'eis_server.dart';
import 'input_capture_log.dart';

/// The xdg-desktop-portal InputCapture *backend* — what lets a Synergy-style
/// application (DeskFlow, Input Leap) take this machine's keyboard and mouse
/// while the pointer is "on" another computer.
///
/// The frontend is the only D-Bus peer. The contract, as the frontend drives it:
///
/// 1. `CreateSession` (interface v1), or `CreateSession2` then `Start` (v2):
///    the user is asked, and the session is granted keyboard and/or pointer.
/// 2. `GetZones`: the monitors, in logical coordinates, with a `zone_set` id.
/// 3. `SetPointerBarriers`: lines on the outer edges of those zones, validated
///    against the `zone_set` they were drawn for.
/// 4. `ConnectToEIS`: a socket the application opens a libei receiver on.
/// 5. `Enable`: barriers armed. Pushing the pointer through one emits
///    `Activated`, and input flows over the EI socket until the application
///    calls `Release` (or the shell ends it with `Deactivated`).
///
/// Both session-creation paths are served because the frontend picks one by
/// the `version` it read off this backend **when it started**: a frontend that
/// came up before the shell took the bus name read nothing, assumes v1, and
/// calls `CreateSession`. Unlike ScreenCast's `AvailableSourceTypes`, which the
/// frontend copies once and which `portal_frontend.dart` has to repair by
/// restarting it, `SupportedCapabilities` is *bound* to the backend's property
/// and refreshes when the name gains an owner — so serving v1 as well is the
/// whole of the repair.
///
/// Flutter-free, like the ScreenCast backend beside it.

const String inputCaptureInterface = 'org.freedesktop.impl.portal.InputCapture';
const String _sessionInterface = 'org.freedesktop.impl.portal.Session';

const int _responseSuccess = 0;
const int _responseCancelled = 1;
const int _responseError = 2;

/// The interface version served. 2 adds `CreateSession2`/`Start`, persistence
/// options this backend ignores (nothing is restored, so nothing is returned),
/// and the clipboard flag it never sets.
const int _interfaceVersion = 2;

/// Where one portal session is.
enum _Stage { created, starting, started }

class _Session implements CaptureClient {
  _Session(this.handle, this.object, this.frontend, this.appId);

  final String handle;
  final InputCaptureSessionObject object;

  /// The frontend's unique name; the session dies with it.
  final String frontend;
  final String appId;

  _Stage stage = _Stage.created;
  int capabilities = 0;
  bool enabled = false;
  List<PlacedBarrier> barriers = const [];
  EisEndpoint? eis;
  bool closed = false;

  /// Set by the backend; signals go through it.
  late InputCapturePortalBackend backend;

  @override
  CapturedInputSink? get sink => eis;

  @override
  String get label => appId.isEmpty ? handle : appId;

  @override
  void activated(int activationId, BarrierCrossing crossing) =>
      backend._emit('Activated', this, {
        'activation_id': DBusUint32(activationId),
        'cursor_position':
            DBusStruct([DBusDouble(crossing.x), DBusDouble(crossing.y)]),
        'barrier_id': DBusUint32(crossing.barrier.id),
      });

  @override
  void deactivated(int activationId, double x, double y) =>
      backend._emit('Deactivated', this, {
        'activation_id': DBusUint32(activationId),
        'cursor_position': DBusStruct([DBusDouble(x), DBusDouble(y)]),
      });

  @override
  void disabledByUser() {
    enabled = false;
    backend._emit('Disabled', this, const {});
  }
}

class InputCapturePortalBackend extends DBusServiceObject {
  /// [emitSignal] reaches the bus for the shared object this backend's
  /// interface is served from (`PortalBus.emitSignal`); [adoptFd] turns
  /// libeis's raw descriptor into something `package:dbus` can send.
  InputCapturePortalBackend(
    this._client,
    this._engine,
    this._consent, {
    required Future<void> Function(
            String interface, String name, List<DBusValue> values)
        emitSignal,
    AdoptedFd Function(int fd) adoptFd = adoptRawFd,
  })  : _emitSignal = emitSignal,
        _adoptFd = adoptFd,
        super(DBusObjectPath('/org/freedesktop/portal/desktop'));

  final DBusClient _client;
  final InputCaptureEngine _engine;
  final InputCaptureConsent _consent;
  final Future<void> Function(
      String interface, String name, List<DBusValue> values) _emitSignal;
  final AdoptedFd Function(int fd) _adoptFd;

  final Map<String, _Session> _sessions = {};
  StreamSubscription<DBusNameOwnerChangedEvent>? _nameOwnerSub;

  Future<void> init() async {
    _nameOwnerSub = _client.nameOwnerChanged.listen(_onNameOwnerChanged);
    _engine.onZonesChanged = _onZonesChanged;
  }

  static DBusIntrospectArgument _in(String signature, String name) =>
      DBusIntrospectArgument(DBusSignature(signature), DBusArgumentDirection.in_,
          name: name);

  static DBusIntrospectArgument _out(String signature, String name) =>
      DBusIntrospectArgument(DBusSignature(signature), DBusArgumentDirection.out,
          name: name);

  static final _responseArgs = [
    _out('u', 'response'),
    _out('a{sv}', 'results'),
  ];

  static DBusIntrospectSignal _signal(String name) => DBusIntrospectSignal(
        name,
        args: [_out('o', 'session_handle'), _out('a{sv}', 'options')],
      );

  @override
  late final List<DBusServiceInterface> interfaces = [
    DBusServiceInterface(
      inputCaptureInterface,
      methods: {
        'CreateSession': DBusServiceMethod(_createSession, args: [
          _in('o', 'handle'),
          _in('o', 'session_handle'),
          _in('s', 'app_id'),
          _in('s', 'parent_window'),
          _in('a{sv}', 'options'),
          ..._responseArgs,
        ]),
        'CreateSession2': DBusServiceMethod(_createSession2, args: [
          _in('o', 'session_handle'),
          _in('s', 'app_id'),
          _in('a{sv}', 'options'),
          _out('a{sv}', 'results'),
        ]),
        'Start': DBusServiceMethod(_start, args: [
          _in('o', 'handle'),
          _in('o', 'session_handle'),
          _in('s', 'app_id'),
          _in('s', 'parent_window'),
          _in('a{sv}', 'options'),
          ..._responseArgs,
        ]),
        'GetZones': DBusServiceMethod(_getZones, args: [
          _in('o', 'handle'),
          _in('o', 'session_handle'),
          _in('s', 'app_id'),
          _in('a{sv}', 'options'),
          ..._responseArgs,
        ]),
        'SetPointerBarriers': DBusServiceMethod(_setPointerBarriers, args: [
          _in('o', 'handle'),
          _in('o', 'session_handle'),
          _in('s', 'app_id'),
          _in('a{sv}', 'options'),
          _in('aa{sv}', 'barriers'),
          _in('u', 'zone_set'),
          ..._responseArgs,
        ]),
        'Enable': DBusServiceMethod(_enable, args: _toggleArgs),
        'Disable': DBusServiceMethod(_disable, args: _toggleArgs),
        'Release': DBusServiceMethod(_release, args: _toggleArgs),
        'ConnectToEIS': DBusServiceMethod(_connectToEis, args: [
          _in('o', 'session_handle'),
          _in('s', 'app_id'),
          _in('a{sv}', 'options'),
          _out('h', 'fd'),
        ]),
      },
      properties: {
        'SupportedCapabilities': DBusServiceProperty(DBusSignature('u'),
            () => DBusUint32(_engine.supportedCapabilities)),
        'version': DBusServiceProperty(
            DBusSignature('u'), () => const DBusUint32(_interfaceVersion)),
      },
      signals: [
        _signal('Disabled'),
        _signal('Activated'),
        _signal('Deactivated'),
        _signal('ZonesChanged'),
      ],
      onError: (call, error) {
        inputCaptureLog('InputCapture ${call.name} failed: $error');
        // The two methods whose reply is not a response code answer with a
        // D-Bus error, which the frontend relays to the application.
        if (call.name == 'CreateSession2' || call.name == 'ConnectToEIS') {
          return DBusMethodErrorResponse.failed('$error');
        }
        return _result(_responseError);
      },
    ),
  ];

  static final _toggleArgs = [
    _in('o', 'session_handle'),
    _in('s', 'app_id'),
    _in('a{sv}', 'options'),
    ..._responseArgs,
  ];

  static DBusMethodResponse _result(int response,
          [Map<String, DBusValue> results = const {}]) =>
      DBusMethodSuccessResponse(
          [DBusUint32(response), DBusDict.stringVariant(results)]);

  static Map<String, DBusValue> _options(DBusValue value) =>
      value is DBusDict ? value.asStringVariantDict() : const {};

  static String _string(DBusValue value) =>
      value is DBusString ? value.value : '';

  static int? _uint(Map<String, DBusValue> options, String key) {
    final value = options[key];
    return value is DBusUint32 ? value.value : null;
  }

  _Session? _sessionAt(DBusValue value) =>
      value is DBusObjectPath ? _sessions[value.value] : null;

  // ---------------------------------------------------------------------------
  // Session creation and consent.
  // ---------------------------------------------------------------------------

  Future<_Session?> _newSession(DBusMethodCall call, DBusValue handleValue,
      DBusValue appValue) async {
    if (handleValue is! DBusObjectPath) return null;
    final handle = handleValue.value;
    if (_sessions.containsKey(handle)) return null;
    final object = InputCaptureSessionObject(DBusObjectPath(handle), this);
    final session =
        _Session(handle, object, call.sender ?? '', _string(appValue))
          ..backend = this;
    _sessions[handle] = session;
    await _client.registerObject(object);
    return session;
  }

  /// v1: create *and* start — the consent prompt happens here.
  Future<DBusMethodResponse> _createSession(DBusMethodCall call) async {
    final v = call.values;
    if (v.length < 5) return DBusMethodErrorResponse.invalidArgs();
    final session = await _newSession(call, v[1], v[2]);
    if (session == null) return _result(_responseError);
    final response = await _ask(session, v[0], _options(v[4]));
    if (response.$1 != _responseSuccess) {
      await _teardown(session.handle);
    }
    return _result(response.$1, response.$2);
  }

  /// v2: create only; [_start] asks.
  Future<DBusMethodResponse> _createSession2(DBusMethodCall call) async {
    final v = call.values;
    if (v.length < 3) return DBusMethodErrorResponse.invalidArgs();
    final session = await _newSession(call, v[0], v[1]);
    if (session == null) {
      return DBusMethodErrorResponse.failed('cannot create this session');
    }
    return DBusMethodSuccessResponse([DBusDict.stringVariant(const {})]);
  }

  Future<DBusMethodResponse> _start(DBusMethodCall call) async {
    final v = call.values;
    if (v.length < 5) return DBusMethodErrorResponse.invalidArgs();
    final session = _sessionAt(v[1]);
    if (session == null || session.stage != _Stage.created) {
      return _result(_responseError);
    }
    final response = await _ask(session, v[0], _options(v[4]));
    return _result(response.$1, response.$2);
  }

  /// The consent prompt, with the frontend's Request exported meanwhile so it
  /// can withdraw the question.
  Future<(int, Map<String, DBusValue>)> _ask(_Session session,
      DBusValue handleValue, Map<String, DBusValue> options) async {
    final requested = _uint(options, 'capabilities') ?? 0;
    final capabilities = requested & _engine.supportedCapabilities;
    if (capabilities == 0) {
      inputCaptureLog('${session.label}: asked for no capability this '
          'backend supports ($requested)');
      return (_responseError, const <String, DBusValue>{});
    }
    session.stage = _Stage.starting;

    final request = handleValue is DBusObjectPath
        ? PortalRequest(handleValue, _consent.cancel)
        : null;
    if (request != null) await _client.registerObject(request);
    bool allowed;
    try {
      allowed = await _consent.ask(InputCaptureConsentRequest(
          appId: session.appId, capabilities: capabilities));
    } finally {
      if (request != null) {
        try {
          await _client.unregisterObject(request);
        } catch (_) {}
      }
    }
    if (session.closed) return (_responseCancelled, const <String, DBusValue>{});
    if (!allowed) {
      session.stage = _Stage.created;
      inputCaptureLog('${session.label}: input capture declined');
      return (_responseCancelled, const <String, DBusValue>{});
    }
    session
      ..stage = _Stage.started
      ..capabilities = capabilities;
    inputCaptureLog('${session.label}: input capture allowed '
        '(capabilities $capabilities)');
    return (
      _responseSuccess,
      <String, DBusValue>{'capabilities': DBusUint32(capabilities)},
    );
  }

  // ---------------------------------------------------------------------------
  // Zones and barriers.
  // ---------------------------------------------------------------------------

  Future<DBusMethodResponse> _getZones(DBusMethodCall call) async {
    final v = call.values;
    if (v.length < 4) return DBusMethodErrorResponse.invalidArgs();
    final session = _sessionAt(v[1]);
    if (session == null || session.stage != _Stage.started) {
      return _result(_responseError);
    }
    return _result(_responseSuccess, {
      'zones': DBusArray(DBusSignature('(uuii)'), [
        for (final zone in _engine.zones)
          DBusStruct([
            DBusUint32(zone.width),
            DBusUint32(zone.height),
            DBusInt32(zone.x),
            DBusInt32(zone.y),
          ]),
      ]),
      'zone_set': DBusUint32(_engine.zoneSet),
    });
  }

  Future<DBusMethodResponse> _setPointerBarriers(DBusMethodCall call) async {
    final v = call.values;
    if (v.length < 6 || v[4] is! DBusArray || v[5] is! DBusUint32) {
      return DBusMethodErrorResponse.invalidArgs();
    }
    final session = _sessionAt(v[1]);
    if (session == null || session.stage != _Stage.started) {
      return _result(_responseError);
    }

    // Type-tested per barrier: a malformed one fails alone.
    final requested = <RequestedBarrier>[];
    final malformed = <int>[];
    for (final entry in (v[4] as DBusArray).children) {
      final barrier = entry is DBusDict ? entry.asStringVariantDict() : null;
      final id = barrier?['barrier_id'];
      final position = barrier?['position'];
      final coords = position is DBusStruct ? position.children : const [];
      if (id is! DBusUint32 ||
          coords.length != 4 ||
          coords.any((c) => c is! DBusInt32)) {
        if (id is DBusUint32) malformed.add(id.value);
        continue;
      }
      final c = [for (final value in coords) (value as DBusInt32).value];
      requested.add(RequestedBarrier(id.value, c[0], c[1], c[2], c[3]));
    }

    // Setting barriers suspends the session; `Enable` arms the new set.
    if (session.enabled) {
      session.enabled = false;
      _engine.disarm(session);
    }

    final zoneSet = (v[5] as DBusUint32).value;
    final List<int> failed;
    if (zoneSet != _engine.zoneSet) {
      inputCaptureLog('${session.label}: barriers drawn for zone set $zoneSet, '
          'but the current one is ${_engine.zoneSet}');
      session.barriers = const [];
      failed = [for (final b in requested) b.id];
    } else {
      final result = placeBarriers(_engine.zones, requested);
      session.barriers = result.placed;
      failed = result.failed;
    }
    failed.addAll(malformed);
    if (failed.isNotEmpty) {
      inputCaptureLog('${session.label}: barriers refused: $failed');
    }
    return _result(_responseSuccess, {
      'failed_barriers': DBusArray.uint32(failed),
    });
  }

  // ---------------------------------------------------------------------------
  // Enable, Disable, Release.
  // ---------------------------------------------------------------------------

  Future<DBusMethodResponse> _enable(DBusMethodCall call) async {
    final session = _sessionAt(call.values.firstOrNull ?? const DBusString(''));
    if (session == null || session.stage != _Stage.started) {
      return _result(_responseError);
    }
    session.enabled = true;
    _engine.arm(session, session.barriers);
    return _result(_responseSuccess);
  }

  Future<DBusMethodResponse> _disable(DBusMethodCall call) async {
    final session = _sessionAt(call.values.firstOrNull ?? const DBusString(''));
    if (session == null) return _result(_responseError);
    session.enabled = false;
    _engine.disarm(session);
    return _result(_responseSuccess);
  }

  Future<DBusMethodResponse> _release(DBusMethodCall call) async {
    final v = call.values;
    if (v.length < 3) return DBusMethodErrorResponse.invalidArgs();
    final session = _sessionAt(v[0]);
    if (session == null) return _result(_responseError);
    final options = _options(v[2]);
    double? x;
    double? y;
    final position = options['cursor_position'];
    if (position is DBusStruct &&
        position.children.length == 2 &&
        position.children.every((c) => c is DBusDouble)) {
      x = (position.children[0] as DBusDouble).value;
      y = (position.children[1] as DBusDouble).value;
    }
    _engine.release(session,
        activationId: _uint(options, 'activation_id'), cursorX: x, cursorY: y);
    return _result(_responseSuccess);
  }

  // ---------------------------------------------------------------------------
  // The EI socket.
  // ---------------------------------------------------------------------------

  Future<DBusMethodResponse> _connectToEis(DBusMethodCall call) async {
    final v = call.values;
    if (v.isEmpty) return DBusMethodErrorResponse.invalidArgs();
    final session = _sessionAt(v[0]);
    if (session == null || session.stage != _Stage.started) {
      return DBusMethodErrorResponse.failed('invalid session');
    }
    if (session.eis != null) {
      return DBusMethodErrorResponse.failed('already connected');
    }
    final eis = _engine.openEis(
        capabilities: session.capabilities, appId: session.appId);
    final AdoptedFd adopted;
    try {
      adopted = _adoptFd(eis.addClient());
    } catch (_) {
      _engine.closeEis(eis);
      rethrow;
    }
    session.eis = eis;
    eis.onDisconnected = () => _engine.clientGone(session);
    // The reply is written synchronously once this returns; the receiver has
    // its own copy by then, and ours would keep the socket alive past the
    // application's exit — which is how libeis notices one.
    adopted.closeSoon();
    return DBusMethodSuccessResponse([DBusUnixFd(adopted.handle)]);
  }

  // ---------------------------------------------------------------------------
  // Signals and teardown.
  // ---------------------------------------------------------------------------

  void _emit(String name, _Session session, Map<String, DBusValue> options) {
    if (session.closed) return;
    unawaited(_emitSignal(inputCaptureInterface, name, [
      DBusObjectPath(session.handle),
      DBusDict.stringVariant(options),
    ]).catchError((Object e) {
      inputCaptureLog('InputCapture: cannot emit $name: $e');
    }));
  }

  /// The layout changed. The engine has already dropped every barrier; each
  /// session keeps its enabled flag and gets new barriers from the
  /// `SetPointerBarriers` + `Enable` the application answers this with.
  void _onZonesChanged() {
    for (final session in _sessions.values) {
      session.barriers = const [];
      if (session.stage != _Stage.started) continue;
      _emit('ZonesChanged', session, {'zone_set': DBusUint32(_engine.zoneSet)});
    }
  }

  /// `Session.Close` from the frontend.
  Future<void> closeSession(InputCaptureSessionObject object) async {
    final handle = _sessions.entries
        .where((e) => identical(e.value.object, object))
        .map((e) => e.key)
        .firstOrNull;
    if (handle != null) await _teardown(handle);
  }

  Future<void> _teardown(String handle, {bool emitClosed = false}) async {
    final session = _sessions.remove(handle);
    if (session == null) return;
    _engine.disarm(session);
    if (session.stage == _Stage.starting) _consent.cancel();
    session.closed = true;
    if (session.eis case final eis?) _engine.closeEis(eis);
    session.eis = null;
    if (emitClosed) {
      try {
        await session.object.emitSignal(_sessionInterface, 'Closed');
      } catch (_) {}
    }
    try {
      await _client.unregisterObject(session.object);
    } catch (_) {}
    inputCaptureLog('InputCapture session closed: $handle');
  }

  void _onNameOwnerChanged(DBusNameOwnerChangedEvent event) {
    if (event.newOwner != null && event.newOwner!.isNotEmpty) return;
    final dead = _sessions.entries
        .where((e) => e.value.frontend == event.name)
        .map((e) => e.key)
        .toList();
    for (final handle in dead) {
      unawaited(_teardown(handle));
    }
  }

  /// Shell shutdown.
  Future<void> dispose() async {
    await _nameOwnerSub?.cancel();
    _engine.onZonesChanged = null;
    for (final handle in _sessions.keys.toList()) {
      await _teardown(handle, emitClosed: true);
    }
  }
}

/// `org.freedesktop.impl.portal.Session` — one per session handle.
class InputCaptureSessionObject extends DBusServiceObject {
  InputCaptureSessionObject(super.path, this._backend);

  final InputCapturePortalBackend _backend;

  @override
  late final List<DBusServiceInterface> interfaces = [
    DBusServiceInterface(
      _sessionInterface,
      methods: {
        'Close': DBusServiceMethod((call) async {
          await _backend.closeSession(this);
          return DBusMethodSuccessResponse([]);
        }),
      },
      properties: {
        'version':
            DBusServiceProperty(DBusSignature('u'), () => const DBusUint32(1)),
      },
      signals: [DBusIntrospectSignal('Closed')],
    ),
  ];
}
