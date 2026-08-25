import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/hover_region.dart';

import 'tap_target.dart';

void main() {
  testWidgets('builder sees the pointer enter and leave', (tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);

    var enters = 0;
    var exits = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: HoverRegion(
            onEnter: () => enters++,
            onExit: () => exits++,
            builder: (context, hovered) => SizedBox(
              width: 40,
              height: 40,
              child: Text(hovered ? 'on' : 'off'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('off'), findsOneWidget);

    await gesture.moveTo(tester.getCenter(find.byType(HoverRegion)));
    await tester.pump();
    expect(find.text('on'), findsOneWidget);
    expect(enters, 1);

    await gesture.moveTo(const Offset(1000, 1000));
    await tester.pump();
    expect(find.text('off'), findsOneWidget);
    expect(exits, 1);
  });

  testWidgets('onTap fires from every corner of a box that hit-tests nothing',
      (tester) async {
    // A bare `SizedBox` is a `RenderConstrainedBox`: `hitTestSelf` is false, so
    // without the opaque detector this widget accepts a hit nowhere at all.
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: HoverRegion(
            onTap: () => taps++,
            builder: (context, hovered) =>
                const SizedBox(width: 40, height: 40),
          ),
        ),
      ),
    );

    await tapEveryCorner(tester, find.byType(HoverRegion));
    expect(taps, 4);
  });

  testWidgets('a builder-only region emits no GestureDetector', (tester) async {
    // An unconditional opaque box would swallow hits meant for a `Stack`
    // sibling underneath — `panels.dart` wraps a control that owns its own
    // recognizer and uses `hovered` for nothing but a reveal.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: HoverRegion(
            builder: (context, hovered) =>
                const SizedBox(width: 40, height: 40),
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(HoverRegion),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
  });

  testWidgets('onTapDown fires on the press, before the release',
      (tester) async {
    // The dismissal contract, pinned at the primitive: every popup toggle in
    // the shell opens inside the pointer-down that arms the reopen guard.
    var downs = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: HoverRegion(
            onTapDown: (_) => downs++,
            builder: (context, hovered) =>
                const SizedBox(width: 40, height: 40),
          ),
        ),
      ),
    );

    final corner = tester.getRect(find.byType(HoverRegion)).topLeft +
        const Offset(2, 2);
    final gesture = await tester.startGesture(corner);
    await tester.pump();
    expect(downs, 1);
    await gesture.up();
    await tester.pump();
    expect(downs, 1);
  });

  testWidgets('a secondary press does not disturb the primary one',
      (tester) async {
    var primary = 0;
    var secondary = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: HoverRegion(
            onTapDown: (_) => primary++,
            onSecondaryTapDown: (_) => secondary++,
            builder: (context, hovered) =>
                const SizedBox(width: 40, height: 40),
          ),
        ),
      ),
    );

    final corner = tester.getRect(find.byType(HoverRegion)).topLeft +
        const Offset(2, 2);
    final gesture = await tester.startGesture(corner,
        buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await gesture.up();
    await tester.pump();
    expect(secondary, 1);
    expect(primary, 0);
  });

  testWidgets('enabled false keeps the box absorbing but drops the callbacks',
      (tester) async {
    var taps = 0;
    var behind = 0;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 40,
            height: 40,
            // The absorbing is measured against a `Stack` sibling underneath,
            // not an ancestor: a hit-test result is a chain from the root down,
            // so an ancestor detector is on the path whatever its descendants
            // do. `HitTestBehavior.opaque` decides only whether
            // `RenderStack.hitTestChildren` keeps walking past this child.
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => behind++,
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned.fill(
                  child: HoverRegion(
                    enabled: false,
                    onTap: () => taps++,
                    builder: (context, hovered) => const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final centre = tester.getCenter(find.byType(HoverRegion));
    await mouse.moveTo(centre);
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.basic,
    );

    await tapEveryCorner(tester, find.byType(HoverRegion));
    expect(taps, 0);
    // Still opaque: a disabled button absorbs rather than letting the click
    // fall through to whatever is behind it.
    expect(behind, 0);
  });
}
