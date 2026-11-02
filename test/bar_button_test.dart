import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/bar_button.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/modules/launcher.dart';
import 'package:moonswing/scopes.dart';

const _hoverColor = Color(0xFF123456);

Widget _host({bool active = false, GestureTapDownCallback? onTapDown}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ThemeScope(
      theme: const ThemeConfig(surfaceHover: _hoverColor),
      child: Center(
        child: BarButton(
          active: active,
          onTapDown: onTapDown,
          child: const SizedBox(width: 20, height: 20),
        ),
      ),
    ),
  );
}

Color? _fillOf(WidgetTester tester) {
  final container = tester.widget<Container>(find.descendant(
    of: find.byType(BarButton),
    matching: find.byType(Container),
  ));
  return (container.decoration as BoxDecoration?)?.color;
}

/// A bar the way `PanelMain` lays one out: the modules a `Row` (or `Column`)
/// centred in a `Stack` the bar's depth deep, which hands each one that depth as
/// a *loose* constraint.
Widget _bar(String anchor, List<Widget> modules) {
  final vertical = anchor == 'left' || anchor == 'right';
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ThemeScope(
      theme: const ThemeConfig(),
      child: Align(
        alignment: Alignment.topLeft,
        child: BarScope(
          anchor: anchor,
          thickness: 32,
          child: SizedBox(
            width: vertical ? 32 : 800,
            height: vertical ? 800 : 32,
            child: Stack(
              children: [
                Align(
                  alignment: vertical
                      ? Alignment.topCenter
                      : Alignment.centerLeft,
                  child: vertical
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: modules,
                        )
                      : Row(mainAxisSize: MainAxisSize.min, children: modules),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('every module in a bar is the bar\'s depth, whatever it holds', (
    tester,
  ) async {
    await tester.pumpWidget(
      _bar('top', [
        // A glyph-sized button — the screenshot camera's shape — beside one
        // holding body text, and a launcher with its own fixed icon box.
        BarButton(
          key: const ValueKey('glyph'),
          child: const SizedBox(
            key: ValueKey('glyph content'),
            width: 11,
            height: 11,
          ),
        ),
        BarButton(
          key: const ValueKey('text'),
          child: const SizedBox(width: 60, height: 19),
        ),
        const LauncherButton(key: ValueKey('launcher')),
      ]),
    );

    for (final key in ['glyph', 'text', 'launcher']) {
      expect(tester.getSize(find.byKey(ValueKey(key))).height, 32, reason: key);
    }
    // Along the bar each keeps its own length: the content plus padding.
    expect(tester.getSize(find.byKey(const ValueKey('glyph'))).width, 11 + 12);
    expect(tester.getSize(find.byKey(const ValueKey('text'))).width, 60 + 12);
    expect(
      tester.getSize(find.byKey(const ValueKey('launcher'))).width,
      18 + 8,
    );
    // And the content is centred in the depth, not pinned to the top.
    expect(
      tester.getCenter(find.byKey(const ValueKey('glyph content'))).dy,
      16,
    );
  });

  testWidgets('a side bar fills its width and keeps each module\'s height', (
    tester,
  ) async {
    await tester.pumpWidget(
      _bar('left', [
        BarButton(
          key: const ValueKey('glyph'),
          child: const SizedBox(width: 11, height: 11),
        ),
      ]),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('glyph'))),
      const Size(32, 11 + 4),
    );
  });

  testWidgets('off a bar a button is sized by its content', (tester) async {
    await tester.pumpWidget(_host());
    expect(tester.getSize(find.byType(BarButton)), const Size(20 + 12, 20 + 4));
  });

  testWidgets('hover fill comes from theme.surfaceHover, not a constant',
      (tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);

    await tester.pumpWidget(_host());
    expect(_fillOf(tester), isNull);

    await gesture.moveTo(tester.getCenter(find.byType(BarButton)));
    await tester.pump();
    final fill = _fillOf(tester)!;
    // The theme's hue at a wash alpha — the one thing the old hand-rolled
    // 0x28FFFFFF constant could never do.
    expect((fill.r * 255).round(), (_hoverColor.r * 255).round());
    expect(fill.a, closeTo(0.16, 0.01));
  });

  testWidgets('active keeps the fill on without the pointer', (tester) async {
    await tester.pumpWidget(_host(active: true));
    expect(_fillOf(tester), isNotNull);
  });

  testWidgets('taps reach the handler', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(onTapDown: (_) => taps++));
    await tester.tap(find.byType(BarButton));
    expect(taps, 1);
  });
}
