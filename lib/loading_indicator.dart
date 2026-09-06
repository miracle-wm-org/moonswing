import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:graceful_shell/scopes.dart';

/// Spinning arc shown while an operation is in flight.
///
/// This is the *only* loader in the shell, and that is the point. There used to
/// be six — a near-identical private copy in each of the four settings pages and
/// a `◐` glyph in `modules/weather.dart` — and they drifted, so "the shell is
/// working on it" did not look like one thing.
///
/// The animation is [SpinKitRing] rather than a hand-rolled controller over a
/// Font Awesome glyph. Two things that buys: the arc sweeps as well as rotates,
/// so a loader at 12px still reads as moving where a rigidly-spinning notch that
/// small mostly does not; and the rate is the package's rather than a number this
/// repo has to keep re-picking.
///
/// [color] is optional because the settings pages never passed one — a null takes
/// the muted popup foreground, so a loader dropped into a themed surface is
/// styled by default. The lookup is skipped when a colour *is* given, which keeps
/// this usable from a subtree with no [ThemeScope] above it.
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key, this.color, this.size = 16.0});

  /// The arc's colour. Null resolves to the theme's muted popup foreground.
  final Color? color;

  /// Width and height of the loader, in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = color ??
        ThemeScope.of(context).popupForeground.withValues(alpha: 0.6);
    // SpinKitRing centres itself inside whatever it is given and its default 7px
    // stroke is sized against a 50px default. The shell asks for 12-22, so the box
    // is pinned to `size` — the footprint the Font Awesome glyph this replaced had
    // — and the stroke is scaled to keep the package's ratio, with a floor so the
    // smallest loader does not thin out to an invisible hairline.
    return SizedBox.square(
      dimension: size,
      child: SpinKitRing(
        color: tint,
        size: size,
        lineWidth: math.max(1.5, size / 7),
      ),
    );
  }
}
