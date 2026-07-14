import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:toml/toml.dart';

AppConfig _load(String toml) =>
    AppConfig.fromMap(TomlDocument.parse(toml).toMap());

void main() {
  group('CalendarConfig', () {
    test('defaults when the section is absent', () {
      final config = _load('[theme]\naccent = "#FF0000"\n');
      expect(config.calendar.google, isNull);
      expect(config.calendar.refreshMinutes, 15);
      expect(config.calendar.weekStart, DateTime.sunday);
    });

    test('reads google credentials', () {
      final config = _load('''
[calendar]
refresh_minutes = 5
week_start = "monday"

[calendar.google]
client_id = "abc.apps.googleusercontent.com"
client_secret = "sekrit"
''');
      expect(config.calendar.refreshMinutes, 5);
      expect(config.calendar.weekStart, DateTime.monday);
      expect(config.calendar.google!.isComplete, isTrue);
      expect(config.calendar.google!.clientId, 'abc.apps.googleusercontent.com');
      expect(config.calendar.google!.clientSecret, 'sekrit');
    });

    test('half-filled credentials are not complete', () {
      final config = _load('''
[calendar.google]
client_id = "abc.apps.googleusercontent.com"
''');
      expect(config.calendar.google!.isComplete, isFalse);
      expect(config.calendar.google!.clientSecret, isEmpty);
    });

    test('a whitespace-only credential is treated as absent', () {
      // Pasting into a text field very easily brings a trailing newline along.
      final config = _load('''
[calendar.google]
client_id = "  abc  "
client_secret = "   "
''');
      expect(config.calendar.google!.clientId, 'abc');
      expect(config.calendar.google!.isComplete, isFalse);
    });

    test('a non-positive refresh interval clamps to one minute', () {
      expect(_load('[calendar]\nrefresh_minutes = 0\n').calendar.refreshMinutes, 1);
      expect(_load('[calendar]\nrefresh_minutes = -5\n').calendar.refreshMinutes, 1);
    });

    test('an unknown week_start falls back to Sunday', () {
      expect(_load('[calendar]\nweek_start = "tuesday"\n').calendar.weekStart,
          DateTime.sunday);
    });
  });
}
