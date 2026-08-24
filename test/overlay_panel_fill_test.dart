import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/overlay.dart';

void main() {
  test('an opaque palette is passed through unchanged', () {
    const theme = ThemeConfig(popupBackground: Color(0xFF2C2C2C));
    expect(overlayPanelFill(theme), const Color(0xFF2C2C2C));
  });

  test('a translucent palette keeps its hue and loses its alpha', () {
    // `glassy` ships popup_background at 0xB0. The panel is a workspace, not a
    // three-row menu: it may take the theme's colour but never its alpha.
    const theme = ThemeConfig(popupBackground: Color(0xB0141821));
    expect(overlayPanelFill(theme), const Color(0xFF141821));
  });

  test('a fully transparent palette still fills', () {
    const theme = ThemeConfig(popupBackground: Color(0x00141821));
    expect(overlayPanelFill(theme).a, 1.0);
  });
}
