import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/modules/dock.dart';

/// Stands in for a dock button. The real one carries the pan recognizer that
/// drives the reorder, so what these tests assert about [_ProbeState] — that it
/// survives a drag starting, and survives the list being reordered under it —
/// is exactly what the gesture needs to survive.
///
/// The dock itself cannot be pumped: resolving a pinned app goes through GIO.
class _Probe extends StatefulWidget {
  const _Probe({required this.label});

  final String label;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  static int _next = 0;

  /// Unique per [State] instance, so a changed id means the element was torn
  /// down and rebuilt rather than moved.
  late final int id = _next++;
  int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    return const SizedBox(width: 20, height: 20);
  }
}

/// Mirrors `DockState.build`: one keyed [DockSlot] per app, exactly one of
/// which may be given a live offset.
Widget _dock(
  List<String> ids, {
  String? dragged,
  ValueListenable<double>? offset,
  double? step,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: kDockSpacing,
      children: [
        for (final (i, id) in ids.indexed)
          DockSlot(
            key: ValueKey(id),
            offset: id == dragged ? offset! : kNoDragOffset,
            slot: step == null ? null : i * step,
            held: id == dragged,
            child: _Probe(label: id),
          ),
      ],
    ),
  );
}

Map<String, int> _ids(WidgetTester tester) => {
      for (final s in tester.stateList<_ProbeState>(find.byType(_Probe)))
        s.widget.label: s.id,
    };

double _translationOf(WidgetTester tester, String id) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byKey(ValueKey(id)),
      matching: find.byType(Transform),
    ),
  );
  return transform.transform.getTranslation().x;
}

void main() {
  group('DockSlot', () {
    testWidgets('a button survives its own drag starting', (tester) async {
      // The regression: giving the dragged button a wrapper the resting ones
      // lack changed that slot's widget type mid-gesture, so the [Row] could
      // not match it to the old element. Flutter tore the button down and
      // disposed the pan recognizer with it, and the drag stopped dead at its
      // first pixel with the dock still believing it was dragging.
      final offset = ValueNotifier<double>(0);
      addTearDown(offset.dispose);

      await tester.pumpWidget(_dock(['a', 'b', 'c']));
      final before = _ids(tester);

      await tester.pumpWidget(
        _dock(['a', 'b', 'c'], dragged: 'b', offset: offset),
      );

      expect(_ids(tester), before);
    });

    testWidgets('every button survives a reorder mid-drag', (tester) async {
      final offset = ValueNotifier<double>(0);
      addTearDown(offset.dispose);

      await tester.pumpWidget(
        _dock(['a', 'b', 'c'], dragged: 'b', offset: offset),
      );
      final before = _ids(tester);

      // 'b' has crossed into the first slot: the list is reordered under the
      // gesture that is still driving it.
      await tester.pumpWidget(
        _dock(['b', 'a', 'c'], dragged: 'b', offset: offset),
      );

      expect(_ids(tester), before);
    });

    testWidgets('a button survives its drag ending', (tester) async {
      final offset = ValueNotifier<double>(0);
      addTearDown(offset.dispose);

      await tester.pumpWidget(
        _dock(['a', 'b', 'c'], dragged: 'b', offset: offset),
      );
      final before = _ids(tester);

      await tester.pumpWidget(_dock(['a', 'b', 'c']));

      expect(_ids(tester), before);
    });

    testWidgets('the offset moves the child without rebuilding it',
        (tester) async {
      final offset = ValueNotifier<double>(0);
      addTearDown(offset.dispose);

      await tester.pumpWidget(
        _dock(['a', 'b', 'c'], dragged: 'b', offset: offset),
      );
      final builds = {
        for (final s in tester.stateList<_ProbeState>(find.byType(_Probe)))
          s.widget.label: s.builds,
      };
      expect(_translationOf(tester, 'b'), 0);

      offset.value = 17;
      await tester.pump();

      expect(_translationOf(tester, 'b'), 17);
      // A pointer move re-runs the one Transform: no button rebuilds, and the
      // resting slots do not move.
      expect(
        {
          for (final s in tester.stateList<_ProbeState>(find.byType(_Probe)))
            s.widget.label: s.builds,
        },
        builds,
      );
      expect(_translationOf(tester, 'a'), 0);
      expect(_translationOf(tester, 'c'), 0);
    });

    testWidgets('a resting slot never moves', (tester) async {
      await tester.pumpWidget(_dock(['a', 'b']));
      expect(_translationOf(tester, 'a'), 0);
      expect(_translationOf(tester, 'b'), 0);
    });
  });

  group('DockSlot slides', () {
    // Each probe is 20 wide and the dock spaces them kDockSpacing apart.
    const step = 20 + kDockSpacing;

    double x(WidgetTester tester, String id) =>
        tester.getTopLeft(find.byKey(ValueKey(id))).dx +
        _translationOf(tester, id);

    testWidgets('the button passed slides aside rather than jumping', (
      tester,
    ) async {
      final offset = ValueNotifier<double>(0);
      addTearDown(offset.dispose);
      await tester.pumpWidget(
        _dock(['a', 'b', 'c'], dragged: 'a', offset: offset, step: step),
      );
      // 'a' crosses into the second slot: the list is reordered, and the
      // offset republished against a's new slot, in the same frame.
      offset.value = step * 0.6 - step;
      await tester.pumpWidget(
        _dock(['b', 'a', 'c'], dragged: 'a', offset: offset, step: step),
      );
      // b is still drawn where it was on the frame it was passed…
      expect(x(tester, 'b'), step);
      await tester.pump(const Duration(milliseconds: 50));
      expect(x(tester, 'b'), inExclusiveRange(0, step));
      await tester.pumpAndSettle();
      expect(x(tester, 'b'), 0);
      // …and the held button never lags the pointer.
      expect(x(tester, 'a'), step * 0.6);
    });

    testWidgets('the dropped button settles into its slot, then rests', (
      tester,
    ) async {
      final offset = ValueNotifier<double>(0);
      addTearDown(offset.dispose);
      await tester.pumpWidget(
        _dock(['a', 'b', 'c'], dragged: 'b', offset: offset, step: step),
      );
      offset.value = 9;
      await tester.pump();
      expect(x(tester, 'b'), step + 9);

      // The drop's frame: b is no longer held, its slot kept for the frame.
      await tester.pumpWidget(_dock(['a', 'b', 'c'], step: step));
      expect(x(tester, 'b'), step + 9);
      await tester.pump(const Duration(milliseconds: 50));
      expect(x(tester, 'b'), inExclusiveRange(step, step + 9));

      // The kept pitch goes after that frame; the slide carries on.
      await tester.pumpWidget(_dock(['a', 'b', 'c']));
      expect(x(tester, 'b'), inExclusiveRange(step, step + 9));
      await tester.pumpAndSettle();
      expect(x(tester, 'b'), step);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('a reorder outside a drag moves at once', (tester) async {
      await tester.pumpWidget(_dock(['a', 'b']));
      await tester.pumpWidget(_dock(['b', 'a']));
      expect(x(tester, 'a'), step);
      expect(x(tester, 'b'), 0);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
