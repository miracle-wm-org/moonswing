import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/icons/icon_resolver.dart';
import 'package:moonswing/icons/pack_glyph.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/icon_pack.dart';

/// An interface icon: [glyph], in the theme's `icon_pack`.
///
/// **The one way the shell draws an interface icon.** No call site names a
/// font's constants (`FontAwesomeIcons.`, `Symbols.`, `LucideIcons.`,
/// `RemixIcons.`) — those live in `lib/icons/packs/` and nowhere else, and
/// `test/icon_pack_test.dart` walks `lib/` to keep it so. A call site that
/// names a font has opted out of the user's choice.
///
/// The pack is read from [ThemeScope], so an open popup restyles when the pack
/// changes, the way it does for a colour; with no scope above (a test, a tree
/// built before the theme), it is the default pack.
///
/// Under the default pack this builds exactly what the call site built before
/// packs existed: [FaIcon] for a Font Awesome glyph, set unboxed at its own
/// advance, and [Icon] for the handful of Material Symbols the sky cards drew.
/// Under any other pack the glyph is an [Icon] enlarged by
/// [IconPack.opticalScale] inside a box of the requested [size] — the box is
/// never scaled, so no row or bar changes height with the pack.
class ShellIcon extends StatelessWidget {
  const ShellIcon(
    this.glyph, {
    super.key,
    this.size,
    this.color,
    this.fill,
    this.weight,
    this.opticalSize,
    this.shadows,
    this.semanticLabel,
    this.pack,
  });

  /// What to draw.
  final ShellGlyph glyph;

  /// The glyph's size; the ambient [IconTheme]'s when null, as for [Icon].
  final double? size;

  /// The glyph's colour; the ambient [IconTheme]'s when null, as for [Icon].
  final Color? color;

  /// The variable-font axes and shadows [Icon] takes. A font without the axis
  /// ignores it, so a call site tuned for Material Symbols' weight is harmless
  /// under Font Awesome — which is the font that call site used to be denied.
  final double? fill;
  final double? weight;
  final double? opticalSize;
  final List<Shadow>? shadows;

  final String? semanticLabel;

  /// Draws in this pack instead of the theme's: for a preview of a pack the user
  /// has not picked yet, and for the account brand marks, which are the
  /// brand's drawing under every theme. Never to opt an ordinary surface out of
  /// the user's choice.
  final IconPack? pack;

  @override
  Widget build(BuildContext context) {
    final chosen =
        pack ?? ThemeScope.maybeOf(context)?.iconPack ?? IconPack.fontAwesome;
    final resolved = resolveGlyph(glyph, chosen);
    switch (resolved.glyph) {
      case FaGlyph(:final data):
        return FaIcon(
          data,
          size: size,
          color: color,
          shadows: shadows,
          semanticLabel: semanticLabel,
        );
      case FontGlyph(:final data, fill: final glyphFill):
        final scale = resolved.scale;
        final icon = Icon(
          data,
          size: size == null ? null : size! * scale,
          color: color,
          fill: fill ?? glyphFill,
          weight: weight,
          // Material Symbols draw differently at different optical sizes, and
          // the axis wants the size the glyph is actually set at. Only for a
          // pack the user picked: the default pack's Material glyphs keep
          // whatever their call site asked for, which is how they looked before.
          opticalSize:
              opticalSize ??
              (chosen.isMaterial && size != null
                  ? (size! * scale).clamp(20.0, 48.0)
                  : null),
          shadows: shadows,
          semanticLabel: semanticLabel,
        );
        if (scale == 1.0 || size == null) return icon;
        // The box the call site asked for, with the larger glyph centred over
        // it. An `OverflowBox` rather than a `Transform`: it is layout, so the
        // glyph is rasterised at its real size rather than magnified.
        return SizedBox.square(
          dimension: size,
          child: OverflowBox(
            maxWidth: size! * scale,
            maxHeight: size! * scale,
            child: icon,
          ),
        );
    }
  }
}
