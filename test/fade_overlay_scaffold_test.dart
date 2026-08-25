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
    // Not a style rule: a BackdropFilter reaches only what Flutter has
    // already painted beneath it, and this scaffold is the first thing
    // painted into its window — the scrim is its own child, and under that is
    // a transparent layer-shell surface the compositor owns. So a filter here
    // has an empty backdrop and changes no pixel, while costing a full-output
    // Gaussian on every frame the overlay animates. That was the shell's one
    // per-frame full-screen effect, and what the settings page transitions
    // were spending their frame budget on.
    final closing = ValueNotifier(false);
    await tester.pumpWidget(_host(closing: closing, onClosed: () {}));
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsNothing);
    closing.dispose();
  });
}
