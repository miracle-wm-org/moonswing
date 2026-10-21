import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';

/// Every [ShellIcon] drawing [glyph], whatever pack it is drawn in.
///
/// What `find.byIcon` was for when the shell drew Font Awesome directly. That
/// matches the resolved `IconData`, which depends on the theme's pack — and on
/// Font Awesome's wrapper, whose unwrapped data compares unequal to the
/// constant a test would name — where the glyph is the thing the surface chose.
Finder findGlyph(ShellGlyph glyph) => find.byWidgetPredicate(
  (widget) => widget is ShellIcon && widget.glyph == glyph,
  description: 'ShellIcon($glyph)',
);
