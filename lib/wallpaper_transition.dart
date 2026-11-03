/// How the desktop moves from one wallpaper to the next — `[background]
/// transition` — and, for `random`, which effect a given change plays.
///
/// Until this table existed every change was the same 1.5s crossfade. The
/// rotation timer, a theme switch with the Theme default shown and an edit to
/// the shown set all go through it, so this is the one place that decides how a
/// wallpaper arrives.
///
/// Pure — no Flutter, no `dart:ui` — so parsing and the random pick are a plain
/// unit test. `lib/background_transition.dart` turns a member into clips,
/// transforms and opacities; the settings UI reads [WallpaperTransition.label]
/// and [WallpaperTransition.description] off these rows.
library;

import 'dart:math' as math;

/// One way of changing wallpaper, or [random], a different one each time.
enum WallpaperTransition {
  /// Draw a different effect from [effects] for every change.
  random(
    'random',
    'Random',
    'A different effect each time the wallpaper changes, never the same one '
        'twice in a row.',
  ),

  /// No animation: the new wallpaper simply replaces the old.
  none('none', 'None', 'The new wallpaper replaces the old one at once.'),

  /// The new wallpaper fades in over the old. What every change played before
  /// this key existed, and still the default.
  fade(
    'fade',
    'Fade',
    'The new wallpaper fades in over the old one. The default.',
  ),

  /// A grid of squares, every other one wiping across first and the rest
  /// following half a square behind.
  checkerboard(
    'checkerboard',
    'Checkerboard',
    'A chequered grid of squares wipes across, every other square half a step '
        'behind its neighbours.',
  ),

  /// A circle opening from the middle of the screen until it reaches the
  /// corners.
  circle(
    'circle',
    'Circle',
    'A circle opens from the middle of the screen and grows out until the new '
        'wallpaper fills it.',
  ),

  /// The old wallpaper turns away about the screen's vertical middle and the
  /// new one turns in to face you, like a card turned over.
  flip(
    'flip',
    'Flip',
    'The old wallpaper turns over like a card, and the new one is on its back.',
  ),

  /// The new wallpaper slides in over the old one from a random edge.
  slide(
    'slide',
    'Slide',
    'The new wallpaper slides in over the old one from a random edge.',
  ),

  /// A straight edge sweeping across from a random side, uncovering the new
  /// wallpaper behind it.
  wipe(
    'wipe',
    'Wipe',
    'A straight edge sweeps across the screen from a random side, uncovering '
        'the new wallpaper.',
  ),

  /// Horizontal slats, each opening downwards at once, like a Venetian blind.
  blinds(
    'blinds',
    'Blinds',
    'The new wallpaper opens in horizontal slats, like a blind.',
  ),

  /// The new wallpaper settles back to size from slightly larger as it fades
  /// in.
  zoom(
    'zoom',
    'Zoom',
    'The new wallpaper settles back to size from slightly larger as it fades '
        'in.',
  ),

  /// The new wallpaper dissolves in as a scatter of small tiles, each landing
  /// at its own moment.
  dissolve(
    'dissolve',
    'Dissolve',
    'The new wallpaper arrives as a scatter of small tiles, each at its own '
        'moment.',
  );

  const WallpaperTransition(this.slug, this.label, this.description);

  /// How `[background] transition` spells this member.
  final String slug;

  /// The settings UI's name for it.
  final String label;

  /// One sentence for the settings UI's dropdown.
  final String description;

  /// The default: the crossfade every change played before the key existed.
  static const WallpaperTransition fallback = WallpaperTransition.fade;

  /// Every concrete effect — what [random] draws from. Neither [random] itself
  /// nor [none], which is the absence of an effect rather than one.
  static final List<WallpaperTransition> effects = [
    for (final t in values)
      if (t != random && t != none) t,
  ];

  /// Whether anything is drawn between the two wallpapers.
  bool get animates => this != none;

  /// Whether this effect comes from a side, which a [WallpaperTransitionPlan]
  /// then names.
  bool get directional => this == slide || this == wipe;

  /// The member [slug] names, or null if this build has no such member — the
  /// caller holds the fallback, so a bad value costs only its own key.
  static WallpaperTransition? fromSlug(String? slug) {
    if (slug == null) return null;
    for (final t in values) {
      if (t.slug == slug) return t;
    }
    return null;
  }
}

/// The screen edge a directional effect comes in from.
enum WallpaperEdge { left, right, top, bottom }

/// What one wallpaper change will play: a concrete effect, the edge it comes
/// from (for [WallpaperTransition.directional] ones) and a seed for any effect
/// with randomness of its own, so a frame is a pure function of the plan and
/// the progress.
class WallpaperTransitionPlan {
  const WallpaperTransitionPlan(
    this.effect, {
    this.edge = WallpaperEdge.right,
    this.seed = 0,
  });

  final WallpaperTransition effect;
  final WallpaperEdge edge;
  final int seed;

  /// The plan for one change under [setting].
  ///
  /// [setting] `random` draws from [WallpaperTransition.effects], never
  /// repeating [previous] — the point of random is that consecutive changes
  /// look different. The edge and seed are drawn whatever the effect, so the
  /// sequence [random] produces does not depend on which effect was picked.
  factory WallpaperTransitionPlan.choose(
    WallpaperTransition setting,
    math.Random random, {
    WallpaperTransition? previous,
  }) {
    var effect = setting;
    if (setting == WallpaperTransition.random) {
      final pool = [
        for (final e in WallpaperTransition.effects)
          if (e != previous) e,
      ];
      effect = pool[random.nextInt(pool.length)];
    }
    final edge = WallpaperEdge.values[random.nextInt(WallpaperEdge.values.length)];
    final seed = random.nextInt(1 << 31);
    return WallpaperTransitionPlan(effect, edge: edge, seed: seed);
  }

  @override
  bool operator ==(Object other) =>
      other is WallpaperTransitionPlan &&
      other.effect == effect &&
      other.edge == edge &&
      other.seed == seed;

  @override
  int get hashCode => Object.hash(effect, edge, seed);

  @override
  String toString() => 'WallpaperTransitionPlan($effect, $edge, $seed)';
}
