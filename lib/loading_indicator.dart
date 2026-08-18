import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:graceful_shell/scopes.dart';

/// Spinning arc shown while an operation is in flight.
///
/// This is the *only* loader in the shell, and that is the point. There used to
/// be six: this one, plus a private near-identical copy in each of
/// `overlay/settings/{network,audio,bluetooth,display}.dart` and a third
/// variant spinning a `◐` glyph in `modules/weather.dart`. They drifted — the
/// settings four resolved their own colour from `ThemeScope` while this one
/// demanded it from the call site, and weather span at a different rate — so
/// "the shell is working on it" did not look like one thing.
///
/// The animation itself is [SpinKitRing] rather than a hand-rolled
/// `AnimationController` + `Transform.rotate` over a Font Awesome glyph.
/// Two things that buys, beyond deleting five copies of the same ticker:
/// the arc sweeps as well as rotates, so a loader at 12px still reads as
/// moving where a rigidly-spinning notch that small mostly does not; and the
/// rate is the package's, not a number this repo has to keep re-picking (the
/// six copies had settled on two).
///
/// [color] is optional because the settings pages never passed one — a null
/// takes the muted popup foreground those four used, so a loader dropped into
/// a themed surface is styled by default. The lookup is skipped entirely when
/// a colour *is* given, which is what keeps this usable from a subtree with no
/// [ThemeScope] above it.
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
    // SpinKitRing centres itself inside whatever it is given and its default
    // 7px stroke is sized against a 50px default. The shell asks for 12-22, so
    // the box is pinned to `size` — the footprint the Font Awesome glyph this
    // replaced had, which is what several call sites lay out against — and the
    // stroke is scaled to keep the package's ratio, with a floor so the
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
