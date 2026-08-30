import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/keyboard/keyboard_short_codes.dart';
import 'package:graceful_shell/keyboard/keyboard_sources.dart';
import 'package:graceful_shell/keyboard/locale1_client.dart';
import 'package:graceful_shell/keyboard/xkb_catalog.dart';

const _us = InputSource('us');
const _de = InputSource('de');
const _deNoDead = InputSource('de', variant: 'nodeadkeys');

void main() {
  group('effectiveSource / activeSourceIndex', () {
    test('an exact pair matches', () {
      expect(
        activeSourceIndex(const [_us, _deNoDead], const Locale1Keyboard(
          layout: 'de',
          variant: 'nodeadkeys',
        )),
        1,
      );
    });

    test('an empty variant matches only the bare layout', () {
      const state = Locale1Keyboard(layout: 'de');
      expect(activeSourceIndex(const [_us, _de], state), 1);
      // Nothing fuzzier: `de` and `de+nodeadkeys` are two rows, and matching
      // one against the other lights the wrong one.
      expect(activeSourceIndex(const [_us, _deNoDead], state), -1);
    });

    test('a multi-group layout reads its first component', () {
      expect(
        activeSourceIndex(const [_us, _de], const Locale1Keyboard(
          layout: 'de,us',
        )),
        1,
      );
      expect(
        effectiveSource(const Locale1Keyboard(
          layout: 'us,de',
          variant: ',nodeadkeys',
        )),
        _us,
      );
    });

    test('a variant list shorter than the layout list is not an error', () {
      expect(
        effectiveSource(const Locale1Keyboard(layout: 'us,de', variant: '')),
        _us,
      );
    });

    test('a layout in no source answers -1, never 0', () {
      expect(
        activeSourceIndex(const [_us, _de], const Locale1Keyboard(
          layout: 'fr',
        )),
        -1,
      );
    });

    test('locale1 reporting nothing is null, not an empty source', () {
      expect(effectiveSource(const Locale1Keyboard()), isNull);
      expect(activeSourceIndex(const [_us], const Locale1Keyboard()), -1);
    });
  });

  group('seedSourcesFrom', () {
    test('zips the comma lists', () {
      expect(
        seedSourcesFrom(const Locale1Keyboard(
          layout: 'us,de',
          variant: ',nodeadkeys',
        )),
        [_us, _deNoDead],
      );
    });

    test('a missing variant component is the default variant', () {
      expect(seedSourcesFrom(const Locale1Keyboard(layout: 'us,de')), [
        _us,
        _de,
      ]);
    });

    test('duplicates collapse and nothing is empty', () {
      expect(seedSourcesFrom(const Locale1Keyboard(layout: 'us,,us')), [_us]);
      expect(seedSourcesFrom(const Locale1Keyboard()), isEmpty);
    });
  });

  group('short codes', () {
    test('the curated table answers where the country is not the language', () {
      expect(shortCodeFor('us'), 'en');
      expect(shortCodeFor('gb'), 'en');
      expect(shortCodeFor('cz'), 'cs');
      expect(shortCodeFor('latam'), 'es');
    });

    test('an unlisted layout is its own truthful identifier', () {
      expect(shortCodeFor('de'), 'de');
      expect(shortCodeFor('fr'), 'fr');
      // Never a guessed language: three characters of the xkb code.
      expect(shortCodeFor('zzzz'), 'zzz');
    });

    test('an empty layout has no code', () => expect(shortCodeFor(''), ''));

    test('collisions take an ordinal, first keeper stays bare', () {
      expect(
        assignShortCodes(const [_us, InputSource('gb'), _de, InputSource('au')]),
        ['en', 'en2', 'de', 'en3'],
      );
    });
  });

  group('rankXkbEntries', () {
    final catalog = parseXkbRulesList('''
! layout
  us              English (US)
  de              German
  gb              English (UK)

! variant
  dvorak          us: English (Dvorak)
  nodeadkeys      de: German (no dead keys)
''');

    test('an empty query keeps the catalogue order', () {
      expect(rankXkbEntries(catalog.entries, '  '), catalog.entries);
    });

    test('an exact code beats a description match', () {
      final ranked = rankXkbEntries(catalog.entries, 'de');
      expect(ranked.first.source, _de);
    });

    test('a base layout sorts above its own variants', () {
      final ranked = rankXkbEntries(catalog.entries, 'german');
      expect(ranked.map((e) => e.source.id).take(2), ['de', 'de+nodeadkeys']);
    });

    test('a word-start beats a mid-word substring', () {
      final ranked = rankXkbEntries(catalog.entries, 'english');
      expect(ranked.length, 3);
    });

    test('nothing matching answers empty rather than everything', () {
      expect(rankXkbEntries(catalog.entries, 'zzzz'), isEmpty);
    });
  });
}
