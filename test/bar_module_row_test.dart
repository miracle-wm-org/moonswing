import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/bar_module_row.dart';

/// A section the way `PanelMain` lays one out: aligned in a bar-deep box,
/// which hands it the depth as a loose constraint.
Widget _section(Axis axis, List<Widget> modules, {Key? key}) {
  final horizontal = axis == Axis.horizontal;
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: horizontal ? 800 : 32,
        height: horizontal ? 32 : 800,
        child: Align(
          alignment: horizontal ? Alignment.centerLeft : Alignment.topCenter,
          child: BarModuleRow(key: key, axis: axis, children: modules),
        ),
      ),
    ),
  );
}

Widget _box(String name, double main, {Axis axis = Axis.horizontal}) =>
    SizedBox(
      key: ValueKey(name),
      width: axis == Axis.horizontal ? main : 20,
      height: axis == Axis.horizontal ? 20 : main,
    );

void main() {
  testWidgets('modules sit a gap apart', (tester) async {
    await tester.pumpWidget(
      _section(Axis.horizontal, [_box('a', 30), _box('b', 40), _box('c', 50)]),
    );
    expect(tester.getSize(find.byType(BarModuleRow)), const Size(136, 20));
    expect(tester.getTopLeft(find.byKey(const ValueKey('b'))).dx, 38);
    expect(tester.getTopLeft(find.byKey(const ValueKey('c'))).dx, 86);
  });

  testWidgets('an empty module takes no room, gap included', (tester) async {
    // A battery on a desktop tower, between two modules that drew something.
    await tester.pumpWidget(
      _section(Axis.horizontal, [
        _box('a', 30),
        const SizedBox.shrink(),
        _box('c', 50),
      ]),
    );
    expect(tester.getSize(find.byType(BarModuleRow)).width, 30 + 8 + 50);
    expect(tester.getTopLeft(find.byKey(const ValueKey('c'))).dx, 38);
  });

  testWidgets('empty modules at either end and side by side cost nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _section(Axis.horizontal, [
        const SizedBox.shrink(),
        const SizedBox.shrink(),
        _box('b', 40),
        const SizedBox.shrink(),
        const SizedBox.shrink(),
      ]),
    );
    expect(tester.getSize(find.byType(BarModuleRow)).width, 40);
    expect(tester.getTopLeft(find.byKey(const ValueKey('b'))).dx, 0);
  });

  testWidgets('a section of nothing but empty modules is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      _section(Axis.horizontal, [
        const SizedBox.shrink(),
        const SizedBox.shrink(),
      ]),
    );
    expect(tester.getSize(find.byType(BarModuleRow)), Size.zero);
  });

  testWidgets('a module that appears brings its gap with it', (tester) async {
    final shown = ValueNotifier(false);
    addTearDown(shown.dispose);
    await tester.pumpWidget(
      _section(Axis.horizontal, [
        _box('a', 30),
        ValueListenableBuilder<bool>(
          valueListenable: shown,
          builder: (context, value, _) =>
              value ? _box('b', 40) : const SizedBox.shrink(),
        ),
        _box('c', 50),
      ]),
    );
    expect(tester.getSize(find.byType(BarModuleRow)).width, 88);

    shown.value = true;
    await tester.pump();
    expect(tester.getSize(find.byType(BarModuleRow)).width, 136);
    expect(tester.getTopLeft(find.byKey(const ValueKey('c'))).dx, 86);

    shown.value = false;
    await tester.pump();
    expect(tester.getSize(find.byType(BarModuleRow)).width, 88);
  });

  testWidgets('a side bar stacks modules and skips the empty ones too', (
    tester,
  ) async {
    await tester.pumpWidget(
      _section(Axis.vertical, [
        _box('a', 30, axis: Axis.vertical),
        const SizedBox.shrink(),
        _box('c', 50, axis: Axis.vertical),
      ]),
    );
    expect(tester.getSize(find.byType(BarModuleRow)), const Size(20, 88));
    expect(tester.getTopLeft(find.byKey(const ValueKey('c'))).dy, 38);
  });

  testWidgets('modules are centred across the bar and offered its depth', (
    tester,
  ) async {
    await tester.pumpWidget(
      _section(Axis.horizontal, [
        const SizedBox(key: ValueKey('short'), width: 10, height: 10),
        // A `BarFill`-style module that takes all the depth it is given.
        const SizedBox(key: ValueKey('tall'), width: 10, height: 1000),
      ]),
    );
    expect(tester.getSize(find.byKey(const ValueKey('tall'))).height, 32);
    expect(tester.getTopLeft(find.byKey(const ValueKey('short'))).dy, 11);
  });

  testWidgets('a tap reaches the module after an empty one', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _section(Axis.horizontal, [
        const SizedBox.shrink(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const SizedBox(key: ValueKey('b'), width: 40, height: 20),
        ),
      ]),
    );
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const ValueKey('b'))) + const Offset(1, 1),
    );
    expect(taps, 1);
  });

  testWidgets('intrinsic width skips the empty ones too', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: IntrinsicWidth(
            child: BarModuleRow(
              axis: Axis.horizontal,
              children: [_box('a', 30), const SizedBox.shrink(), _box('c', 50)],
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(BarModuleRow)).width, 88);
  });
}
