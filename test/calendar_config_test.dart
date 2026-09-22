import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/config.dart';
import 'package:toml/toml.dart';

AppConfig _load(String toml) =>
    AppConfig.fromMap(TomlDocument.parse(toml).toMap());

void main() {
  group('CalendarConfig', () {
    test('defaults when the section is absent', () {
      final config = _load('[theme]\naccent = "#FF0000"\n');
      expect(config.calendar.weekStart, DateTime.sunday);
    });

    test('reads week_start', () {
      final config = _load('[calendar]\nweek_start = "monday"\n');
      expect(config.calendar.weekStart, DateTime.monday);
    });

    test('is case-insensitive', () {
      expect(_load('[calendar]\nweek_start = "Monday"\n').calendar.weekStart,
          DateTime.monday);
    });

    test('an unknown week_start falls back to Sunday', () {
      expect(_load('[calendar]\nweek_start = "tuesday"\n').calendar.weekStart,
          DateTime.sunday);
    });
  });

  group('world clocks', () {
    test('defaults to empty', () {
      expect(_load('[calendar]\nweek_start = "monday"\n').calendar.worldClocks,
          isEmpty);
    });

    test('reads the list in document order', () {
      final clocks = _load('''
[[calendar.world_clocks]]
zone = "Europe/London"

[[calendar.world_clocks]]
zone = "Asia/Tokyo"
label = "HQ"
''').calendar.worldClocks;

      expect(clocks.map((c) => c.zone), ['Europe/London', 'Asia/Tokyo']);
      expect(clocks[0].label, isNull);
      expect(clocks[1].label, 'HQ');
    });

    test('drops entries with no zone, keeping the rest', () {
      final clocks = _load('''
[[calendar.world_clocks]]
label = "Nowhere"

[[calendar.world_clocks]]
zone = "   "

[[calendar.world_clocks]]
zone = "Asia/Tokyo"
''').calendar.worldClocks;

      expect(clocks.map((c) => c.zone), ['Asia/Tokyo']);
    });

    test('an unknown zone name is preserved rather than dropped', () {
      // The database is not consulted here — dropping it would delete the
      // user's row the next time anything writes the config back.
      final clocks =
          _load('[[calendar.world_clocks]]\nzone = "Nowhere/Nothing"\n')
              .calendar
              .worldClocks;
      expect(clocks.single.zone, 'Nowhere/Nothing');
    });

    test('a wrongly typed list degrades to empty without throwing', () {
      final config = _load('[calendar]\nworld_clocks = "Asia/Tokyo"\n');
      expect(config.calendar.worldClocks, isEmpty);
      // The rest of the config survived, which is the point of type-testing.
      expect(config.calendar.weekStart, DateTime.sunday);
    });

    test('an empty label is treated as unset', () {
      final clock = _load(
        '[[calendar.world_clocks]]\nzone = "Asia/Tokyo"\nlabel = "  "\n',
      ).calendar.worldClocks.single;
      expect(clock.label, isNull);
    });

    test('toMap omits an unset label', () {
      expect(const WorldClock(zone: 'Asia/Tokyo').toMap(),
          {'zone': 'Asia/Tokyo'});
      expect(const WorldClock(zone: 'Asia/Tokyo', label: 'HQ').toMap(),
          {'zone': 'Asia/Tokyo', 'label': 'HQ'});
    });
  });
}
