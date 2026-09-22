// What the widget says the Moon is doing, and when it says it.
//
// The wording is the product here, so it is pinned by title rather than by
// kind alone: "Spring tides" and "Neap tides" are the same [MoonFactKind] and
// getting them the wrong way round is the whole bug.

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/moon/moon_facts.dart';
import 'package:moonswing/moon/moon_phase.dart';

MoonReading _at(DateTime instant) => computeMoonReading(at: instant);

List<MoonFact> _factsAt(DateTime instant) => moonFacts(_at(instant));

MoonFact? _of(List<MoonFact> facts, MoonFactKind kind) {
  for (final fact in facts) {
    if (fact.kind == kind) return fact;
  }
  return null;
}

/// A full Moon: 25 January 2024, 17:54 UTC. Near apogee, and not near a node.
final DateTime _full = DateTime.utc(2024, 1, 25, 17, 54);

/// A first quarter: 18 January 2024, 03:53 UTC.
final DateTime _quarter = DateTime.utc(2024, 1, 18, 3, 53);

/// A new Moon: 11 January 2024, 11:57 UTC.
final DateTime _new = DateTime.utc(2024, 1, 11, 11, 57);

/// The full Moon of 14 November 2016 — the closest perigee syzygy since 1948.
final DateTime _supermoon = DateTime.utc(2016, 11, 14, 11, 23);

void main() {
  group('tides', () {
    test('are spring at the syzygies and neap at the quarters', () {
      expect(_of(_factsAt(_full), MoonFactKind.tides)?.title, 'Spring tides');
      expect(_of(_factsAt(_new), MoonFactKind.tides)?.title, 'Spring tides');
      expect(
        _of(_factsAt(_quarter), MoonFactKind.tides)?.title,
        'Neap tides',
      );
    });

    test('a perigee syzygy is called out as the biggest of the year', () {
      final tides = _of(_factsAt(_supermoon), MoonFactKind.tides);
      expect(tides?.title, 'Perigean spring tides');
      expect(tides?.notable, isTrue);
      expect(tides?.detail, contains('flood'));
    });

    test('between the two, they build towards the next syzygy', () {
      // Which milestone is next, not which is nearest. Four days past new the
      // Moon is still nearer to new than to the quarter, and the range is
      // nonetheless shrinking — the quarter is what it is heading for.
      expect(
        _of(_factsAt(DateTime.utc(2024, 1, 15, 12)), MoonFactKind.tides)?.title,
        'Tides easing',
      );
      expect(
        _of(_factsAt(DateTime.utc(2024, 1, 29, 12)), MoonFactKind.tides)?.title,
        'Tides easing',
      );
      // Three days out from full, and from the last quarter's other side.
      expect(
        _of(_factsAt(DateTime.utc(2024, 1, 22, 12)), MoonFactKind.tides)?.title,
        'Tides building',
      );
      expect(
        _of(_factsAt(DateTime.utc(2024, 2, 5, 12)), MoonFactKind.tides)?.title,
        'Tides building',
      );
    });
  });

  group('light', () {
    test('a full Moon is bright and bad for faint things', () {
      final facts = _factsAt(_full);
      expect(_of(facts, MoonFactKind.nightLight)?.title, 'Bright night');
      expect(_of(facts, MoonFactKind.stargazing)?.title, 'Poor for deep sky');
    });

    test('a new Moon is dark and the best week of the month for it', () {
      final facts = _factsAt(_new);
      expect(_of(facts, MoonFactKind.nightLight)?.title, 'Dark night');
      final stargazing = _of(facts, MoonFactKind.stargazing);
      expect(stargazing?.title, 'Best week for faint things');
      expect(stargazing?.notable, isTrue);
    });

    test('a quarter is neither, and says nothing about stargazing', () {
      final facts = _factsAt(_quarter);
      expect(_of(facts, MoonFactKind.nightLight)?.title, 'Moonlit');
      expect(_of(facts, MoonFactKind.stargazing), isNull);
    });
  });

  group('eclipse windows', () {
    test('the total solar eclipse of April 2024 is one', () {
      // A week out, so the eclipse is the *next* new Moon.
      final facts = _factsAt(DateTime.utc(2024, 4, 2));
      final eclipses =
          facts.where((f) => f.kind == MoonFactKind.eclipse).toList();
      expect(eclipses, hasLength(1));
      expect(eclipses.single.title, 'Solar eclipse window');
      expect(eclipses.single.detail, contains('8 Apr'));
      expect(eclipses.single.notable, isTrue);
      // Notable facts come first, and an eclipse is the most notable thing the
      // Moon does.
      expect(facts.first.kind, MoonFactKind.eclipse);
    });

    test('an eclipse season with both kinds lists the nearer one first', () {
      // March 2025: a total lunar eclipse on the 14th, a partial solar on the
      // 29th. Both syzygies fall near a node, which is what an eclipse season
      // is.
      final eclipses = _factsAt(DateTime.utc(2025, 3, 10))
          .where((f) => f.kind == MoonFactKind.eclipse)
          .toList();
      expect(eclipses, hasLength(2));
      expect(eclipses.first.title, 'Lunar eclipse window');
      expect(eclipses.last.title, 'Solar eclipse window');
    });

    test('an ordinary month has none', () {
      // January 2024: the next full Moon is 4.8° off the ecliptic and the next
      // new one 4.2°, which is most of a month either way from a node.
      final facts = _factsAt(DateTime.utc(2024, 1, 20));
      expect(_of(facts, MoonFactKind.eclipse), isNull);
    });
  });

  group('distance', () {
    test('names a supermoon and prints the figure', () {
      final distance = _of(_factsAt(_supermoon), MoonFactKind.distance);
      expect(distance?.title, 'Supermoon');
      expect(distance?.notable, isTrue);
      expect(distance?.detail, contains('356,'));
    });

    test('is an ordinary line at an ordinary distance', () {
      final distance = _of(_factsAt(_full), MoonFactKind.distance);
      expect(distance?.title, 'Distance');
      expect(distance?.notable, isFalse);
      expect(distance?.detail, contains('light-seconds'));
    });
  });

  group('the list', () {
    test('always has something to say, and always says what is next', () {
      for (final instant in [_new, _quarter, _full, _supermoon]) {
        final facts = _factsAt(instant);
        expect(facts, isNotEmpty);
        expect(_of(facts, MoonFactKind.nextPhase), isNotNull);
        expect(_of(facts, MoonFactKind.tides), isNotNull);
      }
    });

    test('puts every notable fact ahead of every ordinary one', () {
      final facts = _factsAt(_supermoon);
      final lastNotable =
          facts.lastIndexWhere((fact) => fact.notable);
      final firstOrdinary = facts.indexWhere((fact) => !fact.notable);
      expect(lastNotable, lessThan(firstOrdinary));
    });

    test('the next principal phase is named and dated', () {
      final next = _of(_factsAt(DateTime.utc(2024, 1, 20)),
          MoonFactKind.nextPhase);
      expect(next?.title, contains('Full moon'));
      expect(next?.detail, contains('25 Jan'));
    });
  });
}
