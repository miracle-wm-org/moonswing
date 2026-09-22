#!/usr/bin/env python3
"""Drives the moonswing ScreenCast backend the way xdg-desktop-portal
does, so the impl contract can be checked without the frontend in the way.

  tool/portal_client_test.py            # monitor share, expect success
  tool/portal_client_test.py --cancel   # close the Request mid-Start

Requires the backend to be running (tool/screencast_spike.dart --portal).
"""

import sys
import threading

from gi.repository import GLib, Gio

BUS_NAME = "org.freedesktop.impl.portal.desktop.moonswing"
OBJ_PATH = "/org/freedesktop/portal/desktop"
IFACE = "org.freedesktop.impl.portal.ScreenCast"

SOURCE_TYPE_MONITOR = 1
SOURCE_TYPE_WINDOW = 2
CURSOR_MODE_EMBEDDED = 2


def main():
    cancel = "--cancel" in sys.argv
    want_window = "--window" in sys.argv

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    proxy = Gio.DBusProxy.new_sync(
        bus, Gio.DBusProxyFlags.NONE, None, BUS_NAME, OBJ_PATH, IFACE, None
    )

    token = "gstest1"
    unique = bus.get_unique_name()[1:].replace(".", "_")
    request_path = f"/org/freedesktop/portal/desktop/request/{unique}/{token}"
    session_path = f"/org/freedesktop/portal/desktop/session/{unique}/{token}"

    # The frontend exports the Session object itself in the real world; here
    # we only need the paths to exist as arguments.
    r = proxy.call_sync(
        "CreateSession",
        GLib.Variant("(oosa{sv})",
                     (request_path, session_path, "com.example.Test", {})),
        Gio.DBusCallFlags.NONE, -1, None)
    print("CreateSession ->", r.unpack())

    types = SOURCE_TYPE_WINDOW if want_window else SOURCE_TYPE_MONITOR
    r = proxy.call_sync(
        "SelectSources",
        GLib.Variant("(oosa{sv})", (request_path, session_path,
                                    "com.example.Test", {
                                        "types": GLib.Variant("u", types),
                                        "multiple": GLib.Variant("b", False),
                                        "cursor_mode": GLib.Variant(
                                            "u", CURSOR_MODE_EMBEDDED),
                                    })),
        Gio.DBusCallFlags.NONE, -1, None)
    print("SelectSources ->", r.unpack())

    if cancel:
        def close_request():
            bus.call_sync(BUS_NAME, request_path,
                          "org.freedesktop.impl.portal.Request", "Close",
                          None, None, Gio.DBusCallFlags.NONE, -1, None)
            print("sent Request.Close")
        threading.Timer(1.5, close_request).start()

    r = proxy.call_sync(
        "Start",
        GLib.Variant("(oossa{sv})", (request_path, session_path,
                                     "com.example.Test", "", {})),
        Gio.DBusCallFlags.NONE, 60000, None)
    response, results = r.unpack()
    print("Start -> response", response, "results", results)

    if response == 0:
        streams = results.get("streams", [])
        print(f"got {len(streams)} stream(s)")
        for node_id, props in streams:
            print(f"  node_id={node_id} props={props}")
        # Tear the session down the way the frontend does when the app stops.
        bus.call_sync(BUS_NAME, session_path,
                      "org.freedesktop.impl.portal.Session", "Close",
                      None, None, Gio.DBusCallFlags.NONE, -1, None)
        print("sent Session.Close")
        return 0
    return 0 if cancel and response == 1 else 1


if __name__ == "__main__":
    sys.exit(main())
