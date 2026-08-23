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
    // blur: 0 keeps the BackdropFilter out of the tree; the handshake is
    // what this test pins, not the compositing.
    child: ThemeScope(
      theme: const ThemeConfig(blur: 0),
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
}
