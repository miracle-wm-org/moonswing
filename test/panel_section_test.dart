// `panel_sections`: each section of a bar drawn as an island of its own,
// tightly round what it holds — and no island at all round a section that holds
// nothing.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/main.dart' show PanelMain;
import 'package:moonswing/module.dart';
import 'package:moonswing/panel_background.dart';
import 'package:moonswing/panel_section.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/panel_gradient.dart';

const _islands = ThemeConfig(
  panelBackground: Color(0x00000000),
  panelGradient: PanelGradient.none,
  panelSections: true,
  panelSectionBackground: Color(0xFF223344),
  panelSectionRadius: 10,
  panelSectionPadding: 6,
  panelSectionBorder: Color(0xFFFFFFFF),
  panelSectionBorderWidth: 1,
);

/// A section of [child] given [depth] across a top bar, centred as the bar
/// centres its middle section.
Widget _section(
  Widget child, {
  ThemeConfig? theme = _islands,
  Axis axis = Axis.horizontal,
  double depth = 28,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: SizedBox(
      width: axis == Axis.horizontal ? 600 : depth,
      height: axis == Axis.horizontal ? depth : 600,
      child: Align(
        child: PanelSection(
          axis: axis,
          theme: theme == null ? null : PanelSection.themeFor(theme),
          child: child,
        ),
      ),
    ),
  ),
);

RenderPanelSection _render(WidgetTester tester, [int index = 0]) =>
    tester.renderObject<RenderPanelSection>(find.byType(PanelSection).at(index));

/// Counts how often it is mounted, so a test can tell a move from a rebuild.
class _Counted extends StatefulWidget {
  const _Counted({required this.width});

  final double width;
  static int mounts = 0;

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    _Counted.mounts++;
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: widget.width, height: 16);
}

void main() {
  group('an island', () {
    testWidgets('wraps its modules along the bar and takes the depth across', (
      tester,
    ) async {
      await tester.pumpWidget(
        _section(const SizedBox(width: 50, height: 12)),
      );
      final section = _render(tester);
      expect(section.showsIsland, isTrue);
      // The modules plus the padding at either end; the whole depth across.
      expect(section.size, const Size(50 + 2 * 6, 28));
      // Centred inside it.
      final child = tester.getRect(find.byType(SizedBox).last);
      final island = tester.getRect(find.byType(PanelSection));
      expect(child.left - island.left, 6);
      expect(child.center.dy, island.center.dy);
    });

    testWidgets('hands its modules the depth inside its rim and gap', (
      tester,
    ) async {
      late BoxConstraints offered;
      await tester.pumpWidget(
        _section(
          LayoutBuilder(
            builder: (context, constraints) {
              offered = constraints;
              return const SizedBox(width: 20, height: 10);
            },
          ),
        ),
      );
      // A fill that takes the whole depth it is offered stops short of the
      // island's rim, as it stops short of the bar's.
      expect(offered.maxHeight, 28 - 2 * panelSectionInnerInset(_islands));
      expect(panelSectionInnerInset(_islands), 1 + kPanelModuleGap);
    });

    testWidgets('runs down a side bar', (tester) async {
      await tester.pumpWidget(
        _section(
          const SizedBox(width: 12, height: 40),
          axis: Axis.vertical,
          depth: 30,
        ),
      );
      expect(_render(tester).size, const Size(30, 40 + 2 * 6));
    });

    testWidgets('is not drawn round a section with nothing to show', (
      tester,
    ) async {
      await tester.pumpWidget(_section(const SizedBox.shrink()));
      final section = _render(tester);
      expect(section.showsIsland, isFalse);
      expect(section.size, Size.zero,
          reason: 'an empty island would be the placeholder an empty module '
              'is not allowed to leave');
      expect(find.byType(PanelSection), isNot(paints..rrect()));
    });

    testWidgets('comes back when a module there has something to show', (
      tester,
    ) async {
      await tester.pumpWidget(_section(const SizedBox.shrink()));
      expect(_render(tester).showsIsland, isFalse);
      await tester.pumpWidget(_section(const SizedBox(width: 30, height: 10)));
      expect(_render(tester).showsIsland, isTrue);
      expect(_render(tester).size.width, 30 + 2 * 6);
    });

    testWidgets('paints its own fill and rim, rounded', (tester) async {
      await tester.pumpWidget(_section(const SizedBox(width: 50, height: 12)));
      expect(
        find.byType(PanelSection),
        paints..rrect(color: const Color(0xFF223344)),
      );
      final decoration = panelSectionDecoration(
        _islands,
        radius: BorderRadius.circular(10),
      );
      expect(decoration.color, const Color(0xFF223344));
      expect(decoration.border, Border.all(color: const Color(0xFFFFFFFF)));
    });

    testWidgets('a radius past half the depth is a capsule', (tester) async {
      const theme = ThemeConfig(
        panelSections: true,
        panelSectionBackground: Color(0xFF223344),
        panelSectionRadius: 64,
        panelSectionPadding: 6,
      );
      await tester.pumpWidget(
        _section(const SizedBox(width: 50, height: 12), theme: theme),
      );
      expect(
        find.byType(PanelSection),
        paints..rrect(
          rrect: RRect.fromRectAndRadius(
            Offset.zero & const Size(62, 28),
            const Radius.circular(14),
          ),
          color: const Color(0xFF223344),
        ),
      );
    });

    testWidgets('takes the gradient the bar would', (tester) async {
      const theme = ThemeConfig(
        panelSections: true,
        panelSectionGradient: PanelGradient.corners,
      );
      expect(panelSectionDecoration(theme), isA<PanelCornerDecoration>());
      expect(
        panelSectionDecoration(
          const ThemeConfig(
            panelSections: true,
            panelSectionGradient: PanelGradient.accent,
          ),
        ).gradient,
        isA<LinearGradient>(),
      );
    });

    testWidgets('answers no hits of its own', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _section(
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox(width: 50, height: 20),
          ),
        ),
      );
      final island = tester.getRect(find.byType(PanelSection));
      // The module, corner to corner.
      await tester.tapAt(island.topLeft + const Offset(6.5, 4.5));
      await tester.tapAt(island.bottomRight - const Offset(6.5, 4.5));
      expect(taps, 2);
      // The padding at either end is the bar's, not the module's.
      await tester.tapAt(island.centerLeft + const Offset(2, 0));
      await tester.tapAt(island.centerRight - const Offset(2, 0));
      expect(taps, 2);
    });
  });

  group('with islands off', () {
    testWidgets('a section is laid out exactly as it always was', (
      tester,
    ) async {
      late BoxConstraints offered;
      await tester.pumpWidget(
        _section(
          LayoutBuilder(
            builder: (context, constraints) {
              offered = constraints;
              return const SizedBox(width: 50, height: 12);
            },
          ),
          theme: const ThemeConfig(),
        ),
      );
      final section = _render(tester);
      expect(section.theme, isNull);
      expect(section.showsIsland, isFalse);
      expect(section.size, const Size(50, 12));
      expect(offered, const BoxConstraints(maxWidth: 600, maxHeight: 28));
      expect(find.byType(PanelSection), isNot(paints..rrect()));
      expect(find.byType(PanelSection), isNot(paints..rect()));
    });

    test('the module inset is the bar\'s alone', () {
      const theme = ThemeConfig(panelBorderWidth: 1.5);
      expect(panelModuleInset(theme), panelContentInset(theme));
      expect(panelSectionInnerInset(theme), 0);
      // On, the island's rim and gap are added to the bar's.
      expect(
        panelModuleInset(_islands),
        panelContentInset(_islands) + 1 + kPanelModuleGap,
      );
    });
  });

  group('on a bar', () {
    setUpAll(() {
      Module.register(
        Module.plain(
          configKey: 'island_test_wide',
          builder: (_) => const _Counted(width: 40),
        ),
      );
      Module.register(
        Module.plain(
          configKey: 'island_test_empty',
          builder: (_) => const SizedBox.shrink(),
        ),
      );
    });

    Widget bar(ThemeConfig theme) => ThemeScope(
      theme: theme,
      child: const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 800,
          height: 32,
          child: PanelMain(
            anchor: 'top',
            panelConfig: PanelConfig(
              name: 'top',
              anchor: 'top',
              height: 32,
              paddingHorizontal: 8,
              layout: LayoutConfig(
                left: ['island_test_wide'],
                center: ['island_test_empty', 'island_test_empty'],
                right: ['island_test_wide', 'island_test_wide'],
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets('each section is its own island, and an empty one is none', (
      tester,
    ) async {
      await tester.pumpWidget(bar(_islands));
      expect(find.byType(PanelSection), findsNWidgets(3));
      final left = _render(tester, 0);
      final centre = _render(tester, 1);
      final right = _render(tester, 2);
      expect(left.showsIsland, isTrue);
      expect(centre.showsIsland, isFalse);
      expect(right.showsIsland, isTrue);

      final depth = 32 - 2 * panelContentInset(_islands);
      expect(left.size, Size(40 + 2 * 6, depth));
      // Two modules, the gap between them, and the padding.
      expect(right.size, Size(40 + 8 + 40 + 2 * 6, depth));
      final rightRect = tester.getRect(find.byType(PanelSection).at(2));
      expect(rightRect.right, 800 - 8, reason: 'padding_horizontal still holds');
    });

    testWidgets('turning islands on or off remounts no module', (
      tester,
    ) async {
      _Counted.mounts = 0;
      await tester.pumpWidget(bar(const ThemeConfig()));
      final mounted = _Counted.mounts;
      expect(mounted, 3);
      await tester.pumpWidget(bar(_islands));
      await tester.pumpWidget(bar(const ThemeConfig()));
      expect(_Counted.mounts, mounted);
    });
  });
}
