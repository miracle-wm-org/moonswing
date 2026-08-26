// The round icon action that sits in the corner of a picture-backed desktop
// card.
//
// Generalized out of the fortune widget's refresh button when the astrology
// card wanted the same control, which is the rule `overlay/settings/controls.
// dart` states for the settings library: **a control the library lacks gets
// added to the library, generalized from the best copy** — the four hand-rolled
// icon buttons that drifted apart before it was written are what that rule is
// made of.
//
// Three things it keeps from the copy it came from:
//
// - **Barely there at rest.** These cards spend nearly all their life being
//   looked at rather than used, and a solid button in the corner of a picture
// is   chrome on the wallpaper.
// - **It takes its colours from the picture, not the theme.** A card whose
//   backdrop runs from a near-black sky to the glare beside a flame has no
// theme   foreground legible across both — the call `weather_widget.dart`,
//   `moon_widget.dart` and the lock screen all make.
// - **It is a *tap*, never a pan.** A desktop widget is dragged from anywhere
// on   its card, and the two recognizers resolve against each other: a press
// that   moves is the drag, one that does not is this. A pan-driven control on
// one of   these cards would have to take the drag somewhere else first.

import 'package:flutter/widgets.dart';

import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/weather/weather_sky.dart'
    show kSkyForeground, kSkyMutedForeground, kSkyTextShadows;

/// The button's box at a card drawn at its reference size.
const double kSkyIconButtonBox = 26;

class SkyIconButton extends StatelessWidget {
  const SkyIconButton({
    super.key,
    required this.onTap,
    required this.icon,
    this.size = kSkyIconButtonBox,
  });

  final VoidCallback onTap;

  /// The glyph. A Material Symbol rather than a Meteocon: the packs the shell
  /// carries for weather have no interface iconography, which is the split
  /// `weather_icons.dart` documents for `kLocationIcon`.
  final IconData icon;

  /// The pointer target, never the glyph — `ShellSizes`' rule. The glyph is
  /// drawn at a little over half of it.
  final double size;

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => AnimatedContainer(
        duration: ShellDurations.fast,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: kSkyForeground.withValues(alpha: hovered ? 0.24 : 0.10),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            icon,
            size: size * 0.6,
            color: hovered ? kSkyForeground : kSkyMutedForeground,
            weight: 500,
            opticalSize: 20,
            shadows: kSkyTextShadows,
          ),
        ),
      ),
    );
  }
}
