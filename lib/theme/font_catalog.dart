import 'dart:io';

import 'package:moonswing/host_process.dart';

/// The font families installed on this machine, via fontconfig's `fc-list`.
///
/// Shelling out costs a fork and fontconfig's first run can rebuild its cache,
/// which is why this is loaded lazily by the one widget that needs it — the theme
/// editor's font picker — rather than from `main()`. Binding `libfontconfig`
/// through `dart:ffi` buys nothing: the set is read once per settings visit.
///
/// Follows the [DiskReader] shape: the runner is injectable so tests never fork,
/// and every failure resolves to an empty list. A machine with no fontconfig is
/// not an error — the caller falls back to a free-typed field.
class FontCatalog {
  FontCatalog({
    Future<ProcessResult> Function(String, List<String>)? runner,
  }) : _run = runner ?? runHostProcess;

  static final FontCatalog instance = FontCatalog();

  final Future<ProcessResult> Function(String, List<String>) _run;

  Future<List<String>>? _cached;

  /// Installed families, deduplicated and sorted. Never throws.
  ///
  /// The *future* is memoised rather than its result, so two callers racing on
  /// a cold catalogue share one process spawn instead of forking twice.
  Future<List<String>> list() => _cached ??= _read();

  Future<List<String>> _read() async {
    try {
      // `%{family[0]}` is the primary family per font file. Plain `fc-list :
      // family` instead prints every localized alias joined by commas
      // ("Ubuntu Nerd Font Propo,Ubuntu Nerd Font Propo Light"), which is noise
      // in a picker.
      final result = await _run('fc-list', ['--format', '%{family[0]}\n']);
      if (result.exitCode != 0) return const [];
      return parseFcListFamilies(result.stdout.toString());
    } catch (_) {
      // No fc-list (a minimal container, a stripped image). The picker degrades
      // to a text field.
      return const [];
    }
  }
}

/// Parses `fc-list --format '%{family[0]}\n'` output into a sorted, deduplicated
/// family list.
///
/// There is one line per font *file*, so a family with four weights appears four
/// times. Comparison is case-insensitive in both the dedupe and the sort: the
/// same family reached through two files can differ only in case.
List<String> parseFcListFamilies(String stdout) {
  final seen = <String>{};
  final families = <String>[];

  for (final line in stdout.split('\n')) {
    // Defensive: fontconfig still emits a comma-joined list for a format that
    // resolves to more than one value.
    final name = line.split(',').first.trim();
    if (name.isEmpty) continue;
    if (!seen.add(name.toLowerCase())) continue;
    families.add(name);
  }

  families.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return families;
}
