/// The sound a volume change makes: the sounds the shell ships, where a
/// configured one resolves to, and the player that plays it.
///
/// Four things here that a change has to keep true.
///
/// - **The shipped sounds are synthesised, not shipped as files.** Nothing in
///   the shell resolves a path relative to the bundle — see
///   `lib/shell_sound.dart`, which every sound in the shell shares that rule
///   through. It is also what keeps the set free software in the only sense
///   that matters here: there is no sample from anywhere, only arithmetic under
///   this project's own GPL-3.0. A user who would rather hear the desktop's
///   stock sound can say so: `audio-volume-change` is the name
///   `sound-theme-freedesktop` ships it under, and a bare name is looked up in
///   the machine's sound themes like every other sound key.
/// - **A pop is a struck tone, so it borrows the chime's renderer** — the
///   timer alarm's reasoning, and the same namespacing: the cache file is
///   `volume-<slug>.wav`, so a voice here and a chime that happened to share a
///   slug cannot share a file.
/// - **It plays through the device that just moved.** mpv opens its stream on
///   the default sink, so the pop is heard at the level the user has just
///   chosen, which is the whole point of it: it answers "how loud is that now"
///   before any music does. A mute is therefore silent by construction and is
///   not played at all; an unmute is.
/// - **A failure is a visible state.** A sound file that has been moved, or an
///   mpv that will not open it, leaves [VolumeSoundStore.error] set and the
///   settings pane renders it — a feedback sound that quietly stopped working
///   is indistinguishable from one the user switched off.
///
/// Flutter-free apart from [ChangeNotifier], like the layer under it.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:moonswing/notification_sound.dart';
import 'package:moonswing/shell_sound.dart';

/// One shipped sound, as the numbers it is rendered from. The chime's
/// [NotificationVoice] under this family's name, as the timer alarm's is.
typedef VolumeVoice = NotificationVoice;

/// The `volume_sound` value a fresh config has.
const String kDefaultVolumeSound = 'pop';

/// How loud the sound is when the config says nothing.
///
/// Quieter than the chime's 0.7: this plays on every press of a volume key,
/// through a device the user is in the middle of turning up.
const double kDefaultVolumeSoundVolume = 0.6;

/// The shortest gap between two sounds.
///
/// A held volume key repeats at twenty-five a second, and PulseAudio reports
/// every step; a pop per step would be a buzz. One pop per this long keeps a
/// held key audibly ticking without piling copies on top of each other.
const Duration kVolumeSoundInterval = Duration(milliseconds: 120);

// ---------------------------------------------------------------------------
// The shipped sounds
// ---------------------------------------------------------------------------

/// A clean series: a feedback sound that plays this often has to be short and
/// unambiguous, and a rich bell turns to mud when it repeats.
const List<NotificationPartial> _cleanPartials = [
  NotificationPartial(1.0, 1.0, 1.0),
  NotificationPartial(2.0, 0.16, 0.5),
  NotificationPartial(3.01, 0.05, 0.25),
];

/// The sounds the shell ships, in the order the settings row lists them.
const List<VolumeVoice> kVolumeVoices = [_pop, _tick, _blip];

/// The default: one short, soft, rounded tone — the shape every desktop's
/// volume feedback has converged on, because it is over before it is noticed
/// and still says how loud the speaker now is.
const VolumeVoice _pop = VolumeVoice(
  slug: 'pop',
  label: 'Pop',
  description: 'One short, soft tone. The default.',
  partials: _cleanPartials,
  strikes: [
    NotificationStrike(at: 0.0, frequency: 830.61, decay: 0.11),
  ],
);

/// A dry click with no tune to it, for somebody who wants to know the key
/// registered and nothing else.
const VolumeVoice _tick = VolumeVoice(
  slug: 'tick',
  label: 'Tick',
  description: 'A dry click with no tune to it.',
  partials: [
    NotificationPartial(1.0, 1.0, 1.0),
    NotificationPartial(1.59, 0.6, 0.6),
    NotificationPartial(2.83, 0.35, 0.35),
  ],
  strikes: [
    NotificationStrike(at: 0.0, frequency: 1760.0, decay: 0.035),
  ],
);

/// A brighter, slightly longer tone than [_pop], which carries over music.
const VolumeVoice _blip = VolumeVoice(
  slug: 'blip',
  label: 'Blip',
  description: 'A bright, slightly longer tone that carries over music.',
  partials: _cleanPartials,
  strikes: [
    NotificationStrike(at: 0.0, frequency: 1318.51, decay: 0.2),
  ],
);

/// The name `sound-theme-freedesktop` ships its volume feedback under, offered
/// by name in [kVolumeSoundHint] because it is the one a user is most likely
/// to already have and want.
const String kFreedesktopVolumeSound = 'audio-volume-change';

/// The placeholder the settings row shows, built from the catalogue so a voice
/// added above cannot go unmentioned in the one place a user would look.
final String kVolumeSoundHint =
    '${kVolumeVoices.map((v) => v.slug).join(', ')}, '
    '$kFreedesktopVolumeSound, none, or a path';

/// The shipped voice called [slug], or null.
VolumeVoice? volumeVoice(String slug) {
  final wanted = slug.trim().toLowerCase();
  for (final voice in kVolumeVoices) {
    if (voice.slug == wanted) return voice;
  }
  return null;
}

/// Renders [voice] into the sound cache if it is not already there, and
/// answers with its path. Namespaced `volume-…` — see the note at the top.
String materialiseVolumeVoice(
  VolumeVoice voice, {
  Map<String, String>? environment,
}) =>
    materialiseSound(
      'volume-${voice.slug}.wav',
      expectedLength: notificationWavByteLength(voice),
      bytes: () => renderNotificationWav(voice),
      environment: environment,
    );

// ---------------------------------------------------------------------------
// Resolving what the config asked for
// ---------------------------------------------------------------------------

/// Where a `volume_sound` value points.
///
/// Four outcomes, and the fourth is why this is a class rather than a nullable
/// path: a name that resolves to nothing is not silence.
@immutable
class VolumeSoundChoice {
  const VolumeSoundChoice.silent()
      : voice = null,
        path = null,
        missing = null;

  const VolumeSoundChoice.shipped(VolumeVoice this.voice)
      : path = null,
        missing = null;

  const VolumeSoundChoice.file(String this.path)
      : voice = null,
        missing = null;

  const VolumeSoundChoice.missing(String this.missing)
      : voice = null,
        path = null;

  /// The shipped voice to render, when the config named one.
  final VolumeVoice? voice;

  /// A file on disk that exists.
  final String? path;

  /// What was asked for, when nothing on disk matched it.
  final String? missing;

  /// Whether this choice plays nothing *on purpose*.
  bool get isSilent => voice == null && path == null && missing == null;
}

/// Resolves the `volume_sound` key's [spelling] against the filesystem.
///
/// An off switch, then a shipped voice, then a path, then a sound-theme name —
/// the order every sound key in the shell resolves in, so a theme containing a
/// `pop` cannot take the shipped one away.
VolumeSoundChoice resolveVolumeSound(
  String spelling, {
  required List<String> soundRoots,
  required bool Function(String path) exists,
  String? home,
}) {
  final wanted = spelling.trim();
  if (isSoundOff(wanted)) return const VolumeSoundChoice.silent();

  final shipped = volumeVoice(wanted);
  if (shipped != null) return VolumeSoundChoice.shipped(shipped);

  final file = resolveSoundFile(
    wanted,
    soundRoots: soundRoots,
    exists: exists,
    home: home,
  );
  return file == null
      ? VolumeSoundChoice.missing(wanted)
      : VolumeSoundChoice.file(file);
}

// ---------------------------------------------------------------------------
// The config the store reads
// ---------------------------------------------------------------------------

/// What `[osd]` says about the sound.
///
/// An `[osd]` key because the indicator is what already watches the volume:
/// the card and the sound answer the same PulseAudio event.
@immutable
class VolumeSoundConfig {
  const VolumeSoundConfig({
    this.sound = kDefaultVolumeSound,
    this.volume = kDefaultVolumeSoundVolume,
  });

  /// A shipped voice's slug, a path, a sound-theme name, or one of
  /// [kShellSoundOff].
  final String sound;

  /// 0 to 1, relative to the device's own level.
  final double volume;

  /// Whether this config asks for anything to be played.
  bool get enabled => !isSoundOff(sound);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VolumeSoundConfig &&
          other.sound == sound &&
          other.volume == volume;

  @override
  int get hashCode => Object.hash(sound, volume);
}

// ---------------------------------------------------------------------------
// The player
// ---------------------------------------------------------------------------

/// Plays the sound when the default output's volume or mute moves.
///
/// Unleased, for the timer alarm's reason: nothing here polls or listens. The
/// OSD service already holds the one PulseAudio subscription for the machine
/// and calls [playNow]; the player is opened by the first volume change of the
/// session and nothing before it.
class VolumeSoundStore extends ChangeNotifier {
  static final VolumeSoundStore instance = VolumeSoundStore._();
  VolumeSoundStore._();

  @visibleForTesting
  factory VolumeSoundStore.forTesting() => VolumeSoundStore._();

  VolumeSoundConfig _config = const VolumeSoundConfig();
  VolumeSoundConfig get config => _config;

  /// The resolved choice, and the spelling it was resolved from — so a config
  /// sweep that did not move this key costs no filesystem walk.
  VolumeSoundChoice? _choice;
  String? _resolvedFrom;

  String? _error;

  /// Why the last attempt to play made no sound, or null.
  String? get error => _error;

  DateTime? _lastPlayed;

  /// The clock [kVolumeSoundInterval] is measured against.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  /// What actually makes a sound. The real one opens libmpv, which no test may
  /// depend on being installed.
  @visibleForTesting
  Future<void> Function(String path, double volume) play = _player.play;

  /// Materialises a shipped voice and answers with the file's path.
  @visibleForTesting
  String Function(VolumeVoice voice) materialise = materialiseVolumeVoice;

  /// Resolves a spelling.
  @visibleForTesting
  VolumeSoundChoice Function(String spelling) resolve = _resolve;

  /// One player for this family, not for the shell — see [ShellSoundPlayer].
  /// Its own also means a pop cuts off the previous pop, never a chime.
  static final ShellSoundPlayer _player = ShellSoundPlayer();

  static VolumeSoundChoice _resolve(String spelling) => resolveVolumeSound(
        spelling,
        soundRoots: shellSoundRoots(),
        exists: (path) => File(path).existsSync(),
      );

  /// Takes the `[osd]` options. A no-op when nothing moved, which matters: the
  /// root re-derives the config on every keystroke anywhere in the settings UI.
  void configure(VolumeSoundConfig config) {
    if (_config == config) return;
    final soundChanged = _config.sound != config.sound;
    _config = config;
    if (soundChanged) {
      _choice = null;
      _resolvedFrom = null;
      // The old reason belonged to the old spelling.
      _error = null;
    }
    _notifyLater();
  }

  /// What the configured spelling points at, resolved at most once per
  /// spelling.
  VolumeSoundChoice get choice {
    if (_choice != null && _resolvedFrom == _config.sound) return _choice!;
    _resolvedFrom = _config.sound;
    return _choice = resolve(_config.sound);
  }

  /// Plays the configured sound, subject to [kVolumeSoundInterval].
  ///
  /// [force] is the settings pane's preview, which the user just asked for and
  /// so may not be swallowed by a key press a moment before it.
  ///
  /// Never throws: this is called from a PulseAudio event handler whose other
  /// half raises the indicator, and a sound that cannot be worked out must cost
  /// the sound and nothing else.
  void playNow({bool force = false}) {
    final at = now();
    if (!force) {
      final last = _lastPlayed;
      // A clock stepped backwards is not a burst: the gap is dropped, not read
      // as negative, or one step back would mute the sound until it caught up.
      if (last != null &&
          !at.isBefore(last) &&
          at.difference(last) < kVolumeSoundInterval) {
        return;
      }
    }

    final VolumeSoundChoice target;
    try {
      target = choice;
    } catch (error) {
      _setError('The volume sound could not be looked up: $error');
      return;
    }

    if (target.isSilent) return;
    if (target.missing != null) {
      _setError('No sound called “${target.missing}” was found. Name one of '
          'the shipped sounds, or give a full path to a file.');
      return;
    }

    _lastPlayed = at;
    final String path;
    try {
      path = target.path ?? _cachedVoicePath(target.voice!);
    } catch (error) {
      _setError('The volume sound could not be written to the cache '
          'directory: $error');
      return;
    }

    play(path, _config.volume.clamp(0.0, 1.0)).then(
      (_) => _setError(null),
      onError: (Object error) =>
          _setError('The volume sound could not be played: $error'),
    );
  }

  /// The shipped voice's file, worked out at most once per process.
  final Map<String, String> _voicePaths = {};

  String _cachedVoicePath(VolumeVoice voice) =>
      _voicePaths[voice.slug] ??= materialise(voice);

  void _setError(String? reason) {
    if (_error == reason) return;
    _error = reason;
    _notifyLater();
  }

  /// Notifies once the current turn is over — [configure] can be reached
  /// while a frame is being built, and the pane that renders [error] lives in
  /// another FlutterView. See `TimerSoundStore._notifyLater`.
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
    _config = const VolumeSoundConfig();
    _choice = null;
    _resolvedFrom = null;
    _error = null;
    _lastPlayed = null;
    _voicePaths.clear();
    _notifyQueued = false;
    now = DateTime.now;
    play = _player.play;
    materialise = materialiseVolumeVoice;
    resolve = _resolve;
  }
}
