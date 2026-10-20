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
- the xdg-desktop-portal backend — ScreenCast and InputCapture — on its own name

The two portal interfaces share that name because a `.portal` file names one bus name and the
frontend calls every interface behind it at one path. So one connection owns the name and one
object at `/org/freedesktop/portal/desktop` serves the union of both backends' interfaces
(`lib/portal_bus.dart`); each contributes its table and takes it back, and the last one out
gives the name up. Either can be switched off, or fail on its own, without taking the other
with it.

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

## Default applications are GIO's, not the shell's

Settings › Default Apps — the default browser, file manager, image viewer, and a default for
every type an installed application declares — keeps no state of its own. It reads and writes
the user's XDG `mimeapps.list` through GIO (`g_app_info_get_default_for_type`,
`g_app_info_set_as_default_for_type`, `g_app_info_reset_type_associations`), the
specification's reference implementation and a library already in the process, so a choice
made there is the one `xdg-open`, every GTK and Qt application and the shell's own desktop
grid follow.

A row stands for a family of types: a browser is `https:` and `http:` links *and* saved web
pages, an image viewer every `image/*` it declares. The extra types are claimed only where the
chosen application declares them. Every write is read back, because GIO writes only the
generic `mimeapps.list` and a desktop-specific `miracle-wm-mimeapps.list` outranks it — a
choice that did not take is a banner naming that file, never a silent no-op.

## Power modes are the daemon's; the knobs under them are root's

Settings › Power has two levels. **Power Mode** — Power Saver, Balanced, Performance — is
power-profiles-daemon's `ActiveProfile`, written over the system bus. The daemon maps the one
choice onto every control the hardware has (the ACPI platform profile, the CPU's
energy/performance preference, AMD's panel power savings), keeps it across reboots, and allows
it for the active session without a password. TuneD's `tuned-ppd` answers the same interface,
and where TuneD is the daemon its whole catalogue of profiles is offered beside the three
modes. The pane also shows what the daemon reports and nothing else does: which drivers
implement the mode, why performance is degraded (a lap, heat), which applications hold a mode,
and — on daemons new enough to have it — whether it adapts on battery. The mode on screen is
always the one the daemon reads back, never the one asked for, so a hold or a refusal shows as
what it is.

**Fine Tuning** is the kernel beneath it: the platform profile with every choice the firmware
offers, the cpufreq governor, the energy/performance preference, turbo boost, and a frequency
cap given as a share of each core's maximum so it means the same thing on a hybrid CPU. Each is
a sysfs file any user can read and only root can write, so edits are held until **Apply** and
written in one `pkexec` run — one administrator prompt, through the shell's own polkit agent,
however many knobs moved. The script is fixed text; every path is checked against an allow-list
and every value against the knob's own choices before anything runs, and they reach it as
arguments, never spliced in. These writes last until reboot, and the profile daemon rewrites
the platform profile and energy preference whenever the mode changes; the pane re-reads them
after every mode change, so what it shows is what the kernel holds.

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
