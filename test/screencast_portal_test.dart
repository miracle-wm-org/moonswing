import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/screencast/pick_types.dart';
import 'package:moonswing/screencast/screencast_portal.dart';

/// Drives [ScreenCastPortalBackend] the way xdg-desktop-portal does, with the
/// capture/PipeWire machinery replaced by fakes. What is under test is the
/// portal contract: response codes, the streams payload shape, and that a
/// session cannot be started twice or started without consent.

class _FakeCast implements ActiveCast {
  _FakeCast(this.streams);

  @override
  final List<PortalStreamInfo> streams;
  bool stopped = false;

  @override
  void stop() => stopped = true;
}

class _FakeEngine implements ScreencastEngine {
  _FakeEngine({this.sourceTypes = sourceTypeMonitor | sourceTypeWindow});

  final int sourceTypes;

  /// Answers the next pick. Null declines.
  PickResult? answer = const PickResult([PickedMonitor('DP-1')]);

  /// When set, `pick` waits on this instead of answering immediately, so a
  /// `Request.Close` can arrive mid-pick.
  Completer<PickResult?>? gate;

  PickRequest? lastRequest;
  bool? lastPaintCursors;
  Object? startCastError;
  final List<_FakeCast> casts = [];
  int stoppedCallbackCount = 0;
  void Function()? _onStopped;

  @override
  int get availableSourceTypes => sourceTypes;

  @override
  Future<PickResult?> pick(PickRequest request) {
    lastRequest = request;
    final g = gate;
    if (g != null) return g.future;
    return Future.value(answer);
  }

  @override
  void cancelPick() {
    final g = gate;
    if (g != null && !g.isCompleted) g.complete(null);
  }

  @override
  Future<ActiveCast> startCast(
    PickResult picked, {
    required bool paintCursors,
    required void Function() onStopped,
  }) async {
    lastPaintCursors = paintCursors;
    _onStopped = onStopped;
    if (startCastError != null) throw startCastError!;
    final cast = _FakeCast([
      for (var i = 0; i < picked.sources.length; i++)
        PortalStreamInfo(
          nodeId: 100 + i,
          sourceType: picked.sources[i] is PickedMonitor
              ? sourceTypeMonitor
              : sourceTypeWindow,
          width: 1920,
          height: 1080,
          x: picked.sources[i] is PickedMonitor ? 0 : null,
          y: picked.sources[i] is PickedMonitor ? 0 : null,
        ),
    ]);
    casts.add(cast);
    return cast;
  }

  /// Simulates a monitor being unplugged mid-cast.
  void fireSourceStopped() {
    stoppedCallbackCount++;
    _onStopped?.call();
  }
}

/// A DBusClient stand-in: registerObject/unregisterObject are all the backend
/// uses, plus a nameOwnerChanged stream it subscribes to.
class _FakeClient implements DBusClient {
  final List<DBusObject> registered = [];
  final _nameOwner = StreamController<DBusNameOwnerChangedEvent>.broadcast();

  @override
  Future<void> registerObject(DBusObject object) async {
    registered.add(object);
    // The real client sets this so emitSignal works; without it the object
    // cannot emit and teardown would throw.
    object.client = this;
  }

  @override
  Future<void> unregisterObject(DBusObject object) async {
    registered.remove(object);
  }

  @override
  Stream<DBusNameOwnerChangedEvent> get nameOwnerChanged => _nameOwner.stream;

  final List<String> emittedSignals = [];

  @override
  Future<void> emitSignal({
    String? destination,
    required DBusObjectPath path,
    required String interface,
    required String name,
    Iterable<DBusValue> values = const [],
  }) async {
    emittedSignals.add('${path.value} $interface.$name');
  }

  void killPeer(String name) => _nameOwner.add(
        DBusNameOwnerChangedEvent(name, oldOwner: name, newOwner: ''),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _sessionPath = '/org/freedesktop/portal/desktop/session/1_1/tok';
const _requestPath = '/org/freedesktop/portal/desktop/request/1_1/tok';
const _frontend = ':1.42';

DBusMethodCall _call(String name, List<DBusValue> values,
        {String sender = _frontend}) =>
    DBusMethodCall(
      sender: sender,
      interface: screenCastInterface,
      name: name,
      values: values,
    );

List<DBusValue> _sessionArgs(String appId, [Map<String, DBusValue>? options]) =>
    [
      DBusObjectPath(_requestPath),
      DBusObjectPath(_sessionPath),
      DBusString(appId),
      DBusDict.stringVariant(options ?? {}),
    ];

/// (response, results) from an impl-portal reply.
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

void main() {
  late _FakeEngine engine;
  late _FakeClient client;
  late ScreenCastPortalBackend backend;

  setUp(() async {
    engine = _FakeEngine();
    client = _FakeClient();
    backend = ScreenCastPortalBackend(client, engine);
    await backend.init();
    backend.client = client;
  });

  Future<(int, Map<String, DBusValue>)> createSession(
          {String appId = 'com.example.App'}) async =>
      _unpack(await backend
          .handleMethodCall(_call('CreateSession', _sessionArgs(appId))));

  Future<(int, Map<String, DBusValue>)> selectSources(
          Map<String, DBusValue> options) async =>
      _unpack(await backend.handleMethodCall(
          _call('SelectSources', _sessionArgs('com.example.App', options))));

  Future<(int, Map<String, DBusValue>)> start() async =>
      _unpack(await backend.handleMethodCall(_call('Start', [
        DBusObjectPath(_requestPath),
        DBusObjectPath(_sessionPath),
        const DBusString('com.example.App'),
        const DBusString(''), // parent_window
        DBusDict.stringVariant(const {}),
      ])));

  group('properties', () {
    test('advertises impl version 2 and both source types', () async {
      expect(_property(await backend.getProperty(screenCastInterface, 'version')),
          const DBusUint32(2));
      expect(
          _property(await backend.getProperty(
              screenCastInterface, 'AvailableSourceTypes')),
          const DBusUint32(sourceTypeMonitor | sourceTypeWindow));
    });

    test('offers hidden and embedded cursors, never metadata', () async {
      expect(
          _property(await backend.getProperty(
              screenCastInterface, 'AvailableCursorModes')),
          const DBusUint32(cursorModeHidden | cursorModeEmbedded));
    });

    test('hides window sharing when the compositor cannot do it', () async {
      final monitorOnly = ScreenCastPortalBackend(
          _FakeClient(), _FakeEngine(sourceTypes: sourceTypeMonitor));
      expect(
          _property(await monitorOnly.getProperty(
              screenCastInterface, 'AvailableSourceTypes')),
          const DBusUint32(sourceTypeMonitor));
    });

    test('rejects calls on an unknown interface', () async {
      final response = await backend.handleMethodCall(DBusMethodCall(
        sender: _frontend,
        interface: 'org.freedesktop.impl.portal.Screenshot',
        name: 'Screenshot',
        values: const [],
      ));
      expect(response, isA<DBusMethodErrorResponse>());
    });

    test('a wrong interface name answers unknown-interface, even for a method '
        'this object does serve', () async {
      final response = await backend.handleMethodCall(DBusMethodCall(
        sender: _frontend,
        interface: 'org.freedesktop.impl.portal.RemoteDesktop',
        name: 'CreateSession',
        values: _sessionArgs('com.example.App'),
      ));
      expect(
        (response as DBusMethodErrorResponse).errorName,
        'org.freedesktop.DBus.Error.UnknownInterface',
      );
      // The guard fired before dispatch: no session was created.
      expect(client.registered, isEmpty);
    });
  });

  group('happy path', () {
    test('CreateSession exports a Session object at the given path', () async {
      final (response, results) = await createSession();
      expect(response, 0);
      expect(results, isEmpty);
      expect(
        client.registered.whereType<PortalSession>().single.path.value,
        _sessionPath,
      );
    });

    test('Start returns one stream per picked source', () async {
      await createSession();
      await selectSources({'types': const DBusUint32(sourceTypeMonitor)});
      engine.answer = const PickResult(
          [PickedMonitor('DP-1'), PickedMonitor('HDMI-A-1')]);

      final (response, results) = await start();
      expect(response, 0);

      final streams = (results['streams'] as DBusArray).children;
      expect(streams, hasLength(2));
      final first = (streams.first as DBusStruct).children.toList();
      expect((first[0] as DBusUint32).value, 100);
      final props = (first[1] as DBusDict).asStringVariantDict();
      expect(props['source_type'], const DBusUint32(sourceTypeMonitor));
      expect((props['size'] as DBusStruct).children.toList(),
          [const DBusInt32(1920), const DBusInt32(1080)]);
      expect(props['position'], isNotNull);
    });

    test('a window stream carries no position, since a window has none',
        () async {
      await createSession();
      await selectSources({'types': const DBusUint32(sourceTypeWindow)});
      engine.answer = const PickResult([PickedWindow('toplevel:3', 'Editor')]);

      final (_, results) = await start();
      final stream = ((results['streams'] as DBusArray).children.single
          as DBusStruct);
      final props =
          (stream.children.toList()[1] as DBusDict).asStringVariantDict();
      expect(props['source_type'], const DBusUint32(sourceTypeWindow));
      expect(props.containsKey('position'), isFalse);
    });
  });

  group('SelectSources options', () {
    test('passes the requested source types through to the picker', () async {
      await createSession();
      await selectSources({
        'types': const DBusUint32(sourceTypeWindow),
        'multiple': const DBusBoolean(true),
      });
      await start();

      expect(engine.lastRequest!.windows, isTrue);
      expect(engine.lastRequest!.monitors, isFalse);
      expect(engine.lastRequest!.multiple, isTrue);
    });

    test('embedded cursor mode asks the capture layer to paint cursors',
        () async {
      await createSession();
      await selectSources({'cursor_mode': const DBusUint32(cursorModeEmbedded)});
      await start();
      expect(engine.lastPaintCursors, isTrue);
    });

    test('hidden cursor mode is the default', () async {
      await createSession();
      await selectSources({});
      await start();
      expect(engine.lastPaintCursors, isFalse);
    });

    test('a source type the compositor cannot serve falls back to monitors',
        () async {
      final monitorOnlyEngine = _FakeEngine(sourceTypes: sourceTypeMonitor);
      final monitorOnly =
          ScreenCastPortalBackend(_FakeClient(), monitorOnlyEngine);
      await monitorOnly.handleMethodCall(
          _call('CreateSession', _sessionArgs('com.example.App')));
      await monitorOnly.handleMethodCall(_call(
          'SelectSources',
          _sessionArgs('com.example.App',
              {'types': const DBusUint32(sourceTypeWindow)})));
      await monitorOnly.handleMethodCall(_call('Start', [
        DBusObjectPath(_requestPath),
        DBusObjectPath(_sessionPath),
        const DBusString('com.example.App'),
        const DBusString(''),
        DBusDict.stringVariant(const {}),
      ]));
      expect(monitorOnlyEngine.lastRequest!.monitors, isTrue);
      expect(monitorOnlyEngine.lastRequest!.windows, isFalse);
    });

    test('a wrongly-typed option is ignored rather than failing the call',
        () async {
      await createSession();
      final (response, _) =
          await selectSources({'types': const DBusString('monitor')});
      expect(response, 0);
      await start();
      expect(engine.lastRequest!.monitors, isTrue);
    });
  });

  group('refusal paths', () {
    test('declining the pick answers cancelled, with no streams', () async {
      await createSession();
      await selectSources({});
      engine.answer = null;

      final (response, results) = await start();
      expect(response, 1);
      expect(results, isEmpty);
      expect(engine.casts, isEmpty);
    });

    test('an empty selection is a refusal, not an empty share', () async {
      await createSession();
      await selectSources({});
      engine.answer = const PickResult([]);
      final (response, _) = await start();
      expect(response, 1);
    });

    test('Request.Close cancels a pick that is still on screen', () async {
      await createSession();
      await selectSources({});
      engine.gate = Completer<PickResult?>();

      final pending = start();
      await pumpEventQueue();

      final request = client.registered.whereType<PortalRequest>().single;
      expect(request.path.value, _requestPath);
      await request.handleMethodCall(DBusMethodCall(
        sender: _frontend,
        interface: requestInterface,
        name: 'Close',
        values: const [],
      ));

      final (response, _) = await pending;
      expect(response, 1);
      // The Request object is unexported once Start returns either way.
      expect(client.registered.whereType<PortalRequest>(), isEmpty);
    });

    test('Start reports an error when the capture layer cannot start',
        () async {
      await createSession();
      await selectSources({});
      engine.startCastError = StateError('monitor vanished');
      final (response, _) = await start();
      expect(response, 2);
    });

    test('Start on an unknown session is an error, not a crash', () async {
      final (response, _) = await start();
      expect(response, 2);
    });

    test('a session cannot be started twice', () async {
      await createSession();
      await selectSources({});
      expect((await start()).$1, 0);
      expect((await start()).$1, 2);
    });

    test('CreateSession twice on one path is refused', () async {
      expect((await createSession()).$1, 0);
      expect((await createSession()).$1, 2);
    });
  });

  group('teardown', () {
    test('Session.Close stops the cast and unexports the object', () async {
      await createSession();
      await selectSources({});
      await start();

      final session = client.registered.whereType<PortalSession>().single;
      await session.handleMethodCall(DBusMethodCall(
        sender: _frontend,
        interface: sessionInterface,
        name: 'Close',
        values: const [],
      ));

      expect(engine.casts.single.stopped, isTrue);
      expect(client.registered.whereType<PortalSession>(), isEmpty);
    });

    test('the frontend dying tears every session down', () async {
      await createSession();
      await selectSources({});
      await start();

      client.killPeer(_frontend);
      await pumpEventQueue();

      expect(engine.casts.single.stopped, isTrue);
      expect(client.registered.whereType<PortalSession>(), isEmpty);
    });

    test('an unrelated peer dying leaves the session alone', () async {
      await createSession();
      await selectSources({});
      await start();

      client.killPeer(':1.99');
      await pumpEventQueue();

      expect(engine.casts.single.stopped, isFalse);
      expect(client.registered.whereType<PortalSession>(), hasLength(1));
    });

    test('a source disappearing closes the session', () async {
      await createSession();
      await selectSources({});
      await start();

      engine.fireSourceStopped();
      await pumpEventQueue();

      expect(engine.casts.single.stopped, isTrue);
      expect(client.registered.whereType<PortalSession>(), isEmpty);
    });

    test('closeAllSessions stops everything (shell shutdown)', () async {
      await createSession();
      await selectSources({});
      await start();

      await backend.closeAllSessions();
      expect(engine.casts.single.stopped, isTrue);
      expect(client.registered.whereType<PortalSession>(), isEmpty);
    });
  });
}
