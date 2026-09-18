/// The alarm a finished countdown makes: the sounds the shell ships, where a
/// configured one resolves to, and the player that rings it.
///
/// Four things here that a change has to keep true.
///
/// - **The shipped alarms are synthesised, not shipped as files.** Nothing in
///   the shell resolves a path relative to the bundle, so a WAV in an `assets:`
///   section would play under `flutter run` and nowhere else — see
///   `lib/shell_sound.dart`, which every sound in the shell shares that rule
///   through. It is also what keeps the set free software in the only sense
///   that matters here: a recorded kitchen timer is somebody's sample and
///   somebody's licence, and these are arithmetic under this project's own
///   GPL-3.0.
/// - **An alarm is a struck tone, so it borrows the chime's renderer.** This is
///   the difference between this file and `lib/capture/capture_sound.dart`,
///   which has a renderer of its own: a shutter is two pieces of metal hitting
///   a stop, which is broadband noise and nothing a sum of sines describes,
///   while a ding is a small bell — exactly what [renderNotificationWav]
///   already builds. What is specific to a timer is therefore only the
///   catalogue of numbers, which is what this file holds. The cache file is
///   namespaced `timer-<slug>.wav` all the same, so a voice here and a chime
///   voice that happened to share a slug cannot share a file.
/// - **A timer sounds *and* says so.** The ding is not the whole announcement:
///   `TimersStore.onFinished` also posts to the shell's notification store, so
///   a timer that ran out while the user was looking elsewhere is still on the
///   list when they look back. The two halves are deliberately one event —
///   `announceFinishedTimer` — and the notification is posted *chimeless*, or
///   the shell would answer one timer with two sounds a frame apart.
/// - **A failure is a visible state.** A sound file that has been moved, or an
///   mpv that will not open it, leaves [TimerSoundStore.error] set and the
///   calendar's timers pane renders it. The notification arrives either way,
///   which is exactly why the silence needs explaining: an alarm that quietly
///   stopped working is indistinguishable from one the user switched off.
///
/// Flutter-free apart from [ChangeNotifier], like the layer under it.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/notification_sound.dart';
import 'package:graceful_shell/shell_sound.dart';

/// One shipped alarm, as the numbers it is rendered from.
///
/// The chime's [NotificationVoice] under this family's name: see the note at
/// the top of the file for why an alarm and a chime share a renderer while the
/// shutter does not.
typedef TimerVoice = NotificationVoice;

/// One struck tone in a [TimerVoice].
typedef TimerStrike = NotificationStrike;

/// One partial of a struck tone.
typedef TimerPartial = NotificationPartial;

/// The `timer_sound` value a fresh config has.
const String kDefaultTimerSound = 'ding';

/// How loud the alarm is when the config says nothing.
///
/// The chime's 0.7 rather than the shutter's 0.6. A shutter confirms something
/// the user just did and is sitting in front of; a timer is the one sound in
/// the shell whose whole job is to reach somebody who has walked away from it.
const double kDefaultTimerVolume = 0.7;

/// The shortest gap between two alarms.
///
/// Three countdowns set to the same minute finish on one [TimersStore.tick],
/// which would otherwise be three copies of the same ding played over each
/// other — a noise rather than an alarm. The first rings and the rest of the
/// batch is swallowed; each one still posts its own notification, so nothing
/// about *what finished* is lost. Longer than the chime's 400ms because these
/// voices are longer than a chime.
const Duration kTimerSoundInterval = Duration(milliseconds: 900);

// ---------------------------------------------------------------------------
// The shipped sounds
// ---------------------------------------------------------------------------

/// A small bell's partials: inharmonic, and the higher the shorter — what makes
/// a ding read as a struck object rather than as a beep.
const List<TimerPartial> _dingPartials = [
  TimerPartial(1.0, 1.0, 1.0),
  TimerPartial(2.76, 0.42, 0.55),
  TimerPartial(5.4, 0.16, 0.32),
  TimerPartial(8.93, 0.07, 0.18),
];

/// A cleaner series for the voices that repeat: an alarm strikes often enough
/// that a rich one turns to mud, so its partials are two and nearly harmonic.
const List<TimerPartial> _tonePartials = [
  TimerPartial(1.0, 1.0, 1.0),
  TimerPartial(2.0, 0.2, 0.45),
  TimerPartial(3.01, 0.08, 0.22),
];

/// The alarms the shell ships, in the order the settings row lists them.
///
/// Four rather than one because a countdown ending is the one sound in the
/// shell the user chooses the loudness of by choosing the *voice*: [_ding] is
/// somebody with the machine in front of them, [_alarm] is somebody in the next
/// room, and [_gong] is somebody who set a timer because they intend to forget
/// about it.
const List<TimerVoice> kTimerVoices = [
  _ding,
  _dingDong,
  _alarm,
  _gong,
];

/// The default: one clear strike, left to ring. A little ding, which is what a
/// kitchen timer has said for a hundred years.
const TimerVoice _ding = TimerVoice(
  slug: 'ding',
  label: 'Ding',
  description: 'One clear strike, left to ring. The default.',
  partials: _dingPartials,
  strikes: [
    TimerStrike(at: 0.0, frequency: 1174.66, decay: 1.25),
  ],
);

/// Two notes falling, D6 down to A5 — a doorbell's figure, and the one voice
/// here that sounds like an announcement rather than an alert.
const TimerVoice _dingDong = TimerVoice(
  slug: 'ding-dong',
  label: 'Ding-dong',
  description: 'Two notes falling, like a doorbell.',
  partials: _dingPartials,
  strikes: [
    TimerStrike(at: 0.0, frequency: 1174.66, decay: 0.6),
    TimerStrike(at: 0.3, frequency: 880.0, decay: 1.4, gain: 0.95),
  ],
);

/// Two bursts of three. Insistent by construction: the repeat is what the ear
/// reads as "this is still going off", and it is the voice for somebody who is
/// not in the room.
const TimerVoice _alarm = TimerVoice(
  slug: 'alarm',
  label: 'Alarm',
  description: 'Two bursts of three quick tones. Hard to miss.',
  partials: _tonePartials,
  strikes: [
    TimerStrike(at: 0.0, frequency: 1046.5, decay: 0.13),
    TimerStrike(at: 0.16, frequency: 1046.5, decay: 0.13, gain: 0.95),
    TimerStrike(at: 0.32, frequency: 1046.5, decay: 0.13, gain: 0.95),
    TimerStrike(at: 0.62, frequency: 1046.5, decay: 0.13, gain: 0.9),
    TimerStrike(at: 0.78, frequency: 1046.5, decay: 0.13, gain: 0.9),
    TimerStrike(at: 0.94, frequency: 1046.5, decay: 0.2, gain: 0.9),
  ],
);

/// One low strike with a long tail. The quiet end of the set — it carries
/// across a room without being an alert about it.
const TimerVoice _gong = TimerVoice(
  slug: 'gong',
  label: 'Gong',
  description: 'One low strike with a long tail.',
  partials: [
    TimerPartial(1.0, 1.0, 1.0),
    TimerPartial(1.51, 0.6, 0.7),
    TimerPartial(2.44, 0.34, 0.45),
    TimerPartial(3.87, 0.16, 0.26),
  ],
  strikes: [
    TimerStrike(at: 0.0, frequency: 329.63, decay: 2.2),
  ],
);

/// The placeholder the settings row shows, built from the catalogue so a voice
/// added above cannot go unmentioned in the one place a user would look.
final String kTimerSoundHint =
    '${kTimerVoices.map((v) => v.slug).join(', ')}, none, or a path';

/// The shipped alarm called [slug], or null.
TimerVoice? timerVoice(String slug) {
  final wanted = slug.trim().toLowerCase();
  for (final voice in kTimerVoices) {
    if (voice.slug == wanted) return voice;
  }
  return null;
}

/// How many bytes [renderNotificationWav] produces for [voice].
///
/// Arithmetic rather than a render — see [wavByteLength].
int timerWavByteLength(
  TimerVoice voice, {
  int sampleRate = kShellSoundSampleRate,
}) =>
    notificationWavByteLength(voice, sampleRate: sampleRate);

/// Renders [voice] into the sound cache if it is not already there, and answers
/// with its path.
///
/// Namespaced `timer-…`, the way the shutter's is: the cache is one directory
/// for the whole shell, and two families whose slugs collided would otherwise
/// be one file played by both.
String materialiseTimerVoice(
  TimerVoice voice, {
  Map<String, String>? environment,
}) =>
    materialiseSound(
      'timer-${voice.slug}.wav',
      expectedLength: timerWavByteLength(voice),
      bytes: () => renderNotificationWav(voice),
      environment: environment,
    );

// ---------------------------------------------------------------------------
// Resolving what the config asked for
// ---------------------------------------------------------------------------

/// Where a `timer_sound` value points.
///
/// Four outcomes, and the fourth is why this is a class rather than a nullable
/// path: a name that resolves to nothing is not silence. The user asked for a
/// sound and did not get one, and [missing] is what the timers pane says so
/// with.
@immutable
class TimerSoundChoice {
  const TimerSoundChoice.silent()
      : voice = null,
        path = null,
        missing = null;

  const TimerSoundChoice.shipped(TimerVoice this.voice)
      : path = null,
        missing = null;

  const TimerSoundChoice.file(String this.path)
      : voice = null,
        missing = null;

  const TimerSoundChoice.missing(String this.missing)
      : voice = null,
        path = null;

  /// The shipped alarm to render, when the config named one.
  final TimerVoice? voice;

  /// A file on disk that exists.
  final String? path;

  /// What was asked for, when nothing on disk matched it.
  final String? missing;

  /// Whether this choice plays nothing *on purpose*.
  bool get isSilent => voice == null && path == null && missing == null;

  /// What the settings and pane rows call it.
  String get label => voice?.label ?? path ?? missing ?? 'None';
}

/// Resolves the `timer_sound` key's [spelling] against the filesystem.
///
/// The order is the order of decreasing certainty about what the user meant: an
/// off switch, then a shipped alarm, then a path they spelled out, then a bare
/// name looked for in the sound themes — so a user who installs a theme
/// containing an `alarm` cannot have the shipped one taken away from them by
/// it.
TimerSoundChoice resolveTimerSound(
  String spelling, {
  required List<String> soundRoots,
  required bool Function(String path) exists,
  String? home,
}) {
  final wanted = spelling.trim();
  if (isSoundOff(wanted)) return const TimerSoundChoice.silent();

  final shipped = timerVoice(wanted);
  if (shipped != null) return TimerSoundChoice.shipped(shipped);

  final file = resolveSoundFile(
    wanted,
    soundRoots: soundRoots,
    exists: exists,
    home: home,
  );
  return file == null
      ? TimerSoundChoice.missing(wanted)
      : TimerSoundChoice.file(file);
}

// ---------------------------------------------------------------------------
// The config the store reads
// ---------------------------------------------------------------------------

/// What `[modules.clock]` says about the alarm.
///
/// A clock key rather than a section of its own because the clock is where the
/// shell's timers live: the bar readout hangs off that module and the composer
/// that starts one is in the calendar page behind it.
@immutable
class TimerSoundConfig {
  const TimerSoundConfig({
    this.sound = kDefaultTimerSound,
    this.volume = kDefaultTimerVolume,
  });

  /// A shipped alarm's slug, a path, a sound-theme name, or one of
  /// [kShellSoundOff].
  final String sound;

  /// 0 to 1.
  final double volume;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimerSoundConfig &&
          other.sound == sound &&
          other.volume == volume;

  @override
  int get hashCode => Object.hash(sound, volume);
}

// ---------------------------------------------------------------------------
// The player
// ---------------------------------------------------------------------------

/// Plays the alarm when a countdown reaches zero.
///
/// Unleased, like `ShutterSoundStore` and for its reason: nothing here listens
/// to anything. `TimersStore` announces a finish and this rings, so the player
/// is opened by the first countdown of the session and nothing before it —
/// which is what a lease would have bought. `TimersStore`'s own ticker already
/// keeps an idle shell asleep.
///
/// One for the machine all the same: one FlutterView per panel per monitor, and
/// two bars carrying the clock must not be two alarms played a frame apart.
class TimerSoundStore extends ChangeNotifier {
  static final TimerSoundStore instance = TimerSoundStore._();
  TimerSoundStore._();

  @visibleForTesting
  factory TimerSoundStore.forTesting() => TimerSoundStore._();

  TimerSoundConfig _config = const TimerSoundConfig();
  TimerSoundConfig get config => _config;

  /// The resolved choice, and the spelling it was resolved from — so a config
  /// sweep that did not move this key costs no filesystem walk.
  TimerSoundChoice? _choice;
  String? _resolvedFrom;

  String? _error;

  /// Why the last attempt to play made no sound, or null.
  ///
  /// Rendered by the calendar's timers pane: the notification arrives either
  /// way, so a silent alarm is otherwise indistinguishable from one the user
  /// turned off on purpose.
  String? get error => _error;

  DateTime? _lastPlayed;

  /// The clock [kTimerSoundInterval] is measured against. Injected so the rate
  /// limit is a unit test rather than a wall-clock wait.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  /// What actually makes a sound. Injected for the reason
  /// `NotificationSoundStore.play` is: the real one opens libmpv, which no test
  /// may depend on being installed.
  @visibleForTesting
  Future<void> Function(String path, double volume) play = _player.play;

  /// Materialises a shipped alarm and answers with the file's path. Injected so
  /// a test never writes into the user's cache directory.
  @visibleForTesting
  String Function(TimerVoice voice) materialise = materialiseTimerVoice;

  /// Resolves a spelling. Injected so a test can answer without a filesystem.
  @visibleForTesting
  TimerSoundChoice Function(String spelling) resolve = _resolve;

  /// One player for this family, not for the shell — see [ShellSoundPlayer].
  static final ShellSoundPlayer _player = ShellSoundPlayer();

  static TimerSoundChoice _resolve(String spelling) => resolveTimerSound(
        spelling,
        soundRoots: shellSoundRoots(),
        exists: (path) => File(path).existsSync(),
      );

  /// Takes the clock module's options. A no-op when nothing moved, which
  /// matters: `Module.loadAll` runs on every keystroke anywhere in the settings
  /// UI.
  ///
  /// The state moves synchronously and the notification does not — see
  /// [_notifyLater]; this is reached from a module's `fromMap`, which runs
  /// inside a build.
  void configure(TimerSoundConfig config) {
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
  TimerSoundChoice get choice {
    if (_choice != null && _resolvedFrom == _config.sound) return _choice!;
    _resolvedFrom = _config.sound;
    return _choice = resolve(_config.sound);
  }

  /// Rings the configured alarm, subject to [kTimerSoundInterval].
  ///
  /// [force] is the settings row's preview, which is a thing the user just
  /// asked for and so may not be swallowed by a countdown that finished a
  /// moment before it.
  ///
  /// Never throws. This is called from `TimersStore.tick`, on the path that has
  /// already retired the entry and is about to notify every readout in the
  /// shell, so an alarm that cannot work out what to play must cost the sound
  /// and nothing else.
  void playNow({bool force = false}) {
    final at = now();
    if (!force) {
      final last = _lastPlayed;
      if (last != null && at.difference(last) < kTimerSoundInterval) return;
    }

    final TimerSoundChoice target;
    try {
      // The filesystem is walked in here, on the first play after an edit.
      target = choice;
    } catch (error) {
      _setError('The timer sound could not be looked up: $error');
      return;
    }

    if (target.isSilent) return;
    if (target.missing != null) {
      _setError('No timer sound called “${target.missing}” was found. '
          'Name one of the shipped sounds, or give a full path to a file.');
      return;
    }

    _lastPlayed = at;
    final String path;
    try {
      path = target.path ?? _cachedVoicePath(target.voice!);
    } catch (error) {
      _setError('The timer sound could not be written to the cache '
          'directory: $error');
      return;
    }

    // Fire and forget, and the failure is caught rather than awaited: the
    // notification for this timer is being posted on the same turn, and an
    // alarm that takes a moment to open must not hold that up.
    play(path, _config.volume.clamp(0.0, 1.0)).then(
      (_) => _setError(null),
      onError: (Object error) =>
          _setError('The timer sound could not be played: $error'),
    );
  }

  /// The shipped alarm's file, worked out at most once per process.
  ///
  /// [materialiseTimerVoice] already skips the synthesis when the file is
  /// there, but it still stats the cache directory, and the answer cannot
  /// change under a running shell.
  final Map<String, String> _voicePaths = {};

  String _cachedVoicePath(TimerVoice voice) =>
      _voicePaths[voice.slug] ??= materialise(voice);

  void _setError(String? reason) {
    if (_error == reason) return;
    _error = reason;
    _notifyLater();
  }

  /// Notifies once the frame in flight is over.
  ///
  /// [configure] is reached from the clock module's `fromMap`, which runs
  /// during a build, and the pane that renders [error] lives in a *different*
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
    _config = const TimerSoundConfig();
    _choice = null;
    _resolvedFrom = null;
    _error = null;
    _lastPlayed = null;
    _voicePaths.clear();
    _notifyQueued = false;
    now = DateTime.now;
    play = _player.play;
    materialise = materialiseTimerVoice;
    resolve = _resolve;
  }
}

/// What `TimersStore` calls when a countdown has reached zero.
///
/// A top-level function rather than the store's method, so the seam
/// `TimersStore` holds is a plain callback a test can answer without touching
/// this singleton — the shape `playShutterSound` has.
void playTimerSound() => TimerSoundStore.instance.playNow();
