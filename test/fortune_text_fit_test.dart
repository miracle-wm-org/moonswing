// How big a fortune is set: measured against the box, never counted in
// characters.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/fortune/fortune_text_fit.dart';

const TextStyle _style = TextStyle(fontFamily: 'Roboto');

void main() {
  // `TextPainter` needs a binding, and nothing else — no widget tree, no
  // canvas. That is the whole point of keeping this a function.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fitFortuneText', () {
    test('takes the largest rung a short fortune fits on', () {
      final fit = fitFortuneText(
        text: 'Yes.',
        style: _style,
        box: const Size(400, 300),
      );

      expect(fit.fontSize, kFortuneTextSizes.first);
      // The line count is what the fortune actually takes, so the cap never
      // bites — see [FortuneTextFit.maxLines] for why it is never null.
      expect(fit.maxLines, 1);
    });

    test('caps at the lines a fitting fortune takes, never at null', () {
      // A `Text` with an ellipsis and no `maxLines` collapses to one line, so
      // "it all fits" must still name a number.
      final fit = fitFortuneText(
        text: 'One two three four five six seven eight nine ten eleven twelve',
        style: _style,
        box: const Size(160, 300),
      );

      expect(fit.maxLines, greaterThan(1));
    });

    test('steps down until a long fortune fits', () {
      const long = 'You will be surprised by a visitor who arrives before you '
          'have finished reading this, and again by the one who follows.';

      final roomy = fitFortuneText(
        text: long,
        style: _style,
        box: const Size(400, 300),
      );
      final tight = fitFortuneText(
        text: long,
        style: _style,
        box: const Size(180, 90),
      );

      expect(tight.fontSize, lessThan(roomy.fontSize));
      expect(kFortuneTextSizes, contains(tight.fontSize));
    });

    test('ellipsises rather than shrinking past the floor', () {
      // A fortune set at 7px is not a fortune that was shown to anybody.
      final fit = fitFortuneText(
        text: 'A very long fortune. ' * 40,
        style: _style,
        box: const Size(120, 50),
      );

      expect(fit.fontSize, kFortuneTextSizes.last);
      expect(fit.maxLines, greaterThanOrEqualTo(1));
    });

    test('never asks for zero lines in a box smaller than one', () {
      final fit = fitFortuneText(
        text: 'Anything at all',
        style: _style,
        box: const Size(60, 4),
      );

      expect(fit.maxLines, 1);
    });

    test('grows the whole ladder with the card', () {
      final small = fitFortuneText(
        text: 'Fortune favours the bold.',
        style: _style,
        box: const Size(200, 60),
      );
      final large = fitFortuneText(
        text: 'Fortune favours the bold.',
        style: _style,
        box: const Size(400, 120),
        scale: 2,
      );

      expect(large.fontSize, greaterThan(small.fontSize));
    });

    test('caps the size however large the card is', () {
      // A four-word fortune on a 6x4 card would otherwise come out as a poster.
      final fit = fitFortuneText(
        text: 'Soon.',
        style: _style,
        box: const Size(900, 600),
        scale: 4,
      );

      expect(fit.fontSize, kFortuneMaxFontSize);
    });

    test('answers for an empty box without dividing by it', () {
      final fit = fitFortuneText(
        text: 'Something',
        style: _style,
        box: Size.zero,
      );

      expect(fit.fontSize, kFortuneTextSizes.last);
      expect(fit.maxLines, 1);
    });

    test('answers for empty text', () {
      final fit = fitFortuneText(
        text: '',
        style: _style,
        box: const Size(300, 200),
      );

      expect(fit.maxLines, 1);
    });
  });
}
