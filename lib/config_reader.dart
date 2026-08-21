/// Shared field readers for hand-editable TOML tables.
///
/// The invariant every config class in the shell follows: **a wrongly-typed
/// value costs that one key, never the whole table.** A throw out of any
/// `fromMap` is caught by `AppConfig.load`, which answers by discarding the
/// user's *entire* config — so nothing here ever throws. Values are
/// type-tested and coerced (`height = 32.0` in TOML is a double, but the
/// field wants an int), NaN and the infinities fall back rather than clamp
/// (infinity survives `clamp()`, and `double.nan.toInt()` throws), and
/// anything else yields the caller's fallback.
library;

extension TomlReader on Map<String, dynamic> {
  /// The value at [key] when it is a string; [fallback] otherwise.
  String stringOr(String key, String fallback) {
    final raw = this[key];
    return raw is String ? raw : fallback;
  }

  /// The trimmed value at [key] when it is a non-empty string; null otherwise.
  String? stringOrNull(String key) {
    final raw = this[key];
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// The value at [key] as an int, coercing a TOML float with [num.toInt].
  /// [min]/[max] clamp when given.
  int intOr(String key, int fallback, {int? min, int? max}) {
    final raw = this[key];
    if (raw is! num || !raw.isFinite) return fallback;
    var value = raw.toInt();
    if (min != null && value < min) value = min;
    if (max != null && value > max) value = max;
    return value;
  }

  /// The value at [key] as a double, coercing a TOML int with [num.toDouble].
  /// [min]/[max] clamp when given.
  double doubleOr(String key, double fallback, {double? min, double? max}) {
    final raw = this[key];
    if (raw is! num || !raw.isFinite) return fallback;
    var value = raw.toDouble();
    if (min != null && value < min) value = min;
    if (max != null && value > max) value = max;
    return value;
  }

  /// The value at [key] when it is a bool; [fallback] otherwise.
  bool boolOr(String key, bool fallback) {
    final raw = this[key];
    return raw is bool ? raw : fallback;
  }

  /// The strings in the list at [key], dropping non-string elements. A
  /// missing or non-list value yields [fallback].
  List<String> stringListOr(String key,
      [List<String> fallback = const <String>[]]) {
    final raw = this[key];
    if (raw is! List) return fallback;
    return raw.whereType<String>().toList();
  }

  /// The subtable at [key], or null when absent or not a table.
  Map<String, dynamic>? tableOrNull(String key) {
    final raw = this[key];
    return raw is Map<String, dynamic> ? raw : null;
  }

  /// The tables in the array-of-tables at [key], dropping anything else.
  /// List order is preserved — for several callers it is the canonical
  /// presentation order.
  List<Map<String, dynamic>> tableListOr(String key) {
    final raw = this[key];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }
}
