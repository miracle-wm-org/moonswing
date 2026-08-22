import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/hover_region.dart';

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
}
