/// Quick timers: named countdowns the user keeps, started from the overview's
/// timer composer with one click — "Tea, 3m", "Pasta, 10m".
///
/// Kept in `config.toml` as `[[modules.clock.quick_timers]]`, beside the other
/// timer keys, because unlike a running timer (session-only, see
/// [TimersStore]) a preset is something the user wrote down and expects to
/// find again after a restart.
///
/// The reading half is pure and per-row: a hand-edited row with no name or a
/// duration that does not parse costs that row, never the list. The writing
/// half edits the *raw* rows in place by their index in the file, so a row the
/// reader dropped, or a key it does not know, survives the user adding and
/// removing others beside it.
library;

import 'package:flutter/foundation.dart';

import 'package:moonswing/config_store.dart';
import 'package:moonswing/timers/timer_format.dart';

/// Where the presets live in `config.toml`.
const List<String> kQuickTimersPath = ['modules', 'clock', 'quick_timers'];

/// How long a name may be. The composer's chips and the floating card's
/// subtitle are both one line, and a name is a word or two, not a note.
const int kQuickTimerNameMaxLength = 40;

/// One preset: what it is called and how long it runs.
@immutable
class QuickTimer {
  const QuickTimer({required this.name, required this.duration, this.index});

  final String name;
  final Duration duration;

  /// Its row in the file's list, which is what an edit addresses — not its
  /// position among the rows that parsed. Null for one not read from a file.
  final int? index;

  /// The row as it is written: the duration in the unit form the composer's
  /// field accepts, so a hand-edit reads the way the user would type it.
  Map<String, dynamic> toMap() => {
    'name': name,
    'duration': formatCompactDuration(duration),
  };

  @override
  bool operator ==(Object other) =>
      other is QuickTimer &&
      other.name == name &&
      other.duration == duration &&
      other.index == index;

  @override
  int get hashCode => Object.hash(name, duration, index);

  @override
  String toString() => 'QuickTimer($name, $duration, #$index)';
}

/// `1h30m`, `3m`, `45s`, `2m30s` — a duration in the shortest unit form
/// [parseDurationInput] reads back as the same length.
String formatCompactDuration(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final out = StringBuffer();
  if (hours > 0) out.write('${hours}h');
  if (minutes > 0) out.write('${minutes}m');
  if (seconds > 0 || out.isEmpty) out.write('${seconds}s');
  return out.toString();
}

/// A name as it is kept: trimmed, one line, and no longer than
/// [kQuickTimerNameMaxLength]. Empty when there is nothing left of it.
String normalizeQuickTimerName(String raw) {
  final oneLine = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  return oneLine.length > kQuickTimerNameMaxLength
      ? oneLine.substring(0, kQuickTimerNameMaxLength).trimRight()
      : oneLine;
}

/// The duration a row names: a string in any form the composer's field takes,
/// or an integer number of seconds. Null for anything else, and for anything
/// [parseDurationInput] would refuse — zero, or past [kMaxTimerDuration].
Duration? _durationOf(Object? raw) => switch (raw) {
  String s => parseDurationInput(s),
  int seconds when seconds > 0 && seconds <= kMaxTimerDuration.inSeconds =>
    Duration(seconds: seconds),
  _ => null,
};

/// Every row of [raw] that names a preset, in file order.
List<QuickTimer> parseQuickTimers(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final (i, row) in raw.indexed)
      if (row is Map)
        if (row['name'] case final String name
            when normalizeQuickTimerName(name).isNotEmpty)
          if (_durationOf(row['duration']) case final Duration duration)
            QuickTimer(
              name: normalizeQuickTimerName(name),
              duration: duration,
              index: i,
            ),
  ];
}

/// The presets as [ConfigStore] holds them, and the two edits the composer
/// makes. A thin view: nothing is cached, so it is always the file's answer,
/// and listening to it is listening to the store.
class QuickTimerBook {
  const QuickTimerBook(this.config);

  final ConfigStore config;

  List<Object?> get _raw => List<Object?>.of(
    config.get<List>(kQuickTimersPath) ?? const [],
  );

  List<QuickTimer> get timers => parseQuickTimers(_raw);

  /// Keeps a preset called [name] that runs for [duration]. A preset already
  /// called that — ignoring case — takes the new length in place rather than
  /// becoming a second chip with the same label. False when [name] is empty
  /// once trimmed.
  bool save(String name, Duration duration) {
    final normalized = normalizeQuickTimerName(name);
    if (normalized.isEmpty) return false;
    final row = QuickTimer(name: normalized, duration: duration).toMap();
    final raw = _raw;
    final existing = timers
        .where((t) => t.name.toLowerCase() == normalized.toLowerCase())
        .firstOrNull;
    if (existing != null) {
      final old = raw[existing.index!];
      // Its other keys are kept: they are the user's, not the composer's.
      raw[existing.index!] = {...(old as Map).cast<String, dynamic>(), ...row};
    } else {
      raw.add(row);
    }
    config.set(kQuickTimersPath, raw);
    return true;
  }

  /// Forgets [timer]. The key goes with the last one, so a file the user never
  /// gave a preset to is left as it was.
  void remove(QuickTimer timer) {
    final index = timer.index;
    final raw = _raw;
    if (index == null || index >= raw.length) return;
    // The row has to still be this preset: the file is the user's, and an
    // edit to it between the chip being drawn and clicked moves the rows.
    final row = parseQuickTimers([raw[index]]).firstOrNull;
    if (row?.name != timer.name || row?.duration != timer.duration) return;
    raw.removeAt(index);
    config.set(kQuickTimersPath, raw.isEmpty ? null : raw);
  }
}
