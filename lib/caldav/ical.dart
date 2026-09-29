// iCalendar (RFC 5545), as much of it as a task list needs: a parser that
// turns a `.ics` body into a tree of components and properties, and a writer
// that turns the tree back into text another client will read.
//
// The tree keeps *everything* it was given — properties it has no use for,
// parameters, components nobody here reads (`VALARM`, `VTIMEZONE`) — because a
// task synced from somebody's phone is theirs, and writing it back without its
// alarm or its categories would be this shell quietly editing what it did not
// understand. A caller changes the properties it owns and leaves the rest.
//
// Outside data, so the config reader's rule: a line that will not parse costs
// that line, never the file. Only text with no `VCALENDAR` in it at all is no
// calendar.
//
// Flutter-free, for `test/ical_test.dart`.

import 'dart:convert';

/// One `NAME;PARAM=value:VALUE` line.
class ICalProperty {
  ICalProperty(this.name, this.value, [Map<String, String>? params])
    : params = params ?? {};

  /// Upper-cased, as RFC 5545 names are case-insensitive.
  final String name;

  /// Parameter names upper-cased; values with their quotes removed.
  final Map<String, String> params;

  /// The value as written — still escaped, for a TEXT value. See [text].
  final String value;

  /// [value] read as TEXT: `\n`, `\,`, `\;` and `\\` unescaped.
  String get text => unescapeICalText(value);
}

/// A `BEGIN:NAME` … `END:NAME` block.
class ICalComponent {
  ICalComponent(
    this.name, {
    List<ICalProperty>? properties,
    List<ICalComponent>? children,
  }) : properties = properties ?? [],
       children = children ?? [];

  /// Upper-cased: `VCALENDAR`, `VTODO`, `VALARM`, …
  final String name;
  final List<ICalProperty> properties;
  final List<ICalComponent> children;

  /// The first property called [name], if any.
  ICalProperty? property(String name) {
    final upper = name.toUpperCase();
    for (final p in properties) {
      if (p.name == upper) return p;
    }
    return null;
  }

  /// Every property called [name].
  Iterable<ICalProperty> all(String name) {
    final upper = name.toUpperCase();
    return properties.where((p) => p.name == upper);
  }

  /// The first property called [name] read as TEXT, or null.
  String? text(String name) => property(name)?.text;

  /// Replaces every property called [name] with one of [value] — which is
  /// written as given, so a TEXT value is escaped by the caller (see
  /// [setText]). Keeps the place of the first one it replaces, so a rewritten
  /// task reads the way it was written.
  void set(String name, String value, [Map<String, String>? params]) {
    final upper = name.toUpperCase();
    final at = properties.indexWhere((p) => p.name == upper);
    properties.removeWhere((p) => p.name == upper);
    final property = ICalProperty(upper, value, params);
    if (at < 0 || at > properties.length) {
      properties.add(property);
    } else {
      properties.insert(at, property);
    }
  }

  /// [set], with [text] escaped as a TEXT value.
  void setText(String name, String text) => set(name, escapeICalText(text));

  /// Removes every property called [name].
  void remove(String name) {
    final upper = name.toUpperCase();
    properties.removeWhere((p) => p.name == upper);
  }

  /// The child components called [name].
  Iterable<ICalComponent> childrenNamed(String name) {
    final upper = name.toUpperCase();
    return children.where((c) => c.name == upper);
  }
}

/// `\n` for a newline, and `\`, `,` and `;` backslashed.
String escapeICalText(String text) => text
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll('\r\n', r'\n')
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\n');

/// The inverse of [escapeICalText]. An unknown escape keeps its character, and
/// a lone trailing backslash is kept as one.
String unescapeICalText(String value) {
  if (!value.contains(r'\')) return value;
  final out = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final c = value[i];
    if (c != r'\' || i == value.length - 1) {
      out.write(c);
      continue;
    }
    final next = value[++i];
    out.write(switch (next) {
      'n' || 'N' => '\n',
      _ => next,
    });
  }
  return out.toString();
}

/// The `VCALENDAR` in [source], or null when there is none.
///
/// Folded lines are unfolded first. A line that is not `NAME:VALUE` is dropped;
/// an `END` with no matching `BEGIN` is ignored; a component left open at the
/// end of the text is closed there.
ICalComponent? parseICalendar(String source) {
  final stack = <ICalComponent>[];
  ICalComponent? root;
  for (final line in _unfold(source)) {
    final property = _parseLine(line);
    if (property == null) continue;
    if (property.name == 'BEGIN') {
      final component = ICalComponent(property.value.trim().toUpperCase());
      if (stack.isEmpty) {
        // Anything before the calendar, or a second one after it, is not
        // part of it.
        if (root != null || component.name != 'VCALENDAR') {
          stack.add(component);
          continue;
        }
        root = component;
      } else {
        stack.last.children.add(component);
      }
      stack.add(component);
    } else if (property.name == 'END') {
      final name = property.value.trim().toUpperCase();
      final at = stack.lastIndexWhere((c) => c.name == name);
      if (at >= 0) stack.removeRange(at, stack.length);
    } else if (stack.isNotEmpty) {
      stack.last.properties.add(property);
    }
  }
  return root;
}

/// [calendar] as `.ics` text: CRLF line ends, lines folded at 75 octets.
String encodeICalendar(ICalComponent calendar) {
  final out = StringBuffer();
  void write(ICalComponent c) {
    _writeLine(out, 'BEGIN:${c.name}');
    for (final p in c.properties) {
      final line = StringBuffer(p.name);
      p.params.forEach((key, value) {
        line
          ..write(';')
          ..write(key)
          ..write('=')
          ..write(_quoteParam(value));
      });
      line
        ..write(':')
        ..write(p.value);
      _writeLine(out, line.toString());
    }
    for (final child in c.children) {
      write(child);
    }
    _writeLine(out, 'END:${c.name}');
  }

  write(calendar);
  return out.toString();
}

/// A parameter value is quoted when it holds a character that would otherwise
/// end it.
String _quoteParam(String value) {
  final clean = value.replaceAll('"', '');
  return clean.contains(RegExp('[:;,]')) ? '"$clean"' : clean;
}

/// Writes [line] folded to 75 octets a line, never inside a UTF-8 sequence.
void _writeLine(StringBuffer out, String line) {
  var octets = 0;
  for (final rune in line.runes) {
    final char = String.fromCharCode(rune);
    final size = utf8.encode(char).length;
    // A continuation line starts with the space that unfolding removes, which
    // counts towards its 75.
    if (octets + size > 75) {
      out.write('\r\n ');
      octets = 1;
    }
    out.write(char);
    octets += size;
  }
  out.write('\r\n');
}

/// The logical lines of [source]: a line starting with a space or a tab
/// continues the one before it.
List<String> _unfold(String source) {
  final lines = <String>[];
  for (final raw in source.split(RegExp(r'\r\n|\n|\r'))) {
    if (raw.isEmpty) continue;
    if ((raw.startsWith(' ') || raw.startsWith('\t')) && lines.isNotEmpty) {
      lines[lines.length - 1] += raw.substring(1);
    } else {
      lines.add(raw);
    }
  }
  return lines;
}

/// `NAME;P=v;Q="a:b":VALUE`, or null for a line that is not one.
ICalProperty? _parseLine(String line) {
  var i = 0;
  while (i < line.length && line[i] != ';' && line[i] != ':') {
    i++;
  }
  if (i == 0 || i == line.length) return null;
  final name = line.substring(0, i).trim().toUpperCase();
  if (!RegExp(r'^[A-Z0-9-]+$').hasMatch(name)) return null;
  final params = <String, String>{};
  while (i < line.length && line[i] == ';') {
    i++;
    final keyStart = i;
    while (i < line.length &&
        line[i] != '=' &&
        line[i] != ':' &&
        line[i] != ';') {
      i++;
    }
    final key = line.substring(keyStart, i).trim().toUpperCase();
    final value = StringBuffer();
    if (i < line.length && line[i] == '=') {
      i++;
      var quoted = false;
      while (i < line.length) {
        final c = line[i];
        if (c == '"') {
          quoted = !quoted;
        } else if (!quoted && (c == ';' || c == ':')) {
          break;
        } else {
          value.write(c);
        }
        i++;
      }
      // An unterminated quote swallows the value separator: not a line.
      if (quoted) return null;
    }
    if (key.isNotEmpty) params[key] = value.toString();
  }
  if (i >= line.length || line[i] != ':') return null;
  return ICalProperty(name, line.substring(i + 1), params);
}

/// A `DATE` or `DATE-TIME` value, read.
class ICalDateTime {
  const ICalDateTime(this.value, {required this.dateOnly, required this.utc});

  /// For a date, midnight local on that day. For a UTC time, the instant (in
  /// UTC). Otherwise — floating, or with a `TZID` — the wall-clock time as
  /// written, in local time: a task's due *day* is what the board keeps, and
  /// that is the day the user's own calendar wrote.
  final DateTime value;
  final bool dateOnly;
  final bool utc;

  /// The calendar day this falls on, here.
  DateTime get localDay {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}

/// [property]'s value as a date or a date-time, or null when it is neither.
ICalDateTime? parseICalDateTime(ICalProperty? property) {
  if (property == null) return null;
  final text = property.value.trim();
  final date = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(text);
  if (date != null) {
    final day = _checkedDate(date[1]!, date[2]!, date[3]!);
    return day == null ? null : ICalDateTime(day, dateOnly: true, utc: false);
  }
  final time = RegExp(
    r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$',
  ).firstMatch(text);
  if (time == null) return null;
  final day = _checkedDate(time[1]!, time[2]!, time[3]!);
  final h = int.parse(time[4]!);
  final m = int.parse(time[5]!);
  final s = int.parse(time[6]!);
  if (day == null || h > 23 || m > 59 || s > 60) return null;
  final utc = time[7] == 'Z';
  final value = utc
      ? DateTime.utc(day.year, day.month, day.day, h, m, s.clamp(0, 59))
      : DateTime(day.year, day.month, day.day, h, m, s.clamp(0, 59));
  return ICalDateTime(value, dateOnly: false, utc: utc);
}

DateTime? _checkedDate(String y, String m, String d) {
  final year = int.parse(y);
  final month = int.parse(m);
  final day = int.parse(d);
  if (month < 1 || month > 12 || day < 1) return null;
  if (day > DateTime(year, month + 1, 0).day) return null;
  return DateTime(year, month, day);
}

/// `20260929`.
String formatICalDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}'
    '${day.month.toString().padLeft(2, '0')}'
    '${day.day.toString().padLeft(2, '0')}';

/// `20260929T143000Z`: [moment] in UTC, to the second.
String formatICalUtc(DateTime moment) {
  final u = moment.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${formatICalDate(u)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}
