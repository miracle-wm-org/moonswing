// Tux, drawn: the vector the widget renders, and the widget that renders it.
//
// **The shell ships no image assets, and this does not change that.** The art
// is an SVG *string constant*, embedded the way `theme/builtin_themes.dart`
// embeds the shipped palettes as TOML text — there is no `assets:` section in
// `pubspec.yaml`, nothing for the Makefile to install and nothing for the snap
// to stage, and it works identically under `flutter run`, `make install` and
// the snap, none of which resolve paths relative to the bundle. It is a string
// rather than a `CustomPainter` (which `moon_render.dart` and `lamp_scene.dart`
// are) for the reason the request asked for: an SVG is an artwork somebody can
// open, edit and replace with a different penguin, where a painter is a
// function only Dart can read.
//
// Five things a change here has to keep true:
//
// - **It scales, and nothing in it is sized in pixels.** Every coordinate is in
//   the `viewBox`'s own units and [TuxArt] fits the whole drawing into whatever
//   box the grid gives it, so the 1x1 card and a 6x4 one draw the same picture
//   at different sizes rather than a small one cropped or a large one blurred.
//   No `width`/`height` attributes on the root — those would fix a size and
//   make `BoxFit` argue with it.
// - **It is flat, and it is legible small.** 1x1 on the default grid is 96
//   logical pixels, and the whole point of the request is that he works there:
//   so the drawing is solid fills with no gradients, no blurs and no strokes
//   thinner than the shape they outline, because every one of those is the
//   first thing to disappear at that size. The parts that identify him — the
//   white front, the orange beak, the two eyes looking slightly inward — are
//   the largest shapes on the canvas for the same reason.
// - **The flippers are a shade lighter than the body.** Pure black on black is
//   a silhouette with no penguin in it; the raised one especially has to read
//   as an arm rather than as a nick out of the outline. This is why the body is
//   a warm near-black rather than `#000`.
// - **He is waving, and the wave is why he is off-centre.** The `viewBox` is
//   wider than he is and his body sits left of its middle, so the raised
//   flipper has somewhere to go. Re-centring the body without narrowing the
//   `viewBox` puts the wave outside the drawing and clips it.
// - **No `<style>`, no CSS, no SMIL.** `flutter_svg` logs `unhandled element
//   <style/>` for every one it parses (which is what `weather_icons.dart` picks
//   the `line` family over `monochrome` to avoid) and drops SMIL animation
//   silently. Nothing here animates in any case — this is a desktop widget, and
//   the rule the lunar and fortune cards state applies with more force to a
//   picture that never changes at all.

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Tux, as SVG source.
///
/// Drawn for this shell rather than traced from Larry Ewing's original, so it
/// carries the repository's own licence and no attribution obligation travels
/// with the binary. Anyone who would rather have the canonical penguin can
/// replace this one constant with the contents of any SVG file — nothing else
/// in the shell knows what is in here, and [TuxArt] only asks that the root
/// carry a `viewBox`.
const String kTuxSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 264">
  <!-- Feet first: the body overlaps their tops, which is what makes him stand
       on them rather than in front of them. -->
  <g fill="#f7b32b">
    <path d="M96,214 C84,214 52,221 34,233 C22,241 26,252 42,252 C66,252 92,246 102,238 C109,232 106,214 96,214 Z"/>
    <path d="M128,214 C140,214 172,221 190,233 C202,241 198,252 182,252 C158,252 132,246 122,238 C115,232 118,214 128,214 Z"/>
  </g>
  <!-- Webbing. Short of the foot's edge at both ends so it reads as a crease
       rather than as a cut. -->
  <g stroke="#d9901a" stroke-width="3" stroke-linecap="round" fill="none">
    <path d="M62,232 L54,246"/>
    <path d="M82,226 L78,242"/>
    <path d="M162,232 L170,246"/>
    <path d="M142,226 L146,242"/>
  </g>
  <!-- The body. -->
  <path fill="#1c1f26" d="M112,16 C70,16 44,52 44,92 C44,110 38,118 32,128 C16,152 14,190 26,212 C38,234 72,244 112,244 C152,244 186,234 198,212 C210,190 208,152 192,128 C186,118 180,110 180,92 C180,52 154,16 112,16 Z"/>
  <!-- Flippers, over the body and under the white front: the resting one can
       then run as far in as it likes without ever touching the belly. -->
  <g fill="#2c313b">
    <path d="M47,112 C31,124 23,160 27,192 C30,210 43,214 48,203 C40,178 39,140 49,120 Z"/>
    <!-- The wave. Every point of it is above and outside the shoulder it
         leaves, so it reads as raised rather than as a bulge. -->
    <path d="M180,116 C188,94 204,68 216,56 C226,46 240,52 238,68 C234,98 218,134 198,150 C186,159 172,140 180,116 Z"/>
  </g>
  <!-- The white front: one shape from between the eyes to the floor, the way a
       penguin's actually is. Splitting it into a face patch and a belly leaves
       a seam across the neck that no amount of rounding hides. -->
  <path fill="#fcfcfa" d="M112,44 C88,44 70,62 68,86 C66,100 60,108 54,116 C36,140 34,186 46,208 C58,228 84,236 112,236 C140,236 166,228 178,208 C190,186 188,140 170,116 C164,108 158,100 156,86 C154,62 136,44 112,44 Z"/>
  <!-- The beak, and the line across it. -->
  <path fill="#f7b32b" d="M112,84 C128,84 140,92 140,100 C140,110 128,116 112,116 C96,116 84,110 84,100 C84,92 96,84 112,84 Z"/>
  <path stroke="#d9901a" stroke-width="3" stroke-linecap="round" fill="none" d="M88,101 C98,108 126,108 136,101"/>
  <!-- The eyes. The pupils sit inboard of the whites, which is the whole of his
       expression: centred ones stare, and outboard ones look alarmed. -->
  <g fill="#fcfcfa">
    <ellipse cx="94" cy="72" rx="13" ry="16"/>
    <ellipse cx="130" cy="72" rx="13" ry="16"/>
  </g>
  <g fill="#14161b">
    <ellipse cx="99" cy="75" rx="6.5" ry="8"/>
    <ellipse cx="125" cy="75" rx="6.5" ry="8"/>
  </g>
  <g fill="#fcfcfa">
    <circle cx="96.5" cy="71" r="2.4"/>
    <circle cx="122.5" cy="71" r="2.4"/>
  </g>
</svg>
''';

/// Tux at whatever size he is given.
///
/// A thin wrapper over [SvgPicture.string] rather than a call site spelling the
/// same three arguments: `BoxFit.contain` and a centred alignment are what make
/// "scales properly" true at every span the registry allows, and a widget that
/// let either be passed in would let one card get them wrong. The picture is
/// parsed once per string by `flutter_svg`'s own cache, so the several surfaces
/// a multi-monitor desktop draws him on share one.
class TuxArt extends StatelessWidget {
  const TuxArt({super.key, this.semanticsLabel = 'Tux the penguin'});

  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      kTuxSvg,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      semanticsLabel: semanticsLabel,
    );
  }
}
