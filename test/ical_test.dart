import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/caldav/ical.dart';

const String _task =
    'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'PRODID:-//Example//Tasks//EN\r\n'
    'BEGIN:VTODO\r\n'
    'UID:abc-123\r\n'
    'SUMMARY:Buy milk\\, eggs\\; bread\r\n'
    'DESCRIPTION:Line one\\nLine two with a long tail that goes on and on and \r\n'
    ' on past the fold\r\n'
    'DUE;TZID=Europe/London:20260930T170000\r\n'
    'X-OTHER-APP;X-PARAM="a:b":kept\r\n'
    'CATEGORIES:home,errands\r\n'
    'this line is not a property\r\n'
    'BEGIN:VALARM\r\n'
    'ACTION:DISPLAY\r\n'
    'TRIGGER:-PT15M\r\n'
    'END:VALARM\r\n'
    'END:VTODO\r\n'
    'END:VCALENDAR\r\n';

void main() {
  test('parses components, unfolds lines and unescapes text', () {
    final cal = parseICalendar(_task)!;
    expect(cal.name, 'VCALENDAR');
    final todo = cal.childrenNamed('VTODO').single;
    expect(todo.text('SUMMARY'), 'Buy milk, eggs; bread');
    expect(
      todo.text('DESCRIPTION'),
      'Line one\nLine two with a long tail that goes on and on and on past '
      'the fold',
    );
    expect(todo.property('X-OTHER-APP')!.params, {'X-PARAM': 'a:b'});
    expect(todo.childrenNamed('VALARM').single.text('TRIGGER'), '-PT15M');
  });

  test('a line that is not a property costs that line only', () {
    final todo = parseICalendar(_task)!.childrenNamed('VTODO').single;
    expect(todo.properties.map((p) => p.name), [
      'UID',
      'SUMMARY',
      'DESCRIPTION',
      'DUE',
      'X-OTHER-APP',
      'CATEGORIES',
    ]);
  });

  test('text with no calendar is none', () {
    expect(parseICalendar(''), isNull);
    expect(parseICalendar('<html>Not found</html>'), isNull);
    expect(parseICalendar('BEGIN:VCARD\nFN:x\nEND:VCARD\n'), isNull);
  });

  test('writing back keeps what it did not change', () {
    final cal = parseICalendar(_task)!;
    final todo = cal.childrenNamed('VTODO').single;
    todo.setText('SUMMARY', 'Buy oat milk');
    final again = parseICalendar(encodeICalendar(cal))!;
    final t = again.childrenNamed('VTODO').single;
    expect(t.text('SUMMARY'), 'Buy oat milk');
    expect(t.text('CATEGORIES'), 'home,errands');
    expect(t.property('X-OTHER-APP')!.params['X-PARAM'], 'a:b');
    expect(t.property('DUE')!.params['TZID'], 'Europe/London');
    expect(t.childrenNamed('VALARM'), hasLength(1));
    // Rewriting a property keeps its place.
    expect(t.properties.map((p) => p.name).take(2), ['UID', 'SUMMARY']);
  });

  test('folds at 75 octets without splitting a character', () {
    final cal = ICalComponent('VCALENDAR')..setText('SUMMARY', 'é' * 100);
    final text = encodeICalendar(cal);
    for (final line in text.split('\r\n')) {
      expect(utf8.encode(line).length, lessThanOrEqualTo(75));
    }
    expect(parseICalendar(text)!.text('SUMMARY'), 'é' * 100);
  });

  test('escapes round-trip', () {
    const text = 'a\\b, c; d\ne';
    expect(unescapeICalText(escapeICalText(text)), text);
  });

  test('reads dates and date-times', () {
    ICalDateTime? read(String line) {
      final cal = parseICalendar('BEGIN:VCALENDAR\n$line\nEND:VCALENDAR\n')!;
      return parseICalDateTime(cal.properties.single);
    }

    final date = read('DUE;VALUE=DATE:20260930')!;
    expect(date.dateOnly, isTrue);
    expect(date.localDay, DateTime(2026, 9, 30));

    final floating = read('DUE;TZID=Europe/London:20260930T170000')!;
    expect(floating.utc, isFalse);
    expect(floating.localDay, DateTime(2026, 9, 30));

    final utc = read('DUE:20260930T120000Z')!;
    expect(utc.utc, isTrue);
    expect(utc.value, DateTime.utc(2026, 9, 30, 12));

    expect(read('DUE:20260230'), isNull);
    expect(read('DUE:tomorrow'), isNull);
  });

  test('formats dates', () {
    expect(formatICalDate(DateTime(2026, 1, 5)), '20260105');
    expect(
      formatICalUtc(DateTime.utc(2026, 1, 5, 7, 8, 9)),
      '20260105T070809Z',
    );
  });
}
