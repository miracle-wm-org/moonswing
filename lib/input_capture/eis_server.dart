// One InputCapture session's end of the EI socket.
//
// `ConnectToEIS` asks for a file descriptor the application can open a libei
// *receiver* context on. Behind it is one libeis context per session, set up for
// pre-made sockets: every captured event goes to the session that was activated,
// so a context shared between two applications would have to be split again by
// hand — and the frontend already refuses a second `ConnectToEIS` per session, so
// one context is exactly one client.
//
// What a receiver client is sent, in order: a seat (the capabilities this session
// was granted), devices for whatever of the seat it binds — one pointer carrying
// motion, buttons and scroll, one keyboard carrying the compositor's own keymap —
// and then, only between `start` and `stop`, the events themselves. `start`'s
// sequence is the `activation_id` of the `Activated` signal, which is the one
// synchronisation point the portal defines between the bus and this socket.
//
// Flutter-free, like `eis_ffi.dart`.

import 'dart:ffi' show nullptr;

import 'package:ffi/ffi.dart';

import '../native/glib_source.dart';
import '../native/libc.dart';
import 'eis_ffi.dart';
import 'input_capture_log.dart';

/// Portal capability bits (`SupportedCapabilities`).
const int captureCapKeyboard = 1;
const int captureCapPointer = 2;
const int captureCapTouchscreen = 4;

/// The receiving end the capture engine forwards input to. An interface so the
/// engine's tests can record what it would have sent.
abstract class CapturedInputSink {
  /// Begins an emulation sequence numbered [sequence] on every device.
  void start(int sequence);

  /// Releases whatever is still held, then ends the sequence.
  void stop();

  void pointerMotion(double dx, double dy);
  void pointerButton(int button, bool pressed);

  /// Smooth scroll, in logical pixels.
  void scrollDelta(double dx, double dy);

  /// Wheel scroll, in 120ths of a click.
  void scrollDiscrete(int dx, int dy);
  void scrollStop(bool x, bool y);

  /// [keycode] is evdev (no +8 offset).
  void key(int keycode, bool pressed);
  void modifiers(int depressed, int latched, int locked, int group);
}

/// One session's EI socket and the sink behind it — [EisServer], or a test's
/// recording stand-in.
abstract class EisEndpoint implements CapturedInputSink {
  /// A new socket for the application, to be returned from `ConnectToEIS`.
  /// The caller owns the fd until it is handed to D-Bus.
  int addClient();

  /// The compositor's keymap; borrowed — the caller keeps the fd.
  void setKeymap(int fd, int size);

  /// The client went away — the application exited or closed its context.
  set onDisconnected(void Function()? callback);

  /// Drains pending socket traffic. Driven by the GLib loop in the shell; by
  /// hand where there is none.
  void dispatch();

  void dispose();
}

class EisServer implements EisEndpoint {
  EisServer._(this._ffi, this._ctx, this.capabilities, this.name);

  /// A context for one session. Throws when libeis is missing or will not set
  /// up — `ConnectToEIS` answers that as a D-Bus error, which is the one way the
  /// portal has to say "no socket".
  ///
  /// [capabilities] are the portal bits the session was granted; the seat
  /// offers nothing outside them.
  static EisServer create({
    required int capabilities,
    required String name,
    bool attachToGlibLoop = true,
  }) {
    final bindings = EisFfi.instance;
    if (bindings == null) throw StateError('libeis is not installed');
    final ctx = bindings.newContext(nullptr);
    if (ctx.address == 0) throw StateError('eis_new failed');
    final rc = bindings.setupBackendFd(ctx);
    if (rc != 0) {
      bindings.unref(ctx);
      throw StateError('eis_setup_backend_fd failed ($rc)');
    }
    final server = EisServer._(bindings, ctx, capabilities, name);
    if (attachToGlibLoop) {
      server._watch =
          GlibFdWatch(bindings.getFd(ctx), (_) => server.dispatch());
    }
    return server;
  }

  final EisFfi _ffi;
  final EisPtr _ctx;
  final int capabilities;

  /// The application, for the log.
  final String name;

  GlibFdWatch? _watch;
  bool _disposed = false;

  EisPtr? _client;
  EisPtr? _seat;
  EisPtr? _pointer;
  EisPtr? _keyboard;

  /// What the client bound on the seat, as `eis_device_capability` bits.
  int _bound = 0;

  /// The compositor's keymap, borrowed from the engine — the engine owns and
  /// closes the fd, libeis dups it when a device is made.
  int _keymapFd = -1;
  int _keymapSize = 0;

  /// Non-null exactly while emulating.
  int? _sequence;

  final Set<int> _heldKeys = {};
  final Set<int> _heldButtons = {};

  @override
  void Function()? onDisconnected;

  bool get hasClient => _client != null;

  @override
  int addClient() {
    final fd = _ffi.backendFdAddClient(_ctx);
    if (fd < 0) throw StateError('eis_backend_fd_add_client failed ($fd)');
    return fd;
  }

  @override
  void dispatch() {
    if (_disposed) return;
    _ffi.dispatch(_ctx);
    while (!_disposed) {
      final event = _ffi.getEvent(_ctx);
      if (event.address == 0) break;
      try {
        _handle(event);
      } finally {
        _ffi.eventUnref(event);
      }
    }
  }

  void _handle(EisPtr event) {
    switch (_ffi.eventGetType(event)) {
      case eisEventClientConnect:
        _onConnect(_ffi.eventGetClient(event));
      case eisEventClientDisconnect:
        if (_client?.address == _ffi.eventGetClient(event).address) {
          _dropClient(disconnect: false);
          onDisconnected?.call();
        }
      case eisEventSeatBind:
        if (_seat?.address != _ffi.eventGetSeat(event).address) return;
        var bound = 0;
        for (final cap in const [
          eisCapPointer,
          eisCapButton,
          eisCapScroll,
          eisCapKeyboard,
        ]) {
          if (_ffi.eventSeatHasCapability(event, cap)) bound |= cap;
        }
        _bind(bound);
      case eisEventDeviceClosed:
        final device = _ffi.eventGetDevice(event);
        if (device.address == _pointer?.address) {
          _removeDevice(_pointer!);
          _pointer = null;
          _heldButtons.clear();
        } else if (device.address == _keyboard?.address) {
          _removeDevice(_keyboard!);
          _keyboard = null;
          _heldKeys.clear();
        }
    }
  }

  void _onConnect(EisPtr client) {
    // A *sender* wants to type into this machine — that is the RemoteDesktop
    // portal's business, never this socket's.
    if (_client != null || _ffi.clientIsSender(client)) {
      inputCaptureLog('$name: refusing an EI client that is '
          '${_client != null ? 'a second connection' : 'a sender'}');
      _ffi.clientDisconnect(client);
      return;
    }
    _client = _ffi.clientRef(client);
    _ffi.clientConnect(client);

    final seatName = 'moonswing'.toNativeUtf8();
    try {
      _seat = _ffi.clientNewSeat(client, seatName);
    } finally {
      malloc.free(seatName);
    }
    final seat = _seat!;
    if (capabilities & captureCapPointer != 0) {
      _ffi.seatConfigureCapability(seat, eisCapPointer);
      _ffi.seatConfigureCapability(seat, eisCapButton);
      _ffi.seatConfigureCapability(seat, eisCapScroll);
    }
    if (capabilities & captureCapKeyboard != 0) {
      _ffi.seatConfigureCapability(seat, eisCapKeyboard);
    }
    _ffi.seatAdd(seat);
    inputCaptureLog('$name: EI receiver connected');
  }

  void _bind(int bound) {
    final pointerCaps = eisCapPointer | eisCapButton | eisCapScroll;
    final pointerChanged = (bound ^ _bound) & pointerCaps != 0;
    final keyboardChanged = (bound ^ _bound) & eisCapKeyboard != 0;
    _bound = bound;
    if (pointerChanged) _rebuildPointer();
    if (keyboardChanged) _rebuildKeyboard();
  }

  void _rebuildPointer() {
    if (_pointer case final old?) {
      _removeDevice(old);
      _pointer = null;
      _heldButtons.clear();
    }
    final caps = [
      for (final cap in const [eisCapPointer, eisCapButton, eisCapScroll])
        if (_bound & cap != 0) cap,
    ];
    if (caps.isEmpty) return;
    _pointer = _addDevice('moonswing pointer', caps);
  }

  void _rebuildKeyboard() {
    if (_keyboard case final old?) {
      _removeDevice(old);
      _keyboard = null;
      _heldKeys.clear();
    }
    if (_bound & eisCapKeyboard == 0) return;
    _keyboard = _addDevice('moonswing keyboard', const [eisCapKeyboard]);
  }

  EisPtr? _addDevice(String deviceName, List<int> caps) {
    final seat = _seat;
    if (seat == null) return null;
    final device = _ffi.seatNewDevice(seat);
    if (device.address == 0) return null;
    _ffi.deviceConfigureType(device, eisDeviceTypeVirtual);
    final nativeName = deviceName.toNativeUtf8();
    try {
      _ffi.deviceConfigureName(device, nativeName);
    } finally {
      malloc.free(nativeName);
    }
    for (final cap in caps) {
      _ffi.deviceConfigureCapability(device, cap);
    }
    if (caps.contains(eisCapKeyboard) && _keymapFd >= 0) {
      // Without one the receiver has to guess the layout, and guesses US.
      final keymap = _ffi.deviceNewKeymap(
          device, eisKeymapTypeXkb, _keymapFd, _keymapSize);
      if (keymap.address != 0) {
        _ffi.keymapAdd(keymap);
        _ffi.keymapUnref(keymap);
      }
    }
    _ffi.deviceAdd(device);
    _ffi.deviceResume(device);
    if (_sequence case final sequence?) _ffi.startEmulating(device, sequence);
    return device;
  }

  void _removeDevice(EisPtr device) {
    _ffi.deviceRemove(device);
    _ffi.deviceUnref(device);
  }

  /// Takes the compositor's current keymap. A device's keymap is fixed for its
  /// lifetime, so a change (the user switching layout) replaces the keyboard.
  @override
  void setKeymap(int fd, int size) {
    if (fd == _keymapFd && size == _keymapSize) return;
    _keymapFd = fd;
    _keymapSize = size;
    if (_keyboard != null) {
      _releaseKeys();
      _rebuildKeyboard();
    }
  }

  void _frame(EisPtr device) => _ffi.frame(device, _ffi.now(_ctx));

  @override
  void start(int sequence) {
    if (_sequence != null) stop();
    _sequence = sequence;
    for (final device in [_pointer, _keyboard]) {
      if (device != null) _ffi.startEmulating(device, sequence);
    }
  }

  @override
  void stop() {
    if (_sequence == null) return;
    _releaseKeys();
    if (_pointer case final pointer?) {
      for (final button in _heldButtons) {
        _ffi.buttonButton(pointer, button, false);
      }
      if (_heldButtons.isNotEmpty) _frame(pointer);
    }
    _heldButtons.clear();
    for (final device in [_pointer, _keyboard]) {
      if (device != null) _ffi.stopEmulating(device);
    }
    _sequence = null;
  }

  /// A key still down on the far side when capture ends would repeat there
  /// forever — the release happened on this machine.
  void _releaseKeys() {
    final keyboard = _keyboard;
    if (keyboard != null && _sequence != null) {
      for (final key in _heldKeys) {
        _ffi.keyboardKey(keyboard, key, false);
      }
      if (_heldKeys.isNotEmpty) _frame(keyboard);
    }
    _heldKeys.clear();
  }

  EisPtr? get _emittingPointer => _sequence == null ? null : _pointer;
  EisPtr? get _emittingKeyboard => _sequence == null ? null : _keyboard;

  bool _boundCap(int cap) => _bound & cap != 0;

  @override
  void pointerMotion(double dx, double dy) {
    final pointer = _emittingPointer;
    if (pointer == null || !_boundCap(eisCapPointer)) return;
    _ffi.pointerMotion(pointer, dx, dy);
    _frame(pointer);
  }

  @override
  void pointerButton(int button, bool pressed) {
    final pointer = _emittingPointer;
    if (pointer == null || !_boundCap(eisCapButton)) return;
    // A release for a press the far side never saw (the button was down as
    // capture began) is dropped rather than sent.
    if (pressed ? !_heldButtons.add(button) : !_heldButtons.remove(button)) {
      return;
    }
    _ffi.buttonButton(pointer, button, pressed);
    _frame(pointer);
  }

  @override
  void scrollDelta(double dx, double dy) {
    final pointer = _emittingPointer;
    if (pointer == null || !_boundCap(eisCapScroll)) return;
    _ffi.scrollDelta(pointer, dx, dy);
    _frame(pointer);
  }

  @override
  void scrollDiscrete(int dx, int dy) {
    final pointer = _emittingPointer;
    if (pointer == null || !_boundCap(eisCapScroll)) return;
    _ffi.scrollDiscrete(pointer, dx, dy);
    _frame(pointer);
  }

  @override
  void scrollStop(bool x, bool y) {
    final pointer = _emittingPointer;
    if (pointer == null || !_boundCap(eisCapScroll) || !(x || y)) return;
    _ffi.scrollStop(pointer, x, y);
    _frame(pointer);
  }

  @override
  void key(int keycode, bool pressed) {
    final keyboard = _emittingKeyboard;
    if (keyboard == null) return;
    if (pressed ? !_heldKeys.add(keycode) : !_heldKeys.remove(keycode)) {
      return;
    }
    _ffi.keyboardKey(keyboard, keycode, pressed);
    _frame(keyboard);
  }

  @override
  void modifiers(int depressed, int latched, int locked, int group) {
    // Sent whether or not a sequence is running: it is device state, and a
    // receiver entering with Caps Lock on should know before the first key.
    final keyboard = _keyboard;
    if (keyboard == null) return;
    _ffi.keyboardModifiers(keyboard, depressed, latched, locked, group);
  }

  void _dropClient({required bool disconnect}) {
    for (final device in [_pointer, _keyboard]) {
      if (device != null) _removeDevice(device);
    }
    _pointer = null;
    _keyboard = null;
    _heldKeys.clear();
    _heldButtons.clear();
    _bound = 0;
    if (_seat case final seat?) {
      _ffi.seatRemove(seat);
      _ffi.seatUnref(seat);
    }
    _seat = null;
    if (_client case final client?) {
      if (disconnect) _ffi.clientDisconnect(client);
      _ffi.clientUnref(client);
    }
    _client = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    stop();
    _dropClient(disconnect: true);
    _watch?.dispose();
    _watch = null;
    _disposed = true;
    _ffi.unref(_ctx);
  }
}

/// Closes an fd made by [EisServer.addClient] that never reached D-Bus.
void closeClientFd(int fd) {
  if (fd >= 0) closeFd(fd);
}
