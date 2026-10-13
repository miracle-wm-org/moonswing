#!/usr/bin/env python3
"""Drives the InputCapture portal the way DeskFlow does — through the real
xdg-desktop-portal frontend, so the frontend's own checks and the ConnectToEIS
file-descriptor hand-off are part of what is tested — and opens a libei
receiver on the socket it is given.

  tool/input_capture_client_test.py              # arm the right edge, wait
  tool/input_capture_client_test.py --edge left  # or left/top/bottom
  tool/input_capture_client_test.py --timeout 90

Requires the backend (the shell, or tool/screencast_spike.dart
--input-capture), a frontend whose portals.conf routes InputCapture to
moonswing, and libei.so.1. Push the pointer through the armed edge: the
script prints the Activated signal and the first EI events, then Releases
the capture and exits 0. Exits 1 on any refusal or on timeout.
"""

import argparse
import ctypes
import os
import sys

from gi.repository import Gio, GLib

FRONTEND = "org.freedesktop.portal.Desktop"
PATH = "/org/freedesktop/portal/desktop"
IFACE = "org.freedesktop.portal.InputCapture"

CAP_KEYBOARD = 1
CAP_POINTER = 2

EI_CAP_POINTER = 1 << 0
EI_CAP_KEYBOARD = 1 << 2
EI_CAP_SCROLL = 1 << 4
EI_CAP_BUTTON = 1 << 5

EI_EVENTS = {
    1: "connect", 2: "disconnect", 3: "seat added", 5: "device added",
    8: "device resumed", 9: "modifiers", 200: "start emulating",
    201: "stop emulating", 300: "pointer motion", 500: "button",
    600: "scroll", 603: "scroll discrete", 700: "key",
}


class Receiver:
    """A libei receiver context over the portal's socket."""

    def __init__(self, fd):
        lib = ctypes.CDLL("libei.so.1")
        self.lib = lib
        lib.ei_new_receiver.restype = ctypes.c_void_p
        lib.ei_get_event.restype = ctypes.c_void_p
        lib.ei_event_get_seat.restype = ctypes.c_void_p
        lib.ei_event_get_type.argtypes = [ctypes.c_void_p]
        lib.ei_event_unref.argtypes = [ctypes.c_void_p]
        lib.ei_dispatch.argtypes = [ctypes.c_void_p]
        lib.ei_get_event.argtypes = [ctypes.c_void_p]
        lib.ei_get_fd.argtypes = [ctypes.c_void_p]
        lib.ei_event_get_seat.argtypes = [ctypes.c_void_p]
        lib.ei_event_emulating_get_sequence.argtypes = [ctypes.c_void_p]
        lib.ei_event_pointer_get_dx.argtypes = [ctypes.c_void_p]
        lib.ei_event_pointer_get_dx.restype = ctypes.c_double
        lib.ei_event_keyboard_get_key.argtypes = [ctypes.c_void_p]
        lib.ei_event_get_device.argtypes = [ctypes.c_void_p]
        lib.ei_event_get_device.restype = ctypes.c_void_p
        lib.ei_device_keyboard_get_keymap.argtypes = [ctypes.c_void_p]
        lib.ei_device_keyboard_get_keymap.restype = ctypes.c_void_p
        lib.ei_keymap_get_size.argtypes = [ctypes.c_void_p]
        lib.ei_keymap_get_size.restype = ctypes.c_size_t
        self.ctx = lib.ei_new_receiver(None)
        lib.ei_configure_name(ctypes.c_void_p(self.ctx), b"input-capture-test")
        rc = lib.ei_setup_backend_fd(ctypes.c_void_p(self.ctx), fd)
        if rc != 0:
            raise RuntimeError(f"ei_setup_backend_fd failed: {rc}")
        self.events = []
        GLib.io_add_watch(lib.ei_get_fd(self.ctx), GLib.IO_IN, self._ready)

    def _ready(self, *_):
        lib = self.lib
        lib.ei_dispatch(self.ctx)
        while True:
            event = lib.ei_get_event(self.ctx)
            if not event:
                break
            kind = lib.ei_event_get_type(event)
            if kind == 3:  # seat added: take everything it offers
                lib.ei_seat_bind_capabilities(
                    ctypes.c_void_p(lib.ei_event_get_seat(event)),
                    EI_CAP_POINTER, EI_CAP_BUTTON, EI_CAP_SCROLL,
                    EI_CAP_KEYBOARD, None)
            detail = ""
            if kind == 200:
                detail = f" sequence={lib.ei_event_emulating_get_sequence(event)}"
            elif kind == 300:
                detail = f" dx={lib.ei_event_pointer_get_dx(event)}"
            elif kind == 5:
                keymap = lib.ei_device_keyboard_get_keymap(
                    lib.ei_event_get_device(event))
                if keymap:
                    detail = f" with a {lib.ei_keymap_get_size(keymap)}-byte keymap"
            elif kind == 700:
                detail = f" key={lib.ei_event_keyboard_get_key(event)}"
            if kind != 100:  # frames are noise
                name = EI_EVENTS.get(kind, f"event {kind}")
                self.events.append(name)
                print(f"  ei: {name}{detail}")
            lib.ei_event_unref(event)
        return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--edge", default="right",
                        choices=["left", "right", "top", "bottom"])
    parser.add_argument("--timeout", type=int, default=60)
    args = parser.parse_args()

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    sender = bus.get_unique_name()[1:].replace(".", "_")
    loop = GLib.MainLoop()
    state = {"failed": None}
    counter = [0]

    def fail(message):
        state["failed"] = message
        loop.quit()

    def request(method, params_before, options, params_after=()):
        """Calls a Request-returning method and waits for its Response."""
        counter[0] += 1
        token = f"ictest{os.getpid()}_{counter[0]}"
        options = dict(options, handle_token=GLib.Variant("s", token))
        handle = f"{PATH}/request/{sender}/{token}"
        answer = {}

        def on_response(_c, _s, _p, _i, _n, params):
            answer["value"] = params.unpack()
            loop.quit()

        sub = bus.signal_subscribe(FRONTEND, "org.freedesktop.portal.Request",
                                   "Response", handle, None,
                                   Gio.DBusSignalFlags.NO_MATCH_RULE,
                                   on_response)
        args = GLib.Variant.new_tuple(
            *params_before, GLib.Variant("a{sv}", options), *params_after)
        bus.call_sync(FRONTEND, PATH, IFACE, method, args, None,
                      Gio.DBusCallFlags.NONE, -1, None)
        loop.run()
        bus.signal_unsubscribe(sub)
        response, results = answer["value"]
        print(f"{method} -> {response} {results}")
        if response != 0:
            print(f"FAIL: {method} answered {response}")
            sys.exit(1)
        return results

    results = request("CreateSession", [GLib.Variant("s", "")], {
        "session_handle_token": GLib.Variant("s", f"icsession{os.getpid()}"),
        "capabilities": GLib.Variant("u", CAP_KEYBOARD | CAP_POINTER),
    })
    session = results["session_handle"]

    results = request("GetZones", [GLib.Variant("o", session)], {})
    zones, zone_set = results["zones"], results["zone_set"]
    if not zones:
        print("FAIL: no zones")
        sys.exit(1)

    # The outermost zone on the chosen side, and a barrier the length of it.
    if args.edge in ("left", "right"):
        pick = (min if args.edge == "left" else max)(
            zones, key=lambda z: z[2] + (0 if args.edge == "left" else z[0]))
        w, h, x, y = pick
        bx = x if args.edge == "left" else x + w
        position = (bx, y, bx, y + h - 1)
    else:
        pick = (min if args.edge == "top" else max)(
            zones, key=lambda z: z[3] + (0 if args.edge == "top" else z[1]))
        w, h, x, y = pick
        by = y if args.edge == "top" else y + h
        position = (x, by, x + w - 1, by)
    barriers = [{"barrier_id": GLib.Variant("u", 1),
                 "position": GLib.Variant("(iiii)", position)}]
    results = request("SetPointerBarriers", [GLib.Variant("o", session)], {},
                      [GLib.Variant("aa{sv}", barriers),
                       GLib.Variant("u", zone_set)])
    if results.get("failed_barriers"):
        print("FAIL: barrier refused")
        sys.exit(1)

    reply, fds = bus.call_with_unix_fd_list_sync(
        FRONTEND, PATH, IFACE, "ConnectToEIS",
        GLib.Variant("(oa{sv})", (session, {})), GLib.VariantType("(h)"),
        Gio.DBusCallFlags.NONE, -1, None, None)
    fd = fds.get(reply.unpack()[0])
    print(f"ConnectToEIS -> fd {fd}")
    receiver = Receiver(fd)

    activation = {}

    def on_signal(_c, _s, _p, _i, name, params):
        session_handle, options = params.unpack()
        if session_handle != session:
            return
        print(f"signal {name}: {options}")
        if name == "Activated":
            activation.update(options)
            # Let a little captured input arrive, then hand it back.
            GLib.timeout_add(1500, release)
        elif name in ("Disabled", "Deactivated"):
            fail(f"capture ended by the shell ({name})")

    def release():
        x, y = activation.get("cursor_position", (0.0, 0.0))
        bus.call_sync(FRONTEND, PATH, IFACE, "Release", GLib.Variant(
            "(oa{sv})", (session, {
                "activation_id": GLib.Variant("u", activation["activation_id"]),
                "cursor_position": GLib.Variant(
                    "(dd)", (x - 10 if args.edge == "right" else x + 10, y)),
            })), None, Gio.DBusCallFlags.NONE, -1, None)
        print("Release sent")
        loop.quit()
        return False

    bus.signal_subscribe(FRONTEND, IFACE, None, PATH, None,
                         Gio.DBusSignalFlags.NONE, on_signal)
    bus.call_sync(FRONTEND, PATH, IFACE, "Enable",
                  GLib.Variant("(oa{sv})", (session, {})), None,
                  Gio.DBusCallFlags.NONE, -1, None)
    print(f"Enabled. Push the pointer through the {args.edge} edge "
          f"({position}) within {args.timeout}s.")
    GLib.timeout_add_seconds(args.timeout,
                             lambda: fail("timed out waiting for Activated"))
    loop.run()

    if state["failed"]:
        print("FAIL:", state["failed"])
        sys.exit(1)
    if "start emulating" not in receiver.events:
        print("FAIL: no EI start_emulating after Activated")
        sys.exit(1)
    print("OK")


if __name__ == "__main__":
    main()
