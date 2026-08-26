import 'package:flutter/widgets.dart';

import 'package:graceful_shell/astrology/astrology_config.dart';
import 'package:graceful_shell/astrology/horoscope_api.dart';
import 'package:graceful_shell/astrology/zodiac.dart';
import 'package:graceful_shell/config_store.dart';
// The `28 Aug` formatter. Borrowed the way the lunar widget borrows the
// weather's sky tokens: it lives beside the Moon because that is where the
// first surface needing it was, and nothing about it is about the Moon.
import 'package:graceful_shell/moon/moon_format.dart' show formatMoonDate;
import 'package:graceful_shell/overlay/settings/controls.dart';

/// The astrology desktop widget's settings: the birthday it works from, which
/// horoscope to fetch, and where from.
///
/// Its own Shell category rather than a `[modules.*]` block for the reason
/// `astrology_config.dart` states — there is no bar module, and a birthday is
/// the machine's one answer to one question rather than a per-instance widget
/// option.
///
/// Three things this pane has to keep true:
///
/// - **A half-typed date is not written.** Every other field here commits per
///   keystroke, which is right for a number or a name and wrong for a date: on
///   the way to `1990-04-17` the field passes through `1`, `199`, `1990-0` and
///   a dozen more, none of which is a date and every one of which would blank
///   the card. Only a value [parseBirthday] accepts is written, and an empty
///   field removes the key — so clearing it is still possible and is the only
///   way to unset a birthday.
/// - **It shows what the date resolved to.** The sign is computed rather than
///   looked up, so the only way to confirm the shell read the date the user
///   meant is to say what it made of it. This is also the one surface with
///   room to explain a cusp.
/// - **The server is a setting, not a constant.** The default instance is one
///   person's free deployment of an MIT-licensed server; anybody may run their
///   own, and that possibility is the whole reason this depends on it at all.
class AstrologySection extends StatelessWidget {
  const AstrologySection({super.key, required this.store});

  final ConfigStore store;

  /// What is in the config file right now, whether or not it parses.
  String get _raw => store.get<String>(['astrology', 'birthday'])?.trim() ?? '';

  void _setBirthday(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      store.remove(['astrology', 'birthday']);
      return;
    }
    final parsed = parseBirthday(trimmed);
    if (parsed == null) return;
    // Normalized rather than stored verbatim, so `1990-4-7` typed by hand and
    // the picker's own output are the same value in the file.
    store.set(['astrology', 'birthday'], formatBirthday(parsed));
  }

  /// "This year the Sun enters Leo on 22 Jul and Virgo on 23 Aug."
  ///
  /// Searched rather than quoted, which is the whole justification for
  /// computing the sign instead of tabulating it: the boundaries move by a day
  /// or so from year to year, and a fixed "Jul 23 – Aug 22" is wrong for
  /// anybody born near one about a year in four.
  String _seasonLine(ZodiacSign sign) {
    final now = DateTime.now();
    final season = solarSeasonIn(now.year, sign);
    final next = ZodiacSign.values[(sign.index + 1) % ZodiacSign.values.length];
    final start = formatMoonDate(season.start.toLocal(), reference: now);
    final end = formatMoonDate(season.end.toLocal(), reference: now);
    return 'This year the Sun enters ${sign.label} on $start and '
        '${next.label} on $end.';
  }

  @override
  Widget build(BuildContext context) {
    final raw = _raw;
    final birthday = parseBirthday(raw);
    final reading = birthday == null ? null : zodiacReadingFor(birthday);
    final period = HoroscopePeriod.parse(
      store.get<String>(['astrology', 'period']) ?? 'daily',
    );
    final apiBase =
        store.get<String>(['astrology', 'api_base'])?.trim() ?? '';

    return SettingsSection(
      label: 'Astrology',
      children: [
        SettingsRow(
          label: 'Birthday',
          control: SettingsTextField(
            width: 140,
            initial: raw,
            hint: 'YYYY-MM-DD',
            onChanged: _setBirthday,
          ),
        ),
        if (reading != null) ...[
          SettingsHint('${reading.sign.label} — ${reading.sign.attributes}.'),
          SettingsHint(_seasonLine(reading.sign)),
          if (reading.onCusp)
            SettingsHint(
              // Two days a month this matters and the date alone cannot settle
              // it, so the pane says so rather than picking silently. Noon is
              // the convention for a birth time nobody recorded: it is the
              // instant furthest from either end of the day.
              'The Sun changed signs that day, so this birthday sits on the '
              '${reading.sign.label}–${reading.neighbour!.label} cusp. '
              'Without a birth time the shell reads it at midday, which is '
              '${reading.sign.label}.',
            ),
        ] else if (raw.isNotEmpty)
          const SettingsHint(
            'Not a date the shell can read. Use YYYY-MM-DD — the sign is '
            'computed from where the Sun actually was that day, so the year '
            'matters.',
          )
        else
          const SettingsHint(
            'The Astrology desktop widget needs this. Add it from the '
            'desktop\'s right-click menu, under Add widget.',
          ),
        SettingsRow(
          label: 'Horoscope',
          control: SettingsSegmented(
            options: [
              for (final value in HoroscopePeriod.values) value.path,
            ],
            value: period.path,
            onChanged: (v) => store.set(['astrology', 'period'], v),
          ),
        ),
        SettingsRow(
          label: 'Refresh every',
          control: SettingsNumberField(
            value: store.get<num>(['astrology', 'refresh_minutes']) ?? 180,
            isInt: true,
            onChanged: (v) =>
                store.set(['astrology', 'refresh_minutes'], v.toInt()),
          ),
        ),
        const SettingsHint(
          'Minutes. A horoscope is not a reading of anything that moves — the '
          'only thing a refresh buys is crossing midnight without the card '
          'still showing yesterday\'s.',
        ),
        SettingsRow(
          label: 'Server',
          alignTop: true,
          control: SettingsTextField(
            width: 260,
            initial: apiBase,
            hint: kDefaultHoroscopeApiBase,
            onChanged: (v) {
              final trimmed = v.trim();
              if (trimmed.isEmpty) {
                store.remove(['astrology', 'api_base']);
              } else {
                store.set(['astrology', 'api_base'], trimmed);
              }
            },
          ),
        ),
        const SettingsHint(
          'The horoscope text comes from Horoscope-API, an MIT-licensed server '
          'that reads horoscope.com. The default is its public instance; point '
          'this at your own if you would rather not depend on somebody '
          'else\'s. Leave it empty for the default.',
        ),
      ],
    );
  }
}
