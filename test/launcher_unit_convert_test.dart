import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/launcher/unit_convert.dart';

/// `1 kg = 2.20462 lb, 35.274 oz` — the whole row as one string, which is what
/// makes the peer *choice* and its *order* readable in an expectation.
String _render(String query) {
  final conversion = convertQuery(query);
  if (conversion == null) return 'none';
  final results = conversion.results.map(formatQuantity).join(', ');
  return '${formatQuantity(conversion.input)} = $results';
}

void main() {
  group('convertQuery', () {
    test('a bare quantity is answered in its dimension', () {
      expect(_render('1kg'),
          '1 kg = 2.20462 lb, 35.274 oz, 0.157473 st, 1000 g');
      expect(_render('72f'), '72 °F = 22.2222 °C, 295.372 K');
      expect(_render('1 mi'), '1 mi = 1.60934 km, 1609.34 m, 1760 yd, 5280 ft');
    });

    test('a space between the number and the unit is optional', () {
      expect(_render('2.5kg'), _render('2.5 kg'));
      expect(_render('-40f'), _render('-40 °F'));
    });

    test('a named target is answered on its own', () {
      expect(_render('5 km to mi'), '5 km = 3.10686 mi');
      expect(_render('10 mi in km'), '10 mi = 16.0934 km');
      expect(_render('1 kg into lbs'), '1 kg = 2.20462 lb');
      expect(_render('100 c as f'), '100 °C = 212 °F');
    });

    test('inch survives being spelled like the keyword', () {
      // `in` is both a conversion keyword and inch's symbol, so the split is
      // tried over whole tokens from the right until both halves parse.
      expect(_render('5 in in cm'), '5 in = 12.7 cm');
      expect(_render('5 cm in in'), '5 cm = 1.9685 in');
      expect(_render('5 in'), startsWith('5 in = '));
    });

    test('a target in another dimension is not a conversion', () {
      expect(convertQuery('1 kg to m'), isNull);
      expect(convertQuery('2 to 3'), isNull);
    });

    test('an app search never turns into a conversion', () {
      // Every one of these starts with a digit or ends in something that looks
      // like a unit, which is exactly the shape the gate has to refuse.
      for (final query in [
        'gimp', 'firefox', 'libreoffice', '', '42', '0.5', 'kg',
        '7zip', '1password', 'i3', 'k3b', 'x11-utils', 'gtk2-engines',
        'python3', '2 apps', '5 apps in dock', '3d', '10k', '2+2',
      ]) {
        expect(convertQuery(query), isNull, reason: query);
      }
    });

    test('the calculator and the converter cannot both fire', () {
      // A conversion carries no operator and `looksLikeExpression` demands one,
      // so the two gates are disjoint by construction rather than by ordering.
      expect(convertQuery('2+2'), isNull);
      expect(convertQuery('5 km/h'), isNotNull);
    });
  });

  group('peer choice', () {
    test('a peer from another system comes first', () {
      final peers = peersFor(parseQuantity('1 kg')!);
      expect(peers.first.unit.id, 'pound');
      expect(peers.map((p) => p.unit.system).toList(),
          [UnitSystem.imperial, UnitSystem.imperial, UnitSystem.imperial,
            UnitSystem.metric]);
    });

    test('a conversion nobody can read is dropped', () {
      // `1 mm` is 0.00000062 miles, which is the row spending a quarter of
      // itself saying "very small".
      final peers = peersFor(parseQuantity('1 mm')!);
      expect(peers.map((p) => p.unit.id), ['inch', 'centimetre']);
    });

    test('but the row is never empty', () {
      // Everything a picoscale quantity converts to is unreadable; the least
      // unreadable of them is still worth more than nothing.
      final millimetre = parseQuantity('1 mm')!.unit;
      final peers = peersFor(Quantity(1e-9, millimetre));
      expect(peers, isNotEmpty);
    });

    test('a value under 1 ranks below a large one', () {
      // Three hours is 180 minutes and 0.125 days — the same decade and a half
      // from 1, and only one of them is a number somebody says out loud.
      final peers = peersFor(parseQuantity('3 h')!);
      expect(peers.first.unit.id, 'minute');
    });

    test('temperature keeps its declared order', () {
      // The magnitude rule would throw away the freezing point of water for
      // being too near zero.
      expect(_render('0c'), '0 °C = 32 °F, 273.15 K');
      expect(peersFor(parseQuantity('0 c')!).map((p) => p.unit.id),
          ['fahrenheit', 'kelvin']);
    });

    test('a specialist unit is offered only when it is asked for', () {
      // A knot is the nearest-to-human-sized peer of a speed and the wrong
      // first line of one.
      expect(peersFor(parseQuantity('100 kph')!).map((p) => p.unit.id),
          isNot(contains('knot')));
      expect(_render('100 kph in knots'), '100 km/h = 53.9957 kn');
      expect(_render('90 deg'), '90 ° = 1.5708 rad');
    });

    test('at most four peers', () {
      for (final query in ['1 m', '1 L', '1 s', '1 GB', '1 kg']) {
        expect(peersFor(parseQuantity(query)!).length,
            lessThanOrEqualTo(kUnitPeerLimit),
            reason: query);
      }
    });
  });

  group('the table', () {
    test('no alias is claimed twice', () {
      // A collision is silent: one of the two units simply stops being
      // reachable, and which one depends on table order.
      final seen = <String, String>{};
      for (final unit in kConvertibleUnits) {
        for (final alias in [...unit.aliases, ...unit.exactAliases]) {
          expect(seen[alias], isNull,
              reason: '$alias is both ${seen[alias]} and ${unit.id}');
          seen[alias] = unit.id;
        }
      }
    });

    test('every unit round-trips through its own base', () {
      // A factor of zero or a typo'd offset shows up here and nowhere else:
      // every other test names a handful of units, and the table has eighty.
      for (final unit in kConvertibleUnits) {
        expect(unit.fromBase(unit.toBase(3.5)), closeTo(3.5, 1e-9),
            reason: unit.id);
        expect(unit.factor, isNot(0), reason: unit.id);
      }
    });

    test('every unit is reachable by its own symbol or a spelled alias', () {
      for (final unit in kConvertibleUnits) {
        expect(unitForToken(unit.aliases.first)?.id, unit.id);
      }
    });

    test('kelvin is spelled with a capital, so `10k` stays a number', () {
      expect(unitForToken('K')?.id, 'kelvin');
      expect(unitForToken('kelvin')?.id, 'kelvin');
      expect(unitForToken('k'), isNull);
      expect(convertQuery('10k'), isNull);
    });

    test('whitespace inside a unit does not matter', () {
      expect(unitForToken('fl oz')?.id, 'fluid-ounce');
      expect(unitForToken('sq ft')?.id, 'square-foot');
      expect(unitForToken('km / h')?.id, 'kilometres-per-hour');
    });
  });

  group('formatQuantityValue', () {
    test('six significant figures, not the calculator’s twelve', () {
      expect(formatQuantityValue(2.2046226218487757), '2.20462');
      expect(formatQuantityValue(3280.8398950131235), '3280.84');
    });

    test('exact integers print in full, and long ones are grouped', () {
      expect(formatQuantityValue(1000), '1000');
      expect(formatQuantityValue(1609344), '1,609,344');
      expect(formatQuantityValue(-16404.2), '-16,404.2');
    });

    test('exponent form is left unbroken', () {
      expect(formatQuantityValue(1.2e-9), '1.2e-9');
    });
  });
}
