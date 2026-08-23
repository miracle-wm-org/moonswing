import 'package:flutter/widgets.dart';

import 'package:graceful_shell/scopes.dart';

/// The text environment a shell window needs at its root.
///
/// The shell boots without a `WidgetsApp`, so nothing supplies a
/// [Directionality] — thirteen windows and popups used to open with the same
/// two-widget preamble. This also seeds a [DefaultTextStyle] carrying the
/// theme's font family, so a `TextStyle` that names no `fontFamily` inherits
/// the theme's instead of the engine default; whole settings pages used to
/// drift off-theme one forgotten `fontFamily:` at a time.
///
/// Sits *inside* `ThemeProvider` (it reads [ThemeScope]), which is why
/// `_windowChrome` in `main.dart` is where it goes.
class ShellTextRoot extends StatelessWidget {
  const ShellTextRoot({super.key, this.style, required this.child});

  /// Extra defaults merged over the font family — a popup passes its size
  /// and colour here instead of hand-rolling the preamble.
  final TextStyle? style;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    var base = TextStyle(fontFamily: theme.fontFamily);
    if (style != null) base = base.merge(style);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle.merge(style: base, child: child),
    );
  }
}
