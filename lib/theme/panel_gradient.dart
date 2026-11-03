/// What shape the bar's background takes: `panel_gradient`.
///
/// Pure — no Flutter, no `dart:ui` — for `surface_material.dart`'s reason: the
/// theme parser and the settings picker read this table, and a plain unit test
/// pins it. The pixels are `lib/panel_background.dart`'s.
library;

/// How a bar's background is filled.
///
/// The key used to be a boolean, and a theme file written then still says
/// `true` or `false`: [fromValue] reads those as [accent] and [none], so an
/// existing theme keeps the bar it had. What is written back is the slug.
enum PanelGradient {
  /// A flat sheet of `panel_background`.
  none('none', 'Flat', 'A flat sheet of the panel background.'),

  /// The long-standing fade: `accent` at the bar's own edge, through
  /// `surface_pressed`, to `panel_background`, every stop at
  /// `panel_background`'s alpha. The default.
  accent(
    'accent',
    'Accent fade',
    'Fades from the accent across to the panel background, along the bar.',
  ),

  /// A colour of its own in each of the bar's four corners, blended between
  /// them across the whole bar — `panel_gradient_top_left` and its three
  /// siblings. Which way it runs is which corners share a colour: two along
  /// one edge make a straight fade across the bar, two opposite corners a
  /// diagonal, four apart a wash in no single direction.
  corners(
    'corners',
    'Four corners',
    'A colour in each corner of the bar, blended across it — a fade in any '
        'direction.',
  );

  const PanelGradient(this.slug, this.label, this.description);

  /// How a theme file spells this shape.
  final String slug;

  /// The settings UI's name for it.
  final String label;

  /// One sentence for the settings UI's dropdown.
  final String description;

  /// The shape [slug] names, or null when this build has none by that name.
  static PanelGradient? fromSlug(String? slug) {
    if (slug == null) return null;
    for (final g in PanelGradient.values) {
      if (g.slug == slug) return g;
    }
    return null;
  }

  /// The shape a theme file's raw `panel_gradient` value names: a slug, or one
  /// of the booleans the key was before it had more than two answers. Null for
  /// anything else, so `ThemeConfig.fromMap` holds the fallback.
  static PanelGradient? fromValue(Object? value) => switch (value) {
    true => PanelGradient.accent,
    false => PanelGradient.none,
    String s => fromSlug(s),
    _ => null,
  };
}
