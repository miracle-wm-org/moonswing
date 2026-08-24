/// Formatting and parsing for the shell's timers and stopwatches.
///
/// Pure functions with no Flutter and no store behind them — the
/// `overlay/calendar/month.dart` discipline. The readout the bar paints while a
/// timer runs and the duration the user types into the calendar page are both
/// decided here, so both are plain unit tests.
library;

/// The longest countdown that can be started.
///
/// A cap rather than a free-for-all because the readout is laid out for
/// `H:MM:SS`, and because the parser reads a bare number as minutes: a
/// fat-fingered `999999` is a typo, not a 694-day timer, and answering null
/// lets the Start button simply stay inert instead of accepting it.
const Duration kMaxTimerDuration = Duration(hours: 99);

/// `MM:SS`, or `H:MM:SS` once there is an hour to show.
///
/// Minutes always take two digits so the string keeps its width as the seconds
/// roll over — this readout sits next to the clock in the bar, and one that
/// changed width every ten seconds would drag the whole panel's layout with it.
/// A negative duration reads as `00:00`: a countdown that has run out shows
/// zero, never a minus sign.
String formatTimerDuration(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

final RegExp _digitsOnly = RegExp(r'^\d+$');
final RegExp _unitForm = RegExp(r'^(\d+[hms])+$');
final RegExp _unitToken = RegExp(r'(\d+)([hms])');

/// A duration spelled the way a person types one, or null when it is not one.
///
/// Three shapes, because a timer field that accepts only one of them is a field
/// the user has to learn:
///
///   * colon form — `[hh:]mm:ss`, so `1:30` is unambiguously a minute and a
///     half. Every group but the first is bounded to 59, which is what makes
///     `5:90` a rejected typo rather than a silently accepted six and a half
///     minutes.
///   * unit form — `90s`, `5m`, `1h30m`, `1h 30m 10s`. Repeats sum.
///   * a bare number — minutes, which is what a timer means by it everywhere
///     else on the desktop and what the presets in the calendar page offer.
///
/// Null for anything that does not parse, for zero, and for anything past
/// [kMaxTimerDuration]. Null rather than a throw because this runs on every
/// keystroke: half-typed input is the normal case, not an error.
Duration? parseDurationInput(String raw) {
  final text = raw.trim().toLowerCase();
  if (text.isEmpty) return null;

  final Duration? parsed;
  if (text.contains(':')) {
    parsed = _parseColonForm(text);
  } else if (_digitsOnly.hasMatch(text)) {
    final minutes = int.tryParse(text);
    parsed = minutes == null ? null : Duration(minutes: minutes);
  } else {
    parsed = _parseUnitForm(text);
  }

  if (parsed == null || parsed <= Duration.zero) return null;
  if (parsed > kMaxTimerDuration) return null;
  return parsed;
}

Duration? _parseColonForm(String text) {
  final parts = text.split(':');
  if (parts.length > 3) return null;
  final values = <int>[];
  for (final part in parts) {
    // An empty group is how `:30` and `1:` reach here; both mean zero.
    final value = part.isEmpty ? 0 : int.tryParse(part);
    if (value == null || value < 0) return null;
    values.add(value);
  }
  // Only the leading group is unbounded: `90:00` is ninety minutes, but `5:90`
  // is a mistake rather than five minutes and ninety seconds.
  for (var i = 1; i < values.length; i++) {
    if (values[i] > 59) return null;
  }
  return switch (values.length) {
    3 => Duration(hours: values[0], minutes: values[1], seconds: values[2]),
    2 => Duration(minutes: values[0], seconds: values[1]),
    _ => Duration(seconds: values[0]),
  };
}

Duration? _parseUnitForm(String text) {
  // Whitespace is dropped first and the whole remainder has to be tokens, or
  // `5 apples` would start a five-second timer off its leading `5`.
  final compact = text.replaceAll(RegExp(r'\s+'), '');
  if (!_unitForm.hasMatch(compact)) return null;
  var total = Duration.zero;
  for (final match in _unitToken.allMatches(compact)) {
    final value = int.tryParse(match.group(1)!);
    if (value == null) return null;
    total += switch (match.group(2)) {
      'h' => Duration(hours: value),
      'm' => Duration(minutes: value),
      _ => Duration(seconds: value),
    };
  }
  return total;
}
