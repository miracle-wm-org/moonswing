import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/keyboard/keyboard_sources.dart';
import 'package:graceful_shell/keyboard/xkb_catalog.dart';

/// Pins the `base.lst` parse. Pure — there is no filesystem behind any of this,
/// which is the whole reason [parseXkbRulesList] is separate from
/// [XkbCatalogReader].
const String _kSample = '''
! model
  pc105           Generic 105-key PC
  apple           Apple

! layout
  us              English (US)
  de              German
  br              Portuguese (Brazil)
  pt              Portuguese
  rs              Serbian

! variant
  dvorak          us: English (Dvorak)
  nodeadkeys      de: German (no dead keys)
  nativo          br: Portuguese (Brazil, Nativo)
  nativo          pt: Portuguese (Nativo)
  latinalternatequotes rs: Serbian (Latin, with guillemets)

! option
  grp:alt_shift_toggle  Alt+Shift
''';

void main() {
  group('parseXkbRulesList', () {
    test('reads the layout and variant sections', () {
      final catalog = parseXkbRulesList(_kSample);
      expect(catalog.layouts.length, 5);
      expect(catalog.layoutFor('us')?.description, 'English (US)');
      expect(catalog.variants.length, 5);
      expect(
        catalog.variantFor('de', 'nodeadkeys')?.description,
        'German (no dead keys)',
      );
    });

    test('ignores every section but layout and variant', () {
      final catalog = parseXkbRulesList(_kSample);
      // `pc105` and `grp:alt_shift_toggle` are in the file and must not have
      // been read as layouts.
      expect(catalog.layoutFor('pc105'), isNull);
      expect(catalog.layoutFor('apple'), isNull);
      expect(catalog.layoutFor('grp:alt_shift_toggle'), isNull);
    });

    test('an ! include header is a header, not data', () {
      final catalog = parseXkbRulesList('''
! layout
  us              English (US)

! include %S/base.lst
  bogus           Not a layout

! layout
  de              German
''');
      expect(catalog.layoutFor('bogus'), isNull);
      expect(catalog.layouts.map((l) => l.code), ['us', 'de']);
    });

    test('the code column is not fixed width', () {
      final catalog = parseXkbRulesList(_kSample);
      final variant = catalog.variantFor('rs', 'latinalternatequotes');
      expect(variant?.description, 'Serbian (Latin, with guillemets)');
    });

    test('a variant code is keyed on its layout, not on itself', () {
      final catalog = parseXkbRulesList(_kSample);
      expect(
        catalog.variantFor('br', 'nativo')?.description,
        'Portuguese (Brazil, Nativo)',
      );
      expect(
        catalog.variantFor('pt', 'nativo')?.description,
        'Portuguese (Nativo)',
      );
    });

    test('malformed rows cost themselves and nothing else', () {
      final catalog = parseXkbRulesList('''
! layout
  us              English (US)
  lonely
  de              German

! variant
  broken          no colon here
  ok              de: German (ok)
  spaced          two words: German (spaced)
''');
      expect(catalog.layouts.map((l) => l.code), ['us', 'de']);
      expect(catalog.variants.length, 1);
      expect(catalog.variantFor('de', 'ok')?.description, 'German (ok)');
    });

    test('empty input is an empty catalog, not a throw', () {
      expect(parseXkbRulesList('').isEmpty, isTrue);
      expect(parseXkbRulesList('\n\n   \n').isEmpty, isTrue);
    });

    test('entries put each layout above its own variants', () {
      final catalog = parseXkbRulesList(_kSample);
      final ids = [for (final e in catalog.entries) e.source.id];
      expect(ids.indexOf('br'), lessThan(ids.indexOf('br+nativo')));
      expect(ids.indexOf('us'), lessThan(ids.indexOf('us+dvorak')));
      expect(ids.length, 10);
    });
  });

  group('describeSource', () {
    final catalog = parseXkbRulesList(_kSample);

    test('a variant description is used verbatim', () {
      // Never concatenated onto the layout's: the variant's own text already
      // carries the language.
      expect(
        describeSource(catalog, const InputSource('br', variant: 'nativo')),
        'Portuguese (Brazil, Nativo)',
      );
    });

    test('a bare layout gets the layout description', () {
      expect(describeSource(catalog, const InputSource('de')), 'German');
    });

    test('an unknown layout falls back to its xkb spelling', () {
      expect(describeSource(catalog, const InputSource('zz')), 'zz');
      expect(
        describeSource(catalog, const InputSource('zz', variant: 'qq')),
        'zz+qq',
      );
    });

    test('an unknown variant on a known layout keeps both', () {
      expect(
        describeSource(catalog, const InputSource('de', variant: 'nope')),
        'German (nope)',
      );
    });
  });

  group('XkbCatalogReader', () {
    test('takes the first candidate that parses to something', () async {
      final tried = <String>[];
      final reader = XkbCatalogReader(
        paths: const ['/a', '/b'],
        reader: (path) async {
          tried.add(path);
          return path == '/b' ? _kSample : null;
        },
      );
      final catalog = await reader.load();
      expect(tried, ['/a', '/b']);
      expect(catalog.layoutFor('us'), isNotNull);
    });

    test('memoises the future, so racing callers share one read', () async {
      var reads = 0;
      final reader = XkbCatalogReader(
        paths: const ['/a'],
        reader: (_) async {
          reads++;
          return _kSample;
        },
      );
      final results = await Future.wait([reader.load(), reader.load()]);
      expect(reads, 1);
      expect(identical(results[0], results[1]), isTrue);
    });

    test('a machine with no xkb-data yields an empty catalogue', () async {
      final reader = XkbCatalogReader(
        paths: const ['/a'],
        reader: (_) async => throw const FileSystemException('nope'),
      );
      expect((await reader.load()).isEmpty, isTrue);
    });
  });
}
