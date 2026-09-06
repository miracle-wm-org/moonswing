import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay_fade_scaffold.dart';
import 'package:graceful_shell/scopes.dart';

Widget _host({
  required ValueNotifier<bool> closing,
  required VoidCallback onClosed,
  VoidCallback? onBackdropTap,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ThemeScope(
      theme: const ThemeConfig(),
      child: FadeOverlayScaffold(
        closing: closing,
        onClosed: onClosed,
        onBackdropTap: onBackdropTap,
        child: const SizedBox(width: 100, height: 100, child: Text('card')),
      ),
    ),
  );
}

void main() {
  testWidgets('plays the fade-out and then calls onClosed exactly once',
      (tester) async {
    final closing = ValueNotifier(false);
    var closed = 0;
    await tester.pumpWidget(_host(closing: closing, onClosed: () => closed++));
    await tester.pumpAndSettle();
    expect(closed, 0);

    closing.value = true;
    await tester.pump();
    // Mid-animation: the teardown must not have happened yet — the window
    // is destroyed by onClosed, and destroying it mid-fade skips the exit.
    await tester.pump(const Duration(milliseconds: 40));
    expect(closed, 0);

    await tester.pumpAndSettle();
    expect(closed, 1);
    closing.dispose();
  });

  testWidgets('backdrop tap fires, card tap does not dismiss through it',
      (tester) async {
    final closing = ValueNotifier(false);
    var taps = 0;
    await tester.pumpWidget(_host(
      closing: closing,
      onClosed: () {},
      onBackdropTap: () => taps++,
    ));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(5, 5));
    expect(taps, 1);
    closing.dispose();
  });

  testWidgets('paints no backdrop filter', (tester) async {
    // Not a style rule: a BackdropFilter reaches only what Flutter has already
    // painted beneath it, and this scaffold is the first thing painted into its
    // window — the scrim is its own child, and under that is a transparent
    // layer-shell surface the compositor owns. So a filter here has an empty
    // backdrop and changes no pixel, while costing a full-output Gaussian on
    // every frame the overlay animates.
    final closing = ValueNotifier(false);
    await tester.pumpWidget(_host(closing: closing, onClosed: () {}));
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsNothing);
    closing.dispose();
  });

  testWidgets('the opacity layer is bounded by the card, not the output', (
    tester,
  ) async {
    // Every overlay window calls `spanFullOutput`, so an `Opacity` around this
    // whole scaffold is bounded by the *display*: `RenderOpacity` skips its layer
    // at exactly 1.0, so it cost nothing at rest and then allocated and blended a
    // full-output offscreen on every frame in and out — thirty-odd megabytes a
    // frame at 4K. The scrim is a flat fill and fades by its own alpha; only the
    // card keeps a real layer, and it is the card's size.
    final closing = ValueNotifier(false);
    await tester.pumpWidget(_host(closing: closing, onClosed: () {}));
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(Opacity), findsNothing);
    final fade = tester.renderObject<RenderBox>(find.byType(FadeTransition));
    expect(fade.size, const Size(100, 100));

    closing.dispose();
  });

  testWidgets('the scrim fades by its own alpha', (tester) async {
    // The other half of the rule above: mid-animation the scrim has to be
    // *dimmer*, not merely drawn under something transparent. A fill at a
    // lower alpha is the same picture and needs no layer at all.
    final closing = ValueNotifier(false);
    await tester.pumpWidget(_host(closing: closing, onClosed: () {}));
    await tester.pump(const Duration(milliseconds: 80));

    Color scrimNow() => tester
        .widget<ColoredBox>(
          find.descendant(
            of: find.byType(FadeOverlayScaffold),
            matching: find.byType(ColoredBox),
          ),
        )
        .color;

    final midway = scrimNow();
    expect(midway.a, greaterThan(0.0));
    expect(midway.a, lessThan(const ThemeConfig().scrim.a));

    await tester.pumpAndSettle();
    expect(scrimNow().a, const ThemeConfig().scrim.a);

    closing.dispose();
  });
}
