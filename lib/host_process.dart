// Starting a program that belongs to the *host*, not to this bundle.
//
// The snap is **classic**, so the loader path is the host's — except that
// `snap/snapcraft.yaml` prepends `$SNAP/usr/lib/<triplet>` to
// `LD_LIBRARY_PATH` so the shell's own binary finds the libraries staged
// beside it (libmpv, libgtk-layer-shell, libasound, libpulse and their
// transitive deps). That variable is *inherited by every process the shell
// forks*, and the tools it forks — ffmpeg, wl-copy, speaker-test, systemctl —
// are the host's, built against the host's libraries.
//
// The result is a version mismatch inside somebody else's process. The one
// that gets reported is the recorder:
//
//     ffmpeg: symbol lookup error: /usr/lib/x86_64-linux-gnu/libavutil.so.60:
//     undefined symbol: vaMapBuffer2
//
// The host's libavutil is FFmpeg 8, which calls a libva entry point added in
// libva 2.21; `libva.so.2` resolved to the copy staged beside libmpv, which is
// core22's 2.14. Nothing is wrong with either library — the shell simply put
// its own on ffmpeg's search path. A `prime:` exclusion cannot fix it (the
// shell's own libmpv needs that libva), and the mismatch is not confined to
// libva: any staged soname is a trap for any host program.
//
// So the rule is the one that fits every case: **a host program is started
// with the library path the host would have given it.** The staged entries are
// dropped from `LD_LIBRARY_PATH` for the child; everything else the shell
// inherited stays, because a user's own entries are not ours to discard.
//
// Outside a snap this is a no-op: nothing sets `SNAP`, so nothing is filtered
// and the child gets the parent's environment verbatim.

import 'dart:io';

/// Runs a host program, the [Process.run] signature.
///
/// Every injectable runner in the shell is typed `(String, List<String>)`, so
/// this drops straight into the `runner ?? Process.run` defaults.
Future<ProcessResult> runHostProcess(
  String executable,
  List<String> arguments,
) => Process.run(executable, arguments, environment: hostToolEnvironment());

/// Starts a host program, the [Process.start] signature.
Future<Process> startHostProcess(
  String executable,
  List<String> arguments,
) => Process.start(executable, arguments, environment: hostToolEnvironment());

/// The environment overrides a host program is started with.
///
/// Layered *over* the parent environment rather than replacing it — Dart's
/// `includeParentEnvironment` defaults to true — so this carries the one key
/// that needs changing and nothing else. Empty off a snap, and memoised
/// because `Platform.environment` cannot change under a running process.
Map<String, String> hostToolEnvironment() =>
    _hostToolEnvironment ??= {
      if (hostLibraryPath(Platform.environment) case final path?)
        'LD_LIBRARY_PATH': path,
    };

Map<String, String>? _hostToolEnvironment;

/// The `LD_LIBRARY_PATH` a host program should be given when the shell's own
/// is [environment]'s, or null when it needs no change.
///
/// An empty string is a meaningful answer, not "no change": it is what is left
/// when *every* entry was ours, and the loader treats an empty
/// `LD_LIBRARY_PATH` as an unset one. Dart's process API can override a
/// variable but not unset it, which is the same thing here.
String? hostLibraryPath(Map<String, String> environment) {
  final path = environment['LD_LIBRARY_PATH'];
  if (path == null || path.isEmpty) return null;

  final prefixes = _bundlePrefixes(environment);
  if (prefixes.isEmpty) return null;

  final entries = path.split(':');
  final kept = [
    for (final entry in entries)
      if (!_isBundled(entry, prefixes)) entry,
  ];
  if (kept.length == entries.length) return null;
  return kept.join(':');
}

/// Where this bundle's own libraries live, as directory prefixes.
///
/// `$SNAP` is the revisioned mount and covers the paths snapcraft itself
/// writes. The two spellings beside it are the same tree reached through the
/// `current` symlink or through snapd's non-`/snap` mount point (Fedora,
/// openSUSE), which is how an entry a user or a launcher added shows up.
List<String> _bundlePrefixes(Map<String, String> environment) {
  final prefixes = <String>[];
  final snap = environment['SNAP'];
  if (snap != null && snap.isNotEmpty) prefixes.add(_trimSlashes(snap));
  final name = environment['SNAP_NAME'];
  if (name != null && name.isNotEmpty) {
    prefixes.add('/snap/$name');
    prefixes.add('/var/lib/snapd/snap/$name');
  }
  return prefixes;
}

bool _isBundled(String entry, List<String> prefixes) {
  final normalized = _trimSlashes(entry);
  return prefixes.any(
    (prefix) => normalized == prefix || normalized.startsWith('$prefix/'),
  );
}

/// Trailing slashes are not significant to the loader, so they must not be
/// significant to the match either: `$SNAP/lib/` and `$SNAP/lib` are one
/// directory.
String _trimSlashes(String path) {
  var trimmed = path;
  while (trimmed.length > 1 && trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}
