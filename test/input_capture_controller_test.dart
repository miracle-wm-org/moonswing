import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/input_capture/barriers.dart';
import 'package:moonswing/input_capture/capture_controller.dart';
import 'package:moonswing/input_capture/eis_server.dart';
import 'package:moonswing/native/libc.dart';

/// The input-capture state machine with Wayland and libeis replaced by
/// recorders: what arms which strips, what activates, where the input goes while
/// captured, and every way a capture ends.

class _FakeSurfaces implements CaptureSurfaces {
  Set<StripKey> strips = {};
  CaptureZone? capturing;
  final List<(double?, double?)> ended = [];

  @override
  void showStrips(Set<StripKey> strips) => this.strips = Set.of(strips);

  @override
  void beginCapture(CaptureZone zone) => capturing = zone;

  @override
  void endCapture({double? hintX, double? hintY}) {
    if (capturing == null) return;
    capturing = null;
    ended.add((hintX, hintY));
  }
}

class _RecordingSink implements EisEndpoint {
  final List<String> log = [];
  (int, int)? keymap;
  bool disposed = false;

  @override
  void Function()? onDisconnected;

  @override
  int addClient() => -1;

  @override
  void setKeymap(int fd, int size) => keymap = (fd, size);

  @override
  void dispatch() {}

  @override
  void dispose() => disposed = true;

  @override
  void start(int sequence) => log.add('start $sequence');

  @override
  void stop() => log.add('stop');

  @override
  void pointerMotion(double dx, double dy) => log.add('motion $dx $dy');

  @override
  void pointerButton(int button, bool pressed) =>
      log.add('button $button $pressed');

  @override
  void scrollDelta(double dx, double dy) => log.add('scroll $dx $dy');

  @override
  void scrollDiscrete(int dx, int dy) => log.add('discrete $dx $dy');

  @override
  void scrollStop(bool x, bool y) => log.add('scrollstop $x $y');

  @override
  void key(int keycode, bool pressed) => log.add('key $keycode $pressed');

  @override
  void modifiers(int depressed, int latched, int locked, int group) =>
      log.add('mods $depressed $locked');
}

class _Client implements CaptureClient {
  _Client(this.sink);

  @override
  _RecordingSink? sink;

  @override
  String get label => 'test';

  final List<String> signals = [];
  BarrierCrossing? lastCrossing;

  @override
  void activated(int activationId, BarrierCrossing crossing) {
    lastCrossing = crossing;
    signals.add('activated $activationId');
  }

  @override
  void deactivated(int activationId, double x, double y) =>
      signals.add('deactivated $activationId');

  @override
  void disabledByUser() => signals.add('disabled');
}

const _zone = CaptureZone(x: 0, y: 0, width: 1920, height: 1080, connector: 'DP-1');
const _rightStrip = StripKey(_zone, BarrierEdge.right);

void main() {
  late _FakeSurfaces surfaces;
  late CaptureController controller;
  late _Client client;
  late List<PlacedBarrier> barriers;

  setUp(() {
    surfaces = _FakeSurfaces();
    controller = CaptureController(
      surfaces: surfaces,
      eisFactory: (caps, appId) => _RecordingSink(),
    );
    controller.updateZones([_zone]);
    client = _Client(_RecordingSink());
    barriers = placeBarriers(
            [_zone], [const RequestedBarrier(7, 1920, 0, 1920, 1079)])
        .placed;
  });

  void pushThrough() {
    controller.pointerOnStrip(_rightStrip, 1919.5, 300);
    controller.relativeMotion(2, 0);
  }

  test('arming makes the strip, disarming removes it', () {
    controller.arm(client, barriers);
    expect(surfaces.strips, {_rightStrip});
    controller.disarm(client);
    expect(surfaces.strips, isEmpty);
  });

  test('an outward push on the strip activates, with the sequence first', () {
    controller.arm(client, barriers);
    pushThrough();

    expect(controller.isActive, isTrue);
    expect(surfaces.capturing, _zone);
    expect(surfaces.strips, isEmpty, reason: 'strips come down while captured');
    expect(client.signals, ['activated 1']);
    expect(client.lastCrossing!.barrier.id, 7);
    expect(client.sink!.log.first, 'start 1',
        reason: 'start_emulating carries the activation_id');
  });

  test('a push along the strip, or with no strip under the pointer, does not',
      () {
    controller.arm(client, barriers);
    controller.pointerOnStrip(_rightStrip, 1919.5, 300);
    controller.relativeMotion(0, 5);
    controller.pointerLeftStrip();
    controller.relativeMotion(5, 0);
    expect(controller.isActive, isFalse);
  });

  test('a session with no EI socket is never activated', () {
    client.sink = null;
    controller.arm(client, barriers);
    pushThrough();
    expect(controller.isActive, isFalse);
  });

  test('captured input reaches the sink, and nothing after release', () {
    controller.arm(client, barriers);
    pushThrough();
    final sink = client.sink!;
    sink.log.clear();

    controller.relativeMotion(3, -1);
    controller.button(0x110, true);
    controller.key(30, true);
    controller.axisValue120(0, 120);
    controller.frame();
    controller.axis(1, 4.5);
    controller.frame();

    expect(sink.log, [
      'motion 3.0 -1.0',
      'button 272 true',
      'key 30 true',
      'discrete 0 120',
      'scroll 4.5 0.0',
    ]);

    controller.release(client, activationId: 1, cursorX: 1900, cursorY: 300);
    expect(sink.log.last, 'stop');
    expect(surfaces.ended.single, (1900.0, 300.0));
    expect(surfaces.strips, {_rightStrip}, reason: 'still armed');
    expect(client.signals, ['activated 1'],
        reason: 'Release is answered by no signal');

    sink.log.clear();
    controller.relativeMotion(3, 0);
    expect(sink.log, isEmpty);
  });

  test('a Release naming an older activation is ignored', () {
    controller.arm(client, barriers);
    pushThrough();
    controller.release(client, activationId: 99);
    expect(controller.isActive, isTrue);
  });

  test('Super+Shift+Escape deactivates and disables, in that order', () {
    controller.arm(client, barriers);
    pushThrough();
    controller.keyboardEnter(const []);
    controller.key(keyLeftMeta, true);
    controller.key(keyLeftShift, true);
    controller.key(keyEsc, true);

    expect(controller.isActive, isFalse);
    expect(client.signals, ['activated 1', 'deactivated 1', 'disabled']);
    expect(surfaces.strips, isEmpty,
        reason: 'disabled, so the next push cannot take input straight back');
    expect(client.sink!.log, isNot(contains('key $keyEsc true')),
        reason: 'the chord itself never reaches the other machine');
  });

  test('losing the keyboard while captured deactivates', () {
    controller.arm(client, barriers);
    pushThrough();
    controller.keyboardLeave();
    expect(client.signals, ['activated 1', 'deactivated 1']);
    expect(surfaces.strips, {_rightStrip});
  });

  test('a zone change ends the capture, drops barriers and bumps the set', () {
    var changed = 0;
    controller.onZonesChanged = () => changed++;
    final before = controller.zoneSet;
    controller.arm(client, barriers);
    pushThrough();

    controller.updateZones(
        [const CaptureZone(x: 0, y: 0, width: 2560, height: 1440)]);
    expect(changed, 1);
    expect(controller.zoneSet, isNot(before));
    expect(client.signals.last, 'deactivated 1');
    expect(surfaces.strips, isEmpty);

    // The same layout again is no change at all.
    controller.updateZones(
        [const CaptureZone(x: 0, y: 0, width: 2560, height: 1440)]);
    expect(changed, 1);
  });

  test('activation ids increase across captures', () {
    controller.arm(client, barriers);
    pushThrough();
    controller.release(client);
    pushThrough();
    expect(client.signals, ['activated 1', 'activated 2']);
  });

  test('the keymap is lent to every endpoint, current ones and later ones', () {
    final first = controller.openEis(capabilities: 3, appId: 'a')
        as _RecordingSink;
    final fd = memfdCreate('keymap-test');
    controller.keymap(fd, 64);
    expect(first.keymap, (fd, 64));
    final second = controller.openEis(capabilities: 3, appId: 'b')
        as _RecordingSink;
    expect(second.keymap, (fd, 64));
    controller.closeEis(first);
    expect(first.disposed, isTrue);
    expect(controller.endpoints, [second]);
    // Owns the fd, and closes it.
    controller.dispose();
  });
}
