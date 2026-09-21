---
title: Windows and popups
description: The one window registry, layer-shell rules, and why nothing but the popup coordinator closes a popup.
sidebar:
  order: 2
---

Every surface the shell draws — panel, background, overlay, OSD, badge, selection surface,
lock screen, popup — is a `WindowEntry` in the **one** root `WindowRegistry`, reachable
through `WindowRegistry.of(context)`. The `wlr-layer-shell` bridge is the `layer_shell` git
dependency, which also re-exports the `@internal` SDK windowing pieces.

## The registry is reconciled, never rebuilt

The root's set of entries is diffed against the live ones, keyed on controller. A declarative
list returned from `build` would take every module's popup down with it on any rebuild.

Survivors keep the builder they were created with, so builders read the root's fields rather
than capturing them. Entries render **unkeyed**, which means dropping one shifts every later
one down a slot — hence the registration order: per-monitor surfaces, then overlays, then
popups last.

## Destroying a native window

:::danger[A native window may only be destroyed once Flutter has let go of its view]
`gtk_widget_destroy` on a window with a live view aborts the shell. The destroy cascade
disposes the per-view renderer whose `frame_mutex` the raster thread is holding, and
`g_mutex_clear` on a held mutex is a glib `abort()`.
:::

`WindowTeardown` is the only correct path, and every teardown goes through it. It unmaps,
polls `viewIsAttached` once per frame, then waits one more. It **schedules its own frames** —
an idle shell produces none — destroys anyway at `maxFrames`, and re-checks `isDestroyed`.
Lock passes `hide: false`.

## Layer-shell rules

**A full-screen layer-shell surface must call `spanFullOutput`.** The default exclusive zone
of 0 means *"move me so I don't occlude surfaces that reserved space"*, so the compositor
otherwise shrinks a full-screen surface into the gap between the panels.

**Panels take no keyboard focus; a popup that types borrows it.** Panels are
`LayerShellKeyboardMode.none`, which is what stops the bar pulling focus off whatever the
user is typing in. Interactivity is inherited by popups, so `openPopup(needsKeyboard:)` flips
the *panel* to `onDemand` and back on close and from `dispose`. Only a borrow that actually
flipped is given back, and the flip is force-committed or it sits queued on a mapped surface.
The desktop surface does the same for an icon rename.

**A margin is native, never a Flutter `Padding`.** With no input-region support, an inset
inside a full-size surface swallows every click in the gap. The exclusive zone stays the panel
height: per `wlr-layer-shell` the zone *includes* the margin, so adding it would reserve it
twice.

## Popups

Nothing in the *Wayland* stack says a popup should go away. The Linux popup controller takes
no `gdk_seat_grab`, so no `popup_done` ever arrives, and `ext-foreign-toplevel-list-v1` carries
no state at all. GTK does report a window gaining and losing keyboard focus, but a panel never
takes any — it is deliberately the mode that does not steal focus from whatever you are typing
in — so for a bar and its popups that signal never fires. Flutter's own app-lifecycle state
cannot help either: the engine derives it from a single window, the one the shell never shows.
`PopupCoordinator.instance` is the only thing that closes them, `PopupDismissArea` the only
thing that notices a click on a shell surface, and the compositor's own IPC the only thing that
notices one anywhere else.

- A handle's **chain** is itself plus its transitive parents, and nothing in a chain dismisses
  anything else in it. Parentage is read from `TransientScope.maybeOf(context)`, never passed
  by a call site — which is what makes the `TransientScope` wrapper in the entry builder
  load-bearing.
- The coordinator requests a **graceful** close (the owner's `onDismiss`), never
  `closeLayerWindow` itself, so exit animations still play.
- `TransientPolicy` is two booleans. `dismissesOthers: false` is a hover tooltip;
  `dismissable: false` is a consent prompt, because dismissing the screencast picker is a
  *denial*. Refusal is inherited down a chain.
- The **reopen guard** exists because `PopupDismissArea`'s ancestor `Listener` fires before any
  descendant recognizer — without it, no bar popup could be dismissed by its own button. It is
  primary-button only, keyed on the host `State`.
- A **closing popup outlives the host that closed it.** `closePopup` drops every reference
  synchronously, so close-then-open in one gesture works, and moves the handle, entry, window
  and `onClosed` into a record that finishes on the animation **or a timer**, and outright on
  `dispose`.

Two clicks `PopupDismissArea` cannot catch by construction: one on an ordinary application
window (there is no grab), and one on bare desktop with no background surface. A full-screen
invisible barrier is not the answer — with no input-region support it would swallow every click
on the monitor.

A popup grab is what *should* catch the first of the two — with one, the compositor
dismisses the popup on any outside click and says so, which is how every menu on the
desktop works. Flutter's Linux popups never take one, so the request never goes out.
There is an experiment behind `GRACEFUL_SHELL_POPUP_GRAB` that takes the grab by hand;
whether it works is a question about the compositor rather than the shell, and it is
read off the Wayland wire rather than the screen.

**The first of the two is caught by its consequence instead.** miracle reports which
application window the compositor focused, on the same IPC connection the workspace row
already uses, so clicking Firefox — or Alt+Tabbing to it, or switching workspace — dismisses
whatever the shell had open. Everything dismissable goes, the full-screen overlays included,
since an overlay-layer surface would otherwise stay painted over the window that just took
focus. The consent prompts do not: alt-tabbing away from the screencast picker or the
authentication dialog must not answer it, and dismissing either one *is* the refusal. A switch
the shell asked for itself — the window switcher's own commit — is suppressed briefly, or a
second Alt+Tab pressed during the first one's fade-out would be cancelled by the switch
already in flight. A session not connected to the compositor's IPC keeps the old behaviour,
quietly: there is nowhere a warning about it could usefully be read.

`PopupTransition` plays one controller forward to open and backward to close, so an effect
cannot describe an opening it has no closing for. The effect comes from the theme
(`popup_animation`), snapshotted at open; `PopupEffect.none` wraps nothing and creates no
controller.

Popup content lays out under its own FlutterView, so it must carry its own `ShellTextRoot` —
`Directionality.of` is a null-assert in release too.
