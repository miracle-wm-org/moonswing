import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/overlay_fade_scaffold.dart';
import 'package:moonswing/scopes.dart';

void main() {
  Widget host(ThemeConfig theme, {Widget? child}) => Directionality(
    textDirection: TextDirection.ltr,
    child: ThemeScope(
      theme: theme,
      child: Center(
        child: SizedBox(
          width: 200,
          height: 120,
          child: OverlayCard(
            color: const Color(0xFF202020),
            child: child ?? const SizedBox.expand(),
          ),
        ),
      ),
    ),
  );

  BoxDecoration decoration(WidgetTester tester) =>
      tester
              .widget<DecoratedBox>(
                find.descendant(
                  of: find.byType(OverlayCard),
                  matching: find.byType(DecoratedBox),
                ),
              )
              .decoration
          as BoxDecoration;

  ClipRRect clip(WidgetTester tester) => tester.widget<ClipRRect>(
    find.descendant(
      of: find.byType(OverlayCard),
      matching: find.byType(ClipRRect),
    ),
  );

  testWidgets('the card is rounded to overlay_radius, its content inside', (
    tester,
  ) async {
    await tester.pumpWidget(host(const ThemeConfig(overlayRadius: 20)));

    expect(decoration(tester).borderRadius, BorderRadius.circular(20));
    // Concentric with the inner edge of the rim, so the content's corners
    // follow the card's curve rather than poking past it.
    expect(
      clip(tester).borderRadius,
      BorderRadius.circular(20 - OverlayCard.borderWidth),
    );
    expect(clip(tester).clipBehavior, Clip.antiAlias);
  });

  testWidgets('the default is the 12 every overlay used to hard-code', (
    tester,
  ) async {
    await tester.pumpWidget(host(const ThemeConfig()));
    expect(decoration(tester).borderRadius, BorderRadius.circular(12));
  });

  testWidgets('a square card clips nothing', (tester) async {
    await tester.pumpWidget(host(const ThemeConfig(overlayRadius: 0)));
    expect(decoration(tester).borderRadius, BorderRadius.zero);
    expect(clip(tester).clipBehavior, Clip.none);
  });

  testWidgets('changing the radius keeps the content mounted', (tester) async {
    // The settings panel is one of these cards, and the radius is typed into
    // it: a change of depth on the way to or from a square card would dispose
    // the pane the user is typing in.
    final key = GlobalKey<_ProbeState>();
    await tester.pumpWidget(
      host(const ThemeConfig(overlayRadius: 12), child: _Probe(key: key)),
    );
    final state = key.currentState;
    expect(state, isNotNull);

    await tester.pumpWidget(
      host(const ThemeConfig(overlayRadius: 0), child: _Probe(key: key)),
    );
    await tester.pumpWidget(
      host(const ThemeConfig(overlayRadius: 40), child: _Probe(key: key)),
    );
    expect(key.currentState, same(state));
    expect(state!.disposed, isFalse);
  });
}

class _Probe extends StatefulWidget {
  const _Probe({super.key});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
