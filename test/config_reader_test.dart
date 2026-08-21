import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config_reader.dart';

/// The readers' one job is that nothing a hand-edited TOML file contains can
/// throw — a throw out of a `fromMap` costs the user their whole config.
void main() {
  group('stringOr', () {
    test('right type', () {
      expect({'k': 'v'}.stringOr('k', 'd'), 'v');
    });
    test('wrong types and missing fall back', () {
      expect(<String, dynamic>{'k': 3}.stringOr('k', 'd'), 'd');
      expect(<String, dynamic>{'k': true}.stringOr('k', 'd'), 'd');
      expect(<String, dynamic>{}.stringOr('k', 'd'), 'd');
    });
  });

  group('stringOrNull', () {
    test('trims, and empty means null', () {
      expect({'k': ' v '}.stringOrNull('k'), 'v');
      expect({'k': '   '}.stringOrNull('k'), isNull);
      expect(<String, dynamic>{'k': 3}.stringOrNull('k'), isNull);
      expect(<String, dynamic>{}.stringOrNull('k'), isNull);
    });
  });

  group('intOr', () {
    test('int and float both land as int', () {
      expect(<String, dynamic>{'k': 32}.intOr('k', 0), 32);
      expect(<String, dynamic>{'k': 32.0}.intOr('k', 0), 32);
      expect(<String, dynamic>{'k': 32.9}.intOr('k', 0), 32);
    });
    test('wrong type, NaN and infinity fall back', () {
      expect(<String, dynamic>{'k': '32'}.intOr('k', 7), 7);
      expect(<String, dynamic>{'k': double.nan}.intOr('k', 7), 7);
      expect(<String, dynamic>{'k': double.infinity}.intOr('k', 7), 7);
      expect(<String, dynamic>{}.intOr('k', 7), 7);
    });
    test('clamps', () {
      expect(<String, dynamic>{'k': -5}.intOr('k', 0, min: 1), 1);
      expect(<String, dynamic>{'k': 900}.intOr('k', 0, max: 60), 60);
    });
  });

  group('doubleOr', () {
    test('float and int both land as double', () {
      expect(<String, dynamic>{'k': 1.5}.doubleOr('k', 0), 1.5);
      expect(<String, dynamic>{'k': 2}.doubleOr('k', 0), 2.0);
    });
    test('wrong type, NaN and infinity fall back', () {
      expect(<String, dynamic>{'k': 'x'}.doubleOr('k', 3.5), 3.5);
      expect(<String, dynamic>{'k': double.nan}.doubleOr('k', 3.5), 3.5);
      expect(
          <String, dynamic>{'k': double.negativeInfinity}.doubleOr('k', 3.5),
          3.5);
    });
    test('clamps', () {
      expect(<String, dynamic>{'k': -1.0}.doubleOr('k', 0, min: 0.0), 0.0);
      expect(<String, dynamic>{'k': 999.0}.doubleOr('k', 0, max: 100.0), 100.0);
    });
  });

  group('boolOr', () {
    test('bool passes, anything else falls back', () {
      expect(<String, dynamic>{'k': false}.boolOr('k', true), isFalse);
      expect(<String, dynamic>{'k': 1}.boolOr('k', true), isTrue);
      expect(<String, dynamic>{'k': 'true'}.boolOr('k', false), isFalse);
      expect(<String, dynamic>{}.boolOr('k', true), isTrue);
    });
  });

  group('stringListOr', () {
    test('keeps strings, drops the rest, preserves order', () {
      expect(
          <String, dynamic>{
            'k': ['a', 3, 'b', true, 'c']
          }.stringListOr('k'),
          ['a', 'b', 'c']);
      expect(<String, dynamic>{'k': 'a'}.stringListOr('k'), isEmpty);
      expect(<String, dynamic>{}.stringListOr('k', ['d']), ['d']);
    });
  });

  group('tableOrNull / tableListOr', () {
    test('table', () {
      expect(<String, dynamic>{
        'k': <String, dynamic>{'a': 1}
      }.tableOrNull('k'), {'a': 1});
      expect(<String, dynamic>{'k': 3}.tableOrNull('k'), isNull);
      expect(<String, dynamic>{}.tableOrNull('k'), isNull);
    });
    test('array of tables keeps tables only, in order', () {
      final list = <String, dynamic>{
        'k': [
          <String, dynamic>{'a': 1},
          3,
          <String, dynamic>{'b': 2},
        ]
      }.tableListOr('k');
      expect(list, [
        {'a': 1},
        {'b': 2}
      ]);
      expect(<String, dynamic>{'k': 'x'}.tableListOr('k'), isEmpty);
    });
  });
}
