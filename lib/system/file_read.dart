import 'dart:io';

/// Fail-soft one-shot reads for `/proc`- and `/sys`-style files.
///
/// Null means "not there or unreadable" — every caller in the sampling layer
/// renders that as an absent reading, never an error. A vanished PID
/// directory or an unplugged hwmon node is normal churn, not an exception.
/// This pair used to exist byte-identical in three readers.
String? readStringOrNull(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsStringSync();
  } catch (_) {
    return null;
  }
}

/// See [readStringOrNull].
List<String>? readLinesOrNull(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsLinesSync();
  } catch (_) {
    return null;
  }
}
