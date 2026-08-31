import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';

import 'paint_counter.dart';

/// What the settings panes must keep true about painting, in the two shapes
/// they come in: a lazy sliver category (the Shell pages, built by
/// `_ShellCategoryView` in `overlay/settings/shell.dart`) and a box section
/// inside a `ListView` (the audio, display, network and bluetooth pages).
///
/// The shapes are spelled out here rather than driven through
/// `ShellSettingsPage`, which reaches for the `ConfigStore` singleton that no
/// widget test initialises. What is under test is the structure — the
/// boundaries and the laziness — and every real page is one of these two.
///
/// **Where the counter goes is the whole test.** In both shapes there is
/// already a repaint boundary above the section: a viewport is one, and
/// `ListView` gives its own direct child one as well. So a counter placed
/// *above* the scroller cannot see a mark raised inside it, and would pass on
/// any implementation whatsoever. Both counters below are therefore **siblings
/// of the rows**, inside the section, which is where the containment being
/// asserted actually has to hold.
void main() {
  final counterKey = GlobalKey();

  RenderPaintCounter counter() =>
      counterKey.currentContext!.findRenderObject()! as RenderPaintCounter;

  /// The colour the first row's icon is drawn in — the hover tint while the
  /// pointer is on it, the resting foreground otherwise.
  Color? firstIconColor(WidgetTester tester) => tester
      .widgetList<FaIcon>(
        find.descendant(
          of: find.byType(SettingsIconButton).first,
          matching: find.byType(FaIcon),
        ),
      )
      .first
      .color;

  /// One row of a settings form.
  ///
  /// A [SettingsIconButton] rather than a [SettingsToggle]: the toggle is an
  /// `AnimatedContainer`, so at the frame a hover lands its decoration has not
  /// moved yet and "nothing repainted" would be true for the wrong reason.
  /// This one recolours its glyph on the spot, which is what lets the hover
  /// test assert the hover *worked* before asserting it was contained.
  Widget row(int i) => SettingsRow(
    label: 'Row $i',
    control: SettingsIconButton(icon: FontAwesomeIcons.trash, onTap: () {}),
  );

  Widget counterChild() => PaintCounter(
    key: counterKey,
    child: const SizedBox(width: 40, height: 20),
  );

  Widget frame(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: DefaultTextStyle(
      style: const TextStyle(fontSize: 14),
      child: ThemeScope(
        theme: const ThemeConfig(),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 520, height: 400, child: child),
        ),
      ),
    ),
  );

  /// Pumps a category the way the Shell pane does.
  Future<ScrollController> pumpCategory(
    WidgetTester tester, {
    int rows = 40,
  }) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      frame(
        CustomScrollView(
          controller: controller,
          scrollCacheExtent: const ScrollCacheExtent.pixels(600),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              sliver: SliverSettingsSection(
                label: 'Category',
                children: [
                  counterChild(),
                  for (var i = 0; i < rows; i++) row(i),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  /// Pumps a box section inside a `ListView`.
  Future<void> pumpBoxPage(WidgetTester tester, {int rows = 8}) async {
    await tester.pumpWidget(
      frame(
        ListView(
          children: [
            SettingsSection(
              label: 'Output',
              children: [counterChild(), for (var i = 0; i < rows; i++) row(i)],
            ),
          ],
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a category builds only the rows near the viewport', (
    tester,
  ) async {
    await pumpCategory(tester);
    // Forty rows at roughly 37px each is about 1500px of content against a
    // 400px viewport and a 600px cache extent, so a good half of them must
    // never have been mounted. That is what `background.dart` needs: its tiles
    // are `Image.file`, and `Image` resolves its provider on *mount*, so an
    // eager list decoded the whole wallpaper catalogue on a visit to the page
    // whether or not the user scrolled to any of it. Loose on the count and
    // strict on the property — this is laziness, not a golden.
    final built = tester.widgetList(find.byType(SettingsRow)).length;
    expect(built, lessThan(40));
    expect(built, greaterThan(0));
  });

  testWidgets('scrolling a category re-records none of its rows', (
    tester,
  ) async {
    final controller = await pumpCategory(tester);
    final before = counter().paints;

    // Small enough that the counter stays mounted: the question is what
    // happens to the rows still on screen, not to the ones that leave.
    controller.jumpTo(60);
    await tester.pump();

    // The viewport repaints — its own layer is what moves — but each sliver
    // child is a boundary of its own, so its layer is reused at a new offset
    // and `paint()` is never called on the subtree. Before, the whole page's
    // display list was re-recorded on every scroll frame, and the GTK
    // embedder, which implements no partial repaint, rastered the whole output
    // again behind it.
    expect(counter().paints, before);
  });

  testWidgets('hovering a row re-records none of the others', (tester) async {
    await pumpBoxPage(tester);
    final before = counter().paints;

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: Offset.zero);
    await tester.pump();
    await pointer.moveTo(
      tester.getCenter(find.byType(SettingsIconButton).first),
    );
    await tester.pump();

    // The hover is on — without this the containment assertion below would
    // pass on a control that had simply stopped reacting.
    expect(firstIconColor(tester), const ThemeConfig().accent);
    expect(
      counter().paints,
      before,
      reason:
          'the hover escaped its row and re-recorded the rest of the section '
          'with it',
    );
  });

  testWidgets('a row label is not rebuilt by a hover on its control', (
    tester,
  ) async {
    await pumpBoxPage(tester);
    Text label() => tester.widget<Text>(find.text('Row 0'));
    final before = label();

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: Offset.zero);
    await tester.pump();
    await pointer.moveTo(
      tester.getCenter(find.byType(SettingsIconButton).first),
    );
    await tester.pump();

    // A repaint boundary contains a repaint; it does not contain a rebuild.
    // The companion discipline is to keep whatever a `HoverRegion.builder`
    // returns hover-*dependent* and hoist the rest into the enclosing `build`,
    // so the work the boundary contains is a decoration and not a paragraph.
    // Identity is the only thing that tells a rebuilt widget from a reused one.
    expect(identical(label(), before), isTrue);
  });
}
