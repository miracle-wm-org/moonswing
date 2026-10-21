import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/theme/font_face_warmer.dart';

const _style = TextStyle(fontSize: 13);

void main() {
  testWidgets('lays a requested family out after the frame, then tells it', (
    tester,
  ) async {
    final laidOut = <String>[];
    final warmer = FontFaceWarmer(layout: (span, _) => laidOut.add(span.text!));
    var told = 0;

    warmer.request('Cantarell', _style, TextScaler.noScaling, () => told++);
    expect(laidOut, isEmpty, reason: 'nothing is laid out inside the request');
    expect(warmer.isWarm('Cantarell'), isFalse);

    await tester.pump();

    expect(laidOut, ['Cantarell']);
    expect(told, 1);
    expect(warmer.isWarm('Cantarell'), isTrue);

    // Already warm: nothing queued, nobody told again.
    warmer.request('Cantarell', _style, TextScaler.noScaling, () => told++);
    await tester.pump();
    expect(laidOut, ['Cantarell']);
    expect(told, 1);
  });

  testWidgets('a family withdrawn before its turn is never laid out', (
    tester,
  ) async {
    final laidOut = <String>[];
    final warmer = FontFaceWarmer(layout: (span, _) => laidOut.add(span.text!));
    void scrolledPast() {}
    var told = 0;

    warmer.request('Noto Sans CJK', _style, TextScaler.noScaling, scrolledPast);
    warmer.request('Ubuntu Sans', _style, TextScaler.noScaling, () => told++);
    warmer.cancel('Noto Sans CJK', scrolledPast);
    await tester.pump();

    expect(laidOut, ['Ubuntu Sans']);
    expect(told, 1);
    expect(warmer.isWarm('Noto Sans CJK'), isFalse);
  });

  testWidgets(
    'a spent budget leaves the rest for the next frame, oldest first',
    (tester) async {
      final laidOut = <String>[];
      // Zero budget: exactly one family per frame, the floor that keeps a slow
      // face progressing.
      final warmer = FontFaceWarmer(
        budget: Duration.zero,
        layout: (span, _) => laidOut.add(span.text!),
      );
      for (final family in ['A', 'B', 'C']) {
        warmer.request(family, _style, TextScaler.noScaling, () {});
      }

      await tester.pump();
      expect(laidOut, ['A']);
      await tester.pump();
      expect(laidOut, ['A', 'B']);
      await tester.pump();
      expect(laidOut, ['A', 'B', 'C']);

      // Drained: no frame is asked for once the queue is empty.
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets('lays out the text and scale the row will draw', (tester) async {
    TextSpan? span;
    TextScaler? scaler;
    final warmer = FontFaceWarmer(
      layout: (s, t) {
        span = s;
        scaler = t;
      },
    );
    const style = TextStyle(fontSize: 13, fontFamily: 'JetBrains Mono');
    const scale = TextScaler.linear(1.5);

    warmer.request('JetBrains Mono', style, scale, () {});
    await tester.pump();

    expect(span?.text, 'JetBrains Mono');
    expect(span?.style, style);
    expect(scaler, scale);
  });
}
