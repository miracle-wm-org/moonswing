// A glyph per row of the WMO table.
//
// The other half of `weather_condition.dart`, split off because this one needs
// a widget library and that one is a plain unit test.
//
// Meteocons — `weather_icons_animated`, the Bas Milius set — rather than
// Material Symbols, which is what these were before and which replaced the
// emoji the bar started with. Two things the change buys. The set carries the
// WMO table's own granularity and then some: a *shower* is a break in the
// cloud with rain falling through it and Meteocons draws it that way
// (`partly-cloudy-day-rain`), where Material Symbols had one `rainy` and a
// heavier version of it, so "Showers" and "Rain" were the same picture with
// different words under them. And they move, which is the point of a weather
// icon on a desktop card that is already drawing a live sky behind it.
//
// Four things a change here has to keep true:
//
// - **An animated icon is a Lottie, never the animated SVG.** The pack ships
//   both. The SVGs carry their motion as SMIL (`<animateTransform>`), which
//   `flutter_svg` parses and drops — so `WeatherIconFormat.svgAnimated` renders
//   a still frame that merely costs more to parse than `svgStatic` does, and
//   the difference is invisible until somebody wonders why the animated icons
//   never animated. [WeatherIcon] therefore reaches for Lottie or for nothing.
// - **A moving icon is capped below the display's rate.** `weather_sky.dart`'s
//   rule, and its reason: these run for as long as the desktop widget is on
//   screen, on a machine that may be doing nothing else, and nothing in a
//   weather glyph moves fast enough to want 16ms. The cap is the same 30 the
//   sky behind it uses, so the card has one frame budget rather than two.
// - **A tinted icon comes from an *outlined* family, never from the fill one.**
//   `BlendMode.srcIn` over a full-colour Meteocon flattens it to a silhouette,
//   and the silhouette of `partly-cloudy-day` is a single blob where the sun
//   and the cloud used to be. The outlined families survive being painted one
//   colour, which is what the bar needs — a bar icon no theme can recolour is
//   exactly what these replaced an emoji to avoid. Of the two it is **line**
//   rather than `monochrome`, and the difference is not visual: `srcIn`
//   flattens both to the same outline. 196 of the 236 monochrome files carry a
//   `<style>` block that no element in them references, and `flutter_svg`
//   logs `unhandled element <style/>` for every one it parses — a line of
//   noise per icon, in a shell whose log is where its real failures are read.
// - **A slug this build does not know costs the icon, not the panel.**
//   `conditionForCode`'s rule one layer up, applied to the pack: a version that
//   renames a slug must degrade to `not-available`, not throw out of a
//   `build`. That is why every name here goes through [_glyph] and never
//   through `WeatherIcons.named`, which throws.
//
// Night has its own glyphs for the conditions where the sky is visible through
// the cloud, and only those: it is the sun or the moon in the icon that
// differs, and a raincloud at midnight is the same raincloud.

import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart' show FrameRate;
import 'package:material_symbols_icons/symbols.dart';
import 'package:weather_icons_animated/weather_icons_animated.dart'
    as meteocons;

import 'package:graceful_shell/weather/weather_condition.dart';

/// One icon of the Meteocons set, as a value.
///
/// Aliased rather than used under its own name because the package spells it
/// `WeatherIconData` and exports a `WeatherIcon` *widget* beside it, which is
/// the name this file's own wrapper has had since it existed.
typedef WeatherGlyph = meteocons.WeatherIconData;

/// How many frames a second an animated glyph is allowed. `weather_sky.dart`'s
/// `kSkyFrameInterval` states the same budget from the other end; a card
/// carrying both should not be running them at two different rates.
const FrameRate kWeatherIconFrameRate = FrameRate(30);

/// The icon for a slug this build does not recognise — which is also the icon
/// for weather it cannot fetch.
final WeatherGlyph _unavailable =
    meteocons.WeatherIcons.named('not-available');

/// [slug], or [_unavailable] if the installed pack has no such name.
///
/// Never `WeatherIcons.named`, which throws: the pack is a version constraint
/// like any other, and a slug renamed upstream must cost this one icon rather
/// than every surface that draws it.
WeatherGlyph _glyph(String slug) =>
    meteocons.WeatherIcons.maybeNamed(slug) ?? _unavailable;

/// The icon for [condition]. [night] picks the moonlit variant where there is
/// one.
WeatherGlyph weatherIcon(WeatherCondition condition, {bool night = false}) {
  final heavy = condition.intensity >= 0.8;

  return switch (condition.kind) {
    WeatherKind.clear => _glyph(night ? 'clear-night' : 'clear-day'),
    // Meteocons has no "mainly clear"; a sun with one cloud beside it is what
    // `partly-cloudy-*` draws, and it is the right picture for both rows.
    WeatherKind.mainlyClear ||
    WeatherKind.partlyCloudy =>
      _glyph(night ? 'partly-cloudy-night' : 'partly-cloudy-day'),
    // Day-neutral on purpose: overcast is the definition of the sun not being
    // visible, so `overcast-day` — which draws one shining through — would
    // contradict the label beside it.
    WeatherKind.overcast => _glyph('overcast'),
    WeatherKind.fog => _glyph(night ? 'fog-night' : 'fog-day'),
    WeatherKind.drizzle => _glyph('drizzle'),
    WeatherKind.freezingDrizzle => _glyph('sleet'),
    WeatherKind.rain => _glyph(heavy ? 'extreme-rain' : 'rain'),
    WeatherKind.freezingRain => _glyph(heavy ? 'extreme-sleet' : 'sleet'),
    WeatherKind.snow => _glyph(heavy ? 'extreme-snow' : 'snow'),
    WeatherKind.snowGrains => _glyph('snow'),
    // A shower is rain falling through a *break* in the cloud, which is the
    // one distinction Material Symbols could not draw and this pack can. The
    // violent end of the scale gives it up: at that intensity there is no
    // break left to show.
    WeatherKind.rainShowers => heavy
        ? _glyph('extreme-rain')
        : _glyph(night ? 'partly-cloudy-night-rain' : 'partly-cloudy-day-rain'),
    WeatherKind.snowShowers => heavy
        ? _glyph('extreme-snow')
        : _glyph(night ? 'partly-cloudy-night-snow' : 'partly-cloudy-day-snow'),
    WeatherKind.thunderstorm =>
      _glyph(night ? 'thunderstorms-night' : 'thunderstorms-day'),
    // There is no thunder-and-hail glyph in the set. Severity is the half of
    // this row somebody acts on, and the label beside the icon is already
    // saying "with hail".
    WeatherKind.thunderstormHail => _glyph('thunderstorms-extreme'),
    // Not a blank: the module still has a temperature to show, and an icon
    // that says "something, and the shell does not know what" is the honest
    // rendering of a code from a table this build predates.
    WeatherKind.unknown => _unavailable,
  };
}

/// The icon a chance-of-rain figure is printed beside.
final WeatherGlyph kPrecipitationIcon = _glyph('raindrop');

final WeatherGlyph kHumidityIcon = _glyph('humidity');
final WeatherGlyph kWindIcon = _glyph('wind');
final WeatherGlyph kFeelsLikeIcon = _glyph('thermometer');

/// The bar module with no reading to show. Meteocons draws this one as a cloud
/// with a slash through it, which is the right shape for the same reason the
/// Material Symbol before it was: the thing that is unavailable is the
/// weather, and a warning triangle in a bar reads as the shell itself being in
/// trouble.
final WeatherGlyph kWeatherUnavailableIcon = _unavailable;

/// The place marker, and the one icon on these surfaces that is **not** a
/// Meteocon: it is a weather set, and a map pin is not weather. Rendered with a
/// plain [Icon] at the call site rather than through [WeatherIcon], which takes
/// a [WeatherGlyph].
const IconData kLocationIcon = Symbols.location_on;

/// A weather glyph, at the one size, family and frame rate the shell draws
/// them at.
///
/// Three renderings behind one widget, chosen by what the call site asks for
/// rather than by a flag it has to remember:
///
/// - a [color] means the outlined **line** family painted that colour — the
///   bar, the popup's small metrics, the detail row over the sky;
/// - no colour and [animate] means the **fill** family as a Lottie, capped at
///   [kWeatherIconFrameRate] — the desktop widget's hero, over its own sky;
/// - no colour and no animation is the same fill family as a still SVG.
///
/// [size] is the box, and Meteocons draw inside a 512-unit viewBox with
/// generous padding — `clear-day` is 384 across — so a glyph asked for at 16
/// reads at about 12. The call sites that came from Material Symbols were
/// therefore all grown by roughly a quarter when they moved here; a new one
/// should be picked by eye against its neighbours rather than copied off a
/// Material Symbols size.
///
/// There is no `shadows`, which the Material Symbols wrapper took: a [Shadow]
/// hangs off a *glyph*, and neither an SVG picture nor a Lottie is one. What
/// the desktop widget was using it for is already guaranteed by `SkyScrim` —
/// something dark under the readout whatever the sky is doing — and the text
/// beside these still carries `kSkyTextShadows` itself. Painting the artwork
/// twice to fake one would double the raster cost of every icon on the card
/// for a card that already has a scrim under it.
class WeatherIcon extends StatelessWidget {
  const WeatherIcon(
    this.icon, {
    super.key,
    required this.size,
    this.color,
    this.animate = false,
  });

  final WeatherGlyph icon;

  /// The box the glyph is laid out in, both edges.
  final double size;

  /// Null draws the Meteocon in its own colours. Anything else paints it flat
  /// in that colour, from the outlined `line` family — see the class doc for
  /// why those are not the same source artwork.
  final Color? color;

  /// Whether the glyph plays. Off by default, and deliberately: an animation is
  /// a `Ticker` that never settles, so a surface that turns this on is a
  /// surface nothing may `pumpAndSettle` — the trap `WeatherSky` and
  /// `TrackMarquee` already carry. Only the desktop widget's hero sets it, off
  /// the same `animate` flag that gates its sky.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final tint = color;
    if (tint != null) {
      return meteocons.WeatherIcon(
        icon: icon,
        style: meteocons.WeatherIconStyle.line,
        format: meteocons.WeatherIconFormat.svgStatic,
        size: size,
        color: tint,
      );
    }

    return meteocons.WeatherIcon(
      icon: icon,
      style: meteocons.WeatherIconStyle.fill,
      format: animate
          ? meteocons.WeatherIconFormat.lottie
          : meteocons.WeatherIconFormat.svgStatic,
      size: size,
      animate: animate,
      repeat: animate,
      frameRate: animate ? kWeatherIconFrameRate : null,
    );
  }
}
