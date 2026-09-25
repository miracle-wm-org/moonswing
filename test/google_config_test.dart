import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/google/google_config.dart';

void main() {
  group('toggleCalendar', () {
    const primaries = ['me@example.com', 'me@work.example'];

    List<String> toggle(
      List<String> selected,
      String id, {
      required bool on,
      bool primary = false,
    }) => toggleCalendar(
      selected,
      id: id,
      primary: primary,
      on: on,
      primaries: primaries,
    );

    test('an ordinary calendar comes and goes by its id', () {
      expect(toggle(['primary'], 'team', on: true), ['primary', 'team']);
      expect(toggle(['primary', 'team'], 'team', on: false), ['primary']);
      expect(toggle(['primary', 'team'], 'team', on: true), [
        'primary',
        'team',
      ]);
    });

    test('one primary off spells the others out, and back on folds them', () {
      final off = toggle(
        ['primary', 'team'],
        'me@work.example',
        on: false,
        primary: true,
      );
      expect(off, ['me@example.com', 'team']);
      expect(
        isCalendarSelected(off, id: 'me@work.example', primary: true),
        isFalse,
      );
      expect(
        isCalendarSelected(off, id: 'me@example.com', primary: true),
        isTrue,
      );
      expect(toggle(off, 'me@work.example', on: true, primary: true), [
        'primary',
        'team',
      ]);
    });

    test('with one account it reads as it always did', () {
      List<String> single(List<String> s, {required bool on}) => toggleCalendar(
        s,
        id: 'me@example.com',
        primary: true,
        on: on,
        primaries: const ['me@example.com'],
      );
      expect(single(['primary', 'team'], on: false), ['team']);
      expect(single(['team'], on: true), ['team', 'primary']);
    });
  });
}
