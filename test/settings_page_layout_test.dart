import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';

const _theme = ThemeConfig();

Future<void> _pump(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ThemeScope(theme: _theme, child: child),
    ),
  );
}

const _contentKey = Key('content');

void main() {
  testWidgets('a wide pane centres the page in a column of the max width', (
    tester,
  ) async {
    await _pump(
      tester,
      1400,
      const CustomScrollView(
        slivers: [
          SliverSettingsPage(
            sliver: SliverToBoxAdapter(
              child: SizedBox(key: _contentKey, height: 40),
            ),
          ),
        ],
      ),
    );
    final content = tester.getRect(find.byKey(_contentKey));
    expect(content.width, kSettingsContentMaxWidth);
    expect(content.center.dx, 700);
    expect(content.top, kSettingsPagePadding.top);
  });

  testWidgets('a narrow pane keeps the gutter and gives up the max width', (
    tester,
  ) async {
    await _pump(
      tester,
      500,
      const CustomScrollView(
        slivers: [
          SliverSettingsPage(
            sliver: SliverToBoxAdapter(
              child: SizedBox(key: _contentKey, height: 40),
            ),
          ),
        ],
      ),
    );
    final content = tester.getRect(find.byKey(_contentKey));
    expect(content.left, kSettingsPagePadding.left);
    expect(content.right, 500 - kSettingsPagePadding.right);
  });

  testWidgets('a tap lands on what is drawn inside the centred column', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      1400,
      CustomScrollView(
        slivers: [
          SliverSettingsPage(
            sliver: SliverToBoxAdapter(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox(key: _contentKey, height: 40),
              ),
            ),
          ),
        ],
      ),
    );
    // A corner, not the centre: an offset hit test passes at the centre of a
    // box that is only shifted a little.
    await tester.tapAt(
      tester.getTopLeft(find.byKey(_contentKey)) + const Offset(2, 2),
    );
    expect(taps, 1);
    // And the gutter beside it is not the content.
    await tester.tapAt(const Offset(10, 20));
    expect(taps, 1);
  });

  testWidgets('the header starts on the same edge as the page under it', (
    tester,
  ) async {
    await _pump(
      tester,
      1400,
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsPageHeader(title: 'Title'),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverSettingsPage(
                  sliver: SliverToBoxAdapter(
                    child: SizedBox(key: _contentKey, height: 40),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    expect(
      tester.getTopLeft(find.text('Title')).dx,
      tester.getTopLeft(find.byKey(_contentKey)).dx,
    );
  });

  test('the centring inset never goes negative', () {
    expect(settingsCentringInset(100), 0);
    expect(
      settingsCentringInset(
        kSettingsContentMaxWidth + kSettingsPagePadding.horizontal + 200,
      ),
      100,
    );
  });
}
