// The bar's shape against the screen: a margin per screen edge
// (`panel_margin`), which corners round (`panel_corners`), and how both meet
// the join where two flush bars share a corner (`panel_join_radius`).

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toml/toml.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/desktop/desktop_layout.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/panel_background.dart';
import 'package:moonswing/panel_join.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/panel_gradient.dart';

/// A top bar and a left bar joined in the top-left corner, both floating 8px
/// off the screen's right and bottom edges: the frame the per-edge margin
/// exists for.
const _frame = PanelMargins(right: 8, bottom: 8);

const _theme = ThemeConfig(
  panelRadius: 10,
  panelJoinRadius: 12,
  panelMargin: _frame,
  panelGradient: PanelGradient.none,
);

const _r = Radius.circular(10);

Set<PanelCorner> _rounded(
  String anchor, {
  ThemeConfig theme = _theme,
  PanelJoins joins = PanelJoins.none,
}) => panelRoundedCorners(anchor: anchor, theme: theme, joins: joins);

void main() {
  group('panel_margin', () {
    test('one number is every edge, and is written back as one', () {
      final theme = ThemeConfig.fromMap({'panel_margin': 6});
      expect(theme.panelMargin, const PanelMargins.all(6));
      expect(theme.toMap()['panel_margin'], 6);
      // A TOML float coerces, as every integer key's does.
      expect(
        ThemeConfig.fromMap({'panel_margin': 6.0}).panelMargin,
        const PanelMargins.all(6),
      );
    });

    test('a table gives each edge its own, a missing edge 0', () {
      final theme = ThemeConfig.fromMap({
        'panel_margin': {'right': 8, 'bottom': 4.0},
      });
      expect(theme.panelMargin, const PanelMargins(right: 8, bottom: 4));
      expect(theme.toMap()['panel_margin'], {
        'top': 0,
        'right': 8,
        'bottom': 4,
        'left': 0,
      });
    });

    test('a bad edge costs that edge, never the key or the theme', () {
      final theme = ThemeConfig.fromMap({
        'panel_margin': {'top': 'lots', 'right': 1e9, 'left': -3},
        'panel_radius': 7.0,
      });
      expect(theme.panelMargin, const PanelMargins(right: 256));
      expect(theme.panelRadius, 7.0);
      expect(
        ThemeConfig.fromMap({'panel_margin': true}).panelMargin,
        PanelMargins.zero,
      );
      expect(
        ThemeConfig.fromMap({'panel_margin': double.nan}).panelMargin,
        PanelMargins.zero,
      );
    });

    test('a theme file round-trips either form', () {
      for (final margin in const [
        PanelMargins.all(12),
        PanelMargins(top: 0, right: 8, bottom: 8, left: 0),
      ]) {
        final theme = ThemeConfig(panelMargin: margin);
        final text = TomlDocument.fromMap(theme.toMap()).toString();
        final back = ThemeConfig.fromMap(TomlDocument.parse(text).toMap());
        expect(back.panelMargin, margin);
        expect(back, theme);
      }
    });

    test('withEdge moves one edge and nothing else', () {
      expect(
        const PanelMargins.all(4).withEdge('left', 0),
        const PanelMargins(top: 4, right: 4, bottom: 4, left: 0),
      );
      expect(const PanelMargins.all(4).withEdge('left', 4).isUniform, isTrue);
    });

    test('each bar is given its own edge and the two at its ends', () {
      const margin = PanelMargins(top: 1, right: 2, bottom: 3, left: 4);
      expect(panelEndEdges('top'), ('left', 'right'));
      expect(panelEndEdges('bottom'), ('left', 'right'));
      expect(panelEndEdges('left'), ('top', 'bottom'));
      expect(panelEndEdges('right'), ('top', 'bottom'));
      expect(margin.of('top'), 1);
      expect(margin.of('right'), 2);
      expect(margin.of('bottom'), 3);
      expect(margin.of('left'), 4);
      expect(margin.of('middle'), 1, reason: 'an unknown anchor is top');
    });

    test('the desktop grid clears each bar by its own edge only', () {
      final insets = panelInsetsFor(const {
        'top': PanelConfig(anchor: 'top', height: 32),
        'left': PanelConfig(anchor: 'left', height: 40),
      }, const PanelMargins(top: 0, left: 6, right: 8, bottom: 8));
      expect(insets, const EdgeInsets.fromLTRB(46, 32, 0, 0));
    });
  });

  group('panel_corners', () {
    test('reads the three words and a list, written back the same way', () {
      for (final (raw, choice) in [
        ('auto', PanelCornerChoice.auto),
        ('all', PanelCornerChoice.all),
        ('none', PanelCornerChoice.none),
      ]) {
        final theme = ThemeConfig.fromMap({'panel_corners': raw});
        expect(theme.panelCorners, choice);
        expect(theme.toMap()['panel_corners'], raw);
      }
      final picked = ThemeConfig.fromMap({
        'panel_corners': ['bottom_right', 'top_right'],
      });
      expect(
        picked.panelCorners,
        const PanelCornerChoice.only({
          PanelCorner.topRight,
          PanelCorner.bottomRight,
        }),
      );
      // Clockwise from the top-left, whatever order it was written in.
      expect(picked.toMap()['panel_corners'], ['top_right', 'bottom_right']);
    });

    test('an unknown corner costs that corner; anything else the key', () {
      expect(
        ThemeConfig.fromMap({
          'panel_corners': ['top_left', 'middle', 3],
        }).panelCorners,
        const PanelCornerChoice.only({PanelCorner.topLeft}),
      );
      expect(
        ThemeConfig.fromMap({'panel_corners': 'round'}).panelCorners,
        PanelCornerChoice.auto,
      );
      expect(
        ThemeConfig.fromMap({'panel_corners': 4}).panelCorners,
        PanelCornerChoice.auto,
      );
      expect(const ThemeConfig().panelCorners, PanelCornerChoice.auto);
      expect(
        const ThemeConfig(panelCorners: PanelCornerChoice.none),
        isNot(const ThemeConfig()),
      );
    });
  });

  group('the corners a bar rounds', () {
    test('automatic keeps the rule every existing theme was drawn by', () {
      const flush = ThemeConfig(panelRadius: 10);
      expect(_rounded('top', theme: flush), {
        PanelCorner.bottomLeft,
        PanelCorner.bottomRight,
      });
      expect(_rounded('right', theme: flush), {
        PanelCorner.topLeft,
        PanelCorner.bottomLeft,
      });
      const floating = ThemeConfig(
        panelRadius: 10,
        panelMargin: PanelMargins.all(8),
      );
      for (final anchor in const ['top', 'bottom', 'left', 'right']) {
        expect(
          panelCornerRadius(anchor: anchor, theme: floating),
          BorderRadius.circular(10),
          reason: anchor,
        );
      }
    });

    test('automatic rounds the outer corner at an end that floats', () {
      // Flush against the top and the left, short of the right edge.
      expect(_rounded('top'), {
        PanelCorner.bottomLeft,
        PanelCorner.bottomRight,
        PanelCorner.topRight,
      });
      // Flush against the left and the top, short of the bottom edge.
      expect(_rounded('left'), {
        PanelCorner.topRight,
        PanelCorner.bottomRight,
        PanelCorner.bottomLeft,
      });
      // A bottom bar sits on the edge that floats, so all four round.
      expect(_rounded('bottom'), PanelCorner.values.toSet());
    });

    test('a joined frame: flush at the join, round at the far ends', () {
      // The feature's own picture: the pair meets in the top-left corner, the
      // inner corners there square off for the fillet, and every corner at an
      // end that floats rounds.
      expect(
        panelCornerRadius(
          anchor: 'top',
          theme: _theme,
          joins: const PanelJoins(start: 40),
        ),
        const BorderRadius.only(topRight: _r, bottomRight: _r),
      );
      expect(
        panelCornerRadius(
          anchor: 'left',
          theme: _theme,
          joins: const PanelJoins(start: 32),
        ),
        const BorderRadius.only(bottomLeft: _r, bottomRight: _r),
      );
    });

    test('chosen corners are taken as written, on every bar', () {
      const chosen = ThemeConfig(
        panelRadius: 10,
        panelCorners: PanelCornerChoice.only({
          PanelCorner.topLeft,
          PanelCorner.bottomRight,
        }),
      );
      for (final anchor in const ['top', 'bottom', 'left', 'right']) {
        expect(
          panelCornerRadius(anchor: anchor, theme: chosen),
          const BorderRadius.only(topLeft: _r, bottomRight: _r),
          reason: anchor,
        );
      }
      expect(
        panelCornerRadius(
          theme: const ThemeConfig(
            panelRadius: 10,
            panelMargin: PanelMargins.all(8),
            panelCorners: PanelCornerChoice.none,
          ),
        ),
        BorderRadius.zero,
      );
    });

    test('a join still squares a chosen inner corner', () {
      const chosen = ThemeConfig(
        panelRadius: 10,
        panelJoinRadius: 12,
        panelCorners: PanelCornerChoice.all,
      );
      expect(
        panelCornerRadius(
          anchor: 'top',
          theme: chosen,
          joins: const PanelJoins(start: 40),
        ),
        const BorderRadius.only(topLeft: _r, topRight: _r, bottomRight: _r),
      );
    });
  });

  group('the join under per-edge margins', () {
    test('an end meets its neighbour only where both edges are flush', () {
      const both = PanelJoins(start: 40, end: 36);
      expect(
        activePanelJoins(_theme, both, anchor: 'top'),
        const PanelJoins(start: 40),
        reason: 'flush on the left, floating off the right',
      );
      expect(
        activePanelJoins(_theme, both, anchor: 'left'),
        const PanelJoins(start: 40),
        reason: 'flush at the top, floating off the bottom',
      );
      expect(
        activePanelJoins(_theme, both, anchor: 'bottom'),
        PanelJoins.none,
        reason: 'a bar that floats off its own edge meets nothing',
      );
    });

    test('the bars grow for a fillet only in a corner left flush', () {
      expect(panelJoinRadiusOf(_theme), 12);
      expect(panelSurfaceReach(_theme, joined: {PanelCorner.topLeft}), 12);
      expect(panelSurfaceReach(_theme, joined: {PanelCorner.topRight}), 0);
      expect(panelSurfaceReach(_theme, joined: const {}), 0);
    });

    test('which corners the geometry joins', () {
      const top = PanelConfig(name: 'top', anchor: 'top', height: 32);
      const left = PanelConfig(name: 'left', anchor: 'left', height: 40);
      const right = PanelConfig(name: 'right', anchor: 'right', height: 36);
      expect(panelJoinCorners([top]), isEmpty);
      expect(panelJoinCorners([top, left]), {PanelCorner.topLeft});
      expect(panelJoinCorners([top, left, right]), {
        PanelCorner.topLeft,
        PanelCorner.topRight,
      });
    });

    test('a far end that floats is not read as a stop', () {
      // Mir's placement: the top bar spans the joined corner and stops 8px
      // short of the right edge for its margin, the left bar starts under it
      // and stops 8px short of the bottom. Measured as though the margins
      // were not taken off, the left bar is the one stopped at its start —
      // so it paints the fillet there, and the top bar paints nothing.
      Widget? layer(String anchor, Size surface, PanelJoins joins) =>
          panelJoinLayer(
            theme: _theme,
            anchor: anchor,
            thickness: anchor == 'top' ? 32 : 40,
            joins: joins,
            surface: surface,
            screenSize: () => const Size(1920, 1080),
          );

      expect(
        layer('top', const Size(1912, 44), const PanelJoins(start: 40)),
        isNull,
      );
      final left = layer(
        'left',
        const Size(52, 1080 - 32 - 8),
        const PanelJoins(start: 32),
      );
      expect(left, isNotNull);
      final painter =
          ((left! as IgnorePointer).child! as CustomPaint).painter!
              as PanelJoinPainter;
      expect(painter.atStart, isTrue);
      expect(painter.atEnd, isFalse);
    });
  });

  group('the settings row', () {
    testWidgets('each side commits on its own', (tester) async {
      final moved = <(String, int)>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ThemeScope(
            theme: const ThemeConfig(),
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => Align(
                    alignment: Alignment.topLeft,
                    child: SettingsSidesField(
                      top: 0,
                      right: 8,
                      bottom: 8,
                      left: 0,
                      max: 256,
                      onChanged: (side, v) => moved.add((side, v)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      for (final side in const ['Top', 'Right', 'Bottom', 'Left']) {
        expect(find.text(side), findsOneWidget);
      }
      final left = find.byType(EditableText).at(3);
      await tester.tap(left);
      await tester.enterText(left, '999');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(moved, [('left', 256)]);
    });
  });
}
