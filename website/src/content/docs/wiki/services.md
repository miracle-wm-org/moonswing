---
title: Services and D-Bus
description: The four exported bus surfaces, how applications get launched, and the session lock.
sidebar:
  order: 5
---

The shell exports four surfaces on the session bus:

- `org.freedesktop.Notifications` — the session's notification daemon
- `org.kde.StatusNotifierWatcher`, plus the host (with a `com.canonical.dbusmenu` client for
  tray menus)
- `org.freedesktop.PolicyKit1.AuthenticationAgent`
- the ScreenCast portal backend, on its own name

Every exported object extends `DBusServiceObject`, where **one interface table** drives
`handleMethodCall`'s guard and dispatch, `getProperty`, `getAllProperties` and `introspect`.
Objects used to list their members two or three times each, which is how one lost its interface
guard and another's `GetAll` returned nothing.

One-shot queries use the process-wide clients in `dbus_clients.dart`; long-lived services own
their connections. BlueZ is the documented exception — it scopes discovery to the requesting
connection. That file is Flutter-free, because the portal has to compile into
`tool/screencast_spike.dart`.

Losing a name to another daemon is a **graceful decline** for `ShellServices` but a **visible
failure** for the feature, which carries its own status: notifications going to a daemon the
shell cannot see must not render as a quiet day. Registrations that a peer restart silently
drops — polkitd's — are re-established from `nameOwnerChanged`.

## Launching an application is a D-Bus act too

GIO spawns a desktop entry's command out of this process, so the application inherits the
shell's cgroup. Under the snap that is `snap.moonswing.…scope`, which is how snapd decides
the snap "has running apps" and refuses to refresh it — and why stopping the shell's unit used
to take everything ever launched from it down as well.

So every launch is followed by an **adoption**: `StartTransientUnit` on the session's systemd
user manager moves the pid into an `app-…-<pid>.scope` of its own under `app.slice`.

The one hook that catches *every* launch is `GAppLaunchContext::launched` — the same context
that `g_app_info_launch`, `g_app_info_launch_uris`, `g_app_info_launch_default_for_uri` and
`g_desktop_app_info_launch_action` are all already given for their startup-notification token,
which is why `_launchContext()` falls back to a plain `g_app_launch_context_new()` rather than
launching with none.

The adoption is best-effort by construction: it runs after the application has started, a
session with no systemd user manager (or a shell cgroup outside its delegated subtree) costs
the scope and nothing else, and a `ServiceUnknown` is remembered so twenty launches are not
twenty doomed round trips.

## polkit

**The shell never authenticates anybody itself.** Only the setuid-root
`polkit-agent-helper-1` can tell polkitd that an authentication happened, and the cookie goes
to it on **stdin, never `argv`** — that is CVE-2015-3255.

PAM (`lib/lock/pam_authenticator.dart`) runs the whole exchange in `Isolate.run` with an
`isolateLocal` conversation callback: PAM invokes it synchronously on the calling thread and
blocks for seconds on a failure. The response array uses the C allocator, because PAM `free()`s
it.

## Lock

Session lock is `ext-session-lock-v1`, through a standalone package that dlopens
`libgtk-session-lock.so.0` and does for that protocol what `layer_shell` does for
`wlr-layer-shell`. `initSessionLock()` swaps in a subclass of `ExtendedWindowingOwnerLinux`, so
lock windows register into the same registrar as every other window.

The compositor hides every other surface while locked and blanks any output with no lock
surface, so a monitor the shell fails to cover is blank — never exposed.

Four ordering rules, each of them a crash or a security hole:

1. **Create lock windows undecorated, before realize.** gtk-layer-shell calls
   `gtk_window_set_decorated(FALSE)` itself; the gtk-session-lock fork does not, and a decorated
   GTK3 window draws its CSD titlebar *inside* the lock surface.
2. **Lock windows exist only while locked** — one per monitor, including monitors hotplugged
   mid-lock.
3. **Tear down as detach → unlock → destroy, unmapping the role before each destroy.**
   Destroying a GTK window while Flutter still renders into its `FlView` is a use-after-free;
   `unlockAndDestroy()` syncs with the compositor first; and GTK destroys the `wl_surface` on
   unmap while gtk-session-lock destroys the `ext_session_lock_surface_v1` only in the
   finalizer — so without `gtk_session_lock_unmap_lock_window()` first, the compositor kills the
   connection.
4. **Never unlock on the way out.** `dispose()` drops the lock without sending an unlock: a
   client that disconnects without `unlock_and_destroy` leaves the session locked, which is
   exactly what should happen if the shell dies while locked.
