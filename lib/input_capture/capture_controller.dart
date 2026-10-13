// What happens between an application arming its barriers and getting its input
// back — the input-capture state machine, with the Wayland half behind
// [CaptureSurfaces] so a test can drive every transition without a compositor.
//
// Three states, one capture at a time for the whole machine:
//
// - **Idle**: no session has barriers armed. No surfaces exist.
// - **Armed**: at least one session called `Enable` with barriers. A one-pixel
//   strip sits along every zone edge any of them is on, and a push outward
//   while the pointer is on one of those strips crosses the barrier.
// - **Active**: a barrier was crossed. A transparent surface covers that
//   output, takes the keyboard and locks the pointer, and every key, button,
//   scroll and relative motion goes to the activated session's EI socket
//   instead of to any application on this machine.
//
// Capture ends three ways, and only one of them is the application's: its
// `Release` (no signal, it asked); the shell's own reasons — the zones changed,
// the capture surface lost the keyboard (a session lock, a compositor that took
// focus back), the EI client went away — which deactivate with a `Deactivated`
// signal; and the **escape chord**, Super+Shift+Escape, which also *disables*
// the session. That chord is the user's guarantee: a misbehaving or wedged
// application holding the keyboard and mouse can always be made to let go, and
// cannot simply take them again on the next push against the edge.
//
// Flutter-free.

import 'dart:io';

import 'barriers.dart';
import 'eis_server.dart';
import 'input_capture_log.dart';
import '../native/libc.dart';

/// evdev codes the escape chord is made of.
const int keyEsc = 1;
const int keyLeftShift = 42;
const int keyRightShift = 54;
const int keyLeftMeta = 125;
const int keyRightMeta = 126;

/// `wl_pointer.axis`.
const int _axisVertical = 0;
const int _axisHorizontal = 1;

/// One zone edge that needs a strip.
class StripKey {
  const StripKey(this.zone, this.edge);

  final CaptureZone zone;
  final BarrierEdge edge;

  @override
  bool operator ==(Object other) =>
      other is StripKey && other.zone == zone && other.edge == edge;

  @override
  int get hashCode => Object.hash(zone, edge);

  @override
  String toString() => 'StripKey(${edge.name} of $zone)';
}

/// The Wayland half: making and removing surfaces. Everything it observes comes
/// back through the controller's input methods.
abstract class CaptureSurfaces {
  /// Makes exactly these strips exist.
  void showStrips(Set<StripKey> strips);

  /// Covers [zone]'s output, takes the keyboard and locks the pointer.
  void beginCapture(CaptureZone zone);

  /// Undoes [beginCapture], suggesting the cursor end up at global ([hintX],
  /// [hintY]) when given.
  void endCapture({double? hintX, double? hintY});
}

/// One portal session, as the controller sees it.
abstract class CaptureClient {
  /// Where captured input goes; null until `ConnectToEIS`.
  CapturedInputSink? get sink;

  /// For the log.
  String get label;

  void activated(int activationId, BarrierCrossing crossing);
  void deactivated(int activationId, double x, double y);

  /// The user took input back with the escape chord; the session is no longer
  /// enabled.
  void disabledByUser();
}

/// What the portal backend needs from the capture machinery — a seam so
/// `test/input_capture_portal_test.dart` can drive the backend with a fake.
abstract class InputCaptureEngine {
  /// `SupportedCapabilities`.
  int get supportedCapabilities;

  List<CaptureZone> get zones;

  /// Changes whenever [zones] does; `SetPointerBarriers` must quote the current
  /// one.
  int get zoneSet;

  /// The zones changed. Every session's barriers are already gone.
  set onZonesChanged(void Function()? callback);

  /// A new EI endpoint for a session granted [capabilities]. Throws when the
  /// machine has no libeis.
  EisEndpoint openEis({required int capabilities, required String appId});

  /// Disposes an endpoint [openEis] made.
  void closeEis(EisEndpoint endpoint);

  /// [client]'s EI connection went away; a capture it holds ends.
  void clientGone(CaptureClient client);

  /// Arms [barriers] for [client], replacing any it had.
  void arm(CaptureClient client, List<PlacedBarrier> barriers);

  /// Disarms [client], ending its capture (with no signal) if it has one.
  void disarm(CaptureClient client);

  /// The application's `Release`. Ignored unless [activationId] (when given)
  /// names the capture that is running.
  void release(CaptureClient client,
      {int? activationId, double? cursorX, double? cursorY});
}

class CaptureController implements InputCaptureEngine {
  CaptureController({
    required CaptureSurfaces surfaces,
    required EisEndpoint Function(int capabilities, String appId) eisFactory,
    int capabilities = captureCapKeyboard | captureCapPointer,
    int firstActivationId = 0,
  })  : _surfaces = surfaces,
        _eisFactory = eisFactory,
        supportedCapabilities = capabilities,
        _activationId = firstActivationId;

  final CaptureSurfaces _surfaces;
  final EisEndpoint Function(int capabilities, String appId) _eisFactory;

  @override
  final int supportedCapabilities;

  List<CaptureZone> _zones = const [];
  int _zoneSet = 1;

  @override
  List<CaptureZone> get zones => _zones;

  @override
  int get zoneSet => _zoneSet;

  @override
  set onZonesChanged(void Function()? callback) => _onZonesChanged = callback;
  void Function()? _onZonesChanged;

  /// Insertion-ordered, so with two sessions armed on one edge the earlier one
  /// wins, consistently.
  final Map<CaptureClient, List<PlacedBarrier>> _armed = {};

  final Set<EisEndpoint> _endpoints = {};

  /// The compositor's keymap, owned here and lent to every endpoint.
  int _keymapFd = -1;
  int _keymapSize = 0;
  List<int>? _keymapContents;

  int _depressed = 0;
  int _latched = 0;
  int _locked = 0;
  int _group = 0;

  // Armed: where on which strip the pointer is.
  StripKey? _hover;
  double _px = 0;
  double _py = 0;

  // Active.
  CaptureClient? _active;
  int _activationId;
  double _cursorX = 0;
  double _cursorY = 0;

  /// Keys down while the capture surface has the keyboard — the escape chord's
  /// only input, kept here rather than read from the modifier mask because the
  /// mask's bit for Super depends on the keymap.
  final Set<int> _held = {};

  // Scroll, accumulated over one `wl_pointer.frame`.
  double _scrollX = 0;
  double _scrollY = 0;
  int _v120X = 0;
  int _v120Y = 0;
  bool _stopX = false;
  bool _stopY = false;

  bool get isActive => _active != null;

  /// Every endpoint [openEis] made that is still open.
  Iterable<EisEndpoint> get endpoints => _endpoints;

  /// The running capture's id, for tests.
  int? get activeId => _active == null ? null : _activationId;

  // ---------------------------------------------------------------------------
  // The portal's side.
  // ---------------------------------------------------------------------------

  @override
  EisEndpoint openEis({required int capabilities, required String appId}) {
    final endpoint = _eisFactory(capabilities, appId);
    if (_keymapFd >= 0) endpoint.setKeymap(_keymapFd, _keymapSize);
    _endpoints.add(endpoint);
    return endpoint;
  }

  @override
  void closeEis(EisEndpoint endpoint) {
    _endpoints.remove(endpoint);
    endpoint.dispose();
  }

  @override
  void arm(CaptureClient client, List<PlacedBarrier> barriers) {
    if (identical(_active, client)) _end();
    _armed.remove(client);
    if (barriers.isNotEmpty) _armed[client] = List.unmodifiable(barriers);
    _syncStrips();
  }

  @override
  void disarm(CaptureClient client) {
    if (identical(_active, client)) _end();
    if (_armed.remove(client) != null) _syncStrips();
  }

  @override
  void release(CaptureClient client,
      {int? activationId, double? cursorX, double? cursorY}) {
    if (!identical(_active, client)) return;
    if (activationId != null && activationId != _activationId) return;
    _end(hintX: cursorX, hintY: cursorY);
  }

  // ---------------------------------------------------------------------------
  // The compositor's side.
  // ---------------------------------------------------------------------------

  /// The outputs changed. A new layout is a new zone set: every armed barrier
  /// was validated against the old one, so all of them are dropped and each
  /// session is told to ask again.
  void updateZones(List<CaptureZone> zones) {
    if (sameZones(zones, _zones)) return;
    _zones = List.unmodifiable(zones);
    _zoneSet = (_zoneSet + 1) & 0xffffffff;
    if (_active != null) _deactivate('the displays changed');
    _armed.clear();
    _hover = null;
    _syncStrips();
    _onZonesChanged?.call();
  }

  /// The compositor connection is gone; nothing it made survives.
  void connectionLost() {
    if (_active != null) _deactivate('the compositor connection was lost');
    _armed.clear();
    _hover = null;
    updateZones(const []);
  }

  void pointerOnStrip(StripKey strip, double x, double y) {
    _hover = strip;
    _px = x;
    _py = y;
  }

  void pointerLeftStrip() => _hover = null;

  void relativeMotion(double dx, double dy) {
    final active = _active;
    if (active != null) {
      _cursorX += dx;
      _cursorY += dy;
      active.sink?.pointerMotion(dx, dy);
      return;
    }
    final strip = _hover;
    if (strip == null) return;
    for (final MapEntry(key: client, value: barriers) in _armed.entries) {
      final crossing = crossingFor(
        barriers.where((b) => b.zone == strip.zone && b.edge == strip.edge),
        _px,
        _py,
        dx,
        dy,
      );
      if (crossing != null) {
        _activate(client, crossing);
        return;
      }
    }
  }

  void button(int button, bool pressed) =>
      _active?.sink?.pointerButton(button, pressed);

  void axis(int axis, double value) {
    if (axis == _axisVertical) _scrollY += value;
    if (axis == _axisHorizontal) _scrollX += value;
  }

  /// `axis_discrete` (seat v5–7): whole clicks.
  void axisDiscrete(int axis, int discrete) => axisValue120(axis, discrete * 120);

  void axisValue120(int axis, int value120) {
    if (axis == _axisVertical) _v120Y += value120;
    if (axis == _axisHorizontal) _v120X += value120;
  }

  void axisStop(int axis) {
    if (axis == _axisVertical) _stopY = true;
    if (axis == _axisHorizontal) _stopX = true;
  }

  /// `wl_pointer.frame`: one logical scroll, sent as whichever kind it was —
  /// wheel clicks when the compositor said so, smooth pixels otherwise.
  void frame() {
    final sink = _active?.sink;
    if (sink != null) {
      if (_v120X != 0 || _v120Y != 0) {
        sink.scrollDiscrete(_v120X, _v120Y);
      } else if (_scrollX != 0 || _scrollY != 0) {
        sink.scrollDelta(_scrollX, _scrollY);
      }
      if (_stopX || _stopY) sink.scrollStop(_stopX, _stopY);
    }
    _scrollX = _scrollY = 0;
    _v120X = _v120Y = 0;
    _stopX = _stopY = false;
  }

  /// Takes ownership of [fd].
  ///
  /// A compositor may send the same keymap again — wlroots does on focus
  /// changes — and each time it is a new descriptor. A device's keymap is
  /// fixed for its lifetime, so a "change" replaces the EI keyboard; comparing
  /// the contents is what keeps a repeat from doing that, possibly just as a
  /// capture starts.
  void keymap(int fd, int size) {
    final contents = _readKeymap(fd, size);
    if (contents != null &&
        _keymapContents != null &&
        _sameBytes(contents, _keymapContents!)) {
      closeFd(fd);
      return;
    }
    _keymapContents = contents;
    final previous = _keymapFd;
    _keymapFd = fd;
    _keymapSize = size;
    for (final endpoint in _endpoints) {
      endpoint.setKeymap(fd, size);
    }
    if (previous >= 0) closeFd(previous);
  }

  void keyboardEnter(List<int> keys) {
    _held
      ..clear()
      ..addAll(keys);
  }

  /// The capture surface lost the keyboard. While capturing that means the
  /// compositor has given it to something else — a lock screen, a prompt — and
  /// keys typed now would go there *and* be expected on the other machine.
  void keyboardLeave() {
    _held.clear();
    if (_active != null) _deactivate('the capture surface lost the keyboard');
  }

  void key(int key, bool pressed) {
    if (pressed) {
      _held.add(key);
    } else {
      _held.remove(key);
    }
    final active = _active;
    if (active == null) return;
    if (pressed && key == keyEsc && _chordHeld) {
      inputCaptureLog('${active.label}: input taken back with '
          'Super+Shift+Escape; the session is disabled');
      // Disarmed first, so ending the capture does not put its strips back;
      // and `Deactivated` before `Disabled`, the order the portal specifies.
      _armed.remove(active);
      _deactivate(null);
      active.disabledByUser();
      return;
    }
    active.sink?.key(key, pressed);
  }

  /// The keymap's bytes, read through `/proc` so the descriptor's own offset
  /// is untouched for libeis; null when it cannot be read, which only costs
  /// the duplicate check.
  static List<int>? _readKeymap(int fd, int size) {
    if (fd < 0) return null;
    try {
      final bytes = File('/proc/self/fd/$fd').readAsBytesSync();
      return bytes.length >= size ? bytes.sublist(0, size) : bytes;
    } catch (_) {
      return null;
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool get _chordHeld =>
      (_held.contains(keyLeftMeta) || _held.contains(keyRightMeta)) &&
      (_held.contains(keyLeftShift) || _held.contains(keyRightShift));

  void modifiers(int depressed, int latched, int locked, int group) {
    _depressed = depressed;
    _latched = latched;
    _locked = locked;
    _group = group;
    _active?.sink?.modifiers(depressed, latched, locked, group);
  }

  /// The capture surface went away under us (its output was unplugged).
  void captureLost() {
    if (_active != null) _deactivate('the captured output went away');
  }

  @override
  void clientGone(CaptureClient client) {
    if (identical(_active, client)) {
      _deactivate('the application closed its EI connection');
    }
  }

  // ---------------------------------------------------------------------------

  void _activate(CaptureClient client, BarrierCrossing crossing) {
    final sink = client.sink;
    if (sink == null) return;
    _activationId = (_activationId + 1) & 0xffffffff;
    _active = client;
    _hover = null;
    _cursorX = crossing.x;
    _cursorY = crossing.y;
    _held.clear();
    _scrollX = _scrollY = 0;
    _v120X = _v120Y = 0;
    _stopX = _stopY = false;
    inputCaptureLog('${client.label}: barrier ${crossing.barrier.id} crossed; '
        'capturing as activation $_activationId');

    _surfaces.showStrips(const {});
    _surfaces.beginCapture(crossing.barrier.zone);
    // The sequence before the first event, per the portal: the application
    // matches `start_emulating`'s sequence to the signal's activation_id.
    sink.start(_activationId);
    sink.modifiers(_depressed, _latched, _locked, _group);
    client.activated(_activationId, crossing);
  }

  /// Ends the capture with a `Deactivated` signal — the shell's decision, not
  /// the application's. [reason] is for the log; null when already logged.
  void _deactivate(String? reason) {
    final client = _active;
    if (client == null) return;
    final id = _activationId;
    final x = _cursorX;
    final y = _cursorY;
    if (reason != null) {
      inputCaptureLog('${client.label}: capture $id ended: $reason');
    }
    _end();
    client.deactivated(id, x, y);
  }

  void _end({double? hintX, double? hintY}) {
    final client = _active;
    if (client == null) return;
    _active = null;
    _held.clear();
    client.sink?.stop();
    _surfaces.endCapture(hintX: hintX, hintY: hintY);
    _syncStrips();
  }

  void _syncStrips() {
    if (_active != null) return;
    final strips = <StripKey>{
      for (final barriers in _armed.values)
        for (final b in barriers) StripKey(b.zone, b.edge),
    };
    if (_hover != null && !strips.contains(_hover)) _hover = null;
    _surfaces.showStrips(strips);
  }

  void dispose() {
    if (_active != null) _end();
    _armed.clear();
    _surfaces.showStrips(const {});
    _endpoints.clear();
    if (_keymapFd >= 0) closeFd(_keymapFd);
    _keymapFd = -1;
  }
}
