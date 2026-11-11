// The overview's header: the settings search on the left, the tab strip in the
// middle, the close button on the right — and a strip that stays put as the
// search comes and goes with the Settings tab.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/overlay/overlay.dart';

const _tabsKey = Key('tabs');
const _leadingKey = Key('leading');
const _closeKey = Key('close');

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  double tabsWidth = 400,
  bool searching = true,
}) async {
  // Wide enough for the widest header asked for, at one pixel a point.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 200);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: OverviewHeaderLayout(
            leading: searching
                ? LayoutBuilder(
                    key: _leadingKey,
                    builder: (context, constraints) => SizedBox(
                      width: constraints.maxWidth.clamp(0.0, 300.0),
                      height: 34,
                    ),
                  )
                : const SizedBox.shrink(),
            tabs: FittedBox(
              key: _tabsKey,
              fit: BoxFit.scaleDown,
              child: SizedBox(width: tabsWidth, height: 40),
            ),
            trailing: const SizedBox(key: _closeKey, width: 32, height: 32),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a roomy header centres the strip on the panel', (tester) async {
    await _pump(tester, width: 1200);

    final tabs = tester.getRect(find.byKey(_tabsKey));
    expect(tabs.center.dx, 600);
    // The search takes what it wants of the room left of the strip.
    expect(tester.getRect(find.byKey(_leadingKey)).left, 0);
    expect(tester.getSize(find.byKey(_leadingKey)).width, 300);
    expect(tester.getRect(find.byKey(_closeKey)).right, 1200);
    // As tall as its tallest piece, each centred on it.
    expect(tester.getSize(find.byType(OverviewHeaderLayout)).height, 40);
    expect(tester.getRect(find.byKey(_closeKey)).top, 4);
  });

  testWidgets('a narrow header slides the strip over for the search', (
    tester,
  ) async {
    await _pump(tester, width: 700);

    final tabs = tester.getRect(find.byKey(_tabsKey));
    expect(tabs.left, kOverviewHeaderLeadingMinWidth + kOverviewHeaderGap);
    expect(
      tester.getSize(find.byKey(_leadingKey)).width,
      kOverviewHeaderLeadingMinWidth,
    );
    expect(tabs.right, lessThanOrEqualTo(700 - 32 - kOverviewHeaderGap));
  });

  testWidgets('a strip wider than the room scales down rather than overflow', (
    tester,
  ) async {
    await _pump(tester, width: 700, tabsWidth: 900);

    expect(tester.takeException(), isNull);
    final tabs = tester.getRect(find.byKey(_tabsKey));
    expect(tabs.left, kOverviewHeaderLeadingMinWidth + kOverviewHeaderGap);
    expect(tabs.right, 700 - 32 - kOverviewHeaderGap);
  });

  testWidgets('the strip does not move when the search goes', (tester) async {
    for (final width in [700.0, 900.0, 1200.0]) {
      await _pump(tester, width: width);
      final withSearch = tester.getRect(find.byKey(_tabsKey));
      await _pump(tester, width: width, searching: false);
      expect(
        tester.getRect(find.byKey(_tabsKey)),
        withSearch,
        reason: 'at $width',
      );
    }
  });
}
