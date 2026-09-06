// `RgbaColor` (miracle's four floats) and `#AARRGGBB` (what the settings colour
// field speaks), in both directions.
//
// The two halves of the shell's colour story do not meet anywhere else:
// `package:miracle` is a plain Dart package whose colours are components from
// 0.0 to 1.0, and `SettingsColorField` takes and returns the same hex string the
// theme files are written in. Deliberately Flutter-free so the rounding is a
// plain unit test — an off-by-one in the byte conversion is a colour that
// changes every time the page is opened and closed.
library;

import 'package:miracle/miracle.dart';

/// One component, 0.0–1.0, as a two-digit hex byte.
String _byte(double component) {
  final value = (component.isFinite ? component : 0.0).clamp(0.0, 1.0);
  return (value * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase();
}

/// [color] as `#AARRGGBB`, or as `#RRGGBB` when [includeAlpha] is false.
///
/// Opaque colours are written without their alpha: miracle's compositor
/// background has no alpha at all (the C struct is three floats), and a `#FF`
/// in front of it would invite the user to edit a component that is discarded.
String rgbaToHex(RgbaColor color, {bool includeAlpha = true}) {
  final rgb = '${_byte(color.red)}${_byte(color.green)}${_byte(color.blue)}';
  return includeAlpha ? '#${_byte(color.alpha)}$rgb' : '#$rgb';
}

/// `#RRGGBB` or `#AARRGGBB` (the `#` optional) as a colour, or null.
///
/// Null rather than a thrown or a substituted black: the caller is a field the
/// user is part-way through typing into, and every hex passes through several
/// unparseable states on its way to being one. See `ColorFieldState`.
RgbaColor? rgbaFromHex(String hex) {
  final digits = hex.startsWith('#') ? hex.substring(1) : hex;
  if (digits.length != 6 && digits.length != 8) return null;
  final value = int.tryParse(digits.length == 6 ? 'FF$digits' : digits,
      radix: 16);
  if (value == null) return null;
  return RgbaColor(
    alpha: ((value >> 24) & 0xFF) / 255,
    red: ((value >> 16) & 0xFF) / 255,
    green: ((value >> 8) & 0xFF) / 255,
    blue: (value & 0xFF) / 255,
  );
}
