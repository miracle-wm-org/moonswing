import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/bar_module_drag.dart';

/// A module that counts its own builds of state, so a test can tell a module
/// that moved from one that was rebuilt from scratch.
class _Counter extends StatefulWidget {
  const _Counter({required this.label, this.onTapDown});

  final String label;
  final VoidCallback? onTapDown;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  static int created = 0;

  @override
  void initState() {
    super.initState();
    created++;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (_) => widget.onTapDown?.call(),
    child: SizedBox(
      width: 40,
      height: 20,
      child: Text(widget.label, textDirection: TextDirection.ltr),
    ),
  );
}

void main() {
  test(
    'slots are laid out as the row lays them, empty modules taking none',
    () {
      expect(barSlotStart([40, 0, 40], 2, 8), 48);
      expect(barSlotStart([0, 40], 1, 8), 0);
      expect(
        barDropPosition(rest: [40, 40], dragged: 40, start: 70, gap: 8),
        1,
      );
      expect(
        barDropPosition(rest: [40, 40], dragged: 40, start: 100, gap: 8),
        2,
      );
    },
  );

  group('a section', () {
    late List<List<int>> reorders;
    late List<String> tapDowns;

    Future<void> pump(WidgetTester tester, {List<String>? ids}) async {
      reorders = [];
      tapDowns = [];
      final labels = ids ?? const ['a', 'b', 'c'];
      await tester.pumpWidget(
        Align(
          alignment: Alignment.topLeft,
          child: ReorderableBarSection(
            axis: Axis.horizontal,
            gap: 8,
            ids: labels,
            onReorder: reorders.add,
            children: [
              for (final label in labels)
                _Counter(label: label, onTapDown: () => tapDowns.add(label)),
            ],
          ),
        ),
      );
    }

    Future<void> drag(
      WidgetTester tester,
      Offset from,
      List<Offset> steps,
    ) async {
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      for (final step in steps) {
        await gesture.moveBy(step);
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
    }

    testWidgets('a press still opens on its way down', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(
        const Offset(10, 10),
        kind: PointerDeviceKind.mouse,
      );
      // No deadline waited out: a drag in the arena would have held it.
      expect(tapDowns, ['a']);
      await gesture.up();
    });

    testWidgets('dragging the first past the second drops it there', (
      tester,
    ) async {
      await pump(tester);
      _CounterState.created = 0;
      // From a's centre (20) to past b's centre (68).
      await drag(tester, const Offset(20, 10), const [
        Offset(25, 0),
        Offset(30, 0),
      ]);
      expect(reorders, [
        [1, 0, 2],
      ]);
      // Nothing was rebuilt from scratch: each module kept its state.
      expect(_CounterState.created, 0);
    });

    testWidgets('a wobble under the slop is not a drag', (tester) async {
      await pump(tester);
      await drag(tester, const Offset(20, 10), const [Offset(6, 0)]);
      expect(reorders, isEmpty);
    });

    testWidgets('a drag that ends where it began reorders nothing', (
      tester,
    ) async {
      await pump(tester);
      await drag(tester, const Offset(20, 10), const [
        Offset(25, 0),
        Offset(-25, 0),
      ]);
      expect(reorders, isEmpty);
    });

    testWidgets('a module\'s own drag keeps the press', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(
        const Offset(20, 10),
        kind: PointerDeviceKind.mouse,
      );
      // What the dock does from its pan's start.
      BarDragClaim.claim();
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(reorders, isEmpty);
    });

    testWidgets('the dragged module follows the pointer, inside the section', (
      tester,
    ) async {
      await pump(tester);
      final gesture = await tester.startGesture(
        const Offset(20, 10),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(tester.getTopLeft(find.text('a')).dx, 30);
      // Far past the end: held at the section's last slot.
      await gesture.moveBy(const Offset(500, 0));
      await tester.pump();
      expect(tester.getTopLeft(find.text('a')).dx, 96);
      await gesture.up();
      await tester.pump();
      expect(reorders, [
        [1, 2, 0],
      ]);
    });
  });
}
