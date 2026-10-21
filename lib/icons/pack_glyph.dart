/// What a pack's table answers for one `ShellGlyph`: the font glyph to draw,
/// and which of the two ways it is drawn.
library;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// One glyph out of one pack.
sealed class PackGlyph {
  const PackGlyph();
}

/// A Font Awesome glyph, drawn by [FaIcon] exactly as the shell always drew it.
///
/// Kept apart from [FontGlyph] because the two are laid out differently, and the
/// difference is visible: `FaIcon` sets the glyph unboxed at its own advance —
/// Font Awesome's glyphs are not square, and a plain [Icon] would clip or pad
/// them — where every other pack is drawn on a square grid and wants exactly the
/// square box [Icon] gives it.
final class FaGlyph extends PackGlyph {
  const FaGlyph(this.data);

  final FaIconData data;

  @override
  bool operator ==(Object other) => other is FaGlyph && other.data == data;

  @override
  int get hashCode => data.hashCode;

  @override
  String toString() => 'FaGlyph($data)';
}

/// A glyph from a square-grid icon font, drawn by [Icon].
final class FontGlyph extends PackGlyph {
  const FontGlyph(this.data, {this.fill});

  final IconData data;

  /// The `FILL` axis this glyph wants, for a variable font that has one — how
  /// Material Symbols draws what Font Awesome draws as a separate *solid*
  /// glyph. A call site's own `fill` wins over it.
  final double? fill;

  @override
  bool operator ==(Object other) =>
      other is FontGlyph && other.data == data && other.fill == fill;

  @override
  int get hashCode => Object.hash(data, fill);

  @override
  String toString() => 'FontGlyph($data, fill: $fill)';
}
