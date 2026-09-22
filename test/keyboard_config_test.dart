import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';

/// The degradation rule at this end of the pipe: a wrongly-typed value costs
/// that one key, never the whole table — a throw out of any `fromMap` is
/// caught by `AppConfig.load`, which discards the user's entire config.
void main() {
  test('a null table is the empty default', () {
    expect(KeyboardConfig.fromMap(null).sources, isEmpty);
    expect(KeyboardConfig.fromMap(null), const KeyboardConfig());
  });

  test('reads the array of tables in order', () {
    final config = KeyboardConfig.fromMap({
      'sources': [
        {'layout': 'us'},
        {'layout': 'de', 'variant': 'nodeadkeys'},
      ],
    });
    expect(config.sources, const [
      InputSource('us'),
      InputSource('de', variant: 'nodeadkeys'),
    ]);
  });

  test('a non-list sources key costs the list, not a throw', () {
    expect(KeyboardConfig.fromMap({'sources': 'nope'}).sources, isEmpty);
    expect(KeyboardConfig.fromMap({'sources': 7}).sources, isEmpty);
  });

  test('a source with no layout is dropped, never defaulted', () {
    // There is no honest default for "which keyboard".
    final config = KeyboardConfig.fromMap({
      'sources': [
        {'variant': 'nodeadkeys'},
        {'layout': '   '},
        {'layout': 42},
        {'layout': 'us'},
      ],
    });
    expect(config.sources, const [InputSource('us')]);
  });

  test('a non-string variant is the default variant', () {
    final config = KeyboardConfig.fromMap({
      'sources': [
        {'layout': 'de', 'variant': 12},
      ],
    });
    expect(config.sources.single, const InputSource('de'));
  });

  test('exact duplicates collapse', () {
    final config = KeyboardConfig.fromMap({
      'sources': [
        {'layout': 'us'},
        {'layout': 'us', 'variant': ''},
        {'layout': 'us', 'variant': 'dvorak'},
      ],
    });
    expect(config.sources, const [
      InputSource('us'),
      InputSource('us', variant: 'dvorak'),
    ]);
  });

  test('absent and present-but-empty are different states', () {
    // The seeder depends on this: absent means "never configured here", and
    // empty means "the user removed everything".
    expect(KeyboardConfig.fromMap({}).sources, isEmpty);
    expect(KeyboardConfig.fromMap({'sources': []}).sources, isEmpty);
    expect(<String, dynamic>{}.containsKey('sources'), isFalse);
    expect(<String, dynamic>{'sources': []}.containsKey('sources'), isTrue);
  });

  test('value equality', () {
    const a = KeyboardConfig(sources: [InputSource('us')]);
    const b = KeyboardConfig(sources: [InputSource('us')]);
    const c = KeyboardConfig(sources: [InputSource('de')]);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });

  test('InputSource ids round-trip', () {
    expect(const InputSource('us').id, 'us');
    expect(const InputSource('br', variant: 'nativo').id, 'br+nativo');
    expect(InputSource.parseId('br+nativo'),
        const InputSource('br', variant: 'nativo'));
    expect(InputSource.parseId(' us '), const InputSource('us'));
    expect(InputSource.parseId('+nativo'), isNull);
    expect(InputSource.parseId('   '), isNull);
  });

  test('toMap omits an empty variant', () {
    expect(const InputSource('us').toMap(), {'layout': 'us'});
    expect(const InputSource('de', variant: 'x').toMap(), {
      'layout': 'de',
      'variant': 'x',
    });
  });
}
