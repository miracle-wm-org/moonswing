// How big to set a fortune, given the box the grid left for it.
//
// This card is the one place in the shell where the *content* decides the type
// size: a fortune is anything from four words to a twelve-line anecdote, and the
// same card has to hold both. Picking by character count is wrong for the reason
// `TrackMarquee` states — the same 90 characters fit at 14px under one theme's
// font and overflow at 13 under another's — so this measures, with the very
// [TextStyle] the card is about to render in.
//
// Flutter-free apart from `dart:ui`'s text layout, which makes it a plain unit
// test: `TextPainter` needs a binding but no widget tree and no canvas.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The sizes tried, largest first.
///
/// A ladder rather than a continuous solve: a binary search over fractional point
/// sizes lands on values like 13.7, and a card resized by a pixel would re-set its
/// whole fortune imperceptibly differently. Ten rungs from "a short fortune on a
/// big card" down to the floor below which nobody reads it from across a desk.
const List<double> kFortuneTextSizes = [
  22, 20, 18, 16, 15, 14, 13, 12, 11, 10,
];

/// The line spacing every rung is measured and rendered at. Loose, because the
/// text is set over a moving picture and tight leading on top of drifting smoke
/// is genuinely harder to read than the same text on a flat surface.
const double kFortuneLineHeight = 1.35;

/// The ceiling on the chosen size.
///
/// The ladder is multiplied by the card's scale (see the widget's `_CardScale`),
/// and a four-word fortune on a 6x4 card would otherwise come out as a poster.
/// A fortune is a quiet thing on a wallpaper, not a headline.
const double kFortuneMaxFontSize = 30;

/// What to set a fortune in, and how many lines of it there is room for.
@immutable
class FortuneTextFit {
  const FortuneTextFit({required this.fontSize, required this.maxLines});

  final double fontSize;

  /// The line cap to render with. **Always a number, never null**, and that is
  /// load-bearing rather than tidy.
  ///
  /// The card sets `overflow: TextOverflow.ellipsis`, and a [Text] carrying an
  /// ellipsis with no `maxLines` does not wrap and ellipsise the last line the
  /// box holds — it collapses to **one line**. (The ellipsis reaches Skia as a
  /// paragraph style with no line limit, and that combination truncates at the
  /// first overflow.) So the obvious shape for this field — null when the whole
  /// fortune fits — renders a four-line fortune as its first eight words
  /// followed by a full stop's worth of dots, on every card, whatever the
  /// measurement said.
  ///
  /// When the fortune fits this is the number of lines it actually takes, so
  /// the cap never bites; when nothing fits it is what the box holds, and the
  /// card ellipsises there.
  final int maxLines;

  @override
  bool operator ==(Object other) =>
      other is FortuneTextFit &&
      other.fontSize == fontSize &&
      other.maxLines == maxLines;

  @override
  int get hashCode => Object.hash(fontSize, maxLines);

  @override
  String toString() => 'FortuneTextFit($fontSize, maxLines: $maxLines)';
}

/// The largest rung of [sizes] that lays [text] out inside [box].
///
/// [style]'s own `fontSize` and `height` are replaced; everything else about it
/// — family, weight, letter spacing — is what the measurement is made with, and
/// must be what the caller then renders with, or this answers for a different
/// piece of text than the one on screen.
///
/// [textScaler] is the same rule one level up: the theme's `font_size` reaches
/// the rendered [Text] through the ambient scaler rather than through [style],
/// so a fit measured without it picks a rung that no longer fits the box. The
/// size it returns is the *unscaled* one to hand to a `TextStyle`, because the
/// scaler is applied again at paint.
FortuneTextFit fitFortuneText({
  required String text,
  required TextStyle style,
  required Size box,
  double scale = 1.0,
  TextScaler textScaler = TextScaler.noScaling,
  List<double> sizes = kFortuneTextSizes,
  TextDirection textDirection = TextDirection.ltr,
}) {
  final smallest = _sizeAt(sizes.last, scale);
  if (text.isEmpty || box.width <= 0 || box.height <= 0) {
    return FortuneTextFit(fontSize: smallest, maxLines: 1);
  }

  for (final rung in sizes) {
    final size = _sizeAt(rung, scale);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(fontSize: size, height: kFortuneLineHeight),
      ),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: box.width);
    final fits = painter.height <= box.height;
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    if (fits) {
      return FortuneTextFit(fontSize: size, maxLines: math.max(1, lines));
    }
  }

  // Nothing fits: set it at the floor and ellipsise at whatever the box holds.
  // Truncating beats shrinking further — a fortune set at 7px is not a fortune
  // that was shown to anybody.
  final lines =
      (box.height / (textScaler.scale(smallest) * kFortuneLineHeight)).floor();
  return FortuneTextFit(fontSize: smallest, maxLines: math.max(1, lines));
}

double _sizeAt(double rung, double scale) =>
    math.min(rung * scale, kFortuneMaxFontSize);
