/// The non-themeable design tokens — the layer below `ThemeConfig`.
///
/// A theme decides *colours and shape* (`panel_radius`, `popup_radius`,
/// `surface_hover`, the font); these constants decide the sizes and timings
/// that read as "the shell" regardless of theme. Before this file every one
/// of them was an inline literal: six different animation durations, a
/// three-tier radius scale nobody had named, 254 font-size literals, and two
/// different error reds. New UI takes its values from here; a literal that
/// matches a token is a token.
library;

import 'dart:ui';

/// Animation durations, from hover feedback to full-screen overlay fades.
abstract final class ShellDurations {
  /// Hover/press feedback and small icon moves (the most common tier).
  static const Duration fast = Duration(milliseconds: 120);

  /// Toggles and control state changes.
  static const Duration base = Duration(milliseconds: 150);

  /// Full-screen overlay fade in/out (launcher, pickers).
  static const Duration overlayFade = Duration(milliseconds: 160);

  /// Larger reveals: tray spread, flyouts, page slides.
  static const Duration slow = Duration(milliseconds: 180);

  /// The settings overlay's entrance, deliberately statelier.
  static const Duration overlayEntrance = Duration(milliseconds: 240);
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

  /// Section titles and emphasis.
  static const double title = 16;
}

/// The one error red. (`0xFFE05252` was a second one that crept in; keep it
/// singular.)
const Color kErrorColor = Color(0xFFE06C75);

/// Text/iconography drawn on top of `theme.accent` fills.
const Color kOnAccent = Color(0xFFFFFFFF);
