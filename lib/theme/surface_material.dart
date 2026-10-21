/// What a themed surface is *made of*, and what grows on it.
///
/// A colour says what a surface looks like from across the room; a material
/// says what it looks like up close — grain, joints, fissures, a moss bed. The
/// two are separate keys because they are separate decisions: `forest` paints
/// its bar a near-black green and then lays a timber beam over it, and the
/// same oak would read just as well over a lighter palette.
///
/// Pure — no Flutter, no `dart:ui` — for `popup_effect.dart`'s reason: the
/// theme parser and the settings pickers read these tables, and a plain unit
/// test pins them. The pixels are `lib/decor/`'s.
library;

/// One procedural material a bar, a bar's ends, a popup card or a popup's rim
/// can be painted in.
///
/// Every member is *arithmetic*: a tile drawn once from a seeded generator and
/// cached as an image, never an asset — the rule the shipped themes, sounds and
/// emoji table already keep, since nothing in the shell resolves a path inside
/// the bundle. A theme that wants a real photograph names a file instead
/// (`panel_image`, `popup_image`), which wins over the material once it loads.
enum SurfaceMaterial {
  /// Nothing: the surface is its colour alone, exactly as before materials
  /// existed. The default for every key, so a theme spelling none of them is
  /// painted byte-for-byte as it was.
  none('none', 'None', 'No texture; the surface is its colour alone.'),

  /// Planks, with their grain running the length of the surface, knots the
  /// grain bends around, and a seam where one board butts the next.
  wood('wood', 'Wood',
      'Timber planks: grain running the length of the surface, knots, seams.'),

  /// Fitted stones — rounded, irregular, each one shaded as a lump rather than
  /// a flat tile — in a dark mortar bed, with moss in the joints.
  stone('stone', 'Stone',
      'Fitted, rounded stones in a dark mortar bed, with moss in the joints.'),

  /// Tree bark: deep fissures between raised ridges that run *along* the
  /// trunk, crossed by the odd crack and spotted with lichen.
  bark('bark', 'Bark',
      'Ridged bark with deep fissures running along the trunk, and lichen.'),

  /// A soft bed of moss: thousands of fine tufts, with no edges anywhere in it.
  moss('moss', 'Moss', 'A soft bed of fine moss, with no edges in it.');

  const SurfaceMaterial(this.slug, this.label, this.description);

  /// How a theme file spells this material.
  final String slug;

  /// The settings UI's name for it.
  final String label;

  /// One sentence for the settings UI's dropdown.
  final String description;

  /// Whether anything is painted at all. [none] is a real off switch: no tile
  /// is generated and no painter is built.
  bool get paints => this != SurfaceMaterial.none;

  /// The material [slug] names, or null if this build has no such material —
  /// null so `ThemeConfig.fromMap` holds the fallback, as it does for every
  /// other closed set.
  static SurfaceMaterial? fromSlug(String? slug) {
    if (slug == null) return null;
    for (final m in SurfaceMaterial.values) {
      if (m.slug == slug) return m;
    }
    return null;
  }
}

/// What grows off a bar — painted foliage that hangs (or, from a bottom bar,
/// climbs) past the bar's inner edge and over whatever is behind it.
///
/// Each member is a *recipe*: how much of each plant part a bar of a given
/// length grows. The plants themselves are `lib/decor/foliage.dart`'s, and
/// which way they grow is not part of the recipe at all — it is the bar's
/// anchor, read as gravity. A top bar's vines hang, a bottom bar's ferns
/// stand up, and a side bar's tendrils leave it sideways and droop.
enum FoliageStyle {
  /// Nothing grows. The off switch, and the default.
  none('none', 'None', 'Nothing grows off the bar.'),

  /// Ivy: long vines of heart-shaped leaves, dense along the bar itself.
  ivy('ivy', 'Ivy',
      'Long trailing vines of ivy, dense where they leave the bar.'),

  /// Moss: fine hanging strands and drips, a few small leaves, no vines to
  /// speak of. The quietest recipe.
  moss('moss', 'Hanging moss',
      'Fine strands of moss and the odd small leaf — the quietest of these.'),

  /// Everything: ivy vines, hanging moss, ferns sprouting from the bar's ends,
  /// clumps of leaves along its edge and a scatter of berries and flowers in
  /// the bloom colour. What `forest` grows.
  wildwood('wildwood', 'Wildwood',
      'Vines, moss, ferns at the ends, leaf clumps along the edge, and a '
          'scatter of berries and flowers.'),

  /// Autumn: turning boughs of maple and oak gathered in a bar's two corners,
  /// with the odd leaf on its way down — or, on a bar the plants stand on,
  /// pumpkin patches along its edge. The leaves are every colour between
  /// `foliage_color`'s green and `foliage_bloom`'s orange and past it, and
  /// the pumpkins are mostly the bloom. What `autumn` grows.
  harvest('harvest', 'Harvest',
      'Turning leaves in the corners of a top or side bar, and pumpkin '
          'patches along a bottom one.');

  const FoliageStyle(this.slug, this.label, this.description);

  /// How a theme file spells this style.
  final String slug;

  /// The settings UI's name for it.
  final String label;

  /// One sentence for the settings UI's dropdown.
  final String description;

  /// Whether anything grows at all.
  bool get grows => this != FoliageStyle.none;

  /// The style [slug] names, or null when this build has none by that name.
  static FoliageStyle? fromSlug(String? slug) {
    if (slug == null) return null;
    for (final s in FoliageStyle.values) {
      if (s.slug == slug) return s;
    }
    return null;
  }
}
