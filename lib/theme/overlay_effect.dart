/// Which animation a full-screen overlay plays as it opens — and, reversed, as
/// it closes — and on what easing.
///
/// The layer-shell overlays (the settings panel, the launcher, the emoji picker,
/// the power menu, the polkit prompt, the screencast picker, the keybind
/// cheat sheet) all arrive through `FadeOverlayScaffold`, and until this table
/// existed they all arrived exactly one way: a scrim fading up under a card
/// scaling from 0.96 on an `easeOutCubic`, at 160ms, with no way to say
/// otherwise. This is that decision named and handed to the theme, the way
/// `popup_animation` did for menu cards.
///
/// Two tables rather than one, because they answer different questions. An
/// [OverlayEffect] is *what moves*; an [OverlayCurve] is *how it is paced*, and
/// the pair multiply out — a `rise` on an `elastic` and a `flip` on a `linear`
/// are both a sentence this key can say. Timing is the third axis and lives on
/// [ThemeConfig] as two numbers: how long the entrance runs, and what fraction
/// of it the exit takes.
///
/// Pure — no Flutter, no `dart:ui` — so the tables and their parsing are a plain
/// unit test. `lib/overlay_transition.dart` turns a member into transforms and
/// `Curves`; the settings UI reads [OverlayEffect.label] and
/// [OverlayEffect.description] off these rows.
library;

/// One overlay entrance, and by reversal one exit.
///
/// Every effect but [none] fades as well as moves. That is not decoration: an
/// overlay is a card centred over a scrim on a surface that spans the whole
/// output, so an effect that only moved would slide a fully opaque card in from
/// somewhere off-screen, and the scrim it is meant to belong to would already
/// be there.
enum OverlayEffect {
  /// No animation at all: scrim and card are simply there, and simply gone.
  ///
  /// A true off switch, as [PopupEffect.none] is — no controller, no ticker, no
  /// layer over the card — and the answer for a user who finds motion
  /// distracting or a machine that cannot spare the compositing.
  none('none', 'None', 'The overlay appears and disappears with no animation.'),

  /// Opacity alone: the scrim washes in and the card fades up in place.
  fade('fade', 'Fade', 'The scrim and the card fade in, and fade back out.'),

  /// A small scale up from just under full size, under a fade. The default, and
  /// what every overlay played before this key existed.
  scale('scale', 'Scale',
      'The card grows a little into place from its own centre, under a fade. '
          'The default.'),

  /// A scale *down* into place from just over full size, under a fade.
  ///
  /// The counterpart to [scale], and the one that reads as the overlay coming
  /// towards the screen rather than out of it — the shape a modal dialog
  /// traditionally arrives with.
  zoom('zoom', 'Zoom',
      'The card settles back to size from slightly larger, as though coming '
          'towards you.'),

  /// A short travel upward, under a fade.
  rise('rise', 'Rise',
      'The card lifts into place from below, under a fade.'),

  /// A short travel downward, under a fade.
  drop('drop', 'Drop',
      'The card comes down into place from above, under a fade.'),

  /// A cross-axis scale about the card's own centre: it unrolls vertically.
  unfold('unfold', 'Unfold',
      'The card unfolds vertically from its own middle, keeping its width.'),

  /// A perspective rotation about the card's horizontal axis.
  flip('flip', 'Flip',
      'The card tilts open about its horizontal middle, as though hinged '
          'there.'),

  /// A perspective rotation about the card's vertical axis.
  swing('swing', 'Swing',
      'The card swings open about its vertical middle, like a door.'),

  /// A small rotation and scale about the card's centre, under a fade.
  spin('spin', 'Spin',
      'The card turns a few degrees as it scales into place, under a fade.');

  const OverlayEffect(this.slug, this.label, this.description);

  /// How `overlay_animation` spells this effect in a theme file.
  final String slug;

  /// The settings UI's name for it.
  final String label;

  /// One sentence for the settings UI's hint.
  final String description;

  /// Whether anything is drawn between the two end states.
  ///
  /// What the scaffold needs before it builds anything: an effect that animates
  /// has to be given a controller and time to play out before the window is torn
  /// down, and one that does not must cost neither.
  bool get animates => this != OverlayEffect.none;

  /// The effect [slug] names, or null if this build has no such effect.
  ///
  /// Null rather than a throw or a silent default, for the reason
  /// `PopupEffect.fromSlug` is: the caller is `ThemeConfig.fromMap`, whose whole
  /// discipline is that a bad value costs its own key and nothing else, and it
  /// is the one holding the fallback.
  static OverlayEffect? fromSlug(String? slug) {
    if (slug == null) return null;
    for (final effect in OverlayEffect.values) {
      if (effect.slug == slug) return effect;
    }
    return null;
  }
}

/// The easing an [OverlayEffect] is played on.
///
/// A separate key from the effect because the same movement paced two ways is
/// two different arrivals — a card that rises on [easeOut] is answering you,
/// and the same rise on [bounce] is a toy. The exit is this read backwards, so
/// an overshoot on the way in is an anticipation dip on the way out, which is
/// the pair those curves are drawn to make.
///
/// Three of these leave the unit interval ([overshoot], [bounce], [elastic]).
/// That is what makes them worth having — a card that goes a little past its
/// resting size and comes back is the whole effect — and it is why opacity is
/// driven by the same curve *clamped*: an `Opacity` below 0 or above 1 is an
/// assertion failure, not a flourish. See `lib/overlay_transition.dart`.
enum OverlayCurve {
  /// No easing at all. Mechanical, and the honest choice for a very short
  /// duration where an ease has no room to be read.
  linear('linear', 'Linear', 'A constant rate, with no acceleration.'),

  /// Slow to start, fast at the end. On the way out this is the deceleration.
  easeIn('ease_in', 'Ease in', 'Starts slowly and accelerates into place.'),

  /// Fast to start, settling at the end — the shell's standard entrance, and
  /// the default. `Curves.easeOutCubic`, which is what popups play too.
  easeOut('ease_out', 'Ease out',
      'Starts quickly and settles into place. The default.'),

  /// Eased at both ends.
  easeInOut('ease_in_out', 'Ease in and out',
      'Accelerates away and decelerates in, eased at both ends.'),

  /// Material's asymmetric standard curve: a sharper departure than
  /// [easeInOut] with the same soft landing.
  emphasized('emphasized', 'Emphasized',
      'A sharp departure and a soft landing, weighted towards the end.'),

  /// A small overshoot past the resting state, then back.
  overshoot('overshoot', 'Overshoot',
      'Goes a little past where it is heading, then settles back.'),

  /// A landing that bounces before it settles.
  bounce('bounce', 'Bounce', 'Lands, bounces, and lands again.'),

  /// A springy overshoot that oscillates before settling.
  ///
  /// Wants a longer duration than the default to be read as a spring rather
  /// than a stutter — which is what `overlay_animation_duration` is for.
  elastic('elastic', 'Elastic',
      'Springs past and oscillates before settling. Wants a longer duration '
          'than the default.');

  const OverlayCurve(this.slug, this.label, this.description);

  /// How `overlay_animation_curve` spells this easing in a theme file.
  final String slug;

  /// The settings UI's name for it.
  final String label;

  /// One sentence for the settings UI's hint.
  final String description;

  /// The easing [slug] names, or null if this build has no such curve.
  static OverlayCurve? fromSlug(String? slug) {
    if (slug == null) return null;
    for (final curve in OverlayCurve.values) {
      if (curve.slug == slug) return curve;
    }
    return null;
  }
}
