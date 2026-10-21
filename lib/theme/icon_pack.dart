/// Which icon font draws the shell's interface glyphs — a theme key,
/// `icon_pack`.
///
/// Every interface icon is a `ShellGlyph` (`lib/icons/shell_glyph.dart`) named
/// by what it means, and a pack is one answer to "what does *close* look like".
/// The tables live in `lib/icons/packs/`; this file is only the catalogue of
/// packs, so that `ThemeConfig` can parse the key and the settings UI can list
/// it without either reaching for a font.
///
/// Pure — no Flutter, no `dart:ui` — so the table and its parsing are a plain
/// unit test, the way `popup_effect.dart` is.
library;

/// One icon font, and the size it has to be drawn at to sit beside the others.
enum IconPack {
  /// Font Awesome Free, the shell's own set since before it had a choice.
  ///
  /// Also exactly what the shell drew before the key existed, Material Symbols
  /// glyphs on the moon and weather cards included — which is what makes it the
  /// default and the fallback: a glyph another pack has no answer for is drawn
  /// from here.
  fontAwesome(
    'font_awesome',
    'Font Awesome',
    'Solid, heavy glyphs. The default, and what any other pack falls back to '
        'for a glyph it does not have.',
  ),

  /// Google's Material Symbols, rounded terminals.
  materialRounded(
    'material_rounded',
    'Material Symbols Rounded',
    'Google\'s symbols with rounded corners and ends.',
    opticalScale: 1.2,
  ),

  /// Google's Material Symbols, the outlined style.
  materialOutlined(
    'material_outlined',
    'Material Symbols Outlined',
    'Google\'s symbols, outlined, with crisp corners.',
    opticalScale: 1.2,
  ),

  /// Google's Material Symbols, square terminals.
  materialSharp(
    'material_sharp',
    'Material Symbols Sharp',
    'Google\'s symbols with square corners and ends.',
    opticalScale: 1.2,
  ),

  /// Lucide, the Feather fork: one thin stroke weight, no filled forms.
  lucide(
    'lucide',
    'Lucide',
    'Thin, even strokes and no filled forms. Has no brand logos.',
    opticalScale: 1.1,
  ),

  /// Remix Icon, line style, with its fill style where Font Awesome is solid.
  remix(
    'remix',
    'Remix Icon',
    'Neutral line icons, filled where a state wants to read as on.',
    opticalScale: 1.2,
  );

  const IconPack(
    this.slug,
    this.label,
    this.description, {
    this.opticalScale = 1.0,
  });

  /// How `icon_pack` spells this pack in a theme file.
  final String slug;

  /// The settings UI's name for it.
  final String label;

  /// One sentence for the settings UI's hint.
  final String description;

  /// How much larger than the requested size this pack's glyphs are drawn, so
  /// that one reads as big as a Font Awesome glyph at the same size.
  ///
  /// Font Awesome's glyphs fill their em box; the others are drawn on a
  /// 24-unit grid with padding around the live area. The numbers are measured
  /// rather than chosen: the median extent of the glyphs the shell uses, over
  /// the em, is 1.0 for Font Awesome, 0.83 for Material Symbols and Remix and
  /// 0.92 for Lucide. The layout box is never scaled — only the glyph inside
  /// it — so no bar or row changes height with the pack.
  final double opticalScale;

  /// Whether this is one of the three Material Symbols styles, which share one
  /// table and take the font's `opsz` axis.
  bool get isMaterial =>
      this == materialRounded ||
      this == materialOutlined ||
      this == materialSharp;

  /// The pack [slug] names, or null if this build has no such pack.
  ///
  /// Null rather than a throw or a silent default: the caller is
  /// `ThemeConfig.fromMap`, whose whole discipline is that a bad value costs its
  /// own key and nothing else, and it is the one that holds the fallback.
  static IconPack? fromSlug(String? slug) {
    if (slug == null) return null;
    for (final pack in IconPack.values) {
      if (pack.slug == slug) return pack;
    }
    return null;
  }
}
