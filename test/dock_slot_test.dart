import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/modules/dock.dart';

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
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: kDockSpacing,
      children: [
        for (final id in ids)
          DockSlot(
            key: ValueKey(id),
            offset: id == dragged ? offset! : kNoDragOffset,
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
}
