// `[astrology]`, as a typed object.
//
// Beside the store rather than in the widget, the way `weather_config.dart` and
// `system/system_monitor_config.dart` sit beside theirs.
//
// It is a **top-level** section rather than `[modules.astrology]` because there
// is no bar module: the birthday is the machine's one answer to one question,
// and `[[desktop.widgets]] options` — the other candidate — is per instance, so
// two cards on two monitors could disagree about whose desktop this is. The
// section is read straight out of `ConfigStore` by the store that wants it and
// is deliberately *not* an `AppConfig` field: `AppConfig` is what `main()`
// reads before the first frame to size native windows, and nothing about a
// birthday does that. `[calendar]`'s week start is the nearest precedent and
// `ThemeStore` watching `ConfigStore` for the `theme` key alone is the exact
// shape.

import 'package:graceful_shell/astrology/horoscope_api.dart';
import 'package:graceful_shell/astrology/zodiac.dart';
import 'package:graceful_shell/config_reader.dart';

/// The years a birthday may fall in.
///
/// Not taste: `sunPosition` is Meeus's low-accuracy solar series, good to about
/// 0.01° across the centuries either side of J2000 and drifting outside them.
/// A birthday in the year 12 is a mistyped one, and answering it with a sign
/// computed from a series that no longer holds would be answering it wrongly
/// rather than refusing.
const int kEarliestBirthYear = 1600;
const int kLatestBirthYear = 2400;

class AstrologyConfig {
  const AstrologyConfig({
    this.birthday,
    this.period = 'daily',
    this.refreshMinutes = 180,
    this.apiBase = kDefaultHoroscopeApiBase,
  });

  /// The date the user was born, at local midnight, or null when they have not
  /// said. Only the date part is ever read — see [zodiacReadingFor].
  final DateTime? birthday;

  /// `daily`, `weekly` or `monthly`; anything else reads as daily.
  final String period;

  /// How often the horoscope is re-fetched, in minutes.
  ///
  /// Three hours by default, and floored per period by
  /// [HoroscopePeriod.minimumInterval] — see [refreshInterval]. A horoscope is
  /// not a reading of anything that moves, so the only thing a refresh buys is
  /// crossing midnight without the card still showing yesterday's; asking more
  /// often than that is spending somebody else's free deployment on a paragraph
  /// that has not changed.
  final int refreshMinutes;

  /// Which server to ask. The public instance by default; anybody may run the
  /// MIT-licensed one themselves and point this at it, which is the whole
  /// reason it is a key.
  final String apiBase;

  HoroscopePeriod get horoscopePeriod => HoroscopePeriod.parse(period);

  /// The sign the birthday falls in, with its cusp neighbour when there is one.
  /// Null when no birthday is configured, which is the widget's one actionable
  /// empty state.
  ZodiacReading? get reading {
    final day = birthday;
    return day == null ? null : zodiacReadingFor(day);
  }

  ZodiacSign? get sign => reading?.sign;

  /// The poll period actually used: the configured one, never shorter than the
  /// floor the chosen period sets.
  Duration get refreshInterval {
    final configured = Duration(minutes: refreshMinutes);
    final floor = horoscopePeriod.minimumInterval;
    return configured < floor ? floor : configured;
  }

  factory AstrologyConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const AstrologyConfig();
    return AstrologyConfig(
      birthday: parseBirthday(map['birthday']),
      period: map.stringOr('period', 'daily'),
      // Bounded like the weather's: this is a timer period, and
      // `refresh_minutes = 0` is a tight loop against somebody's free API.
      refreshMinutes: map.intOr('refresh_minutes', 180, min: 1, max: 10080),
      apiBase: map.stringOrNull('api_base') ?? kDefaultHoroscopeApiBase,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AstrologyConfig &&
          other.birthday == birthday &&
          other.period == period &&
          other.refreshMinutes == refreshMinutes &&
          other.apiBase == apiBase;

  @override
  int get hashCode => Object.hash(birthday, period, refreshMinutes, apiBase);
}

/// A `birthday` value, whatever shape it arrived in, as local midnight on that
/// date — or null when it is not a date this build will act on.
///
/// Three shapes are accepted, because three can turn up in the same file. The
/// settings UI writes a **string**, which is the only form `TomlDocument`
/// round-trips without opinion. A user who hand-writes `birthday = 1990-04-17`
/// has written a TOML *local date*, which the parser hands back as one of its
/// own types — so anything else falls back to its `toString`, which for all of
/// them is the ISO date this then parses. And a `DateTime` is what a caller
/// constructing the config in a test has to hand.
///
/// Out of [kEarliestBirthYear]..[kLatestBirthYear] is **absent** rather than
/// clamped, `TomlReader.doubleOrNull`'s rule: a year of 190 is a typo, and
/// answering it with the sign for 1600 would substitute a plausible-looking
/// answer for the one the user meant.
DateTime? parseBirthday(Object? raw) {
  if (raw == null) return null;

  final DateTime parsed;
  if (raw is DateTime) {
    parsed = raw;
  } else {
    final text = (raw is String ? raw : raw.toString()).trim();
    if (text.isEmpty) return null;
    // Just the date: a hand-written TOML offset date-time would otherwise carry
    // a zone that shifts the day, and the day is the whole of the answer.
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    // Rejected rather than rolled over: `DateTime(2001, 13, 40)` is a valid
    // Dart call that answers some day in February 2002, and silently moving
    // somebody's birthday by five months is worse than not reading it.
    final candidate = DateTime(year, month, day);
    if (candidate.month != month || candidate.day != day) return null;
    parsed = candidate;
  }

  if (parsed.year < kEarliestBirthYear || parsed.year > kLatestBirthYear) {
    return null;
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// `1990-04-17` — what the settings UI writes back, and the only form this file
/// promises to round-trip.
String formatBirthday(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-$month-$day';
}
