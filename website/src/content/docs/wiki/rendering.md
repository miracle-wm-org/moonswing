---
title: Theming and repaint discipline
description: How a theme reaches every FlutterView, and the rules that keep an idle shell from repainting an output.
sidebar:
  order: 4
---

## A theme is a file

A theme is not a config section: it is a flat TOML table under
`~/.config/graceful-shell/themes/`, named by a top-level `theme = "dracula"` in
`config.toml`. `ThemeStore` owns the resolved palette, the catalogue, seeding, CRUD and the
debounced write, and reads `ConfigStore` for the `theme` key alone — never `appConfig`, which
would re-run `Module.loadAll`.

- **`ThemeProvider` is the only thing that constructs a `ThemeScope`.** Each FlutterView is
  given the theme separately, so a module that snapshotted `ThemeScope.of` when opening a
  window froze it. Listening is what makes an already-open popup restyle.
- **`font_size` is a `TextScaler` on the `MediaQuery` that `ThemeProvider` publishes**, so the
  whole `ShellFontSizes` scale moves as one and 13.0 is `noScaling`. A `DefaultTextStyle` size
  would reach only text that names none. Which means **a `TextPainter` deciding a layout must
  be given the scaler**. Pixels are *not* scaled: growing the type is not an instruction to
  grow the bar.
- **Shipped themes are embedded constants** — read-only, forked on edit, and **re-seeded when
  they drift**, so a palette fix reaches an install that has already run. Membership in
  `kBuiltInThemes` *is* the read-only test. They are constants because nothing in the shell
  resolves paths relative to the bundle, which is also why the emoji table and Tux's SVG are
  constants and `pubspec.yaml` has no `assets:` section.
- **Popup geometry is theme-driven and grows the compositor surface.** A shadow or attach flare
  paints outside the card's box, but a popup is its own surface sized to its content. So
  `openPopup` pads the measured box by `popupSurfaceInsets`, offsets the positioner by the
  same, and grows the GTK geometry hints — all three, or every menu lands off its button.
  `popup_gap = 0` is the attached mode: the joined edge squares off, drops its rim, clamps the
  shadow and reaches a collar into the panel.
- **`lib/theme/tokens.dart`** sits below the theme: `ShellDurations`, `ShellRadii`,
  `ShellFontSizes` (a scale *relative* to `body`), `ShellSizes` (pointer-target boxes, never
  glyph sizes), `kErrorColor`, `kOnAccent`. A literal that matches a token is a token.
- Alpha is overridden where prose is read: `panelBackgroundDecoration` honours
  `panel_background`'s alpha verbatim, while the settings panel and everything floating over it
  force opacity.
- There is deliberately **no blur key**. A `BackdropFilter` reaches only what Flutter already
  painted beneath it, which in an overlay window is nothing — it changed no pixel while costing
  a full-output Gaussian per frame.

## Repaint discipline

Panels, overlays and the desktop surface have **no repaint boundary of their own**, so any
render object marked needing paint re-records the whole surface picture and damages the whole
output. The two things that do this most are the two things done most often: something tinting
under the pointer, and something ticking once a second.

- **A boundary per cell, tile, card or button** contains the damage — two of them where an
  animating layer sits inside a labelled one, so the label stays out of it.
- **Hand unchanged children in rather than rebuilding them.** An identical child widget is
  skipped outright, so a hover rebuild updates a decoration instead of re-shaping a paragraph.
- **Per-item `ValueNotifier` instead of `setState` on the parent.** Selection following a
  pointer, a band crossing icons, a grid cell ringing: as parent state, each of those rebuilds
  every child, including any that measure text as they build. `MouseRegion` fires enter and
  exit as *content* moves under a stationary cursor too, so a scroll does it every frame.
- **A repaint boundary contains a repaint; only a *relayout* boundary contains a relayout.**
  Changing a `Text` marks needs-layout, which stops at the nearest tightly-constrained
  ancestor — and that ancestor then marks itself needing paint, stepping over any boundary
  nested inside it.
- **Measure text with the ambient `TextScaler`** and the style actually rendered. Anything
  deciding a layout from a measurement — marquees, text-fit ladders, "does this row fit" —
  measures a different font otherwise.
- Long lists are `ListView`/`GridView` with a fixed extent, never a `Column`, which overflows
  the moment the user adds one more item. Set `cacheExtent` deliberately: the 250px default is
  several screens of rows at small item heights.
- **Nothing animates at rest.** A ticker is created when there is something to show and disposed
  when there is not. Tests pin this with a settle plus `transientCallbackCount == 0`.

## Shared primitives

**`HoverRegion`** is `builder: (context, hovered) => …` plus tap callbacks. It emits the
`GestureDetector` too, at `HitTestBehavior.opaque`, and that half is load-bearing: a detector
with no `behavior:` is `deferToChild`, and `Padding`, `Align`, `ConstrainedBox`, `ClipRRect`,
`Row`/`Column`/`Stack`, `RenderImage` and an undecorated `Container` all answer
`hitTestSelf == false` — so a 26px button hovered over 26px and *fired* over the 11px glyph.

> **Greppable rule:** every `GestureDetector(` in `lib/` carries a `behavior:` or is inside
> `HoverRegion`.

A decorated `Container` is hit-testable only inside its `borderRadius`;
`Container(color: cond ? c : null)` only while `cond` holds; opaque is not enough without a box
of at least `ShellSizes.minTapTarget`. `onTapDown` is not interchangeable with `onTap` — every
popup toggle opens on tap-*down*, inside the pointer-down that the reopen guard is consumed in.
`test/tap_target_test.dart` taps **corners**, because a centre tap passes on every one of these
bugs.

The rest of the shared set:

- **`BarButton`** and **`SkyIconButton`** — bar-module chrome, and the round action on a
  picture-backed desktop card.
- **`ShellTextRoot`** — `Directionality` plus a theme-font `DefaultTextStyle`, applied once per
  window.
- **`FadeOverlayScaffold`** — scrim and centred scale-in card, and owner of the `closing`
  handshake (reverse, *then* `onClosed`, which may tear the window down). Nothing may wrap it
  in an `Opacity`: these windows span the output, so that layer is a full-output offscreen per
  frame.
- **`AnchoredSearchDropdown`** — the one dropdown. It floats in the **root** overlay, because an
  inline one pushes the form down as it opens and cannot open off the bottom of the screen.
- **`OverlaySearchField`** — the launcher/emoji/settings search field, with `RenderEditable`
  mouse wiring a hand-rolled copy would get wrong.
- **`lib/overlay/settings/controls.dart`** — the themed form controls. Pages import them; they
  never redeclare one. Private clones are how the audio and bluetooth pages lost the theme font
  and the display page froze its palette. A control the library lacks gets *added to the
  library*.
