---
title: Stores, leases and controllers
description: Why shared state is a singleton with an acquire/release lease, and the four rules every store follows.
sidebar:
  order: 3
---

Shared state is a singleton `ChangeNotifier` — `ThemeStore`, `OsdStore`, `TrayStore`,
`SystemStatsStore`, `NotificationStore`, `MprisStore`, `WeatherStore`, `AppIndex`,
`TimersStore`, `DesktopStore`, and more. Four rules run through all of them.

## One poller, connection or timer for the machine

One FlutterView per panel per monitor means anything owned by a widget is owned *N* times.
Two bars used to mean two `/proc` walks, two `GET_TREE`s, two bus connections.

Consumers `acquire()` and `release()`; the last release stops the work. A lease can have
tiers — a *detail* lease adds a per-process walk or a position poll on top of the basic one.

:::caution[A `Timer.periodic` in a widget `State` is the anti-pattern leases exist to prevent]
An idle shell with a feature switched off must wake for it exactly never.
:::

`acquire()` must not notify synchronously: it runs inside the acquirer's `initState`.

## Elapsed time is derived, never accumulated

Hold a reference point and subtract against the wall clock. A ticker that adds its own period
to a running total drifts by however late each wakeup was, and loses a suspend entirely. A
backwards clock step is dropped, not subtracted.

## A read that finds nothing new must not notify

Every surface on every monitor is listening, so a store compares a signature carrying only
what a surface actually renders. Stores that mutate two lists at once have to guard against
their own synchronous notifications re-entering mid-write.

## A failure is a visible state, not a silence

A lost bus name, an unreachable API, a missing external tool: the last good value stays on
screen, the reason is rendered, and a **retry** is offered. All of these recover without a
restart, and the shell cannot see it happen. A missing external tool names the *package*,
never a package manager.

An empty list from a failed service is indistinguishable from a genuinely empty one, which is
why loaders and error states are not decoration.

## Controllers

`lib/request_controller.dart` holds the seam that lets something deep inside a surface ask the
root for a window.

`RequestController<Req, Res>` carries a request/response pair and bakes in three rules no
subclass may lose:

1. **No listener means an immediate decline** — a headless run never awaits a window that will
   not appear. For the screencast picker, this *is* the consent guarantee.
2. A second request **supersedes the first as declined**.
3. **`dispose` answers the awaiting caller.**

`SignalController` is the fire-and-forget shape: a monotonic counter plus `notifyListeners`.
Neither is `InputTriggerStore`, which reports compositor triggers and whose listeners toggle
on any notification.
