import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Formats a KiB count the way `/proc` hands them to us.
String formatBytesKb(int kb) {
  if (kb >= 1024 * 1024) return '${(kb / 1024 / 1024).toStringAsFixed(1)}G';
  if (kb >= 1024) return '${(kb / 1024).toStringAsFixed(1)}M';
  return '${kb}K';
}

/// Formats a byte count, for the sources (`df`, `/proc/net/dev`) that report
/// bytes rather than KiB.
String formatBytes(int bytes) {
  const units = ['B', 'K', 'M', 'G', 'T'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)}${units[unit]}';
}

/// Formats a transfer rate.
String formatRate(double bytesPerSecond) =>
    '${formatBytes(bytesPerSecond.round())}/s';

/// Formats a duration for a process or the system that may have been up for
/// days. Deliberately days-aware: the old module's helper capped at hours, so a
/// week-old browser read as `147h`.
String formatUptime(Duration d) {
  final days = d.inDays;
  final hours = d.inHours.remainder(24);
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}

String formatTemperature(double celsius, String unit) {
  if (unit == 'fahrenheit') return '${(celsius * 9 / 5 + 32).round()}°F';
  return '${celsius.round()}°C';
}

FaIconData temperatureIcon(double celsius) {
  if (celsius >= 80) return FontAwesomeIcons.temperatureHigh;
  if (celsius <= 30) return FontAwesomeIcons.temperatureLow;
  return FontAwesomeIcons.temperatureHalf;
}
