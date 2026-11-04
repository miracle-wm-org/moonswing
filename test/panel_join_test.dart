// Where two flush bars meet, the fillet that rounds the inside of the corner
// (`panel_join_radius`): which bars meet, how far their surfaces reach for it,
// which of the two paints it, the shape it is painted in, and the corners the
// bars square off for it.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toml/toml.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/main.dart' show PanelMain;
import 'package:moonswing/panel_background.dart';
import 'package:moonswing/panel_join.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/builtin_themes.dart';
import 'package:moonswing/theme/panel_gradient.dart';
import 'package:moonswing/theme/surface_material.dart';

const _top = PanelConfig(name: 'top', anchor: 'top', height: 32);
const _bottom = PanelConfig(name: 'bottom', anchor: 'bottom', height: 28);
const _left = PanelConfig(name: 'left', anchor: 'left', height: 40);
const _right = PanelConfig(name: 'right', anchor: 'right', height: 36);

/// The one corner [_top] and [_left] meet in.
const _topLeft = {PanelCorner.topLeft};

const _joined = ThemeConfig(
  panelJoinRadius: 12,
  panelGradient: PanelGradient.none,
);

ThemeConfig _shipped(String slug) =>
    ThemeConfig.fromMap(TomlDocument.parse(kBuiltInThemes[slug]!).toMap());

void main() {
  group('which bars meet', () {
    test('a top bar meets the side bars at its two ends', () {
      final all = [_top, _left, _right];
      expect(panelJoinsFor(_top, all), const PanelJoins(start: 40, end: 36));
      expect(panelJoinsFor(_left, all), const PanelJoins(start: 32));
      expect(panelJoinsFor(_right, all), const PanelJoins(start: 32));
    });

    test('a side bar meets the top at its start and the bottom at its end', () {
      final all = [_top, _bottom, _left];
      expect(panelJoinsFor(_left, all), const PanelJoins(start: 32, end: 28));
      expect(panelJoinsFor(_bottom, all), const PanelJoins(start: 40));
    });

    test('a lone bar, or two on parallel edges, meet nothing', () {
      expect(panelJoinsFor(_top, [_top]), PanelJoins.none);
      expect(panelsJoin([_top]), isFalse);
      expect(panelsJoin([_top, _bottom]), isFalse);
      expect(panelsJoin([_left, _right]), isFalse);
      expect(panelsJoin([_top, _left]), isTrue);
    });

    test('two bars stacked on one edge take no part in a join', () {
      // Which of the two is innermost is the compositor's to decide, so
      // neither knows where its corner is.
      const second = PanelConfig(name: 'top2', anchor: 'top', height: 24);
      final all = [_top, second, _left];
      expect(panelJoinsFor(_top, all), PanelJoins.none);
      expect(panelJoinsFor(second, all), PanelJoins.none);
      expect(panelJoinsFor(_left, all), PanelJoins.none);
      expect(panelsJoin(all), isFalse);
    });

    test('an unknown anchor is a top bar, as it is everywhere else', () {
      const odd = PanelConfig(name: 'odd', anchor: 'middle', height: 30);
      expect(panelJoinsFor(_left, [odd, _left]), const PanelJoins(start: 30));
    });
  });

  group('how far the surfaces reach', () {
    test('room for the fillet only while two bars meet', () {
      expect(panelSurfaceReach(_joined, joined: _topLeft), 12);
      expect(
        panelSurfaceReach(_joined, joined: const {}),
        0,
        reason: 'a lone bar is never grown for a corner it does not have',
      );
      expect(panelSurfaceReach(const ThemeConfig(), joined: _topLeft), 0);
    });

    test('a fractional radius is given whole pixels of surface', () {
      expect(
        panelSurfaceReach(
          const ThemeConfig(panelJoinRadius: 7.5),
          joined: _topLeft,
        ),
        8,
      );
    });

    test('a floating bar meets nothing', () {
      const floating = ThemeConfig(panelJoinRadius: 12, panelMargin: PanelMargins.all(8));
      expect(panelJoinRadiusOf(floating), 0);
      expect(panelSurfaceReach(floating, joined: _topLeft), 0);
      expect(
        activePanelJoins(floating, const PanelJoins(start: 32)),
        PanelJoins.none,
      );
    });

    test('the foliage and the fillet share one strip', () {
      const both = ThemeConfig(
        panelJoinRadius: 12,
        panelFoliage: FoliageStyle.ivy,
        panelOverhang: 64,
      );
      expect(panelSurfaceReach(both, joined: _topLeft), 64);
      expect(
        panelSurfaceReach(both.copyWithJoin(80), joined: _topLeft),
        64,
        reason: 'clamped to 64 like panel_radius',
      );
    });
  });

  group('which bar paints the fillet', () {
    test('the bar stopped short of the corner paints at its end', () {
      // Mir: the top bar spans, the side bar fits beneath it.
      expect(
        panelJoinOwnership(
          joins: const PanelJoins(start: 32),
          vertical: true,
          length: 1080 - 32,
          screenLength: 1080,
        ),
        (start: true, end: false),
      );
      expect(
        panelJoinOwnership(
          joins: const PanelJoins(start: 40),
          vertical: false,
          length: 1920,
          screenLength: 1920,
        ),
        (start: false, end: false),
        reason: 'the bar across the corner leaves it to the other',
      );
    });

    test('and the other way round, where the side bar spans', () {
      expect(
        panelJoinOwnership(
          joins: const PanelJoins(start: 40),
          vertical: false,
          length: 1920 - 40,
          screenLength: 1920,
        ),
        (start: true, end: false),
      );
      expect(
        panelJoinOwnership(
          joins: const PanelJoins(start: 32),
          vertical: true,
          length: 1080,
          screenLength: 1080,
        ),
        (start: false, end: false),
      );
    });

    test('short by both neighbours, it paints at both ends', () {
      expect(
        panelJoinOwnership(
          joins: const PanelJoins(start: 32, end: 28),
          vertical: true,
          length: 1080 - 60,
          screenLength: 1080,
        ),
        (start: true, end: true),
      );
    });

    test('short by one of two equally deep neighbours, it paints nothing', () {
      expect(
        panelJoinOwnership(
          joins: const PanelJoins(start: 32, end: 32),
          vertical: true,
          length: 1080 - 32,
          screenLength: 1080,
        ),
        (start: false, end: false),
      );
      // Unequal, the shortfall says which end.
      expect(
        panelJoinOwnership(
          joins: const PanelJoins(start: 32, end: 28),
          vertical: true,
          length: 1080 - 28,
          screenLength: 1080,
        ),
        (start: false, end: true),
      );
    });

    test('a length matching no arrangement paints nothing', () {
      expect(
        panelJoinOwnership(
          joins: const PanelJoins(start: 32),
          vertical: true,
          length: 900,
          screenLength: 1080,
        ),
        (start: false, end: false),
      );
    });

    test('with no screen to measure against, Mir places the bars', () {
      expect(
        panelJoinOwnership(
          joins: const PanelJoins(start: 32, end: 28),
          vertical: true,
          length: 500,
          screenLength: null,
        ),
        (start: true, end: true),
      );
      expect(
        panelJoinOwnership(
          joins: const PanelJoins(start: 40, end: 36),
          vertical: false,
          length: 500,
          screenLength: null,
        ),
        (start: false, end: false),
      );
    });
  });

  group('the fillet', () {
    // A left bar 40 deep in a surface grown 12 past it.
    const size = Size(52, 600);

    Path fillet({required bool start}) => panelJoinPath(
      anchor: 'left',
      size: size,
      thickness: 40,
      radius: 12,
      start: start,
    );

    test('fills the corner of the work area and nothing past the round', () {
      final top = fillet(start: true);
      // Hard against both inner edges, right at the corner.
      expect(top.contains(const Offset(40.5, 0.5)), isTrue);
      // Along each edge, inside the round.
      expect(top.contains(const Offset(40.5, 6)), isTrue);
      expect(top.contains(const Offset(46, 0.5)), isTrue);
      // The far corner of its square is the round's centre side: empty.
      expect(top.contains(const Offset(51, 11)), isFalse);
      // Never on the bar, never past the radius.
      expect(top.contains(const Offset(39, 1)), isFalse);
      expect(top.contains(const Offset(41, 13)), isFalse);
      expect(top.getBounds().left, closeTo(40, 0.01));
      expect(top.getBounds().right, closeTo(52, 0.01));
      expect(top.getBounds().bottom, closeTo(12, 0.01));
    });

    test('at the far end it is the mirror image', () {
      final bottom = fillet(start: false);
      expect(bottom.contains(const Offset(40.5, 599.5)), isTrue);
      expect(bottom.contains(const Offset(51, 589)), isFalse);
      expect(bottom.getBounds().top, closeTo(588, 0.01));
    });

    test('lies in the strip past the bar on every edge', () {
      for (final (anchor, surface, strip) in [
        ('top', const Size(800, 44), const Rect.fromLTRB(0, 32, 800, 44)),
        ('bottom', const Size(800, 44), const Rect.fromLTRB(0, 0, 800, 12)),
        ('right', const Size(44, 600), const Rect.fromLTRB(0, 0, 12, 600)),
      ]) {
        for (final start in [true, false]) {
          final bounds = panelJoinPath(
            anchor: anchor,
            size: surface,
            thickness: 32,
            radius: 12,
            start: start,
          ).getBounds();
          expect(
            strip.inflate(0.01).contains(bounds.topLeft),
            isTrue,
            reason: '$anchor ${start ? 'start' : 'end'}',
          );
          expect(
            strip.inflate(0.01).contains(bounds.bottomRight),
            isTrue,
            reason: '$anchor ${start ? 'start' : 'end'}',
          );
        }
      }
    });

    test('takes the colour of the bar at that end', () {
      expect(
        panelJoinFill(_joined, 'left', start: true),
        _joined.panelBackground,
      );
      const fading = ThemeConfig(panelGradient: PanelGradient.accent);
      final accent = fading.accent.withValues(alpha: fading.panelBackground.a);
      // The fade starts at the left of a top bar and the top of a left one —
      // the two ends that meet in the top-left corner.
      expect(panelJoinFill(fading, 'top', start: true), accent);
      expect(panelJoinFill(fading, 'left', start: true), accent);
      expect(
        panelJoinFill(fading, 'bottom', start: true),
        fading.panelBackground,
      );
      expect(panelJoinFill(fading, 'right', start: false), accent);
    });

    test('on a four-corner bar, the colour of its inner corner there', () {
      const tl = Color(0xFF110000);
      const tr = Color(0xFF002200);
      const br = Color(0xFF000033);
      const bl = Color(0xFF440044);
      const corners = ThemeConfig(
        panelGradient: PanelGradient.corners,
        panelGradientTopLeft: tl,
        panelGradientTopRight: tr,
        panelGradientBottomRight: br,
        panelGradientBottomLeft: bl,
      );
      // A left bar's inner edge is its right one: top-right at its top end.
      expect(panelJoinFill(corners, 'left', start: true), tr);
      expect(panelJoinFill(corners, 'left', start: false), br);
      expect(panelJoinFill(corners, 'top', start: true), bl);
      expect(panelJoinFill(corners, 'bottom', start: false), tr);
      expect(panelJoinFill(corners, 'right', start: false), bl);
    });
  });

  group('the corners a joined bar squares off', () {
    const rounded = ThemeConfig(panelRadius: PanelRadii.all(8), panelJoinRadius: 12);

    test('the inner corner at a joined end, and only that one', () {
      expect(
        panelCornerRadius(
          anchor: 'top',
          theme: rounded,
          joins: const PanelJoins(start: 40),
        ),
        const BorderRadius.only(bottomRight: Radius.circular(8)),
      );
      expect(
        panelCornerRadius(
          anchor: 'left',
          theme: rounded,
          joins: const PanelJoins(end: 28),
        ),
        const BorderRadius.only(topRight: Radius.circular(8)),
      );
      expect(
        panelCornerRadius(
          anchor: 'right',
          theme: rounded,
          joins: const PanelJoins(start: 32, end: 28),
        ),
        BorderRadius.zero,
      );
    });

    test('nothing moves for a theme without a fillet', () {
      const plain = ThemeConfig(panelRadius: PanelRadii.all(8));
      expect(
        panelCornerRadius(
          anchor: 'top',
          theme: plain,
          joins: const PanelJoins(start: 40, end: 36),
        ),
        panelCornerRadius(anchor: 'top', theme: plain),
      );
    });
  });

  group('the layer a bar paints', () {
    Widget? layer({
      ThemeConfig theme = _joined,
      PanelJoins joins = const PanelJoins(start: 32),
      Size surface = const Size(52, 1048),
      Size? screen = const Size(1920, 1080),
    }) => panelJoinLayer(
      theme: theme,
      anchor: 'left',
      thickness: 40,
      joins: joins,
      surface: surface,
      screenSize: () => screen,
    );

    test('is there for the bar that owns a corner', () {
      expect(layer(), isNotNull);
    });

    test('and absent for every reason not to paint', () {
      expect(layer(theme: const ThemeConfig()), isNull, reason: 'no fillet');
      expect(layer(joins: PanelJoins.none), isNull, reason: 'a lone bar');
      expect(
        layer(surface: const Size(40, 1048)),
        isNull,
        reason: 'no strip past the bar — no input region was set',
      );
      expect(
        layer(surface: const Size(52, 1080)),
        isNull,
        reason: 'this bar spans the corner',
      );
    });

    testWidgets('paints the corner and lets every click through', (
      tester,
    ) async {
      var tapped = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 52,
              height: 1048,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tapped++,
                  ),
                  layer()!,
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsWidgets);
      // Right in the fillet: the window underneath gets it.
      await tester.tapAt(const Offset(41, 1));
      expect(tapped, 1);
    });
  });

  group('a bar', () {
    // A left bar under a top one, Mir's way: the screen is 1080 tall, the top
    // bar 32 deep, and the left bar's surface grown 12 past its 40.
    Future<void> pumpBar(
      WidgetTester tester, {
      required ThemeConfig theme,
      PanelJoins joins = const PanelJoins(start: 32),
    }) {
      tester.view
        ..physicalSize = const Size(1920, 1080)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      return tester.pumpWidget(
        ThemeScope(
          theme: theme,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 52,
              height: 1048,
              child: PanelMain(
                panelConfig: _left,
                anchor: 'left',
                joins: joins,
                screenSize: () => const Size(1920, 1080),
              ),
            ),
          ),
        ),
      );
    }

    bool paintsJoin(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .any((p) => p.painter is PanelJoinPainter);

    testWidgets('that meets another paints the corner', (tester) async {
      await pumpBar(tester, theme: _joined);
      expect(paintsJoin(tester), isTrue);
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<PanelJoinPainter>()
          .single;
      expect(painter.atStart, isTrue);
      expect(painter.atEnd, isFalse);
      expect(painter.radius, 12);
    });

    testWidgets('alone, or on a theme without the key, paints nothing', (
      tester,
    ) async {
      await pumpBar(tester, theme: _joined, joins: PanelJoins.none);
      expect(paintsJoin(tester), isFalse);
      await pumpBar(tester, theme: _shipped('glassy'));
      expect(paintsJoin(tester), isFalse);
    });

    testWidgets('dracula paints it', (tester) async {
      await pumpBar(tester, theme: _shipped('dracula'));
      expect(paintsJoin(tester), isTrue);
    });
  });

  group('the shipped themes', () {
    test('only dracula rounds its joins', () {
      for (final slug in kBuiltInThemes.keys) {
        final theme = _shipped(slug);
        if (slug == 'dracula') {
          expect(theme.panelJoinRadius, greaterThan(0));
          expect(
            panelJoinRadiusOf(theme),
            theme.panelJoinRadius,
            reason: 'dracula is flush, so its joins are read',
          );
        } else {
          expect(theme.panelJoinRadius, 0.0, reason: slug);
        }
      }
    });

    test('the key round-trips and is clamped', () {
      expect(
        ThemeConfig.fromMap({'panel_join_radius': 10}).panelJoinRadius,
        10.0,
      );
      expect(
        ThemeConfig.fromMap({'panel_join_radius': -4.0}).panelJoinRadius,
        0.0,
      );
      expect(
        ThemeConfig.fromMap({'panel_join_radius': 'round'}).panelJoinRadius,
        0.0,
      );
      expect(
        const ThemeConfig(panelJoinRadius: 6).toMap()['panel_join_radius'],
        6.0,
      );
      expect(const ThemeConfig(panelJoinRadius: 6), isNot(const ThemeConfig()));
    });
  });
}

extension on ThemeConfig {
  ThemeConfig copyWithJoin(double radius) =>
      ThemeConfig.fromMap({...toMap(), 'panel_join_radius': radius});
}
