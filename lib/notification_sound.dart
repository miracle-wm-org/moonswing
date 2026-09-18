/// The notification chime: the sounds the shell ships, where a configured one
/// resolves to, and the leased player that plays it.
///
/// Three things here that a change has to keep true.
///
/// - **The shipped sounds are synthesised, not shipped as files.** Nothing in
///   the shell resolves a path relative to the bundle — the same rule that makes
///   `theme/builtin_themes.dart` a map of strings and Tux an SVG constant — so a
///   chime that lived in an `assets:` section would play under `flutter run` and
///   nowhere else. [renderNotificationWav] builds the waveform from
///   [NotificationVoice], which is a handful of numbers, and the result is
///   written into the user's cache directory the first time it is wanted. It is
///   also what makes the set open source in the only sense that matters here:
///   there is no sample from anywhere, only arithmetic anybody can read.
///   `lib/shell_sound.dart` is where that rule, the RIFF writer, the sound-theme
///   search and the player now live, because `lib/capture/capture_sound.dart`
///   needed every one of them for the shutter. What stayed here is what is
///   specific to a chime: the catalogue, the partial series a struck bell has,
///   and the arrival this plays on.
/// - **Silence is about interruption, so the chime is the first thing it takes.**
///   [NotificationStore.silenced] stops the chime exactly as it stops the bell's
///   shake and the floating card, and for the same reason — nothing is lost, the
///   notification is still collected and the panel still lists it.
/// - **A failure is a visible state.** A sound file that has been moved, or an
///   mpv that will not open it, leaves [NotificationSoundStore.error] set and
///   the panel's sound row renders it. A chime that silently stopped working is
///   indistinguishable from a quiet day.
///
/// Flutter-free apart from [ChangeNotifier] and, through [ShellSoundPlayer],
/// the media_kit player `lib/background.dart` plays video wallpapers through —
/// so the chime costs the shell no new dependency and no new staged library in
/// the snap.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/shell_sound.dart';

/// `expandHome` was declared here before `lib/shell_sound.dart` existed, and a
/// caller that reaches for it through this file is not wrong about where the
/// shell's sound rules live.
export 'package:graceful_shell/shell_sound.dart' show expandHome;

/// The `sound` value a fresh config has.
const String kDefaultNotificationSound = 'chime';

/// The spellings that mean "play nothing". Shared with every other sound the
/// shell plays — see [kShellSoundOff].
const Set<String> kNotificationSoundOff = kShellSoundOff;

/// How loud a chime is when the config says nothing.
const double kDefaultNotificationSoundVolume = 0.7;

/// The sample rate every shipped sound is rendered at.
const int kNotificationSoundSampleRate = kShellSoundSampleRate;

/// The shortest gap between two chimes.
///
/// An application that posts a dozen notifications in a burst — a mail client
/// catching up after a suspend is the reported case — would otherwise play a
/// dozen overlapping copies of the same sound, which is a noise rather than a
/// chime. The first one plays and the rest of the burst is swallowed; the count
/// on the bell is what says how many there were.
const Duration kNotificationSoundInterval = Duration(milliseconds: 400);

// ---------------------------------------------------------------------------
// The shipped sounds
// ---------------------------------------------------------------------------

/// One partial of a struck tone: where it sits above the fundamental, how loud
/// it starts, and how much faster than the fundamental it dies away.
///
/// A struck bar or bell is not harmonic — its partials sit at inharmonic ratios
/// and the high ones fade first, which is the whole difference between a chime
/// and a beep. [decay] below 1 is what does that fading.
@immutable
class NotificationPartial {
  const NotificationPartial(this.ratio, this.gain, this.decay);

  /// Frequency multiplier on the strike's fundamental.
  final double ratio;

  /// Amplitude relative to the fundamental's.
  final double gain;

  /// Multiplier on the strike's decay time.
  final double decay;
}

/// One struck tone in a voice: when it is hit, what note, and how long it rings.
@immutable
class NotificationStrike {
  const NotificationStrike({
    required this.at,
    required this.frequency,
    required this.decay,
    this.gain = 1.0,
  });

  /// Seconds from the start of the sound.
  final double at;

  /// The fundamental, in hertz.
  final double frequency;

  /// Seconds for the fundamental to fall to silence.
  final double decay;

  /// Amplitude relative to the loudest strike in the voice.
  final double gain;
}

/// One shipped sound, as the numbers it is rendered from.
@immutable
class NotificationVoice {
  const NotificationVoice({
    required this.slug,
    required this.label,
    required this.description,
    required this.strikes,
    required this.partials,
  });

  /// What `sound` is set to in `config.toml`.
  final String slug;

  /// What the settings row calls it.
  final String label;

  /// One line on what it sounds like, for the settings row's hint.
  final String description;

  final List<NotificationStrike> strikes;
  final List<NotificationPartial> partials;

  /// How long the rendered file runs for, plus the tail
  /// [renderNotificationWav] fades out over.
  double get duration {
    var end = 0.0;
    for (final strike in strikes) {
      for (final partial in partials) {
        final ring = strike.at + strike.decay * partial.decay;
        if (ring > end) end = ring;
      }
    }
    return end;
  }
}

/// A bell's partials: inharmonic, and the higher the shorter.
const List<NotificationPartial> _bellPartials = [
  NotificationPartial(1.0, 1.0, 1.0),
  NotificationPartial(2.0, 0.34, 0.62),
  NotificationPartial(2.99, 0.18, 0.44),
  NotificationPartial(4.21, 0.09, 0.3),
];

/// A glass rod's: two partials, the second almost inaudible, which is what
/// makes it read as a clean tone rather than as a bell.
const List<NotificationPartial> _glassPartials = [
  NotificationPartial(1.0, 1.0, 1.0),
  NotificationPartial(2.0, 0.14, 0.5),
  NotificationPartial(5.43, 0.05, 0.18),
];

/// The sounds the shell ships, in the order the settings row lists them.
///
/// Five voices rather than one because "a notification arrived" is the shell's
/// most repeated sentence and the user is the only one who knows how loud a
/// room they are in: [_chime] is the default, [_ping] is for somebody who wants
/// to be told without being addressed, and [_bell] is for somebody who does not
/// want to miss it.
const List<NotificationVoice> kNotificationVoices = [
  _chime,
  _ping,
  _glass,
  _bell,
  _knock,
];

/// The default: a rising two-note figure, A5 up to D6. Two notes rather than one
/// because a single tone at this length is a beep, and the interval is what a
/// user hears as a phrase rather than as an alert.
const NotificationVoice _chime = NotificationVoice(
  slug: 'chime',
  label: 'Chime',
  description: 'A rising two-note figure. The default.',
  partials: _bellPartials,
  strikes: [
    NotificationStrike(at: 0.0, frequency: 880.0, decay: 0.75),
    NotificationStrike(at: 0.11, frequency: 1174.66, decay: 0.95, gain: 0.9),
  ],
);

/// One short, high tone. The quietest thing in the set that is still a sound.
const NotificationVoice _ping = NotificationVoice(
  slug: 'ping',
  label: 'Ping',
  description: 'One short, high tone.',
  partials: _glassPartials,
  strikes: [
    NotificationStrike(at: 0.0, frequency: 1567.98, decay: 0.34),
  ],
);

/// Three notes up a major triad — C6, E6, G6 — struck close together, so they
/// read as one gesture rather than as three arrivals.
const NotificationVoice _glass = NotificationVoice(
  slug: 'glass',
  label: 'Glass',
  description: 'Three bright notes up a chord.',
  partials: _glassPartials,
  strikes: [
    NotificationStrike(at: 0.0, frequency: 1046.5, decay: 0.5),
    NotificationStrike(at: 0.07, frequency: 1318.51, decay: 0.55, gain: 0.92),
    NotificationStrike(at: 0.14, frequency: 1567.98, decay: 0.7, gain: 0.84),
  ],
);

/// A single low strike left to ring. The one voice in the set that is hard to
/// miss, which is the point of it.
const NotificationVoice _bell = NotificationVoice(
  slug: 'bell',
  label: 'Bell',
  description: 'One low strike, left to ring.',
  partials: _bellPartials,
  strikes: [
    NotificationStrike(at: 0.0, frequency: 587.33, decay: 1.6),
  ],
);

/// Two dull taps. No pitch anybody would name, so it carries across a room
/// without sounding like a musical instrument going off beside the user.
const NotificationVoice _knock = NotificationVoice(
  slug: 'knock',
  label: 'Knock',
  description: 'Two dull taps, with no tune to them.',
  partials: [
    NotificationPartial(1.0, 1.0, 1.0),
    NotificationPartial(1.61, 0.7, 0.55),
    NotificationPartial(2.73, 0.4, 0.3),
    NotificationPartial(3.94, 0.22, 0.16),
  ],
  strikes: [
    NotificationStrike(at: 0.0, frequency: 174.61, decay: 0.2),
    NotificationStrike(at: 0.13, frequency: 164.81, decay: 0.26, gain: 0.85),
  ],
);

/// The placeholder the settings row shows, built from the catalogue so a voice
/// added above cannot go unmentioned in the one place a user would look.
final String kNotificationSoundHint =
    '${kNotificationVoices.map((v) => v.slug).join(', ')}, none, or a path';

/// The shipped voice called [slug], or null.
NotificationVoice? notificationVoice(String slug) {
  final wanted = slug.trim().toLowerCase();
  for (final voice in kNotificationVoices) {
    if (voice.slug == wanted) return voice;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/// How long the attack ramp is. See [kShellSoundAttackSeconds] for why there is
/// one at all.
const double _kAttackSeconds = kShellSoundAttackSeconds;

/// How many frames [renderNotificationWav] will produce for [voice].
int _frames(NotificationVoice voice, int sampleRate) => math.max(
    1, ((voice.duration + kShellSoundReleaseSeconds) * sampleRate).ceil());

/// How many bytes [renderNotificationWav] will produce for [voice].
///
/// Arithmetic rather than a render, which is the whole point of it:
/// [materialiseVoice] compares this against what is on disk, and a check that
/// had to render the file first would spend the synthesis it exists to skip on
/// every chime for the life of the install.
int notificationWavByteLength(
  NotificationVoice voice, {
  int sampleRate = kNotificationSoundSampleRate,
}) =>
    wavByteLength(_frames(voice, sampleRate));

/// Renders [voice] as a 16-bit mono RIFF WAV.
///
/// Pure: the same voice renders the same bytes on any machine, which is what
/// lets `test/notification_sound_test.dart` pin the header and the envelope
/// without a sound card.
Uint8List renderNotificationWav(
  NotificationVoice voice, {
  int sampleRate = kNotificationSoundSampleRate,
}) {
  final frames = _frames(voice, sampleRate);
  final samples = Float64List(frames);

  for (var i = 0; i < frames; i++) {
    final t = i / sampleRate;
    var value = 0.0;
    for (final strike in voice.strikes) {
      final since = t - strike.at;
      if (since < 0) continue;
      // The attack is shared by every partial of one strike, so a strike is one
      // event rather than four that happen to start together.
      final attack =
          since < _kAttackSeconds ? since / _kAttackSeconds : 1.0;
      for (final partial in voice.partials) {
        final life = strike.decay * partial.decay;
        if (since > life) continue;
        // Exponential, and reaching -60dB exactly at `life`: a linear ramp on a
        // ringing tone reads as somebody turning a knob down.
        final envelope = math.exp(-6.907755 * since / life);
        value += math.sin(2 * math.pi * strike.frequency * partial.ratio * t) *
            partial.gain *
            envelope *
            attack *
            strike.gain;
      }
    }
    samples[i] = value;
  }

  return encodeWav16(samples, sampleRate: sampleRate);
}

// ---------------------------------------------------------------------------
// Resolving what the config asked for
// ---------------------------------------------------------------------------

/// Where a `sound` value points.
///
/// Four outcomes, and the fourth is why this is a class rather than a nullable
/// path: a name that resolves to nothing is not silence. The user asked for a
/// sound and did not get one, and [missing] is what the panel says so with.
@immutable
class NotificationSoundChoice {
  const NotificationSoundChoice.silent()
      : voice = null,
        path = null,
        missing = null;

  const NotificationSoundChoice.shipped(NotificationVoice this.voice)
      : path = null,
        missing = null;

  const NotificationSoundChoice.file(String this.path)
      : voice = null,
        missing = null;

  const NotificationSoundChoice.missing(String this.missing)
      : voice = null,
        path = null;

  /// The shipped voice to render, when the config named one.
  final NotificationVoice? voice;

  /// A file on disk that exists.
  final String? path;

  /// What was asked for, when nothing on disk matched it.
  final String? missing;

  /// Whether this choice plays nothing *on purpose*.
  bool get isSilent => voice == null && path == null && missing == null;

  /// What the settings and panel rows call it.
  String get label => voice?.label ?? path ?? missing ?? 'None';
}

/// Resolves the `sound` key's [spelling] against the filesystem.
///
/// The order is the order of decreasing certainty about what the user meant: an
/// off switch, then a shipped voice, then a path they spelled out, then a bare
/// name looked for in the sound themes — so a user who installs a theme
/// containing a `chime` cannot have the shipped one taken away from them by it.
/// The last two of those are [resolveSoundFile], because they are the same two
/// for every sound the shell plays; [exists] is injected through it for the
/// reason `NotificationStore.daemonStarter` is.
NotificationSoundChoice resolveNotificationSound(
  String spelling, {
  required List<String> soundRoots,
  required bool Function(String path) exists,
  String? home,
}) {
  final wanted = spelling.trim();
  if (isSoundOff(wanted)) return const NotificationSoundChoice.silent();

  final shipped = notificationVoice(wanted);
  if (shipped != null) return NotificationSoundChoice.shipped(shipped);

  final file = resolveSoundFile(
    wanted,
    soundRoots: soundRoots,
    exists: exists,
    home: home,
  );
  return file == null
      ? NotificationSoundChoice.missing(wanted)
      : NotificationSoundChoice.file(file);
}

/// Where a bare sound name is looked for, in search order. [shellSoundRoots]
/// under the chime's own name, which is what `config.toml`'s reader documents.
List<String> notificationSoundRoots({Map<String, String>? environment}) =>
    shellSoundRoots(environment: environment);

/// Where the shipped sounds are written so something can open them.
String notificationSoundCacheDirectory({Map<String, String>? environment}) =>
    shellSoundCacheDirectory(environment: environment);

// ---------------------------------------------------------------------------
// The config the module pushes down
// ---------------------------------------------------------------------------

/// What `[modules.notifications]` says about the chime.
@immutable
class NotificationSoundConfig {
  const NotificationSoundConfig({
    this.sound = kDefaultNotificationSound,
    this.volume = kDefaultNotificationSoundVolume,
  });

  /// A shipped voice's slug, a path, a sound-theme name, or one of
  /// [kNotificationSoundOff].
  final String sound;

  /// 0 to 1.
  final double volume;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationSoundConfig &&
          other.sound == sound &&
          other.volume == volume;

  @override
  int get hashCode => Object.hash(sound, volume);
}

// ---------------------------------------------------------------------------
// The player
// ---------------------------------------------------------------------------

/// Plays the chime when a notification arrives.
///
/// Leased, like every other shared worker in the shell and for the same reason:
/// one FlutterView per panel per monitor means a store owned by a widget is
/// owned N times, and two bars would be two chimes played a frame apart. The
/// lease is held by the **notifications module**, so the chime exists exactly
/// when the bell does — a user with no `notifications` module in any panel has
/// asked for no notification furniture at all, and `[modules.notifications]` is
/// where the key that configures this lives.
///
/// Nothing here is created until a lease is taken and the player is disposed
/// with the last release, so a shell with the module switched off never opens
/// mpv.
class NotificationSoundStore extends ChangeNotifier {
  static final NotificationSoundStore instance = NotificationSoundStore._();
  NotificationSoundStore._();

  @visibleForTesting
  factory NotificationSoundStore.forTesting() => NotificationSoundStore._();

  NotificationStore get _notifications => NotificationStore.instance;

  NotificationSoundConfig _config = const NotificationSoundConfig();
  NotificationSoundConfig get config => _config;

  /// The resolved choice, and the spelling it was resolved from — so a config
  /// sweep that did not move this key costs no filesystem walk.
  NotificationSoundChoice? _choice;
  String? _resolvedFrom;

  String? _error;

  /// Why the last attempt to play made no sound, or null.
  ///
  /// Rendered by the panel's sound row: a chime that has quietly stopped working
  /// looks exactly like a machine nobody is sending notifications to.
  String? get error => _error;

  DateTime? _lastPlayed;

  int _leases = 0;
  int _prevUnread = 0;
  bool _listening = false;

  /// The clock [kNotificationSoundInterval] is measured against. Injected so
  /// the rate limit is a unit test rather than a wall-clock wait.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  /// What actually makes a sound. Injected for the reason
  /// `NotificationStore.daemonStarter` is: the real one opens libmpv, which no
  /// test may depend on being installed.
  @visibleForTesting
  Future<void> Function(String path, double volume) play = _playWithMediaKit;

  /// Materialises a shipped voice and answers with the file's path. Injected so
  /// a test never writes into the user's cache directory.
  @visibleForTesting
  String Function(NotificationVoice voice) materialise = materialiseVoice;

  /// Resolves a spelling. Injected so a test can answer without a filesystem.
  @visibleForTesting
  NotificationSoundChoice Function(String spelling) resolve = _resolve;

  static NotificationSoundChoice _resolve(String spelling) =>
      resolveNotificationSound(
        spelling,
        soundRoots: notificationSoundRoots(),
        exists: (path) => File(path).existsSync(),
      );

  // --- leasing -------------------------------------------------------------

  void acquire() {
    _leases++;
    if (_listening) return;
    _listening = true;
    // Seeded rather than started at zero: a module rebuilt while notifications
    // are already waiting must not chime for the backlog it arrived to find.
    _prevUnread = _notifications.unreadCount;
    _notifications.addListener(_onNotificationsChanged);
  }

  void release() {
    if (_leases > 0) _leases--;
    if (_leases > 0) return;
    if (!_listening) return;
    _listening = false;
    _notifications.removeListener(_onNotificationsChanged);
    _closePlayer();
  }

  @visibleForTesting
  int get leaseCount => _leases;

  /// Whether anything is actually holding the chime open.
  ///
  /// False means no `notifications` module is in any panel, so nothing is
  /// listening for an arrival and no configured sound will play. A real state
  /// rather than an implementation detail: it is the difference between a
  /// chime that is switched off and one that is broken, and the panel's sound
  /// row says which.
  bool get armed => _listening;

  // --- config --------------------------------------------------------------

  /// Takes the module's options. A no-op when nothing moved, which matters:
  /// `Module.loadAll` runs on every keystroke anywhere in the settings UI.
  ///
  /// The state moves synchronously and the notification does not — see
  /// [_notifyLater]. Both of this store's call sites are inside a build.
  void configure(NotificationSoundConfig config) {
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

  /// What the configured spelling points at, resolved at most once per spelling.
  NotificationSoundChoice get choice {
    if (_choice != null && _resolvedFrom == _config.sound) return _choice!;
    _resolvedFrom = _config.sound;
    return _choice = resolve(_config.sound);
  }

  // --- playing -------------------------------------------------------------

  void _onNotificationsChanged() {
    final unread = _notifications.unreadCount;
    final arrived = unread > _prevUnread;
    _prevUnread = unread;
    if (!arrived) return;
    // Silence is about interruption, and a sound is the most interrupting thing
    // the shell does. The notification is still collected and still counted.
    if (_notifications.silenced) return;
    playNow();
  }

  /// Plays the configured sound, subject to [kNotificationSoundInterval].
  ///
  /// Public because the panel's sound row previews with it, which is also the
  /// one way a user can tell a misconfigured path from a quiet machine.
  void playNow({bool force = false}) {
    final at = now();
    if (!force) {
      final last = _lastPlayed;
      if (last != null && at.difference(last) < kNotificationSoundInterval) {
        return;
      }
    }

    final target = choice;
    if (target.isSilent) return;
    if (target.missing != null) {
      _setError('No sound file called “${target.missing}” was found. '
          'Name one of the shipped sounds, or give a full path to a file.');
      return;
    }

    _lastPlayed = at;
    final String path;
    try {
      path = target.path ?? _cachedVoicePath(target.voice!);
    } catch (error) {
      _setError('The chime could not be written to the cache directory: '
          '$error');
      return;
    }

    // Fire and forget, and the failure is caught rather than awaited: a chime
    // that takes a moment to open must not hold up the frame the notification
    // itself is being drawn on.
    play(path, _config.volume.clamp(0.0, 1.0)).then(
      (_) => _setError(null),
      onError: (Object error) => _setError('The chime could not be played: '
          '$error'),
    );
  }

  /// The shipped voice's file, worked out at most once per process.
  ///
  /// [materialiseVoice] already skips the synthesis when the file is there, but
  /// it still stats the cache directory; this is the chime's hot path and the
  /// answer cannot change under a running shell.
  final Map<String, String> _voicePaths = {};

  String _cachedVoicePath(NotificationVoice voice) =>
      _voicePaths[voice.slug] ??= materialise(voice);

  void _setError(String? reason) {
    if (_error == reason) return;
    _error = reason;
    _notifyLater();
  }

  /// Notifies once the frame in flight is over.
  ///
  /// Every writer here can be reached from inside a build: [configure] is
  /// called from the notifications module's `initState` and `didUpdateWidget`,
  /// which both run during one, and the panel's sound row listens to this store
  /// from a *different* FlutterView — so a synchronous `notifyListeners` would
  /// be a `markNeedsBuild` on an element already being built, which is an
  /// assertion rather than a stale frame. The same rule the leases state as
  /// "`acquire()` must not notify synchronously".
  ///
  /// A microtask rather than a post-frame callback, because this file is
  /// deliberately free of the widget layer.
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
    _leases = 0;
    if (_listening) {
      _listening = false;
      _notifications.removeListener(_onNotificationsChanged);
    }
    _config = const NotificationSoundConfig();
    _choice = null;
    _resolvedFrom = null;
    _error = null;
    _lastPlayed = null;
    _prevUnread = 0;
    _voicePaths.clear();
    _notifyQueued = false;
    now = DateTime.now;
    play = _playWithMediaKit;
    materialise = materialiseVoice;
    resolve = _resolve;
  }
}

/// Renders [voice] into the cache directory if it is not already there, and
/// answers with its path.
///
/// Re-rendered when the file's length does not match what this build produces,
/// so a voice whose numbers were tuned in a later release reaches an install
/// that has already run — the same rule `ThemeStore` re-seeds shipped palettes
/// under.
String materialiseVoice(
  NotificationVoice voice, {
  Map<String, String>? environment,
}) =>
    materialiseSound(
      '${voice.slug}.wav',
      expectedLength: notificationWavByteLength(voice),
      bytes: () => renderNotificationWav(voice),
      environment: environment,
    );

/// The one media_kit player the chime uses.
///
/// One for the process, kept between chimes: opening a player costs an mpv
/// initialisation, and a store that built one per notification would spend it
/// every time. It is closed with the last lease. The shutter keeps its own —
/// see [ShellSoundPlayer] for why the two are not one.
final ShellSoundPlayer _player = ShellSoundPlayer();

Future<void> _playWithMediaKit(String path, double volume) =>
    _player.play(path, volume);

void _closePlayer() => _player.close();
