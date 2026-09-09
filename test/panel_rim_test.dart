import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/panel_background.dart';
import 'package:graceful_shell/panel_rim.dart';

/// A rimmed bar draws its rim along its *inner* edge too — the edge every menu
/// comes out of — and the compositor places a bar popup **below** the panel, so
/// nothing the card paints can ever reach that line. The bar has to leave it
/// out across the mouth itself, which is what these pin: the arithmetic that
/// says how much of the bar the mouth covers, and the painter that skips it.

/// The shape `carbon` ships: rimmed, attached, flared.
const _carbonish = ThemeConfig(
  panelBorder: Color(0xFF525252),
  panelBorderWidth: 1.0,
  popupGap: 0.0,
  popupAttachRadius: 12.0,
);

void main() {
  group('which themes paint their own rim', () {
    test('only a bar that is rimmed and attaches its popups', () {
      expect(panelPaintsOwnRim(_carbonish), isTrue);
      // No rim: nothing to break, and the decoration keeps building no Border
      // at all.
      expect(panelPaintsOwnRim(const ThemeConfig()), isFalse);
      // A gap: the cards genuinely float clear of the bar, so the rim is a
      // boundary again and stays the decoration's.
      expect(
          panelPaintsOwnRim(
              const ThemeConfig(panelBorderWidth: 1.0, popupGap: 6.0)),
          isFalse);
    });

    test('and only then does the decoration give the rim up', () {
      // Both halves or neither: the decoration must keep its Border for every
      // theme the painter does not cover, or those bars lose their rim outright.
      expect(
          panelBackgroundDecoration(theme: _carbonish, includeRim: false)
              .border,
          isNull);
      expect(panelBackgroundDecoration(theme: _carbonish).border,
          Border.all(color: _carbonish.panelBorder, width: 1.0));
    });
  });

  group('the stretch the mouth covers', () {
    // A 1600-wide bar, a module centred at 400, a card 200 wide inside a window
    // grown by a 12px flare on each side.
    PanelRimBreak range({
      double anchorCentre = 400,
      double cardExtent = 200,
      double flare = 12,
      double panelExtent = 1600,
    }) =>
        attachedMouthRange(
          anchorCentre: anchorCentre,
          windowExtent: cardExtent + 2 * flare,
          leadingInset: flare,
          cardExtent: cardExtent,
          flare: flare,
          panelExtent: panelExtent,
        );

    test('is the card plus its flare, centred on the module', () {
      // The flare bows the card outward exactly where it meets the bar, so that
      // is the width the join occupies — breaking only the card's width would
      // leave two stubs of the bar's rim under the ears.
      expect(range(), (288.0, 512.0));
    });

    test('a square join breaks exactly the card', () {
      expect(range(flare: 0), (300.0, 500.0));
    });

    test('slides back onto the bar the way the compositor slides the popup',
        () {
      // kPopupSlide is what keeps a popup opened from a module at either end of
      // the bar on the output, and the break has to move with it or it opens
      // under empty bar. The window is 224 wide here, so the last position it
      // fits at starts at 1376.
      expect(range(anchorCentre: 1590), (1376.0, 1600.0));
      expect(range(anchorCentre: 10), (0.0, 224.0));
    });

    test('a window wider than the bar starts at the bar', () {
      // Degenerate rather than negative: clamping to a negative slack would put
      // the break off the near end.
      final wide = range(cardExtent: 2000, panelExtent: 1600);
      expect(wide.$1, lessThanOrEqualTo(0));
      expect(wide.$2, greaterThan(1600));
    });
  });

  group('the painter', () {
    const size = Size(1600, 32);

    Rect? cut(String anchor, {PanelRimBreak? gap, double width = 1.0}) =>
        PanelRimPainter(
          color: const Color(0xFF525252),
          width: width,
          radius: BorderRadius.zero,
          anchor: anchor,
          gap: gap,
        ).breakRect(anchor == 'left' || anchor == 'right'
            ? const Size(32, 1600)
            : size);

    test('cuts the inner edge, on whichever side that is', () {
      // The inner edge is the one facing the screen's interior, so it is the
      // opposite of the edge the bar is anchored to.
      expect(cut('top', gap: (300, 500)),
          const Rect.fromLTRB(300, 31, 500, 32));
      expect(cut('bottom', gap: (300, 500)),
          const Rect.fromLTRB(300, 0, 500, 1));
      expect(cut('left', gap: (300, 500)),
          const Rect.fromLTRB(31, 300, 32, 500));
      expect(cut('right', gap: (300, 500)),
          const Rect.fromLTRB(0, 300, 1, 500));
    });

    test('cuts exactly the rim\'s own thickness and no more', () {
      // A taller band would eat into the bar's *fill*, which the decoration
      // underneath draws — and the desktop would show through the hole.
      final rect = cut('top', gap: (300, 500), width: 3)!;
      expect(rect.height, 3.0);
      expect(rect.bottom, 32.0);
    });

    test('cuts nothing without a break, or for a degenerate one', () {
      expect(cut('top'), isNull);
      expect(cut('top', gap: (400, 400)), isNull);
      expect(cut('top', gap: (500, 300)), isNull);
      expect(cut('top', gap: (300, 500), width: 0), isNull);
    });

    test('repaints when the break moves and not otherwise', () {
      // Every panel on every monitor listens to the store, so a popup that
      // resizes while open — the sound slider swaps its label on every drag —
      // must not repaint bars whose break did not move.
      const base = PanelRimPainter(
        color: Color(0xFF525252),
        width: 1,
        radius: BorderRadius.zero,
        anchor: 'top',
        gap: (300, 500),
      );
      expect(base.shouldRepaint(base), isFalse);
      expect(
          base.shouldRepaint(const PanelRimPainter(
            color: Color(0xFF525252),
            width: 1,
            radius: BorderRadius.zero,
            anchor: 'top',
            gap: (301, 500),
          )),
          isTrue);
    });

    testWidgets('paints without complaint, broken or whole', (tester) async {
      for (final anchor in const ['top', 'bottom', 'left', 'right']) {
        for (final gap in <PanelRimBreak?>[null, (300, 500)]) {
          await tester.pumpWidget(Center(
            child: SizedBox(
              width: 1600,
              height: 32,
              child: CustomPaint(
                painter: PanelRimPainter(
                  color: const Color(0xFF525252),
                  width: 1,
                  // Rounded as well as square: the corner arcs are part of the
                  // same stroked outline and the break is clipped out of it, so
                  // a radius is never in the break's way.
                  radius: BorderRadius.circular(6),
                  anchor: anchor,
                  gap: gap,
                ),
              ),
            ),
          ));
          expect(tester.takeException(), isNull, reason: '$anchor $gap');
        }
      }
    });
  });

  group('the rim does not take the bar\'s clicks', () {
    // The regression this group exists for: the rim first shipped as a
    // `CustomPaint` *stacked over* the bar's content, on the reasoning that a
    // painter with no child absorbs no hits. The opposite is true — a
    // background painter's `hitTest` defaults to *every point is a hit*
    // (`hitTestSelf` is `hitTest(position) ?? true`), and only a foreground
    // painter's defaults to none — so a full-width rim over a `carbon` bar
    // swallowed every click on every module in it.
    setUp(PanelRimBreaks.instance.clearAll);
    tearDown(PanelRimBreaks.instance.clearAll);

    // A 700x32 bar — one that fits the test surface whole, so the tap
    // coordinates below are the bar's own — whose content is one tappable
    // module.
    Widget bar(ThemeConfig theme, Object? panel, VoidCallback onTap) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 700,
              height: 32,
              child: panelWithRim(
                theme: theme,
                anchor: 'top',
                panel: panel,
                content: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );

    testWidgets('a module under the rim still fires', (tester) async {
      var taps = 0;
      await tester.pumpWidget(bar(_carbonish, null, () => taps++));
      await tester.tap(find.byType(GestureDetector));
      expect(taps, 1);
    });

    testWidgets('including flush against the edge the rim is drawn on',
        (tester) async {
      // Corners and the inner edge, the way `tap_target_test` does: a centre
      // tap passes even when the line itself is eating hits.
      var taps = 0;
      await tester.pumpWidget(bar(_carbonish, null, () => taps++));
      final box = tester.getRect(find.byType(GestureDetector));
      for (final at in [
        box.topLeft + const Offset(0.5, 0.5),
        box.bottomRight - const Offset(0.5, 0.5),
        // The inner edge — where the mouth of every menu opens.
        Offset(box.center.dx, box.bottom - 0.5),
      ]) {
        await tester.tapAt(at);
      }
      expect(taps, 3);
    });

    testWidgets('and still fires with a menu open across the mouth',
        (tester) async {
      final panel = Object();
      var taps = 0;
      PanelRimBreaks.instance.set(panel, (300, 500));
      await tester.pumpWidget(bar(_carbonish, panel, () => taps++));
      // Under the break and beside it alike: the clip is a paint concern only.
      await tester.tapAt(tester.getRect(find.byType(GestureDetector)).topLeft +
          const Offset(400, 16));
      await tester.tap(find.byType(GestureDetector));
      expect(taps, 2);

      // And once the menu closes: the rim comes back whole over a bar that is
      // still taking clicks.
      PanelRimBreaks.instance.clear(panel);
      await tester.pump();
      await tester.tap(find.byType(GestureDetector));
      expect(taps, 3);
    });

    testWidgets('a theme that paints no rim is handed back untouched',
        (tester) async {
      // No wrapper at all for every other theme, so those bars keep the tree,
      // the layers and the hit test they always had.
      const theme = ThemeConfig();
      final content = SizedBox(key: UniqueKey());
      expect(
          panelWithRim(
              theme: theme, anchor: 'top', panel: null, content: content),
          same(content));

      var taps = 0;
      await tester.pumpWidget(bar(theme, null, () => taps++));
      await tester.tap(find.byType(GestureDetector));
      expect(taps, 1);
    });
  });

  group('the store', () {
    setUp(PanelRimBreaks.instance.clearAll);
    tearDown(PanelRimBreaks.instance.clearAll);

    test('is keyed per panel', () {
      final a = Object();
      final b = Object();
      PanelRimBreaks.instance.set(a, (10, 20));
      expect(PanelRimBreaks.instance.of(a), (10.0, 20.0));
      expect(PanelRimBreaks.instance.of(b), isNull);
      expect(PanelRimBreaks.instance.of(null), isNull);
    });

    test('does not notify for a break that did not move', () {
      // Every bar in the shell listens; a popup rebuilding at the same size
      // must not re-lay any of them.
      final panel = Object();
      var notifications = 0;
      void listener() => notifications++;
      PanelRimBreaks.instance.addListener(listener);
      addTearDown(() => PanelRimBreaks.instance.removeListener(listener));

      PanelRimBreaks.instance.set(panel, (10, 20));
      expect(notifications, 1);
      PanelRimBreaks.instance.set(panel, (10, 20));
      expect(notifications, 1);
      PanelRimBreaks.instance.set(panel, (10, 21));
      expect(notifications, 2);
      PanelRimBreaks.instance.clear(panel);
      expect(notifications, 3);
      PanelRimBreaks.instance.clear(panel);
      expect(notifications, 3, reason: 'nothing left to clear');
    });
  });
}
