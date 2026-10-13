// libeis — the *server* half of libei, the emulated-input protocol.
//
// An InputCapture application never sees a Wayland event: the portal hands it a
// socket, it opens a libei *receiver* context on it, and from then on every
// captured key and pointer motion arrives as an EI event the shell sends. libeis
// is what speaks the shell's end of that socket.
//
// dlopened, never linked, the way PAM and gtk-session-lock are: a machine without
// libeis builds and runs the shell, and only input capture is missing — which
// `startInputCaptureService` reports by throwing. Flutter-free, like the rest of
// `lib/input_capture/` below the consent dialog, so `tool/screencast_spike.dart`
// can compile it.

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import '../native/ffi_util.dart';

typedef EisPtr = ffi.Pointer<ffi.Void>;

/// `enum eis_device_capability`.
const int eisCapPointer = 1 << 0;
const int eisCapPointerAbsolute = 1 << 1;
const int eisCapKeyboard = 1 << 2;
const int eisCapTouch = 1 << 3;
const int eisCapScroll = 1 << 4;
const int eisCapButton = 1 << 5;

/// `enum eis_device_type`.
const int eisDeviceTypeVirtual = 1;

/// `enum eis_keymap_type`.
const int eisKeymapTypeXkb = 1;

/// `enum eis_event_type` — the ones a receiver-side server can be sent.
const int eisEventClientConnect = 1;
const int eisEventClientDisconnect = 2;
const int eisEventSeatBind = 3;
const int eisEventDeviceClosed = 4;

class EisFfi {
  EisFfi._(ffi.DynamicLibrary lib) {
    newContext = lib.lookupFunction<EisPtr Function(EisPtr),
        EisPtr Function(EisPtr)>('eis_new');
    unref = lib.lookupFunction<EisPtr Function(EisPtr),
        EisPtr Function(EisPtr)>('eis_unref');
    setupBackendFd = lib.lookupFunction<ffi.Int32 Function(EisPtr),
        int Function(EisPtr)>('eis_setup_backend_fd');
    backendFdAddClient = lib.lookupFunction<ffi.Int32 Function(EisPtr),
        int Function(EisPtr)>('eis_backend_fd_add_client');
    getFd = lib.lookupFunction<ffi.Int32 Function(EisPtr),
        int Function(EisPtr)>('eis_get_fd');
    dispatch = lib.lookupFunction<ffi.Void Function(EisPtr),
        void Function(EisPtr)>('eis_dispatch');
    getEvent = lib.lookupFunction<EisPtr Function(EisPtr),
        EisPtr Function(EisPtr)>('eis_get_event');
    now = lib.lookupFunction<ffi.Uint64 Function(EisPtr),
        int Function(EisPtr)>('eis_now');

    eventUnref = lib.lookupFunction<EisPtr Function(EisPtr),
        EisPtr Function(EisPtr)>('eis_event_unref');
    eventGetType = lib.lookupFunction<ffi.Int32 Function(EisPtr),
        int Function(EisPtr)>('eis_event_get_type');
    eventGetClient = lib.lookupFunction<EisPtr Function(EisPtr),
        EisPtr Function(EisPtr)>('eis_event_get_client');
    eventGetSeat = lib.lookupFunction<EisPtr Function(EisPtr),
        EisPtr Function(EisPtr)>('eis_event_get_seat');
    eventGetDevice = lib.lookupFunction<EisPtr Function(EisPtr),
        EisPtr Function(EisPtr)>('eis_event_get_device');
    eventSeatHasCapability = lib.lookupFunction<
        ffi.Bool Function(EisPtr, ffi.Int32),
        bool Function(EisPtr, int)>('eis_event_seat_has_capability');

    clientRef = lib.lookupFunction<EisPtr Function(EisPtr),
        EisPtr Function(EisPtr)>('eis_client_ref');
    clientUnref = lib.lookupFunction<EisPtr Function(EisPtr),
        EisPtr Function(EisPtr)>('eis_client_unref');
    clientIsSender = lib.lookupFunction<ffi.Bool Function(EisPtr),
        bool Function(EisPtr)>('eis_client_is_sender');
    clientGetName = lib.lookupFunction<ffi.Pointer<Utf8> Function(EisPtr),
        ffi.Pointer<Utf8> Function(EisPtr)>('eis_client_get_name');
    clientConnect = lib.lookupFunction<ffi.Void Function(EisPtr),
        void Function(EisPtr)>('eis_client_connect');
    clientDisconnect = lib.lookupFunction<ffi.Void Function(EisPtr),
        void Function(EisPtr)>('eis_client_disconnect');
    clientNewSeat = lib.lookupFunction<
        EisPtr Function(EisPtr, ffi.Pointer<Utf8>),
        EisPtr Function(EisPtr, ffi.Pointer<Utf8>)>('eis_client_new_seat');

    seatUnref = lib.lookupFunction<EisPtr Function(EisPtr),
        EisPtr Function(EisPtr)>('eis_seat_unref');
    seatConfigureCapability = lib.lookupFunction<
        ffi.Void Function(EisPtr, ffi.Int32),
        void Function(EisPtr, int)>('eis_seat_configure_capability');
    seatAdd = lib.lookupFunction<ffi.Void Function(EisPtr),
        void Function(EisPtr)>('eis_seat_add');
    seatRemove = lib.lookupFunction<ffi.Void Function(EisPtr),
        void Function(EisPtr)>('eis_seat_remove');
    seatNewDevice = lib.lookupFunction<EisPtr Function(EisPtr),
        EisPtr Function(EisPtr)>('eis_seat_new_device');

    deviceUnref = lib.lookupFunction<EisPtr Function(EisPtr),
        EisPtr Function(EisPtr)>('eis_device_unref');
    deviceConfigureType = lib.lookupFunction<
        ffi.Void Function(EisPtr, ffi.Int32),
        void Function(EisPtr, int)>('eis_device_configure_type');
    deviceConfigureName = lib.lookupFunction<
        ffi.Void Function(EisPtr, ffi.Pointer<Utf8>),
        void Function(EisPtr, ffi.Pointer<Utf8>)>('eis_device_configure_name');
    deviceConfigureCapability = lib.lookupFunction<
        ffi.Void Function(EisPtr, ffi.Int32),
        void Function(EisPtr, int)>('eis_device_configure_capability');
    deviceNewKeymap = lib.lookupFunction<
        EisPtr Function(EisPtr, ffi.Int32, ffi.Int32, ffi.Size),
        EisPtr Function(EisPtr, int, int, int)>('eis_device_new_keymap');
    keymapAdd = lib.lookupFunction<ffi.Void Function(EisPtr),
        void Function(EisPtr)>('eis_keymap_add');
    keymapUnref = lib.lookupFunction<EisPtr Function(EisPtr),
        EisPtr Function(EisPtr)>('eis_keymap_unref');
    deviceAdd = lib.lookupFunction<ffi.Void Function(EisPtr),
        void Function(EisPtr)>('eis_device_add');
    deviceRemove = lib.lookupFunction<ffi.Void Function(EisPtr),
        void Function(EisPtr)>('eis_device_remove');
    deviceResume = lib.lookupFunction<ffi.Void Function(EisPtr),
        void Function(EisPtr)>('eis_device_resume');

    startEmulating = lib.lookupFunction<ffi.Void Function(EisPtr, ffi.Uint32),
        void Function(EisPtr, int)>('eis_device_start_emulating');
    stopEmulating = lib.lookupFunction<ffi.Void Function(EisPtr),
        void Function(EisPtr)>('eis_device_stop_emulating');
    frame = lib.lookupFunction<ffi.Void Function(EisPtr, ffi.Uint64),
        void Function(EisPtr, int)>('eis_device_frame');
    pointerMotion = lib.lookupFunction<
        ffi.Void Function(EisPtr, ffi.Double, ffi.Double),
        void Function(EisPtr, double, double)>('eis_device_pointer_motion');
    buttonButton = lib.lookupFunction<
        ffi.Void Function(EisPtr, ffi.Uint32, ffi.Bool),
        void Function(EisPtr, int, bool)>('eis_device_button_button');
    scrollDelta = lib.lookupFunction<
        ffi.Void Function(EisPtr, ffi.Double, ffi.Double),
        void Function(EisPtr, double, double)>('eis_device_scroll_delta');
    scrollDiscrete = lib.lookupFunction<
        ffi.Void Function(EisPtr, ffi.Int32, ffi.Int32),
        void Function(EisPtr, int, int)>('eis_device_scroll_discrete');
    scrollStop = lib.lookupFunction<
        ffi.Void Function(EisPtr, ffi.Bool, ffi.Bool),
        void Function(EisPtr, bool, bool)>('eis_device_scroll_stop');
    keyboardKey = lib.lookupFunction<
        ffi.Void Function(EisPtr, ffi.Uint32, ffi.Bool),
        void Function(EisPtr, int, bool)>('eis_device_keyboard_key');
    keyboardModifiers = lib.lookupFunction<
        ffi.Void Function(
            EisPtr, ffi.Uint32, ffi.Uint32, ffi.Uint32, ffi.Uint32),
        void Function(EisPtr, int, int, int,
            int)>('eis_device_keyboard_send_xkb_modifiers');
  }

  static EisFfi? _instance;
  static bool _attempted = false;

  /// The bindings, or null when no libeis is installed. Remembered either way:
  /// a library that did not load will not load later in the same process.
  static EisFfi? get instance {
    if (_attempted) return _instance;
    _attempted = true;
    final lib = openFirstLibrary(const ['libeis.so.1', 'libeis.so']);
    if (lib == null) return null;
    try {
      _instance = EisFfi._(lib);
    } catch (_) {
      // A libeis too old to export something below. 1.0 has all of it.
      _instance = null;
    }
    return _instance;
  }

  late final EisPtr Function(EisPtr userData) newContext;
  late final EisPtr Function(EisPtr eis) unref;
  late final int Function(EisPtr eis) setupBackendFd;
  late final int Function(EisPtr eis) backendFdAddClient;
  late final int Function(EisPtr eis) getFd;
  late final void Function(EisPtr eis) dispatch;
  late final EisPtr Function(EisPtr eis) getEvent;
  late final int Function(EisPtr eis) now;

  late final EisPtr Function(EisPtr event) eventUnref;
  late final int Function(EisPtr event) eventGetType;
  late final EisPtr Function(EisPtr event) eventGetClient;
  late final EisPtr Function(EisPtr event) eventGetSeat;
  late final EisPtr Function(EisPtr event) eventGetDevice;
  late final bool Function(EisPtr event, int cap) eventSeatHasCapability;

  late final EisPtr Function(EisPtr client) clientRef;
  late final EisPtr Function(EisPtr client) clientUnref;
  late final bool Function(EisPtr client) clientIsSender;
  late final ffi.Pointer<Utf8> Function(EisPtr client) clientGetName;
  late final void Function(EisPtr client) clientConnect;
  late final void Function(EisPtr client) clientDisconnect;
  late final EisPtr Function(EisPtr client, ffi.Pointer<Utf8> name)
      clientNewSeat;

  late final EisPtr Function(EisPtr seat) seatUnref;
  late final void Function(EisPtr seat, int cap) seatConfigureCapability;
  late final void Function(EisPtr seat) seatAdd;
  late final void Function(EisPtr seat) seatRemove;
  late final EisPtr Function(EisPtr seat) seatNewDevice;

  late final EisPtr Function(EisPtr device) deviceUnref;
  late final void Function(EisPtr device, int type) deviceConfigureType;
  late final void Function(EisPtr device, ffi.Pointer<Utf8> name)
      deviceConfigureName;
  late final void Function(EisPtr device, int cap) deviceConfigureCapability;
  late final EisPtr Function(EisPtr device, int type, int fd, int size)
      deviceNewKeymap;
  late final void Function(EisPtr keymap) keymapAdd;
  late final EisPtr Function(EisPtr keymap) keymapUnref;
  late final void Function(EisPtr device) deviceAdd;
  late final void Function(EisPtr device) deviceRemove;
  late final void Function(EisPtr device) deviceResume;

  late final void Function(EisPtr device, int sequence) startEmulating;
  late final void Function(EisPtr device) stopEmulating;
  late final void Function(EisPtr device, int timeUs) frame;
  late final void Function(EisPtr device, double dx, double dy) pointerMotion;
  late final void Function(EisPtr device, int button, bool press) buttonButton;
  late final void Function(EisPtr device, double dx, double dy) scrollDelta;
  late final void Function(EisPtr device, int dx, int dy) scrollDiscrete;
  late final void Function(EisPtr device, bool x, bool y) scrollStop;
  late final void Function(EisPtr device, int keycode, bool press) keyboardKey;
  late final void Function(
          EisPtr device, int depressed, int latched, int locked, int group)
      keyboardModifiers;
}
