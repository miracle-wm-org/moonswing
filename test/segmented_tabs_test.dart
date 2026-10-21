import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/segmented_tabs.dart';
import 'package:moonswing/theme/overlay_effect.dart';

import 'tap_target.dart';

const _tabs = [
  SegmentedTab(label: 'Calendar', icon: ShellGlyph.calendarDays),
  SegmentedTab(label: 'Settings', icon: ShellGlyph.settings),
  SegmentedTab(label: 'System Info'),
];

Widget _host(
  int selected,
  ValueChanged<int> onSelected, {
  ThemeConfig theme = const ThemeConfig(),
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: ThemeScope(
    theme: theme,
    child: Center(
      child: SegmentedTabBar(
        tabs: _tabs,
        selected: selected,
        onSelected: onSelected,
      ),
    ),
  ),
);

Finder _segment(String label) => find
    .ancestor(of: find.text(label), matching: find.byType(RepaintBoundary))
    .first;

void main() {
  testWidgets('every segment fires its own index from every corner', (
    tester,
  ) async {
    final picked = <int>[];
    await tester.pumpWidget(_host(0, picked.add));

    for (final (i, tab) in _tabs.indexed) {
      picked.clear();
      await tapEveryCorner(tester, _segment(tab.label));
      expect(picked, [i, i, i, i], reason: tab.label);
    }
  });

  testWidgets('segments share one height and sit edge to edge', (tester) async {
    await tester.pumpWidget(_host(0, (_) {}));
    final rects = [for (final t in _tabs) tester.getRect(_segment(t.label))];
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].height, rects[0].height);
      expect(rects[i].left, rects[i - 1].right);
    }
  });

  testWidgets('the pill slides, then nothing ticks at rest', (tester) async {
    await tester.pumpWidget(_host(0, (_) {}));
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_host(2, (_) {}));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a theme with no overlay motion moves the pill at once', (
    tester,
  ) async {
    const still = ThemeConfig(overlayEffect: OverlayEffect.none);
    await tester.pumpWidget(_host(0, (_) {}, theme: still));
    await tester.pumpWidget(_host(1, (_) {}, theme: still));
    expect(tester.binding.transientCallbackCount, 0);
  });
}
