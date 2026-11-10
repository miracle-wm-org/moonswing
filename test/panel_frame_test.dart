// `panel_join`: the bars as one frame round the screen — every pair that can
// meet does, whatever the margins, which are then the screen's; the corners
// they meet in are square and the rim between them is left out. And
// `panel_square_flush_corners`, which squares a corner wherever it lies on a
// screen edge the bar touches.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/desktop/desktop_layout.dart';
import 'package:moonswing/main.dart' show PanelMain;
import 'package:moonswing/panel_background.dart';
import 'package:moonswing/panel_join.dart';
import 'package:moonswing/panel_rim.dart';
import 'package:moonswing/scopes.dart';

const _top = PanelConfig(name: 'top', anchor: 'top', height: 32);
const _bottom = PanelConfig(name: 'bottom', anchor: 'bottom', height: 28);
const _left = PanelConfig(name: 'left', anchor: 'left', height: 40);
const _right = PanelConfig(name: 'right', anchor: 'right', height: 36);

const _frame = [_top, _bottom, _left, _right];

PanelMargins _margins(
  ThemeConfig theme,
  PanelConfig panel, [
  List<PanelConfig> panels = _frame,
]) => panelScreenMargins(
  theme,
  panel.anchor,
  joins: panelJoinsFor(panel, panels),
);

void main() {
  group('the margins of a joined frame', () {
    test("a bottom margin lifts the bottom bar, and the side bar's end with "
        'it', () {
      const theme = ThemeConfig(
        panelJoin: true,
        panelMargin: PanelMargins(bottom: 10),
      );
      const panels = [_left, _bottom];
      expect(_margins(theme, _bottom, panels), const PanelMargins(bottom: 10));
      // Stopped by the bottom bar's zone, which already includes its margin:
      // a margin of its own here would open a gap between the two.
      expect(_margins(theme, _left, panels), PanelMargins.zero);
    });

    test("the margins are the screen's, each moving its edge of the frame", () {
      const theme = ThemeConfig(
        panelJoin: true,
        panelMargin: PanelMargins(top: 4, right: 6, bottom: 8, left: 10),
      );
      // The top and bottom bars run across the corners, so their ends stand
      // off the screen's sides by the side bars' own margins.
      expect(
        _margins(theme, _top),
        const PanelMargins(top: 4, right: 6, bottom: 8, left: 10),
      );
      expect(_margins(theme, _bottom).of('bottom'), 8);
      expect(_margins(theme, _bottom).of('left'), 10);
      expect(_margins(theme, _bottom).of('right'), 6);
      // The side bars stand off their own edge and stop against the top and
      // bottom bars.
      final left = _margins(theme, _left);
      expect((left.left, left.top, left.bottom), (10, 0, 0));
      final right = _margins(theme, _right);
      expect((right.right, right.top, right.bottom), (6, 0, 0));
    });

    test('an end that meets nothing keeps the margin of its side', () {
      const theme = ThemeConfig(
        panelJoin: true,
        panelMargin: PanelMargins(top: 4, bottom: 8, left: 10),
      );
      const panels = [_top, _left];
      final left = _margins(theme, _left, panels);
      expect((left.left, left.top, left.bottom), (10, 0, 8));
      final top = _margins(theme, _top, panels);
      expect((top.top, top.left, top.right), (4, 10, 0));
    });

    test('two bars on one edge are never joined', () {
      const theme = ThemeConfig(
        panelJoin: true,
        panelMargin: PanelMargins(top: 4, left: 10),
      );
      const second = PanelConfig(name: 'second', anchor: 'left', height: 24);
      const panels = [_top, _left, second];
      expect(panelJoinsFor(_left, panels), PanelJoins.none);
      final left = _margins(theme, _left, panels);
      expect((left.left, left.top), (10, 4));
    });

    test('without the flag nothing moves', () {
      const margin = PanelMargins(top: 4, right: 6, bottom: 8, left: 10);
      const theme = ThemeConfig(panelMargin: margin, panelJoinRadius: 12);
      for (final panel in _frame) {
        expect(_margins(theme, panel), margin.onScreen(panel.anchor));
      }
    });

    test('the zone off each edge is that edge’s margin', () {
      const theme = ThemeConfig(
        panelJoin: true,
        panelMargin: PanelMargins(top: 4, right: 6, bottom: 8, left: 10),
      );
      expect(panelOuterMargin(theme, 'top'), 4);
      expect(panelOuterMargin(theme, 'right'), 6);
      expect(panelOuterMargin(theme, 'bottom'), 8);
      expect(panelOuterMargin(theme, 'left'), 10);
      // The desktop grid clears the same zones.
      expect(
        panelInsetsFor(
          {for (final p in _frame) p.name: p},
          theme.panelMargin,
          join: true,
        ),
        const EdgeInsets.fromLTRB(50, 36, 42, 36),
      );
    });
  });

  group('every pair meets', () {
    const floating = ThemeConfig(
      panelJoin: true,
      panelMargin: PanelMargins.all(8),
      panelJoinRadius: 12,
    );

    test('whatever the margins', () {
      const joins = PanelJoins(start: 32, end: 28);
      expect(activePanelJoins(floating, joins, anchor: 'left'), joins);
      // Without the flag the same bars float apart and meet nowhere.
      final apart = ThemeConfig.fromMap({
        ...floating.toMap(),
        'panel_join': false,
      });
      expect(activePanelJoins(apart, joins, anchor: 'left'), PanelJoins.none);
    });

    test('with or without a fillet', () {
      const square = ThemeConfig(
        panelJoin: true,
        panelMargin: PanelMargins.all(8),
      );
      const joins = PanelJoins(start: 32);
      expect(activePanelJoins(square, joins, anchor: 'left'), joins);
      expect(panelJoinRadiusOf(square), 0);
    });

    test('and a floating frame still takes its fillet', () {
      expect(panelJoinRadiusOf(floating), 12);
      expect(
        panelSurfaceReach(floating, joined: {PanelCorner.bottomRight}),
        12,
      );
      expect(panelSurfaceReach(floating, joined: const {}), 0);
    });

    test('the bar that stops short paints the fillet, margins and all', () {
      // A left bar under a top one in a frame floated 10 off every edge: the
      // top bar's zone is 32 + 10, and the left bar's free bottom end stands
      // 10 off the screen's bottom edge.
      const theme = ThemeConfig(
        panelJoin: true,
        panelMargin: PanelMargins.all(10),
        panelJoinRadius: 12,
      );
      final layer = panelJoinLayer(
        theme: theme,
        anchor: 'left',
        thickness: 40,
        joins: const PanelJoins(start: 32),
        surface: const Size(52, 1080 - 42 - 10),
        screenSize: () => const Size(1920, 1080),
      );
      expect(layer, isNotNull);
    });
  });

  group('the corners of a joined frame', () {
    const theme = ThemeConfig(
      panelJoin: true,
      panelMargin: PanelMargins.all(10),
      panelRadius: PanelRadii.all(8),
    );

    test('the bar running across a corner holds its outer corner', () {
      // The bottom bar meets the left one at its start: the inner corner
      // there is square, the frame's own corner rounds.
      expect(
        panelRoundedCorners(
          anchor: 'bottom',
          theme: theme,
          joins: const PanelJoins(start: 40),
        ),
        {PanelCorner.bottomLeft, PanelCorner.bottomRight, PanelCorner.topRight},
      );
    });

    test('the bar stopping against it squares both corners at that end', () {
      expect(
        panelRoundedCorners(
          anchor: 'left',
          theme: theme,
          joins: const PanelJoins(end: 28),
        ),
        {PanelCorner.topLeft, PanelCorner.topRight},
      );
      expect(
        panelCornerRadius(
          anchor: 'right',
          theme: theme,
          joins: const PanelJoins(start: 32, end: 28),
        ),
        BorderRadius.zero,
      );
    });

    test("radii and chosen corners name the screen's corners", () {
      // One radius for each corner of the frame: on a side bar, `top_left` is
      // the screen's top-left, not the bar's own.
      const radii = PanelRadii(topLeft: 4, bottomRight: 6);
      const joined = ThemeConfig(
        panelJoin: true,
        panelMargin: PanelMargins.all(10),
        panelRadius: radii,
        panelCorners: PanelCornerChoice.only({
          PanelCorner.topLeft,
          PanelCorner.bottomRight,
        }),
      );
      expect(
        panelCornerRadius(anchor: 'left', theme: joined),
        const BorderRadius.only(
          topLeft: Radius.circular(4),
          bottomRight: Radius.circular(6),
        ),
      );
      // Without the flag the same keys are the bar's own, turned onto the
      // screen.
      final own = ThemeConfig.fromMap({...joined.toMap(), 'panel_join': false});
      expect(
        panelCornerRadius(anchor: 'left', theme: own),
        const BorderRadius.only(
          bottomLeft: Radius.circular(4),
          topRight: Radius.circular(6),
        ),
      );
    });
  });

  group('square corners at the screen edge', () {
    const all = ThemeConfig(
      panelRadius: PanelRadii.all(8),
      panelCorners: PanelCornerChoice.all,
      panelSquareFlushCorners: true,
    );

    ThemeConfig floated(PanelMargins margin) =>
        ThemeConfig.fromMap({...all.toMap(), 'panel_margin': margin.encode()});

    test('a corner on an edge the bar touches is square', () {
      // Flush against the top, floating off both sides: the top corners lie
      // on the screen's top edge.
      expect(
        panelRoundedCorners(
          anchor: 'top',
          theme: floated(const PanelMargins(left: 10, right: 10)),
        ),
        {PanelCorner.bottomLeft, PanelCorner.bottomRight},
      );
      // An end running to the screen's side squares both corners there.
      expect(
        panelRoundedCorners(
          anchor: 'top',
          theme: floated(const PanelMargins(top: 6, right: 10)),
        ),
        {PanelCorner.topRight, PanelCorner.bottomRight},
      );
    });

    test('a bar touching no edge rounds every corner it picks', () {
      expect(
        panelRoundedCorners(
          anchor: 'left',
          theme: floated(const PanelMargins.all(6)),
        ),
        PanelCorner.values.toSet(),
      );
    });

    test('a flush bar is square', () {
      expect(panelCornerRadius(anchor: 'right', theme: all), BorderRadius.zero);
    });

    test('off, every corner picked rounds', () {
      final off = ThemeConfig.fromMap({
        ...all.toMap(),
        'panel_square_flush_corners': false,
      });
      expect(
        panelRoundedCorners(anchor: 'top', theme: off),
        PanelCorner.values.toSet(),
      );
    });

    test('in a joined frame, the margins it reads are the frame’s', () {
      // A frame flush against the left edge and floating off the bottom and
      // the right: the bottom bar's left end runs to the screen's left edge
      // (its outer corner there is square), its inner corner there is the
      // join's, and its right end floats.
      const theme = ThemeConfig(
        panelJoin: true,
        panelMargin: PanelMargins(bottom: 10, right: 6),
        panelRadius: PanelRadii.all(8),
        panelCorners: PanelCornerChoice.all,
        panelSquareFlushCorners: true,
      );
      expect(
        panelRoundedCorners(
          anchor: 'bottom',
          theme: theme,
          joins: const PanelJoins(start: 40),
        ),
        {PanelCorner.topRight, PanelCorner.bottomRight},
      );
    });
  });

  group('the rim between joined bars', () {
    const rimmed = ThemeConfig(
      panelJoin: true,
      panelBorderWidth: 2,
      popupGap: 6,
    );

    test('is painted by the painter only where there is a seam', () {
      expect(
        panelPaintsOwnRim(
          rimmed,
          anchor: 'left',
          joins: const PanelJoins(start: 32),
        ),
        isTrue,
      );
      // Floating clear of every screen edge, so there is no flush side to
      // leave out either: a bar meeting nothing keeps its Border.
      final floating = ThemeConfig.fromMap({
        ...rimmed.toMap(),
        'panel_margin': 8,
      });
      expect(panelPaintsOwnRim(floating, anchor: 'left'), isFalse);
      // Nor does one meeting another under a theme without the flag.
      final apart = ThemeConfig.fromMap({
        ...floating.toMap(),
        'panel_join': false,
      });
      expect(
        panelPaintsOwnRim(
          apart,
          anchor: 'left',
          joins: const PanelJoins(start: 32),
        ),
        isFalse,
      );
    });

    test("the bar that stops leaves out its end, not its sides' lines", () {
      expect(
        panelJoinSeams(
          anchor: 'left',
          size: const Size(40, 1000),
          width: 2,
          joins: const PanelJoins(start: 32, end: 28),
        ),
        [
          const Rect.fromLTRB(2, 0, 38, 2),
          const Rect.fromLTRB(2, 998, 38, 1000),
        ],
      );
    });

    test('the bar running across leaves out its inner rim over the end', () {
      // The left bar, 40 deep, lies against the top of the bottom bar from its
      // start; its two long rims meet the bottom bar's inner one either side.
      expect(
        panelJoinSeams(
          anchor: 'bottom',
          size: const Size(1900, 28),
          width: 2,
          joins: const PanelJoins(start: 40),
        ),
        [const Rect.fromLTRB(2, 0, 38, 2)],
      );
      // A top bar's inner rim is its bottom edge; at its far end.
      expect(
        panelJoinSeams(
          anchor: 'top',
          size: const Size(1900, 32),
          width: 2,
          joins: const PanelJoins(end: 36),
        ),
        [const Rect.fromLTRB(1866, 30, 1898, 32)],
      );
    });

    test('nothing is left out with no rim or no join', () {
      expect(
        panelJoinSeams(
          anchor: 'top',
          size: const Size(1900, 32),
          width: 0,
          joins: const PanelJoins(start: 40),
        ),
        isEmpty,
      );
      expect(
        panelJoinSeams(
          anchor: 'top',
          size: const Size(1900, 32),
          width: 2,
          joins: PanelJoins.none,
        ),
        isEmpty,
      );
    });

    testWidgets('a joined bar paints its rim with the seam left out', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1920, 1080)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ThemeScope(
          theme: rimmed,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 40,
              height: 1048,
              child: PanelMain(
                panelConfig: _left,
                anchor: 'left',
                joins: const PanelJoins(start: 32),
                screenSize: () => const Size(1920, 1080),
              ),
            ),
          ),
        ),
      );
      final rim = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.foregroundPainter)
          .whereType<PanelRimPainter>()
          .single;
      expect(rim.joins, const PanelJoins(start: 32));
      expect(rim.gap, isNull);
      // Flush against the screen's left and bottom edges, which draw no rim;
      // its top end lies against the top bar, which is the seam's business.
      expect(rim.flush, {'left', 'bottom'});
      // The decoration has given its Border up to the painter.
      final decorations = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>();
      expect(decorations, isNotEmpty);
      expect(decorations.every((d) => d.border == null), isTrue);
    });
  });

  group('the keys', () {
    test('round-trip, and a wrong type costs only the key', () {
      final theme = ThemeConfig.fromMap({
        'panel_join': true,
        'panel_square_flush_corners': true,
      });
      expect(theme.panelJoin, isTrue);
      expect(theme.panelSquareFlushCorners, isTrue);
      expect(theme.toMap()['panel_join'], true);
      expect(theme.toMap()['panel_square_flush_corners'], true);
      expect(theme, isNot(const ThemeConfig()));
      final bad = ThemeConfig.fromMap({
        'panel_join': 'yes',
        'panel_square_flush_corners': 1,
        'panel_radius': 6,
      });
      expect(bad.panelJoin, isFalse);
      expect(bad.panelSquareFlushCorners, isFalse);
      expect(bad.panelRadius, const PanelRadii.all(6));
    });
  });
}
