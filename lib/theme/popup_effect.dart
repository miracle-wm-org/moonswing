/// Which animation a popup plays as it opens — and, reversed, as it closes.
///
/// The shell used to have exactly one: a 500 ms elastic scale that every popup
/// content widget wrapped itself in by hand, with no counterpart on the way
/// out, so a card that sprang into view simply blinked out of existence again.
/// This is that decision named, made a theme key (`popup_animation`), and given
/// the one property that makes an exit animation possible at all: **every
/// effect is played forward to open and reversed to close**, so the way out is
/// the way in backwards and no effect needs a second definition to describe it.
///
/// Pure — no Flutter, no `dart:ui` — so the table and its parsing are a plain
/// unit test. `lib/popup_transition.dart` is what turns a member of this enum
/// into curves and transforms; the settings UI reads [label] and [description]
/// straight off these rows.
library;

/// One popup entrance, and by reversal one exit.
enum PopupEffect {
  /// No animation at all: the card is simply there, and simply gone.
  ///
  /// Not a degenerate case — it is what the dock's menus use, and what a user
  /// who finds motion distracting picks for the whole shell.
  none('none', 'None', 'The card appears and disappears with no animation.'),

  /// Opacity alone.
  fade('fade', 'Fade', 'The card fades in, and fades back out.'),

  /// A short travel out of the bar the popup is anchored to, under a fade.
  ///
  /// The default, and the one effect that reads as the card *coming from* its
  /// button rather than merely arriving: the direction is the panel's own edge,
  /// so a bottom bar's menus rise and a top bar's drop.
  slide('slide', 'Slide and fade',
      'A quick travel out of the bar the popup belongs to, under a fade. '
          'The default.'),

  /// A scale about the card's centre, under a fade.
  scale('scale', 'Scale',
      'The card grows into place from its own centre, under a fade.'),

  /// A scale anchored at the edge the popup is joined to, so the card unrolls
  /// out of the bar rather than growing in place.
  grow('grow', 'Grow from edge',
      'The card unrolls out of the bar it is anchored to, growing from the '
          'edge they share.'),

  /// A perspective rotation about the axis of that same edge.
  flip('flip', 'Flip',
      'The card swings open about the edge it shares with the bar, as though '
          'hinged there.'),

  /// A small rotation and scale about the card's centre, under a fade.
  spin('spin', 'Spin',
      'The card turns a few degrees as it scales into place, under a fade.');

  const PopupEffect(this.slug, this.label, this.description);

  /// How `popup_animation` spells this effect in a theme file.
  final String slug;

  /// The settings UI's name for it.
  final String label;

  /// One sentence for the settings UI's hint.
  final String description;

  /// Whether anything is drawn between the two end states.
  ///
  /// The one thing `PopupHost` needs to know without building a widget: an
  /// effect that animates has to be given time to play out before the window is
  /// destroyed, and one that does not must never cost a frame of delay.
  bool get animates => this != PopupEffect.none;

  /// The effect [slug] names, or null if this build has no such effect.
  ///
  /// Null rather than a throw or a silent default: the caller is
  /// `ThemeConfig.fromMap`, whose whole discipline is that a bad value costs
  /// its own key and nothing else, and it is the one that holds the fallback.
  static PopupEffect? fromSlug(String? slug) {
    if (slug == null) return null;
    for (final effect in PopupEffect.values) {
      if (effect.slug == slug) return effect;
    }
    return null;
  }
}
