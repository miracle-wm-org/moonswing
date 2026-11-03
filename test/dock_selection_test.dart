import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/modules/dock.dart';

void main() {
  group('DockSelection', () {
    Future<void> pumpField(WidgetTester tester) => tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.expand(),
          ),
        );

    testWidgets('a press on the icon keeps it selected', (tester) async {
      await pumpField(tester);
      final selection = DockSelection(contains: (_) => true);
      addTearDown(selection.dispose);

      selection.select();
      await tester.tapAt(const Offset(10, 10));
      expect(selection.value, isTrue);
    });

    testWidgets('a press anywhere else clears it', (tester) async {
      await pumpField(tester);
      final selection = DockSelection(
        contains: (e) => e.position.dx < 50,
      );
      addTearDown(selection.dispose);

      selection.select();
      await tester.tapAt(const Offset(200, 10));
      expect(selection.value, isFalse);
    });

    testWidgets('watches no pointers while nothing is selected',
        (tester) async {
      await pumpField(tester);
      var asked = 0;
      final selection = DockSelection(contains: (_) {
        asked++;
        return false;
      });
      addTearDown(selection.dispose);

      await tester.tapAt(const Offset(10, 10));
      expect(asked, 0, reason: 'never selected, so no route is held');

      selection.select();
      await tester.tapAt(const Offset(10, 10));
      expect(asked, 1);
      expect(selection.value, isFalse);

      await tester.tapAt(const Offset(10, 10));
      expect(asked, 1, reason: 'clearing gives the route back');
    });

    testWidgets('clear and dispose give the route back', (tester) async {
      await pumpField(tester);
      var asked = 0;
      final selection = DockSelection(contains: (_) {
        asked++;
        return true;
      });

      selection.select();
      selection.select(); // a second click on a selected icon adds no route
      await tester.tapAt(const Offset(10, 10));
      expect(asked, 1);

      selection.clear();
      await tester.tapAt(const Offset(10, 10));
      expect(asked, 1);

      selection.select();
      selection.dispose();
      await tester.tapAt(const Offset(10, 10));
      expect(asked, 1);
    });
  });
}
