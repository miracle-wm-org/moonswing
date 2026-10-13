import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/input_capture/barriers.dart';
import 'package:moonswing/input_capture/capture_controller.dart';
import 'package:moonswing/input_capture/consent_types.dart';
import 'package:moonswing/input_capture/eis_server.dart';
import 'package:moonswing/input_capture/input_capture_portal.dart';
import 'package:moonswing/native/libc.dart';

/// Drives [InputCapturePortalBackend] the way xdg-desktop-portal does — both
/// session paths, zones, barriers, the EI socket and the signals — over the
/// real [CaptureController], with Wayland and libeis replaced by fakes.

class _FakeSurfaces implements CaptureSurfaces {
  Set<StripKey> strips = {};
  CaptureZone? capturing;

  @override
  void showStrips(Set<StripKey> strips) => this.strips = Set.of(strips);

  @override
  void beginCapture(CaptureZone zone) => capturing = zone;

  @override
  void endCapture({double? hintX, double? hintY}) => capturing = null;
}

class _FakeEndpoint implements EisEndpoint {
  final List<String> log = [];
  bool disposed = false;

  @override
  void Function()? onDisconnected;

  /// A real descriptor, so the backend's fd adoption runs for real.
  @override
  int addClient() => memfdCreate('input-capture-test');

  @override
  void setKeymap(int fd, int size) {}

  @override
  void dispatch() {}

  @override
  void dispose() => disposed = true;

  @override
  void start(int sequence) => log.add('start $sequence');

  @override
  void stop() => log.add('stop');

  @override
  void pointerMotion(double dx, double dy) => log.add('motion');

  @override
  void pointerButton(int button, bool pressed) {}

  @override
  void scrollDelta(double dx, double dy) {}

  @override
  void scrollDiscrete(int dx, int dy) {}

  @override
  void scrollStop(bool x, bool y) {}

  @override
  void key(int keycode, bool pressed) {}

  @override
  void modifiers(int depressed, int latched, int locked, int group) {}
}

class _FakeConsent implements InputCaptureConsent {
  bool answer = true;
  final List<InputCaptureConsentRequest> asked = [];
  Completer<bool>? _pending;
  bool hold = false;

  @override
  Future<bool> ask(InputCaptureConsentRequest request) {
    asked.add(request);
    if (!hold) return Future.value(answer);
    final pending = Completer<bool>();
    _pending = pending;
    return pending.future;
  }

  @override
  void cancel() {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(false);
  }
}

class _FakeClient implements DBusClient {
  final List<DBusObject> registered = [];
  final _nameOwner = StreamController<DBusNameOwnerChangedEvent>.broadcast();

  @override
  Future<void> registerObject(DBusObject object) async {
    registered.add(object);
    object.client = this;
  }

  @override
  Future<void> unregisterObject(DBusObject object) async {
    registered.remove(object);
  }

  @override
  Stream<DBusNameOwnerChangedEvent> get nameOwnerChanged => _nameOwner.stream;

  @override
  Future<void> emitSignal({
    String? destination,
    required DBusObjectPath path,
    required String interface,
    required String name,
    Iterable<DBusValue> values = const [],
  }) async {}

  void killPeer(String name) => _nameOwner.add(
        DBusNameOwnerChangedEvent(name, oldOwner: name, newOwner: ''),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _session = '/org/freedesktop/portal/desktop/session/1_1/tok';
const _request = '/org/freedesktop/portal/desktop/request/1_1/tok';
const _frontend = ':1.42';
const _app = 'org.deskflow.deskflow';

const _left = CaptureZone(x: 0, y: 0, width: 1920, height: 1080, connector: 'DP-1');
const _right =
    CaptureZone(x: 1920, y: 0, width: 1920, height: 1080, connector: 'DP-2');

DBusMethodCall _call(String name, List<DBusValue> values) => DBusMethodCall(
      sender: _frontend,
      interface: inputCaptureInterface,
      name: name,
      values: values,
    );

(int, Map<String, DBusValue>) _unpack(DBusMethodResponse response) {
  final values = (response as DBusMethodSuccessResponse).values;
  return (
    (values[0] as DBusUint32).value,
    (values[1] as DBusDict).asStringVariantDict(),
  );
}

/// `DBusGetPropertyResponse` wraps the value in a variant in `values[0]`.
DBusValue _property(DBusMethodResponse response) =>
    ((response as DBusMethodSuccessResponse).values.single as DBusVariant)
        .value;

DBusDict _caps(int caps) =>
    DBusDict.stringVariant({'capabilities': DBusUint32(caps)});

DBusDict _barrier(int id, int x1, int y1, int x2, int y2) =>
    DBusDict.stringVariant({
      'barrier_id': DBusUint32(id),
      'position': DBusStruct(
          [DBusInt32(x1), DBusInt32(y1), DBusInt32(x2), DBusInt32(y2)]),
    });

void main() {
  late _FakeSurfaces surfaces;
  late CaptureController engine;
  late _FakeConsent consent;
  late _FakeClient client;
  late InputCapturePortalBackend backend;
  late List<(String, String, Map<String, DBusValue>)> signals;
  late List<_FakeEndpoint> endpoints;

  setUp(() async {
    surfaces = _FakeSurfaces();
    endpoints = [];
    engine = CaptureController(
      surfaces: surfaces,
      eisFactory: (caps, appId) {
        final endpoint = _FakeEndpoint();
        endpoints.add(endpoint);
        return endpoint;
      },
    );
    engine.updateZones([_left, _right]);
    consent = _FakeConsent();
    client = _FakeClient();
    signals = [];
    backend = InputCapturePortalBackend(
      client,
      engine,
      consent,
      emitSignal: (interface, name, values) async {
        signals.add((
          name,
          (values[0] as DBusObjectPath).value,
          (values[1] as DBusDict).asStringVariantDict(),
        ));
      },
    );
    await backend.init();
  });

  Future<(int, Map<String, DBusValue>)> createSessionV1([int caps = 3]) async =>
      _unpack(await backend.handleMethodCall(_call('CreateSession', [
        DBusObjectPath(_request),
        DBusObjectPath(_session),
        const DBusString(_app),
        const DBusString(''),
        _caps(caps),
      ])));

  Future<DBusMethodResponse> createSession2() => backend.handleMethodCall(
        _call('CreateSession2', [
          DBusObjectPath(_session),
          const DBusString(_app),
          DBusDict.stringVariant(const {}),
        ]),
      );

  Future<(int, Map<String, DBusValue>)> start([int caps = 3]) async =>
      _unpack(await backend.handleMethodCall(_call('Start', [
        DBusObjectPath(_request),
        DBusObjectPath(_session),
        const DBusString(_app),
        const DBusString(''),
        _caps(caps),
      ])));

  Future<(int, Map<String, DBusValue>)> getZones() async =>
      _unpack(await backend.handleMethodCall(_call('GetZones', [
        DBusObjectPath(_request),
        DBusObjectPath(_session),
        const DBusString(_app),
        DBusDict.stringVariant(const {}),
      ])));

  Future<(int, Map<String, DBusValue>)> setBarriers(
          List<DBusDict> barriers, int zoneSet) async =>
      _unpack(await backend.handleMethodCall(_call('SetPointerBarriers', [
        DBusObjectPath(_request),
        DBusObjectPath(_session),
        const DBusString(_app),
        DBusDict.stringVariant(const {}),
        DBusArray(DBusSignature('a{sv}'), barriers),
        DBusUint32(zoneSet),
      ])));

  Future<DBusMethodResponse> simple(String name,
          [Map<String, DBusValue> options = const {}]) =>
      backend.handleMethodCall(_call(name, [
        DBusObjectPath(_session),
        const DBusString(_app),
        DBusDict.stringVariant(options),
      ]));

  /// The whole of DeskFlow's opening, up to an armed right-hand barrier.
  Future<void> armRightEdge() async {
    expect((await createSessionV1()).$1, 0);
    final zoneSet = ((await getZones()).$2['zone_set'] as DBusUint32).value;
    final failed = (await setBarriers(
            [_barrier(1, 3840, 0, 3840, 1079)], zoneSet))
        .$2['failed_barriers'] as DBusArray;
    expect(failed.children, isEmpty);
    final eis = await simple('ConnectToEIS');
    expect((eis as DBusMethodSuccessResponse).values.single, isA<DBusUnixFd>());
    expect(_unpack(await simple('Enable')).$1, 0);
  }

  test('advertises keyboard and pointer, and interface version 2', () async {
    final caps = await backend.getProperty(
        inputCaptureInterface, 'SupportedCapabilities');
    expect(_property(caps), const DBusUint32(3));
    final version = await backend.getProperty(inputCaptureInterface, 'version');
    expect(_property(version), const DBusUint32(2));
  });

  test('v1 CreateSession asks, and grants what was asked for and supported',
      () async {
    final (response, results) = await createSessionV1(1 | 2 | 4);
    expect(response, 0);
    expect((results['capabilities'] as DBusUint32).value, 3,
        reason: 'touchscreen is not offered');
    expect(consent.asked.single.appId, _app);
    expect(client.registered.whereType<InputCaptureSessionObject>(), hasLength(1));
  });

  test('a declined v1 session answers 1 and is gone', () async {
    consent.answer = false;
    expect((await createSessionV1()).$1, 1);
    expect(client.registered, isEmpty);
    expect((await getZones()).$1, 2);
  });

  test('v2: CreateSession2 asks nothing; Start asks, once', () async {
    final created = await createSession2();
    expect(created, isA<DBusMethodSuccessResponse>());
    expect(consent.asked, isEmpty);
    expect((await getZones()).$1, 2, reason: 'not started yet');

    expect((await start()).$1, 0);
    expect(consent.asked, hasLength(1));
    expect((await start()).$1, 2, reason: 'Start may only be called once');
  });

  test('closing the Request withdraws the question', () async {
    consent.hold = true;
    final pending = createSessionV1();
    await Future<void>.delayed(Duration.zero);
    expect(client.registered.whereType<DBusObject>().map((o) => o.path.value),
        contains(_request));
    consent.cancel();
    expect((await pending).$1, 1);
  });

  test('GetZones reports width, height, x, y and a zone set', () async {
    await createSessionV1();
    final (response, results) = await getZones();
    expect(response, 0);
    final zones = (results['zones'] as DBusArray).children.cast<DBusStruct>();
    expect(zones.map((z) => z.children.map((v) => v.toNative()).toList()), [
      [1920, 1080, 0, 0],
      [1920, 1080, 1920, 0],
    ]);
    expect((results['zone_set'] as DBusUint32).value, engine.zoneSet);
  });

  test('SetPointerBarriers reports inside, malformed and stale barriers',
      () async {
    await createSessionV1();
    final zoneSet = engine.zoneSet;
    final (_, results) = await setBarriers([
      _barrier(1, 3840, 0, 3840, 1079),
      _barrier(2, 1920, 0, 1920, 1079), // between the monitors
      DBusDict.stringVariant({'barrier_id': const DBusUint32(3)}),
    ], zoneSet);
    expect((results['failed_barriers'] as DBusArray).children.map((v) => v.toNative()),
        [2, 3]);

    final stale = await setBarriers(
        [_barrier(4, 3840, 0, 3840, 1079)], zoneSet + 7);
    expect((stale.$2['failed_barriers'] as DBusArray).children.map((v) => v.toNative()),
        [4]);
  });

  test('Enable arms; a push activates; Release ends it with no signal',
      () async {
    await armRightEdge();
    expect(surfaces.strips, {const StripKey(_right, BarrierEdge.right)});

    engine.pointerOnStrip(
        const StripKey(_right, BarrierEdge.right), 3839.5, 200);
    engine.relativeMotion(3, 0);

    final activated = signals.single;
    expect(activated.$1, 'Activated');
    expect(activated.$2, _session);
    expect((activated.$3['barrier_id'] as DBusUint32).value, 1);
    final id = (activated.$3['activation_id'] as DBusUint32).value;
    expect(endpoints.single.log.first, 'start $id');
    final position = activated.$3['cursor_position'] as DBusStruct;
    expect((position.children[0] as DBusDouble).value, greaterThanOrEqualTo(3840));

    await simple('Release', {
      'activation_id': DBusUint32(id),
      'cursor_position':
          DBusStruct([const DBusDouble(3830), const DBusDouble(200)]),
    });
    expect(engine.isActive, isFalse);
    expect(signals, hasLength(1));
  });

  test('SetPointerBarriers suspends an enabled session until Enable', () async {
    await armRightEdge();
    await setBarriers([_barrier(5, 0, 0, 0, 1079)], engine.zoneSet);
    expect(surfaces.strips, isEmpty);
    await simple('Enable');
    expect(surfaces.strips, {const StripKey(_left, BarrierEdge.left)});
  });

  test('a zone change deactivates, then says ZonesChanged', () async {
    await armRightEdge();
    engine.pointerOnStrip(
        const StripKey(_right, BarrierEdge.right), 3839.5, 200);
    engine.relativeMotion(3, 0);

    engine.updateZones([_left]);
    expect(signals.map((s) => s.$1), ['Activated', 'Deactivated', 'ZonesChanged']);
    expect((signals.last.$3['zone_set'] as DBusUint32).value, engine.zoneSet);
  });

  test('a second ConnectToEIS is refused', () async {
    await armRightEdge();
    expect(await simple('ConnectToEIS'), isA<DBusMethodErrorResponse>());
  });

  test('the frontend going away closes its sessions and their sockets',
      () async {
    await armRightEdge();
    client.killPeer(_frontend);
    await Future<void>.delayed(Duration.zero);
    expect(client.registered, isEmpty);
    expect(surfaces.strips, isEmpty);
    expect(endpoints.single.disposed, isTrue);
  });

  test('Session.Close mid-capture ends it without a signal', () async {
    await armRightEdge();
    engine.pointerOnStrip(
        const StripKey(_right, BarrierEdge.right), 3839.5, 200);
    engine.relativeMotion(3, 0);
    final object =
        client.registered.whereType<InputCaptureSessionObject>().single;
    await object.handleMethodCall(DBusMethodCall(
      sender: _frontend,
      interface: 'org.freedesktop.impl.portal.Session',
      name: 'Close',
    ));
    expect(engine.isActive, isFalse);
    expect(signals.map((s) => s.$1), ['Activated']);
  });
}
