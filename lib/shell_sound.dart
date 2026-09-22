/// The layer under the shell's synthesised sounds: how a waveform becomes a
/// file, where a hand-written `sound` spelling is looked for, and the one
/// player that opens the result.
///
/// Two features sit on this — the notification chime
/// (`lib/notification_sound.dart`) and the camera shutter
/// (`lib/capture/capture_sound.dart`) — and they arrived a release apart. What
/// is here is what the second one would otherwise have copied: the RIFF writer
/// and its anti-click envelope, the XDG sound-theme search, the cache
/// directory, and the mpv wrapper. What is *not* here is either family's
/// catalogue or its choice class, because those name a set of voices and the
/// whole point of a catalogue is that it is specific.
///
/// **The shipped sounds are synthesised, not shipped as files.** Nothing in the
/// shell resolves a path relative to the bundle — the same rule that makes
/// `theme/builtin_themes.dart` a map of strings and Tux an SVG constant — so a
/// sound that lived in an `assets:` section would play under `flutter run` and
/// nowhere else. Each family builds its waveform from a handful of numbers,
/// [encodeWav16] turns that into a file, and the result is written into the
/// user's cache directory the first time it is wanted. It is also what makes
/// the set free software in the only sense that matters here: there is no
/// sample from anywhere, no third party's licence to carry, only arithmetic
/// under this project's own GPL-3.0.
///
/// Flutter-free apart from `@immutable` and the media_kit player, which is the
/// same one `lib/background.dart` plays video wallpapers through — so a
/// synthesised sound costs the shell no new dependency and no new staged
/// library in the snap.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// The sample rate every shipped sound is rendered at.
const int kShellSoundSampleRate = 44100;

/// The spellings that mean "play nothing".
///
/// Three of them because these keys are hand-typed into `config.toml` and a
/// user who writes `sound = "off"` has said what they meant; the settings rows
/// offer `none`, which is the one the shell writes.
const Set<String> kShellSoundOff = {'none', 'off', 'silent'};

/// How long an attack ramp is.
///
/// Not a taste decision: a waveform that starts at full amplitude on sample
/// zero has a step discontinuity in it, which every speaker in the world
/// reproduces as a click in front of the sound. A shutter is *made* of clicks,
/// so it wants the shorter end of this; a struck tone wants the longer.
const double kShellSoundAttackSeconds = 0.004;

/// How long [encodeWav16] fades the tail over, for the same reason at the other
/// end: the file ends when it ends, and a sample that is not near zero when it
/// does is a click.
const double kShellSoundReleaseSeconds = 0.012;

/// The peak a rendered waveform is normalised to.
///
/// Normalised rather than trusted: a voice is a hand-written list of gains that
/// sum to whatever they sum to, and a recipe that happened to add up past 1.0
/// would clip — which is audible, unlike the few tenths of a decibel this
/// costs.
const double kShellSoundPeak = 0.89;

/// The RIFF header's size, and where the samples start.
const int kWavHeaderBytes = 44;

/// How many bytes [encodeWav16] produces for [frames] mono 16-bit frames.
///
/// Arithmetic rather than a render, which is the whole point of it: a
/// materialiser compares this against what is on disk, and a check that had to
/// render the file first would spend the synthesis it exists to skip every time
/// the sound plays for the life of the install.
int wavByteLength(int frames) => kWavHeaderBytes + frames * 2;

/// Normalises [samples], fades the tail, and writes the lot as a 16-bit mono
/// RIFF WAV.
///
/// Pure: the same samples encode to the same bytes on any machine, which is
/// what lets the sound tests pin a header and an envelope without a sound card.
Uint8List encodeWav16(
  Float64List samples, {
  int sampleRate = kShellSoundSampleRate,
  double peak = kShellSoundPeak,
  double releaseSeconds = kShellSoundReleaseSeconds,
}) {
  final frames = samples.length;

  var loudest = 0.0;
  for (var i = 0; i < frames; i++) {
    final magnitude = samples[i].abs();
    if (magnitude > loudest) loudest = magnitude;
  }
  final scale = loudest > 0 ? peak / loudest : 0.0;
  final releaseFrames = math.min(frames, (releaseSeconds * sampleRate).ceil());

  final bytes = Uint8List(wavByteLength(frames));
  final view = ByteData.sublistView(bytes);
  _writeWavHeader(view, frames: frames, sampleRate: sampleRate);

  for (var i = 0; i < frames; i++) {
    var value = samples[i] * scale;
    final intoRelease = i - (frames - releaseFrames);
    if (intoRelease > 0) {
      value *= 1.0 - intoRelease / releaseFrames;
    }
    final sample = (value * 32767).round().clamp(-32768, 32767);
    view.setInt16(kWavHeaderBytes + i * 2, sample, Endian.little);
  }
  return bytes;
}

/// The 44-byte canonical RIFF/WAVE header for mono 16-bit PCM.
void _writeWavHeader(
  ByteData view, {
  required int frames,
  required int sampleRate,
}) {
  const channels = 1;
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final dataBytes = frames * blockAlign;

  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      view.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  view.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  view.setUint16(20, 1, Endian.little); // format 1 = PCM
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, byteRate, Endian.little);
  view.setUint16(32, blockAlign, Endian.little);
  view.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  view.setUint32(40, dataBytes, Endian.little);
}

// ---------------------------------------------------------------------------
// Where a spelling points
// ---------------------------------------------------------------------------

/// Whether [spelling] is one of [kShellSoundOff], or empty.
bool isSoundOff(String spelling) {
  final wanted = spelling.trim();
  return wanted.isEmpty || kShellSoundOff.contains(wanted.toLowerCase());
}

/// The sound-theme extensions worth trying, commonest first.
const List<String> _kSoundExtensions = [
  '.oga',
  '.ogg',
  '.wav',
  '.opus',
  '.flac',
  '.mp3',
];

/// The sound themes a bare name is looked for under. `freedesktop` is the one
/// `sound-theme-freedesktop` installs and is what every desktop on the machine
/// already plays.
const List<String> _kSoundThemes = ['freedesktop', 'ubuntu', 'default'];

/// The file [spelling] points at, or null when nothing on disk matches it.
///
/// Called once a family has ruled out its own off switch and its own shipped
/// catalogue, so what is left is the two things that are the same for every
/// sound in the shell: a path the user spelled out, and a bare name from the
/// machine's sound theme.
///
/// Pure apart from [exists], which is injected for the same reason
/// `NotificationStore.daemonStarter` is: the rules here are a table of string
/// manipulations and a unit test must be able to reach them on a machine with
/// no sound theme installed.
///
/// Null is not silence. The caller asked for a sound and did not get one, and
/// saying so is what keeps a mistyped path from reading as a quiet machine.
String? resolveSoundFile(
  String spelling, {
  required List<String> soundRoots,
  required bool Function(String path) exists,
  String? home,
}) {
  final wanted = spelling.trim();
  if (wanted.isEmpty) return null;

  // Anything with a separator in it is a path the user typed, and a path that
  // is not there is a missing file rather than a name to go looking for: a
  // typo in `/usr/share/sounds/…` must not silently resolve to something else.
  if (wanted.contains('/')) {
    final expanded = expandHome(wanted, home: home);
    return exists(expanded) ? expanded : null;
  }

  // A name spelled with an extension is tried verbatim as well as stripped, so
  // both `camera-shutter` and `camera-shutter.oga` find the same file.
  final dot = wanted.indexOf('.');
  final bare = dot > 0 ? wanted.substring(0, dot) : wanted;
  final verbatim = dot > 0 ? <String>[wanted] : const <String>[];
  for (final root in soundRoots) {
    for (final candidate in [
      // A file sitting directly in a sounds directory, spelled with its
      // extension or without.
      for (final name in verbatim) '$root/$name',
      for (final extension in _kSoundExtensions) '$root/$bare$extension',
      // The sound-theme layout: `<theme>/<profile>/<name>.<ext>`.
      for (final theme in _kSoundThemes)
        for (final profile in const ['stereo', 'mono'])
          for (final extension in _kSoundExtensions)
            '$root/$theme/$profile/$bare$extension',
    ]) {
      if (exists(candidate)) return candidate;
    }
  }
  return null;
}

/// `~` and `~/…` expanded against [home], which defaults to the environment's.
///
/// Anything else is returned verbatim, a bare `~user` included: this shell has
/// no business guessing at another account's home directory.
String expandHome(String path, {String? home}) {
  if (path != '~' && !path.startsWith('~/')) return path;
  final resolved = home ?? Platform.environment['HOME'];
  if (resolved == null || resolved.isEmpty) return path;
  if (path == '~') return resolved;
  return '$resolved/${path.substring(2)}';
}

/// Where a bare sound name is looked for, in search order.
///
/// The XDG data directories with `/sounds` on the end, user first — which is
/// where `sound-theme-freedesktop` and every desktop's own theme install to.
List<String> shellSoundRoots({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final home = env['HOME'];
  final roots = <String>[];

  /// Appends `/sounds` to one XDG data directory. The trailing slash is dropped
  /// first: `XDG_DATA_HOME=~/data/` is a legal spelling, and a root with a
  /// doubled separator in it would have one in every candidate below it.
  void add(String? base) {
    if (base == null || base.isEmpty) return;
    var trimmed = base;
    while (trimmed.length > 1 && trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    final root = '$trimmed/sounds';
    if (!roots.contains(root)) roots.add(root);
  }

  final dataHome = env['XDG_DATA_HOME'];
  add(dataHome != null && dataHome.isNotEmpty
      ? dataHome
      : (home == null ? null : '$home/.local/share'));
  for (final dir in (env['XDG_DATA_DIRS'] ?? '').split(':')) {
    add(dir);
  }
  add('/usr/local/share');
  add('/usr/share');
  return roots;
}

/// Where the shipped sounds are written so something can open them.
///
/// The user's cache directory rather than a temporary file: these are rendered
/// once and played for the life of the install, and a cache is exactly the
/// contract — losing it costs a few milliseconds of arithmetic.
String shellSoundCacheDirectory({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final cacheHome = env['XDG_CACHE_HOME'];
  if (cacheHome != null && cacheHome.isNotEmpty) {
    return '$cacheHome/moonswing/sounds';
  }
  final home = env['HOME'] ?? '.';
  return '$home/.cache/moonswing/sounds';
}

/// Renders [bytes] into the sound cache as [name] if it is not already there,
/// and answers with its path.
///
/// [expectedLength] is what this build's arithmetic says the file should be, so
/// a voice whose numbers were tuned in a later release reaches an install that
/// has already run — the same rule `ThemeStore` re-seeds shipped palettes
/// under. It is passed rather than measured because [bytes] is a callback: the
/// whole point is to *not* render when the file is already right.
String materialiseSound(
  String name, {
  required int expectedLength,
  required Uint8List Function() bytes,
  Map<String, String>? environment,
}) {
  final directory = shellSoundCacheDirectory(environment: environment);
  final path = '$directory/$name';
  final file = File(path);
  if (file.existsSync() && file.lengthSync() == expectedLength) return path;
  Directory(directory).createSync(recursive: true);
  file.writeAsBytesSync(bytes(), flush: true);
  return path;
}

// ---------------------------------------------------------------------------
// Playing it
// ---------------------------------------------------------------------------

/// One media_kit player, opened on the first sound and kept after it.
///
/// One *per sound family*, not one for the shell: an mpv player plays one file
/// at a time, so a shared one would have a notification arriving mid-screenshot
/// cut the shutter off — two features silencing each other through a resource
/// neither of them knows it is sharing. Opening a second player costs an mpv
/// initialisation, which is the thing this class exists to spend once.
///
/// Nothing is created until [play] is first called, so a shell whose user has
/// switched a sound off never opens mpv at all.
class ShellSoundPlayer {
  ShellSoundPlayer();

  Player? _player;

  /// Opens [path] at [volume] (0 to 1) and returns once mpv has taken it.
  ///
  /// Throws what media_kit throws — a caller that wants a missing file or a
  /// broken mpv to be a visible state has to catch it and say so.
  Future<void> play(String path, double volume) async {
    final player = _player ??= Player(
      // Nothing here has a picture or a subtitle track, and
      // `lib/background.dart` builds its own player the same way.
      configuration: const PlayerConfiguration(libass: false),
    );
    await player.setVolume((volume * 100).clamp(0.0, 100.0));
    await player.open(Media(Uri.file(path).toString()), play: true);
  }

  /// Drops the player, if one was ever opened.
  void close() {
    final player = _player;
    _player = null;
    player?.dispose();
  }
}
