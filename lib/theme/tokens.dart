/// The non-themeable design tokens — the layer below `ThemeConfig`.
///
/// A theme decides colours and shape; these constants decide the sizes and
/// timings that read as "the shell" whatever the theme. A literal that matches
/// a token is a token.
library;

import 'dart:ui';

/// Animation durations, from hover feedback to full-screen overlay fades.
abstract final class ShellDurations {
  /// Hover/press feedback and small icon moves (the most common tier).
  static const Duration fast = Duration(milliseconds: 120);

  /// Toggles and control state changes.
  static const Duration base = Duration(milliseconds: 150);

  /// A full-screen overlay's entrance (`overlay_animation`), when the theme
  /// spells no `overlay_animation_duration`.
  ///
  /// The *default* rather than the timing, as [popupIn] is for popups: a theme
  /// moves it, and `ThemeConfig.overlayInDuration` is what actually plays.
  /// Still the flat timing for the handful of fades that are not an overlay
  /// entrance — the notification panel's own exit reads it directly.
  static const Duration overlayFade = Duration(milliseconds: 160);

  /// Larger reveals: tray spread, flyouts, page slides.
  static const Duration slow = Duration(milliseconds: 180);

  /// The settings overlay's entrance, deliberately statelier.
  ///
  /// Read as a *ratio* to [overlayFade] rather than as a duration — see
  /// `FadeOverlayScaffold.durationScale`. Spelled as a duration because that is
  /// what it has always been and what it reads as: 240ms against the shell's
  /// 160.
  static const Duration overlayEntrance = Duration(milliseconds: 240);

  /// A popup card's entrance (`popup_animation`), when the theme spells no
  /// `popup_animation_duration`.
  ///
  /// Quick: the card has to be readable by the time the pointer reaches it.
  /// This is the *default* rather than the timing — a theme moves it, and
  /// `ThemeConfig.popupInDuration` is what actually plays.
  static const Duration popupIn = Duration(milliseconds: 140);

  /// How much of its entrance an exit is given, whatever the entrance lasts.
  ///
  /// An entrance is paced to be followed; a dismissal is the user saying they
  /// are done. A fraction rather than a second duration so a theme that
  /// lengthens the entrance lengthens the exit with it, and the two cannot
  /// drift into an exit longer than the entrance it reverses.
  static const double popupExitFraction = 0.8;

  /// A popup card's exit — the entrance, reversed and shorter: [popupIn] times
  /// [popupExitFraction], which cannot be written as a constant expression.
  ///
  /// The default, as [popupIn] is. See `lib/popup_transition.dart`.
  static const Duration popupOut = Duration(milliseconds: 112);
}

/// Corner radii. The scale observed across the shell, named.
abstract final class ShellRadii {
  /// Bar-module buttons.
  static const double barButton = 4;

  /// Form controls: fields, dropdown rows, small buttons.
  static const double control = 6;

  /// Cards and popups that do not follow `theme.popupRadius`.
  static const double card = 8;

  /// Fully-rounded pills (toggles, option buttons).
  static const double pill = 20;
}

/// Font sizes. The implicit type scale, named.
abstract final class ShellFontSizes {
  /// Fine print: units, timestamps, badges.
  static const double caption = 11;

  /// Secondary text: sublabels, hints, empty states.
  static const double secondary = 12;

  /// Body text — most of the shell.
  static const double body = 13;

  /// Control labels and popup text.
  static const double label = 14;

  /// The text somebody is *typing*: the overlay search inputs, via
  /// `OverlaySearchField`. Above [label] because a query is composed rather
  /// than read, below [title] because the card still has headings.
  static const double field = 15;

  /// Section titles and emphasis.
  static const double title = 16;

  /// A section heading — set outside and above the surface it names.
  static const double heading = 20;
}

/// The one error red; keep it singular.
const Color kErrorColor = Color(0xFFE06C75);

/// Text/iconography drawn on top of `theme.accent` fills.
///
/// The other half of the pair is `ThemeConfig.accentText`: this is what goes
/// *on* an accent fill, that is what the accent becomes when it is the text
/// rather than the fill.
const Color kOnAccent = Color(0xFFFFFFFF);

/// The contrast a colour needs against what is behind it to be read *as text*.
///
/// WCAG AA for body copy, and the floor `ThemeConfig.accentText` lifts an
/// accent to. Deliberately not held against fills: a hairline rim, a slider's
/// travel or a hover wash is furniture rather than prose, and holding those to
/// a reading ratio would flatten every palette in the shell into two tones.
const double kTextContrast = 4.5;

/// Pointer-target sizes.
///
/// Hover and tap are one box (see `HoverRegion`), so these name *that box*,
/// never the glyph inside it. A `FaIcon` is a bare `RichText` with no box of
/// its own, so an unboxed icon is an 11-14px target.
abstract final class ShellSizes {
  /// The floor for anything clickable that is not deliberately dense.
  static const double minTapTarget = 24;

  /// The settings icon-button box, and the default for a standalone icon
  /// action anywhere in the shell.
  static const double iconButton = 26;

  /// The dense box, for a row already carrying two lines of text. Below
  /// [minTapTarget] only where the row's height forces it.
  static const double iconButtonDense = 18;
}

/// Fading a *theme* colour, which may already be translucent.
///
/// `color.withValues(alpha: x)` replaces the alpha, which is only a fade for an
/// opaque colour. glassy's surfaces are white-alpha — `control_surface` was
/// `#26FFFFFF` — so replacing its 15% with 0.5 painted a todo column half-white:
/// a light grey under white text, and brighter than the tint it was meant to
/// tone down. Every call site reducing a theme surface's alpha goes through here.
extension ThemeColorAlpha on Color {
  /// This colour at [alpha], or at its own alpha if that is already lower.
  ///
  /// Identical to `withValues(alpha:)` for an opaque colour, and never makes a
  /// translucent one *more* opaque than the theme spelled it.
  Color atMostAlpha(double alpha) =>
      a <= alpha ? this : withValues(alpha: alpha);
}
