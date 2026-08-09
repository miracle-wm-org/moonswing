import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
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
}
