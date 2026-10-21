import 'package:moonswing/icons/pack_glyph.dart';
import 'package:moonswing/icons/packs/font_awesome.dart';
import 'package:moonswing/icons/packs/lucide.dart';
import 'package:moonswing/icons/packs/material.dart';
import 'package:moonswing/icons/packs/remix.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/theme/icon_pack.dart';

/// [glyph] as [pack] draws it, and how much to enlarge it by.
///
/// A pack with no answer for a glyph falls back to the default pack's, and the
/// fallback is drawn at the default pack's scale — 1 — since it is that pack's
/// glyph, not this one's: a Font Awesome brand inside a Lucide bar is drawn the
/// size Font Awesome draws it.
({PackGlyph glyph, double scale}) resolveGlyph(
  ShellGlyph glyph,
  IconPack pack,
) {
  final own = packGlyph(glyph, pack);
  if (own != null) return (glyph: own, scale: pack.opticalScale);
  return (glyph: fontAwesomeGlyph(glyph), scale: 1.0);
}

/// [pack]'s own answer for [glyph], or null where it has none and the default
/// pack's is drawn instead.
PackGlyph? packGlyph(ShellGlyph glyph, IconPack pack) => switch (pack) {
  IconPack.fontAwesome => fontAwesomeGlyph(glyph),
  IconPack.materialRounded ||
  IconPack.materialOutlined ||
  IconPack.materialSharp => materialGlyph(glyph, pack),
  IconPack.lucide => lucideGlyph(glyph),
  IconPack.remix => remixGlyph(glyph),
};
