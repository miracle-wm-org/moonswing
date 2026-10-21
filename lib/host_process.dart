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
// **The applications the launcher starts are host programs too**, and they are
// the ones a user notices. GIO spawns them out of this process (see
// `lib/app_info.dart`), so they inherit the same path, and a staged library
// that is merely *older* than the host's does not announce itself the way
// ffmpeg did — it half-works. The reported shape is a GTK application that
// starts and runs with no icons anywhere, its window controls included: the
// host's gdk-pixbuf loader modules are built against the host's gdk-pixbuf, so
// resolving that soname to the copy staged beside libgtk-layer-shell leaves the
// SVG loader unable to load, and every symbolic icon in the theme silently
// decodes to nothing. Hence [hostProgramEnvironment], which the launch context
// in `app_info.dart` applies to every application the shell starts.
//
// **`GDK_PIXBUF_MODULE_FILE` is the same trap from the other side.** The snap's
// launcher sets it so the *shell's* staged gdk-pixbuf reads a cache of the
// staged loaders, not the host's (whose SVG loader needs a newer librsvg than
// the one staged, and aborts GTK on the first icon). A host program given it
// would load core22's loaders into the host's gdk-pixbuf — so it is taken off,
// and *unset* rather than emptied, since gdk-pixbuf opens an empty path as a
// cache file and is then left with no loaders at all.
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
) => Process.run(
  executable,
  arguments,
  environment: hostToolEnvironment(),
  includeParentEnvironment: false,
);

/// Starts a host program, the [Process.start] signature.
Future<Process> startHostProcess(String executable, List<String> arguments) =>
    Process.start(
      executable,
      arguments,
      environment: hostToolEnvironment(),
      includeParentEnvironment: false,
    );

/// The environment changes a host program needs, as variable to new value —
/// where a **null** value means the variable must be *unset* in the child, not
/// set to nothing.
///
/// GIO's launch context has `g_app_launch_context_unsetenv`, so an application
/// launched through `lib/app_info.dart` is given the environment the host would
/// have given it exactly, with no `LD_LIBRARY_PATH` at all where the host sets
/// none; [hostToolEnvironment] does the same for [Process] by handing over the
/// whole environment with the removals left out.
///
/// Empty off a snap, and memoised because `Platform.environment` cannot change
/// under a running process.
Map<String, String?> hostProgramEnvironment() =>
    _hostProgramEnvironment ??= hostProgramOverrides(Platform.environment);

Map<String, String?>? _hostProgramEnvironment;

/// [hostProgramEnvironment] against an arbitrary [environment], which is the
/// half a test on a machine that is not a snap can reach.
Map<String, String?> hostProgramOverrides(Map<String, String> environment) => {
  if (hostLibraryPath(environment) case final path?)
    'LD_LIBRARY_PATH': path.isEmpty ? null : path,
  if (_isBundledPixbufCache(environment)) 'GDK_PIXBUF_MODULE_FILE': null,
};

/// The whole environment a host program is started with, in the shape
/// [Process.run] and [Process.start] take with `includeParentEnvironment:
/// false` — the parent's, with [hostProgramEnvironment] applied.
///
/// Whole rather than layered over the parent, because a layer can override a
/// variable but not remove one, and an empty `GDK_PIXBUF_MODULE_FILE` is not
/// the same as none.
Map<String, String> hostToolEnvironment() => _hostToolEnvironment ??=
    hostToolOverrides(Platform.environment, hostProgramEnvironment());

/// [hostToolEnvironment] for an arbitrary [environment] and [overrides].
Map<String, String> hostToolOverrides(
  Map<String, String> environment,
  Map<String, String?> overrides,
) => {
  for (final MapEntry(:key, :value) in environment.entries)
    if (!overrides.containsKey(key)) key: value,
  for (final MapEntry(:key, :value) in overrides.entries)
    key: ?value,
};

Map<String, String>? _hostToolEnvironment;

/// The `LD_LIBRARY_PATH` a host program should be given when the shell's own
/// is [environment]'s, or null when it needs no change.
///
/// An empty string is a meaningful answer, not "no change": it is what is left
/// when *every* entry was ours, and the loader treats an empty
/// `LD_LIBRARY_PATH` as an unset one; [hostProgramOverrides] turns it into an
/// unset all the same.
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

/// Whether `GDK_PIXBUF_MODULE_FILE` is the snap launcher's cache of the staged
/// loaders: under the bundle, or under the per-user snap directories the
/// launcher writes it to. A value of the user's own elsewhere is left alone.
bool _isBundledPixbufCache(Map<String, String> environment) {
  final file = environment['GDK_PIXBUF_MODULE_FILE'];
  if (file == null || file.isEmpty) return false;
  final prefixes = _bundlePrefixes(environment);
  if (prefixes.isEmpty) return false;
  for (final key in const ['SNAP_USER_COMMON', 'SNAP_USER_DATA']) {
    final dir = environment[key];
    if (dir != null && dir.isNotEmpty) prefixes.add(_trimSlashes(dir));
  }
  return _isBundled(file, prefixes);
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
