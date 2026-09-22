import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/popup.dart';

/// A bar popup is anchored to the *panel's* inner edge, centred on the module
/// that opened it — not to the module's own rect, which sits some distance
/// inside the bar by however much padding that module happens to carry.
/// [barAnchorRect] is the whole of that, and there is no way to observe it
/// without a compositor otherwise.
void main() {
  // A 1600x32 top or bottom bar, and a module sitting 400px along it.
  const panel = Size(1600, 32);
  // Vertically centred with 2px of BarButton padding either side, which is what
  // made every popup overlap the bar by two pixels before this.
  const module = Rect.fromLTWH(400, 2, 60, 28);

  group('a horizontal bar', () {
    test('spans the panel and keeps the module\'s own horizontal extent', () {
      for (final anchor in ['top', 'bottom']) {
        expect(barAnchorRect(module, panel, anchor),
            const Rect.fromLTRB(400, 0, 460, 32),
            reason: anchor);
      }
    });

    test('the anchored edge does not move with the module\'s height', () {
      // The bug this fixes: a taller or shorter module used to move its own
      // popup, because the anchor was its own bottom edge.
      const tall = Rect.fromLTWH(400, 0, 60, 32);
      const short = Rect.fromLTWH(400, 8, 60, 16);
      expect(barAnchorRect(tall, panel, 'top'),
          barAnchorRect(short, panel, 'top'));
      // And the centring axis is untouched, which is what keeps the popup on
      // its icon.
      expect(barAnchorRect(short, panel, 'top').center.dx, module.center.dx);
    });
  });

  group('a vertical bar', () {
    // A 48x1200 left or right bar, module 300px down it.
    const sidePanel = Size(48, 1200);
    const sideModule = Rect.fromLTWH(2, 300, 44, 26);

    test('spans the panel and keeps the module\'s own vertical extent', () {
      for (final anchor in ['left', 'right']) {
        expect(barAnchorRect(sideModule, sidePanel, anchor),
            const Rect.fromLTRB(0, 300, 48, 326),
            reason: anchor);
      }
    });

    test('the anchored edge does not move with the module\'s width', () {
      const wide = Rect.fromLTWH(0, 300, 48, 26);
      expect(barAnchorRect(wide, sidePanel, 'left'),
          barAnchorRect(sideModule, sidePanel, 'left'));
    });
  });

  test('an unknown anchor is treated as horizontal, like popupAnchorsForBar',
      () {
    expect(barAnchorRect(module, panel, 'nonsense'),
        barAnchorRect(module, panel, 'top'));
  });

  test('a panel that has not been laid out falls back to the widget rect', () {
    // A zero-extent anchor rect is an xdg_positioner protocol error, not merely
    // a bad placement, so this can never be allowed to produce one.
    for (final degenerate in [Size.zero, const Size(1600, 0), const Size(0, 32)]) {
      expect(barAnchorRect(module, degenerate, 'top'), module,
          reason: '$degenerate');
    }
  });
}
