import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/system/stat_tile.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// The two things the System Info and Monitor pages were rebuilt around: a
/// section heading that sits *outside* the surface it names, and a label/value
/// pair that stays a pair however wide the page gets.
///
/// Both are geometry rather than colour, so neither shows up in a golden — a
/// later tidy-up that folded the heading back into the card's padding, or dropped
/// [StatLine.labelWidth] as redundant, would look reasonable in review.
void main() {
  const theme = ThemeConfig();

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double width = 800,
  }) async {
    // The test view is 800x600 logical by default, and `SizedBox` enforces its
    // size against the incoming constraints rather than overriding them — so
    // without this the wide case would silently be clamped back to 800 and the
    // assertion that the pair does not drift would be measuring nothing.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width + 40, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 14),
          child: ThemeScope(
            theme: theme,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      ),
    );
  }

  /// The card's elevated surface — the box painted in `controlSurface`.
  Finder surface() => find.descendant(
        of: find.byType(SystemCard),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == theme.controlSurface,
        ),
      );

  group('SystemCard', () {
    testWidgets('sets its heading above the surface, not inside it',
        (tester) async {
      await pump(
        tester,
        const SystemCard(
          title: 'Hardware',
          children: [StatLine(label: 'Processor', value: 'Test CPU')],
        ),
      );

      final heading = tester.getRect(find.text('Hardware'));
      final card = tester.getRect(surface());

      expect(heading.bottom, lessThanOrEqualTo(card.top),
          reason: 'the heading has moved back inside the card');
      // And it is not indented by the surface's own padding, which is what
      // makes it read as naming the block rather than labelling its first row.
      final firstRow = tester.getRect(find.text('Processor'));
      expect(heading.left, lessThan(firstRow.left));
    });

    testWidgets('the heading is set at the heading size', (tester) async {
      await pump(
        tester,
        const SystemCard(title: 'Environment', children: [Text('x')]),
      );

      expect(
        tester.widget<Text>(find.text('Environment')).style!.fontSize,
        ShellFontSizes.heading,
      );
    });

    testWidgets('a headline figure sits on the heading, above the subtitle',
        (tester) async {
      await pump(
        tester,
        const SystemCard(
          title: 'CPU',
          subtitle: 'Test CPU · 8 threads',
          trailing: CardValue('12.5%'),
          children: [Text('x')],
        ),
      );

      final figure = tester.getRect(find.text('12.5%'));
      final subtitle = tester.getRect(find.text('Test CPU · 8 threads'));

      expect(figure.bottom, lessThanOrEqualTo(subtitle.top),
          reason: 'the figure dropped onto the subtitle line');
      expect(
        figure.right,
        closeTo(tester.getRect(find.byType(SystemCard)).right - 2, 0.5),
      );
    });

    testWidgets('stretch fills the height it is given', (tester) async {
      await pump(
        tester,
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SystemCard(
                  title: 'Tall',
                  stretch: true,
                  children: [for (var i = 0; i < 6; i++) const Text('row')],
                ),
              ),
              const Expanded(
                child: SystemCard(
                  title: 'Short',
                  stretch: true,
                  children: [Text('row')],
                ),
              ),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final boxes = tester.widgetList(surface()).length;
      expect(boxes, 2);
      final rects = surface().evaluate().map((e) {
        final box = e.renderObject! as RenderBox;
        return box.localToGlobal(Offset.zero) & box.size;
      }).toList();
      expect(rects[0].bottom, closeTo(rects[1].bottom, 0.5),
          reason: 'the short card stopped short of the stretched row');
    });
  });

  group('StatLine', () {
    Widget line({double? labelWidth}) => StatLine(
          label: 'Operating system',
          value: 'Test Linux 42',
          labelWidth: labelWidth,
        );

    testWidgets('a labelWidth keeps the pair together at any page width',
        (tester) async {
      final valueLefts = <double>[];
      for (final width in [800.0, 1600.0]) {
        await pump(tester, line(labelWidth: 150), width: width);
        final label = tester.getRect(find.text('Operating system'));
        final value = tester.getRect(find.text('Test Linux 42'));

        // 150 of label column plus the 12px gap — and, critically, the same
        // answer on a page twice as wide.
        expect(value.left - label.left, closeTo(162, 0.5));
        valueLefts.add(value.left);
      }
      expect(valueLefts[0], closeTo(valueLefts[1], 0.5));
    });

    testWidgets('without one the value still goes hard right', (tester) async {
      await pump(tester, line(), width: 800);

      expect(tester.getRect(find.text('Test Linux 42')).right,
          closeTo(800, 0.5));
    });
  });
}
