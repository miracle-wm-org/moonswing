import 'package:flutter/widgets.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/scopes.dart';

/// [LoadingIndicator] is the shell's only loader — six near-identical
/// hand-rolled copies collapsed into it — so the two contracts its call sites
/// rely on are worth pinning: it occupies exactly `size`, and it takes the
/// theme's muted popup foreground when no colour is given.
///
/// Nothing here calls `pumpAndSettle`. The loader animates on a `repeat()`ing
/// controller that never settles, so that would sit until the test timed out;
/// a single `pump` is enough to lay out and paint one frame of it.
void main() {
  const theme = ThemeConfig(popupForeground: Color(0xFF102030));

  Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ThemeScope(
            theme: theme,
            child: Center(child: child),
          ),
        ),
      );

  testWidgets('renders a SpinKit loader rather than a hand-rolled one',
      (tester) async {
    await show(tester, const LoadingIndicator(size: 18));

    expect(find.byType(SpinKitRing), findsOneWidget);
  });

  testWidgets('occupies exactly the size it was asked for', (tester) async {
    await show(tester, const LoadingIndicator(size: 22));

    // Several call sites lay out against this footprint — a panel module's
    // placeholder is sized so the modules beside it do not shuffle sideways
    // when the real content lands.
    expect(tester.getSize(find.byType(LoadingIndicator)), const Size(22, 22));
  });

  testWidgets('defaults to the theme muted popup foreground', (tester) async {
    await show(tester, const LoadingIndicator(size: 16));

    expect(
      tester.widget<SpinKitRing>(find.byType(SpinKitRing)).color,
      theme.popupForeground.withValues(alpha: 0.6),
    );
  });

  testWidgets('an explicit colour wins, and needs no ThemeScope',
      (tester) async {
    const red = Color(0xFFFF0000);

    // Deliberately *not* under a ThemeScope: the panel modules pass a colour
    // and the lookup has to stay unreached, or a loader in a subtree with no
    // theme above it would throw.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: LoadingIndicator(color: red, size: 12)),
      ),
    );

    expect(tester.widget<SpinKitRing>(find.byType(SpinKitRing)).color, red);
  });

  testWidgets('keeps a visible stroke at the smallest size in use',
      (tester) async {
    // 12 is the smallest the shell asks for (the workspaces placeholder and
    // the bluetooth scan row). Scaling the package's stroke ratio alone would
    // put it under a pixel there, so there is a floor.
    await show(tester, const LoadingIndicator(size: 12));

    expect(
      tester.widget<SpinKitRing>(find.byType(SpinKitRing)).lineWidth,
      greaterThanOrEqualTo(1.5),
    );
  });
}
