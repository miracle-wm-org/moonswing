/// The shutter: the sounds the shell ships, where a configured one resolves to,
/// and the player that makes the noise when a screenshot is written.
///
/// Three things here that a change has to keep true.
///
/// - **The shipped shutters are synthesised, not shipped as files.** Nothing in
///   the shell resolves a path relative to the bundle, so a WAV in an `assets:`
///   section would play under `flutter run` and nowhere else — see
///   `lib/shell_sound.dart`, which the chime and this share that rule through.
///   A shutter is also the awkward one to source: almost every camera-click
///   recording on the internet is either somebody's copyrighted library or a
///   sample of a Nikon nobody has cleared, and neither can ship in a GPL-3.0
///   tree. [renderShutterWav] builds the click out of filtered noise and a
///   damped resonance, from the numbers in [ShutterVoice] — original work under
///   this project's own licence, with no sample and no third party in it.
/// - **A shutter is noise, not a note.** The chime's voices are sums of sine
///   partials because a struck bell is one; a focal-plane shutter is two pieces
///   of metal hitting a stop, which is a broadband transient with a body
///   resonance behind it. That is why this file has its own renderer rather
///   than another [ShutterVoice]-shaped entry in the chime's catalogue: they
///   share the file format and the filesystem rules, and nothing else.
/// - **A failure is a visible state.** A shutter sound that has been moved, or
///   an mpv that will not open it, leaves [ShutterSoundStore.error] set and the
///   screenshot menu renders it. The photograph is on disk either way, which is
///   exactly why the silence needs explaining: a shutter that quietly stopped
///   working is indistinguishable from one the user switched off.
///
/// Flutter-free apart from [ChangeNotifier], like the layer under it.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:moonswing/shell_sound.dart';

/// The `shutter_sound` value a fresh config has.
const String kDefaultShutterSound = 'shutter';

/// How loud the shutter is when the config says nothing.
///
/// Quieter than the chime's 0.7. A notification is asking for attention; a
/// shutter is confirming something the user just did, and they are sitting in
/// front of it.
const double kDefaultShutterVolume = 0.6;

// ---------------------------------------------------------------------------
// The shipped sounds
// ---------------------------------------------------------------------------

/// One mechanical click: a burst of noise, shaped, with an optional ring behind
/// it.
///
/// The three numbers that decide what it sounds like are [tone], [body] and
/// [decay]. [tone] is how bright the noise is — a one-pole low-pass run over
/// white noise, where 1.0 is the raw hiss of a small metal part and 0.1 is the
/// thud of a big one. [body] is the housing ringing afterwards. [decay] is how
/// long the whole thing lasts, and it is short by definition: a click that
/// rings for a quarter of a second is a bell, and the user took a photograph.
@immutable
class ShutterClick {
  const ShutterClick({
    required this.at,
    required this.decay,
    required this.tone,
    this.gain = 1.0,
    this.body = 0.0,
    this.bodyGain = 0.0,
    this.bodyDecay = 1.0,
  });

  /// Seconds from the start of the sound.
  final double at;

  /// Seconds for the noise to fall to silence.
  final double decay;

  /// The low-pass coefficient the noise is run through, 0 to 1. Lower is
  /// duller: this is the difference between a shutter blade and a mirror box.
  final double tone;

  /// Amplitude relative to the loudest click in the voice.
  final double gain;

  /// The housing's resonance in hertz, or 0 for none. One damped sine rather
  /// than a partial series — a shutter box is not a tuned instrument, and a
  /// second partial reads as one.
  final double body;

  /// The resonance's amplitude relative to the noise burst's.
  final double bodyGain;

  /// Multiplier on [decay] for the resonance, which usually outlasts the
  /// transient that excited it.
  final double bodyDecay;

  /// Seconds from the start of the sound until this click is silent.
  double get end => at + decay * math.max(1.0, bodyDecay);
}

/// One shipped shutter, as the numbers it is rendered from.
@immutable
class ShutterVoice {
  const ShutterVoice({
    required this.slug,
    required this.label,
    required this.description,
    required this.clicks,
  });

  /// What `shutter_sound` is set to in `config.toml`.
  final String slug;

  /// What the settings row calls it.
  final String label;

  /// One line on what it sounds like, for the settings row's hint.
  final String description;

  final List<ShutterClick> clicks;

  /// How long the rendered file runs for, before the tail `encodeWav16` fades
  /// out over.
  double get duration {
    var end = 0.0;
    for (final click in clicks) {
      if (click.end > end) end = click.end;
    }
    return end;
  }
}

/// The shutters the shell ships, in the order the settings row lists them.
///
/// Four rather than one because a shutter is a sound the user hears every time
/// they do a thing they do often, and the difference between the loud one and
/// the quiet one is the difference between a feature and an annoyance.
/// [_shutter] is the default; [_tick] is for somebody who wants the
/// confirmation without the theatre.
const List<ShutterVoice> kShutterVoices = [
  _shutter,
  _snap,
  _clack,
  _tick,
];

/// The default: a single-lens reflex. The mirror swings up and the first
/// curtain goes, then the second curtain closes and the mirror drops back —
/// which is why this is two events about a tenth of a second apart rather than
/// one, and why the second is the duller of the two.
const ShutterVoice _shutter = ShutterVoice(
  slug: 'shutter',
  label: 'Shutter',
  description: 'A reflex camera: mirror up, curtain, mirror down.',
  clicks: [
    ShutterClick(
      at: 0.0,
      decay: 0.028,
      tone: 0.62,
      body: 2100.0,
      bodyGain: 0.3,
      bodyDecay: 1.8,
    ),
    ShutterClick(
      at: 0.095,
      decay: 0.042,
      tone: 0.34,
      gain: 0.86,
      body: 1250.0,
      bodyGain: 0.42,
      bodyDecay: 2.2,
    ),
  ],
);

/// One bright click and nothing else — a leaf shutter, or the noise a
/// mirrorless body makes because somebody decided it should make one.
const ShutterVoice _snap = ShutterVoice(
  slug: 'snap',
  label: 'Snap',
  description: 'One short, bright click.',
  clicks: [
    ShutterClick(
      at: 0.0,
      decay: 0.022,
      tone: 0.8,
      body: 3200.0,
      bodyGain: 0.22,
      bodyDecay: 1.4,
    ),
  ],
);

/// A large, slow mechanism: a heavy clack with the housing ringing under it.
/// The one in the set that is hard to miss, which is the point of it.
const ShutterVoice _clack = ShutterVoice(
  slug: 'clack',
  label: 'Clack',
  description: 'A heavy mechanism, with the body ringing under it.',
  clicks: [
    ShutterClick(
      at: 0.0,
      decay: 0.05,
      tone: 0.3,
      body: 780.0,
      bodyGain: 0.55,
      bodyDecay: 2.6,
    ),
    ShutterClick(
      at: 0.115,
      decay: 0.055,
      tone: 0.2,
      gain: 0.78,
      body: 520.0,
      bodyGain: 0.6,
      bodyDecay: 2.4,
    ),
  ],
);

/// The quietest thing here that is still a sound: a small, dry tick, with no
/// resonance behind it at all.
const ShutterVoice _tick = ShutterVoice(
  slug: 'tick',
  label: 'Tick',
  description: 'A small, dry tick. Barely there.',
  clicks: [
    ShutterClick(at: 0.0, decay: 0.012, tone: 0.55, gain: 0.7),
  ],
);

/// The placeholder the settings row shows, built from the catalogue so a voice
/// added above cannot go unmentioned in the one place a user would look.
final String kShutterSoundHint =
    '${kShutterVoices.map((v) => v.slug).join(', ')}, none, or a path';

/// The shipped shutter called [slug], or null.
ShutterVoice? shutterVoice(String slug) {
  final wanted = slug.trim().toLowerCase();
  for (final voice in kShutterVoices) {
    if (voice.slug == wanted) return voice;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/// The attack a click is ramped in over.
///
/// An eighth of the chime's: the ramp is only there to keep sample zero off a
/// step discontinuity, and a shutter whose attack is audible is a shutter that
/// sounds like a cymbal being brushed.
const double _kClickAttackSeconds = kShellSoundAttackSeconds / 8;

/// The noise source's seed.
///
/// A fixed one, and a generator written out here rather than `math.Random`:
/// [renderShutterWav] has to produce the same bytes on every machine and in
/// every Dart release, because `materialiseSound` decides whether the cached
/// file is stale by comparing its *length* — but the test that pins the
/// envelope compares samples, and a renderer whose output moved under it would
/// be a test that could only ever be re-recorded. The constants are Numerical
/// Recipes' 32-bit LCG.
const int _kNoiseSeed = 0x5f3759df;

/// How many frames [renderShutterWav] will produce for [voice].
int _frames(ShutterVoice voice, int sampleRate) =>
    math.max(1, ((voice.duration + kShellSoundReleaseSeconds) * sampleRate).ceil());

/// How many bytes [renderShutterWav] will produce for [voice].
///
/// Arithmetic rather than a render — see [wavByteLength].
int shutterWavByteLength(
  ShutterVoice voice, {
  int sampleRate = kShellSoundSampleRate,
}) =>
    wavByteLength(_frames(voice, sampleRate));

/// Renders [voice] as a 16-bit mono RIFF WAV.
///
/// Pure, seed and all: the same voice renders the same bytes on any machine,
/// which is what lets `test/capture_sound_test.dart` pin the shape of the click
/// without a sound card.
Uint8List renderShutterWav(
  ShutterVoice voice, {
  int sampleRate = kShellSoundSampleRate,
}) {
  final frames = _frames(voice, sampleRate);
  final samples = Float64List(frames);

  for (final click in voice.clicks) {
    // One generator per click, seeded off the click's own start, so two clicks
    // in a voice are two different noises rather than the same one twice — and
    // so that moving a click in time changes when it happens rather than what
    // it sounds like.
    var noise = _kNoiseSeed ^ (click.at * sampleRate).round();
    var filtered = 0.0;

    final first = (click.at * sampleRate).floor();
    if (first >= frames) continue;
    final life = click.decay;
    final ringLife = click.decay * click.bodyDecay;
    final last = math.min(
      frames,
      first + (math.max(life, ringLife) * sampleRate).ceil() + 1,
    );

    for (var i = math.max(0, first); i < last; i++) {
      final since = i / sampleRate - click.at;
      if (since < 0) continue;

      // A 32-bit LCG, folded to -1..1. Cheap, and every bit of it reproducible.
      noise = (noise * 1664525 + 1013904223) & 0xffffffff;
      final white = noise / 2147483648.0 - 1.0;
      // One-pole low-pass: what turns white noise into a part of a particular
      // size. Run over every sample of the click's life, so the filter's own
      // state is continuous even where the envelope has gone quiet.
      filtered += click.tone * (white - filtered);

      final attack =
          since < _kClickAttackSeconds ? since / _kClickAttackSeconds : 1.0;

      var value = 0.0;
      if (since <= life) {
        // Exponential, reaching -60dB exactly at `life`, as the chime's
        // envelope does — a linear ramp on a transient reads as a fade.
        value += filtered * math.exp(-6.907755 * since / life);
      }
      if (click.body > 0 && click.bodyGain > 0 && since <= ringLife) {
        value += math.sin(2 * math.pi * click.body * since) *
            click.bodyGain *
            math.exp(-6.907755 * since / ringLife);
      }
      samples[i] += value * attack * click.gain;
    }
  }

  return encodeWav16(samples, sampleRate: sampleRate);
}

/// Renders [voice] into the sound cache if it is not already there, and answers
/// with its path.
String materialiseShutter(
  ShutterVoice voice, {
  Map<String, String>? environment,
}) =>
    materialiseSound(
      'shutter-${voice.slug}.wav',
      expectedLength: shutterWavByteLength(voice),
      bytes: () => renderShutterWav(voice),
      environment: environment,
    );

// ---------------------------------------------------------------------------
// Resolving what the config asked for
// ---------------------------------------------------------------------------

/// Where a `shutter_sound` value points.
///
/// Four outcomes, and the fourth is why this is a class rather than a nullable
/// path: a name that resolves to nothing is not silence. The user asked for a
/// sound and did not get one, and [missing] is what the screenshot menu says so
/// with.
@immutable
class ShutterSoundChoice {
  const ShutterSoundChoice.silent()
      : voice = null,
        path = null,
        missing = null;

  const ShutterSoundChoice.shipped(ShutterVoice this.voice)
      : path = null,
        missing = null;

  const ShutterSoundChoice.file(String this.path)
      : voice = null,
        missing = null;

  const ShutterSoundChoice.missing(String this.missing)
      : voice = null,
        path = null;

  /// The shipped shutter to render, when the config named one.
  final ShutterVoice? voice;

  /// A file on disk that exists.
  final String? path;

  /// What was asked for, when nothing on disk matched it.
  final String? missing;

  /// Whether this choice plays nothing *on purpose*.
  bool get isSilent => voice == null && path == null && missing == null;

  /// What the settings and menu rows call it.
  String get label => voice?.label ?? path ?? missing ?? 'None';
}

/// Resolves the `shutter_sound` key's [spelling] against the filesystem.
///
/// The order is the order of decreasing certainty about what the user meant: an
/// off switch, then a shipped shutter, then a path they spelled out, then a
/// bare name looked for in the sound themes — so a user who installs a theme
/// containing a `shutter` cannot have the shipped one taken away from them by
/// it.
ShutterSoundChoice resolveShutterSound(
  String spelling, {
  required List<String> soundRoots,
  required bool Function(String path) exists,
  String? home,
}) {
  final wanted = spelling.trim();
  if (isSoundOff(wanted)) return const ShutterSoundChoice.silent();

  final shipped = shutterVoice(wanted);
  if (shipped != null) return ShutterSoundChoice.shipped(shipped);

  final file = resolveSoundFile(
    wanted,
    soundRoots: soundRoots,
    exists: exists,
    home: home,
  );
  return file == null
      ? ShutterSoundChoice.missing(wanted)
      : ShutterSoundChoice.file(file);
}

// ---------------------------------------------------------------------------
// The config the store reads
// ---------------------------------------------------------------------------

/// What `[modules.screenshot]` says about the shutter.
@immutable
class ShutterSoundConfig {
  const ShutterSoundConfig({
    this.sound = kDefaultShutterSound,
    this.volume = kDefaultShutterVolume,
  });

  /// A shipped shutter's slug, a path, a sound-theme name, or one of
  /// `kShellSoundOff`.
  final String sound;

  /// 0 to 1.
  final double volume;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShutterSoundConfig &&
          other.sound == sound &&
          other.volume == volume;

  @override
  int get hashCode => Object.hash(sound, volume);
}

// ---------------------------------------------------------------------------
// The player
// ---------------------------------------------------------------------------

/// Plays the shutter when a screenshot has been written.
///
/// Unleased, unlike `NotificationSoundStore`, and the difference is worth
/// stating because it looks like an oversight. A chime is played by something
/// *arriving*, so a store with no lease would have to listen for arrivals for
/// the life of the shell whether or not any panel carries the bell. A shutter
/// is played by [CaptureStore] at the end of a capture the user asked for, so
/// nothing here listens to anything, holds a timer or wakes an idle shell — the
/// player is opened by the first screenshot of the session and nothing before
/// it, which is what a lease would have bought.
///
/// One for the machine all the same, for the reason `CaptureStore` is one: one
/// FlutterView per panel per monitor, and two bars carrying the camera icon
/// must not be two shutters played a frame apart.
class ShutterSoundStore extends ChangeNotifier {
  static final ShutterSoundStore instance = ShutterSoundStore._();
  ShutterSoundStore._();

  @visibleForTesting
  factory ShutterSoundStore.forTesting() => ShutterSoundStore._();

  ShutterSoundConfig _config = const ShutterSoundConfig();
  ShutterSoundConfig get config => _config;

  /// The resolved choice, and the spelling it was resolved from — so a config
  /// sweep that did not move this key costs no filesystem walk.
  ShutterSoundChoice? _choice;
  String? _resolvedFrom;

  String? _error;

  /// Why the last attempt to play made no sound, or null.
  ///
  /// Rendered by the screenshot module's menu: the file is on the disk either
  /// way, so a silent shutter is otherwise indistinguishable from one the user
  /// turned off on purpose.
  String? get error => _error;

  /// What actually makes a sound. Injected for the reason
  /// `NotificationSoundStore.play` is: the real one opens libmpv, which no test
  /// may depend on being installed.
  @visibleForTesting
  Future<void> Function(String path, double volume) play = _player.play;

  /// Materialises a shipped shutter and answers with the file's path. Injected
  /// so a test never writes into the user's cache directory.
  @visibleForTesting
  String Function(ShutterVoice voice) materialise = materialiseShutter;

  /// Resolves a spelling. Injected so a test can answer without a filesystem.
  @visibleForTesting
  ShutterSoundChoice Function(String spelling) resolve = _resolve;

  static final ShellSoundPlayer _player = ShellSoundPlayer();

  static ShutterSoundChoice _resolve(String spelling) => resolveShutterSound(
        spelling,
        soundRoots: shellSoundRoots(),
        exists: (path) => File(path).existsSync(),
      );

  /// Takes the screenshot module's options. A no-op when nothing moved, which
  /// matters: `Module.loadAll` runs on every keystroke anywhere in the settings
  /// UI.
  ///
  /// The state moves synchronously and the notification does not — see
  /// [_notifyLater]; this is reached from a module's `fromMap`, which runs
  /// inside a build.
  void configure(ShutterSoundConfig config) {
    if (_config == config) return;
    final soundChanged = _config.sound != config.sound;
    _config = config;
    if (soundChanged) {
      _choice = null;
      _resolvedFrom = null;
      // The old reason belonged to the old spelling. Keeping it would leave a
      // corrected path showing the error it was typed to fix.
      _error = null;
    }
    _notifyLater();
  }

  /// What the configured spelling points at, resolved at most once per
  /// spelling.
  ShutterSoundChoice get choice {
    if (_choice != null && _resolvedFrom == _config.sound) return _choice!;
    _resolvedFrom = _config.sound;
    return _choice = resolve(_config.sound);
  }

  /// Plays the configured shutter.
  ///
  /// No rate limit, unlike the chime's: a screenshot is something the user did,
  /// `CaptureStore.busy` already stops a second one overlapping the first, and
  /// two photographs taken in quick succession are two photographs — swallowing
  /// the second shutter would be the shell telling them one of them did not
  /// happen.
  ///
  /// Never throws. [CaptureStore] calls this on the success path of a capture
  /// that has already written its file, so a shutter that cannot work out what
  /// to play must cost the sound and nothing else — a screenshot reported as
  /// failed because of its own noise would be the worst answer available.
  void playNow() {
    final ShutterSoundChoice target;
    try {
      // The filesystem is walked in here, on the first play after an edit.
      target = choice;
    } catch (error) {
      _setError('The shutter sound could not be looked up: $error');
      return;
    }

    if (target.isSilent) return;
    if (target.missing != null) {
      _setError('No shutter sound called “${target.missing}” was found. '
          'Name one of the shipped sounds, or give a full path to a file.');
      return;
    }

    final String path;
    try {
      path = target.path ?? _cachedVoicePath(target.voice!);
    } catch (error) {
      _setError('The shutter could not be written to the cache directory: '
          '$error');
      return;
    }

    // Fire and forget, and the failure is caught rather than awaited: the
    // screenshot is written and the user is about to be told so, and a shutter
    // that takes a moment to open must not hold that up.
    play(path, _config.volume.clamp(0.0, 1.0)).then(
      (_) => _setError(null),
      onError: (Object error) =>
          _setError('The shutter could not be played: $error'),
    );
  }

  /// The shipped shutter's file, worked out at most once per process.
  ///
  /// [materialiseShutter] already skips the synthesis when the file is there,
  /// but it still stats the cache directory, and the answer cannot change under
  /// a running shell.
  final Map<String, String> _voicePaths = {};

  String _cachedVoicePath(ShutterVoice voice) =>
      _voicePaths[voice.slug] ??= materialise(voice);

  void _setError(String? reason) {
    if (_error == reason) return;
    _error = reason;
    _notifyLater();
  }

  /// Notifies once the frame in flight is over.
  ///
  /// [configure] is reached from the screenshot module's `fromMap`, which runs
  /// during a build, and the menu that renders [error] lives in a *different*
  /// FlutterView — so a synchronous `notifyListeners` would be a
  /// `markNeedsBuild` on an element already being built. A microtask rather
  /// than a post-frame callback, because this file is deliberately free of the
  /// widget layer.
  void _notifyLater() {
    if (_notifyQueued) return;
    _notifyQueued = true;
    scheduleMicrotask(() {
      _notifyQueued = false;
      if (_disposed) return;
      notifyListeners();
    });
  }

  bool _notifyQueued = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Puts the store back to what a fresh process has. For tests, which share
  /// this singleton across cases.
  @visibleForTesting
  void resetForTesting() {
    _config = const ShutterSoundConfig();
    _choice = null;
    _resolvedFrom = null;
    _error = null;
    _voicePaths.clear();
    _notifyQueued = false;
    play = _player.play;
    materialise = materialiseShutter;
    resolve = _resolve;
  }
}

/// What [CaptureStore] calls when a still capture has been written.
///
/// A top-level function rather than the store's method, so the seam
/// `CaptureStore` holds is a plain callback a test can answer without touching
/// this singleton.
void playShutterSound() => ShutterSoundStore.instance.playNow();
