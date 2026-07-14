import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/osd/osd.dart';
import 'package:graceful_shell/osd/osd_store.dart';
import 'package:graceful_shell/scopes.dart';

/// Long enough that a test only reaches the fade-out by pumping there
/// deliberately — [WidgetTester.pumpAndSettle] would otherwise run the hide
/// timer down while it waits for the entry animation.
const hideDelay = Duration(seconds: 2);

/// Comfortably past the card's 200ms entry/exit animation.
const animation = Duration(milliseconds: 300);

/// Pumps the card the way the shell does: alone in its own window, under the
/// ThemeScope the host supplies.
Future<void> pumpOsd(WidgetTester tester, OsdStore store) async {
  await tester.pumpWidget(
    ThemeScope(
      theme: const ThemeConfig(),
      child: SizedBox(
        width: kOsdWindowSize.width,
        height: kOsdWindowSize.height,
        child: OsdWindow(store: store),
      ),
    ),
  );
  await tester.pump(animation);
}

/// Runs [body] against a fresh store, cancelling its hide timer afterwards —
/// a test that ends while the card is still up would otherwise leave a pending
/// timer, which the test framework treats as a leak.
Future<void> withStore(Future<void> Function(OsdStore store) body) async {
  final store = OsdStore.forTesting(hideDelay: hideDelay);
  try {
    await body(store);
  } finally {
    store.dispose();
  }
}

/// Font Awesome icons are [FaIconData], which `find.byIcon` cannot take; the
/// [FaIcon] widget unwraps them to plain [IconData].
Finder faIcon(FaIconData icon) => find.byIcon(icon.data);

/// Width of the bar's filled portion, as a fraction of the track.
double fillFactor(WidgetTester tester) => tester
    .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
    .widthFactor!;

double opacity(WidgetTester tester) =>
    tester.widget<Opacity>(find.byType(Opacity)).opacity;

void main() {
  testWidgets('renders the icon and level for the current request',
      (tester) async {
    await withStore((store) async {
      store.show(OsdKind.volume, 0.75);
      await pumpOsd(tester, store);

      expect(faIcon(FontAwesomeIcons.volumeHigh), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(fillFactor(tester), closeTo(0.75, 0.001));
      expect(opacity(tester), 1.0);
    });
  });

  testWidgets('a muted device shows the crossed-out icon and an empty bar',
      (tester) async {
    await withStore((store) async {
      store.show(OsdKind.microphone, 0.6, muted: true);
      await pumpOsd(tester, store);

      expect(faIcon(FontAwesomeIcons.microphoneSlash), findsOneWidget);
      expect(fillFactor(tester), 0.0);
    });
  });

  testWidgets('a brightness change replaces the volume card on screen',
      (tester) async {
    await withStore((store) async {
      store.show(OsdKind.volume, 0.3);
      await pumpOsd(tester, store);
      expect(faIcon(FontAwesomeIcons.volumeLow), findsOneWidget);

      store.show(OsdKind.brightness, 0.9);
      await tester.pump(animation);

      expect(faIcon(FontAwesomeIcons.sun), findsOneWidget);
      expect(faIcon(FontAwesomeIcons.volumeLow), findsNothing);
      expect(find.text('90%'), findsOneWidget);
    });
  });

  testWidgets('fades out after the delay and then releases the window',
      (tester) async {
    await withStore((store) async {
      store.show(OsdKind.volume, 0.5);
      await pumpOsd(tester, store);

      // Partway through the exit the card is dimming, but the request — and so
      // the window — must survive until the animation has played out.
      await tester.pump(hideDelay);
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(tester), lessThan(1.0));
      expect(store.current, isNotNull);

      await tester.pump(animation);
      expect(store.current, isNull);
    });
  });

  testWidgets('a change mid-fade brings the card back rather than dropping it',
      (tester) async {
    await withStore((store) async {
      store.show(OsdKind.volume, 0.5);
      await pumpOsd(tester, store);

      await tester.pump(hideDelay);
      await tester.pump(const Duration(milliseconds: 100));
      store.show(OsdKind.brightness, 0.4);
      // One frame to restart the ticker, then long enough to finish re-entering.
      await tester.pump();
      await tester.pump(animation);

      expect(store.current?.kind, OsdKind.brightness);
      expect(opacity(tester), 1.0);
      expect(faIcon(FontAwesomeIcons.sun), findsOneWidget);
    });
  });
}
