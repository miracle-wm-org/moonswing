// A glyph per row of the WMO table.
//
// The other half of `weather_condition.dart`, split off because this one needs a
// widget library and that one is a plain unit test.
//
// Meteocons — `weather_icons_animated`, the Bas Milius set — rather than Material
// Symbols. What the change buys is granularity: a *shower* is a break in the
// cloud with rain falling through it and Meteocons draws it that way, where
// Material Symbols had one `rainy` and a heavier version of it.
//
// Three things a change here has to keep true:
//
// - **Nothing here animates, and the pack's Lottie format is not reachable from
//   this file.** The desktop widget's hero glyph used to be one, running a
//   `Ticker` for as long as a wallpaper widget was on screen. A still SVG is what
//   every surface draws now, which is what makes them safe to `pumpAndSettle`.
// - **A tinted icon comes from an *outlined* family, never the fill one.**
//   `BlendMode.srcIn` over a full-colour Meteocon flattens it to a silhouette,
//   and the silhouette of `partly-cloudy-day` is one blob. Of the two outlined
//   families it is **line** rather than `monochrome`, and the difference is not
//   visual: 196 of the 236 monochrome files carry a `<style>` block nothing
//   references, and `flutter_svg` logs `unhandled element <style/>` for each.
// - **A slug this build does not know costs the icon, not the panel.** Every name
//   goes through [_glyph], which degrades to `not-available`, and never through
//   `WeatherIcons.named`, which throws — out of a `build`.
//
// Night has its own glyphs only for the conditions where the sky is visible
// through the cloud: a raincloud at midnight is the same raincloud.

import 'package:flutter/widgets.dart';
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

/// The icon for a slug this build does not recognise — which is also the icon
/// for weather it cannot fetch.
final WeatherGlyph _unavailable = meteocons.WeatherIcons.named('not-available');

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
    WeatherKind.mainlyClear || WeatherKind.partlyCloudy => _glyph(
      night ? 'partly-cloudy-night' : 'partly-cloudy-day',
    ),
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
    WeatherKind.rainShowers =>
      heavy
          ? _glyph('extreme-rain')
          : _glyph(
              night ? 'partly-cloudy-night-rain' : 'partly-cloudy-day-rain',
            ),
    WeatherKind.snowShowers =>
      heavy
          ? _glyph('extreme-snow')
          : _glyph(
              night ? 'partly-cloudy-night-snow' : 'partly-cloudy-day-snow',
            ),
    WeatherKind.thunderstorm => _glyph(
      night ? 'thunderstorms-night' : 'thunderstorms-day',
    ),
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

/// A weather glyph, at the one size and family the shell draws them at.
///
/// Two renderings behind one widget, chosen by what the call site asks for rather
/// than by a flag it has to remember:
///
/// - a [color] means the outlined **line** family painted that colour — the bar,
///   the popup's small metrics, the detail row and forecast strip;
/// - no colour is the **fill** family in its own, drawn as a still SVG.
///
/// Neither moves.
///
/// [size] is the box, and Meteocons draw inside a padded 512-unit viewBox —
/// `clear-day` is 384 across — so a glyph asked for at 16 reads at about 12. The
/// call sites that came from Material Symbols were all grown by roughly a quarter;
/// a new one should be picked by eye against its neighbours.
///
/// There is no `shadows`, which the Material Symbols wrapper took: a [Shadow]
/// hangs off a *glyph*, and an SVG picture is not one. What the desktop widget
/// used it for is already guaranteed by `SkyScrim`.
class WeatherIcon extends StatelessWidget {
  const WeatherIcon(this.icon, {super.key, required this.size, this.color});

  final WeatherGlyph icon;

  /// The box the glyph is laid out in, both edges.
  final double size;

  /// Null draws the Meteocon in its own colours. Anything else paints it flat
  /// in that colour, from the outlined `line` family — see the class doc for
  /// why those are not the same source artwork.
  final Color? color;

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
      format: meteocons.WeatherIconFormat.svgStatic,
      size: size,
    );
  }
}
