import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/desktop_cursor.dart';
import 'package:moonswing/hover_region.dart';

/// The panels never move the pointer off the arrow, whatever is under it.
MouseCursor? _cursor() =>
    RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: child),
);

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

void main() {
  testWidgets('a region asking for a cursor gets it outside the scope', (
    tester,
  ) async {
    // The control: without this the tests below could pass by never hovering.
    final mouse = await _mouse(tester);
    await tester.pumpWidget(
      _host(
        const MouseRegion(
          cursor: SystemMouseCursors.click,
          child: SizedBox(width: 40, height: 40),
        ),
      ),
    );
    await mouse.moveTo(tester.getCenter(find.byType(SizedBox)));
    await tester.pump();
    expect(_cursor(), SystemMouseCursors.click);
  });

  for (final asked in <MouseCursor>[
    SystemMouseCursors.click,
    SystemMouseCursors.text,
    SystemMouseCursors.grab,
    SystemMouseCursors.resizeLeftRight,
  ]) {
    testWidgets('inside the scope, $asked is overruled by the arrow', (
      tester,
    ) async {
      final mouse = await _mouse(tester);
      await tester.pumpWidget(
        _host(
          DesktopCursor(
            // Nested, so the inner region is the deepest annotation in the path —
            // the one that would win without the scope.
            child: MouseRegion(
              cursor: SystemMouseCursors.forbidden,
              child: MouseRegion(
                cursor: asked,
                child: const SizedBox(width: 40, height: 40),
              ),
            ),
          ),
        ),
      );
      await mouse.moveTo(tester.getCenter(find.byType(SizedBox)));
      await tester.pump();
      expect(_cursor(), SystemMouseCursors.basic);
    });
  }

  testWidgets('a link in rich text keeps the arrow', (tester) async {
    // A `TextSpan` with a recognizer asks for the hand on its own, which no
    // call site's `cursor:` would have reached.
    final mouse = await _mouse(tester);
    final recognizer = TapGestureRecognizer()..onTap = () {};
    addTearDown(recognizer.dispose);
    await tester.pumpWidget(
      _host(
        DesktopCursor(
          child: Text.rich(TextSpan(text: 'a link', recognizer: recognizer)),
        ),
      ),
    );
    await mouse.moveTo(tester.getCenter(find.byType(Text)));
    await tester.pump();
    expect(_cursor(), SystemMouseCursors.basic);
  });

  testWidgets('hover and taps beneath the scope still work', (tester) async {
    // Only the cursor is claimed: every region below still hears its own enter
    // and exit, and the click still lands on what it was aimed at.
    final mouse = await _mouse(tester);
    var taps = 0;
    var hovered = false;
    await tester.pumpWidget(
      _host(
        DesktopCursor(
          child: HoverRegion(
            onTap: () => taps++,
            builder: (context, h) {
              hovered = h;
              return const SizedBox(width: 40, height: 40);
            },
          ),
        ),
      ),
    );
    final centre = tester.getCenter(find.byType(SizedBox));
    await mouse.moveTo(centre);
    await tester.pump();
    expect(hovered, isTrue);
    await tester.tapAt(centre);
    await tester.pump();
    expect(taps, 1);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(hovered, isFalse);
  });

  testWidgets('the scope ends at its own box', (tester) async {
    // A sibling outside the scope is not a panel, and keeps what it asked for.
    final mouse = await _mouse(tester);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DesktopCursor(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: SizedBox(key: Key('in'), width: 40, height: 40),
              ),
            ),
            const MouseRegion(
              cursor: SystemMouseCursors.text,
              child: SizedBox(key: Key('out'), width: 40, height: 40),
            ),
          ],
        ),
      ),
    );
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('in'))));
    await tester.pump();
    expect(_cursor(), SystemMouseCursors.basic);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('out'))));
    await tester.pump();
    expect(_cursor(), SystemMouseCursors.text);
  });

  testWidgets('a HoverRegion asks for no hand anywhere', (tester) async {
    // Outside the panels too: the hand was the default, and it is what made a
    // button read as a web page's.
    final mouse = await _mouse(tester);
    await tester.pumpWidget(
      _host(
        HoverRegion(
          onTap: () {},
          builder: (context, hovered) => const SizedBox(width: 40, height: 40),
        ),
      ),
    );
    await mouse.moveTo(tester.getCenter(find.byType(SizedBox)));
    await tester.pump();
    expect(_cursor(), SystemMouseCursors.basic);
  });
}
