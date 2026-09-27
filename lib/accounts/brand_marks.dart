// The services an account can be linked to, drawn in their own colours.
//
// Everything else in the shell is painted in the theme's palette, and these
// deliberately are not: a sign-in row is where the user checks *whose* page the
// browser is about to open, and a provider's mark in its own colours is how
// every other sign-in they have ever seen says so. Each sits on a tile of its
// own so it reads on any theme, light or dark, without the theme choosing it.
//
// Arithmetic rather than image assets, for the reason `pubspec.yaml` has no
// `assets:` section: nothing in the shell resolves paths relative to the
// bundle. Google's G is four arcs and a bar; GitHub's mark is Font
// Awesome's.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/hover_region.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// A service Settings › Accounts can link.
enum AccountBrand {
  google('Google'),
  github('GitHub');

  const AccountBrand(this.label);

  /// The service's own name, spelled its own way.
  final String label;
}

/// Google's brand colours.
abstract final class GoogleColors {
  static const Color blue = Color(0xFF4285F4);
  static const Color red = Color(0xFFEA4335);
  static const Color yellow = Color(0xFFFBBC05);
  static const Color green = Color(0xFF34A853);

  /// The hairline round the white tile, so it holds its edge on a light theme.
  static const Color outline = Color(0xFFDADCE0);

  /// The sign-in button's label and border, from Google's own button.
  static const Color buttonText = Color(0xFF1F1F1F);
  static const Color buttonBorder = Color(0xFF747775);
  static const Color buttonHover = Color(0xFFF2F2F2);
}

/// GitHub's brand colours.
abstract final class GithubColors {
  /// The dark of GitHub's own header, behind the white mark.
  static const Color canvas = Color(0xFF24292F);
  static const Color mark = Color(0xFFFFFFFF);

  /// The button's hover, a step lighter than [canvas].
  static const Color canvasHover = Color(0xFF32383F);

  /// A hairline round the dark tile, so it holds its edge on a dark theme.
  static const Color outline = Color(0x2EFFFFFF);
}

/// [brand]'s mark on its own tile, [size] pixels square.
class BrandMark extends StatelessWidget {
  const BrandMark(this.brand, {super.key, this.size = 36});

  final AccountBrand brand;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.26);
    return switch (brand) {
      AccountBrand.google => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: radius,
          border: Border.all(color: GoogleColors.outline),
        ),
        alignment: Alignment.center,
        child: GoogleG(size: size * 0.58),
      ),
      AccountBrand.github => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: GithubColors.canvas,
          borderRadius: radius,
          border: Border.all(color: GithubColors.outline),
        ),
        alignment: Alignment.center,
        child: FaIcon(
          FontAwesomeIcons.github,
          size: size * 0.62,
          color: GithubColors.mark,
        ),
      ),
    };
  }
}

/// "Sign in with …" in the service's own livery: Google's white button with
/// its four-colour G, GitHub's dark one with the white mark.
///
/// Not a themed [SettingsActionButton]: this is the one button in the shell
/// whose job is to say whose page opens next, and a sign-in button in the
/// theme's accent says only "a button". Sized and padded as a compact settings
/// action, so it sits in a settings row like one.
class BrandSignInButton extends StatelessWidget {
  const BrandSignInButton(
    this.brand, {
    super.key,
    required this.onTap,
    this.loading = false,
  });

  final AccountBrand brand;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final google = brand == AccountBrand.google;
    final foreground = google ? GoogleColors.buttonText : GithubColors.mark;
    return HoverRegion(
      enabled: !loading,
      onTap: onTap,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: google
              ? (hovered ? GoogleColors.buttonHover : const Color(0xFFFFFFFF))
              : (hovered ? GithubColors.canvasHover : GithubColors.canvas),
          borderRadius: BorderRadius.circular(ShellRadii.control),
          border: Border.all(
            color: google ? GoogleColors.buttonBorder : GithubColors.outline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              LoadingIndicator(size: 12, color: foreground)
            else if (google)
              const GoogleG(size: 13)
            else
              const FaIcon(
                FontAwesomeIcons.github,
                size: 14,
                color: GithubColors.mark,
              ),
            const SizedBox(width: 8),
            Text(
              'Sign in with ${brand.label}',
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                fontFamily: theme.fontFamily,
                fontWeight: FontWeight.w500,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Google's four-colour G, with no tile — for a button or a row that already
/// has a light surface behind it.
class GoogleG extends StatelessWidget {
  const GoogleG({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: _GooglePainter()),
  );
}

/// Four arcs round the centre and the blue bar into it.
///
/// Angles run clockwise from three o'clock, as [Canvas.drawArc]'s do, and the
/// gap between the red arc's end and the blue arc's start is the G's mouth.
class _GooglePainter extends CustomPainter {
  const _GooglePainter();

  static const double _deg = math.pi / 180;

  /// Each colour's arc: where it starts and how far it sweeps, in degrees.
  static const List<(Color, double, double)> _arcs = [
    (GoogleColors.blue, 0, 45),
    (GoogleColors.green, 45, 90),
    (GoogleColors.yellow, 135, 80),
    (GoogleColors.red, 215, 100),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final stroke = side * 0.22;
    final center = size.center(Offset.zero);
    final radius = side / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..isAntiAlias = true;
    for (final (color, start, sweep) in _arcs) {
      // A hair of overlap, so antialiasing leaves no seam between colours.
      canvas.drawArc(
        rect,
        start * _deg,
        (sweep + 1) * _deg,
        false,
        paint..color = color,
      );
    }
    // The bar: from just left of centre out to the ring's outer edge.
    canvas.drawRect(
      Rect.fromLTRB(
        center.dx - stroke * 0.05,
        center.dy - stroke / 2,
        center.dx + side / 2,
        center.dy + stroke / 2,
      ),
      Paint()..color = GoogleColors.blue,
    );
  }

  /// A decoration: a `painter:` otherwise counts every point as a hit.
  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_GooglePainter oldDelegate) => false;
}
