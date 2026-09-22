import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/bar_button.dart';
import 'package:moonswing/config.dart';
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

void main() {
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
