import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/modules/clock.dart';
import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/notification_sound.dart';
import 'package:graceful_shell/shell_sound.dart';
import 'package:graceful_shell/timers/timer_sound.dart';
import 'package:graceful_shell/timers/timer_store.dart';

/// A voice out of the shipped catalogue, so the tests below pin what the shell
/// actually rings rather than a fixture that could drift from it.
TimerVoice _voice(String slug) => timerVoice(slug)!;

/// The store under test, with every injectable seam answered in memory: no
/// libmpv, no cache directory, no filesystem, and a clock that does not move
/// unless a test moves it.
TimerSoundStore _store({TimerSoundChoice? choice, DateTime? at}) {
  final store = TimerSoundStore.forTesting();
  store.now = () => at ?? DateTime(2026, 8, 24, 12);
  store.materialise = (voice) => '/cache/timer-${voice.slug}.wav';
  store.resolve = (spelling) =>
      choice ??
      resolveTimerSound(spelling, soundRoots: const [], exists: (_) => false);
  return store;
}

/// The samples of a rendered voice, as doubles in -1..1.
List<double> _samples(Uint8List wav) {
  final view = ByteData.sublistView(wav);
  return [
    for (var i = kWavHeaderBytes; i + 1 < wav.length; i += 2)
      view.getInt16(i, Endian.little) / 32768.0,
  ];
}

/// The loudest sample in `[from, to)`, as a fraction of the file's own peak.
double _energyBetween(List<double> samples, int from, int to) {
  var loudest = 0.0;
  for (var i = from.clamp(0, samples.length);
      i < to.clamp(0, samples.length);
      i++) {
    final magnitude = samples[i].abs();
    if (magnitude > loudest) loudest = magnitude;
  }
  return loudest;
}

int _frame(double seconds) => (seconds * kShellSoundSampleRate).round();

void main() {
  tearDown(TimerSoundStore.instance.resetForTesting);

  group('the shipped alarms', () {
    test('every voice renders a playable RIFF/WAVE file', () {
      for (final voice in kTimerVoices) {
        final bytes = renderNotificationWav(voice);
        expect(bytes.length, greaterThan(kWavHeaderBytes), reason: voice.slug);

        final header = ByteData.sublistView(bytes);
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF',
            reason: voice.slug);
        expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE',
            reason: voice.slug);
        expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data',
            reason: voice.slug);
        expect(header.getUint16(20, Endian.little), 1,
            reason: '${voice.slug}: PCM');
        expect(header.getUint16(22, Endian.little), 1,
            reason: '${voice.slug}: mono');
        expect(header.getUint32(24, Endian.little), kShellSoundSampleRate,
            reason: voice.slug);
      }
    });

    test('the byte length is arithmetic, and it is the right arithmetic', () {
      // `materialiseSound` decides whether a cached file is this build's by
      // comparing its length, so a predictor that disagreed with the renderer
      // would re-synthesise every alarm for the life of the install — or worse,
      // keep a stale one forever.
      for (final voice in kTimerVoices) {
        expect(timerWavByteLength(voice), renderNotificationWav(voice).length,
            reason: voice.slug);
      }
    });

    test('every voice starts and ends at silence', () {
      // A step discontinuity at either end is a click in front of or behind the
      // alarm, which every speaker in the world reproduces faithfully.
      for (final voice in kTimerVoices) {
        final samples = _samples(renderNotificationWav(voice));
        expect(samples.first.abs(), lessThan(0.02), reason: voice.slug);
        expect(samples.last.abs(), lessThan(0.02), reason: voice.slug);
      }
    });

    test('every voice is normalised, and none of them clips', () {
      for (final voice in kTimerVoices) {
        final samples = _samples(renderNotificationWav(voice));
        final peak = samples.fold<double>(
            0, (loudest, s) => s.abs() > loudest ? s.abs() : loudest);
        expect(peak, lessThanOrEqualTo(1.0), reason: voice.slug);
        expect(peak, closeTo(kShellSoundPeak, 0.01), reason: voice.slug);
      }
    });

    test('an alarm rings, but none of them outstays the rate limit', () {
      // Long enough to be heard from another room, and short enough that the
      // next timer's alarm is not played over this one — `kTimerSoundInterval`
      // is what stops a batch overlapping, and a voice longer than it would
      // defeat that.
      for (final voice in kTimerVoices) {
        expect(voice.duration, greaterThan(0.3), reason: voice.slug);
        expect(voice.duration * 1000,
            lessThanOrEqualTo(kTimerSoundInterval.inMilliseconds * 3.0),
            reason: voice.slug);
      }
    });

    test('the default is one strike, and it is the shipped default', () {
      expect(kDefaultTimerSound, 'ding');
      expect(timerVoice(kDefaultTimerSound), isNotNull);
      expect(_voice('ding').strikes, hasLength(1));
    });

    test('ding-dong is two notes, and the second one falls', () {
      final voice = _voice('ding-dong');
      expect(voice.strikes, hasLength(2));
      expect(voice.strikes[1].frequency, lessThan(voice.strikes[0].frequency),
          reason: 'a doorbell falls; a rising figure is the chime');

      final samples = _samples(renderNotificationWav(voice));
      final second = _energyBetween(samples, _frame(voice.strikes[1].at),
          _frame(voice.strikes[1].at + 0.02));
      expect(second, greaterThan(0.2),
          reason: 'the second note has to be audible');
    });

    test('alarm repeats, with a gap the ear can hear', () {
      // The repeat is the whole voice: what makes an alarm read as "still going
      // off" is silence between the bursts, not the tones themselves.
      final voice = _voice('alarm');
      expect(voice.strikes.length, greaterThan(3));

      final samples = _samples(renderNotificationWav(voice));
      final gap = _energyBetween(samples, _frame(0.47), _frame(0.6));
      final burst = _energyBetween(samples, _frame(0.62), _frame(0.68));
      expect(burst, greaterThan(0.2));
      expect(gap, lessThan(burst / 2),
          reason: 'there has to be a rest between the two bursts');
    });

    test('the hint names every shipped voice', () {
      // The settings row's placeholder is the one place a user looks for the
      // set, so a voice added to the catalogue cannot go unmentioned in it.
      for (final voice in kTimerVoices) {
        expect(kTimerSoundHint, contains(voice.slug), reason: voice.slug);
      }
      expect(kTimerSoundHint, contains('none'));
    });

    test('a shipped alarm caches under its own namespace', () {
      // One cache directory for the whole shell, so a timer voice and a chime
      // voice that happened to share a slug must not share a file. Into a
      // temporary XDG_CACHE_HOME, never the machine's own.
      final cache = Directory.systemTemp.createTempSync('timer-sound-test');
      addTearDown(() => cache.deleteSync(recursive: true));
      final environment = {'XDG_CACHE_HOME': cache.path};

      final voice = _voice('ding');
      final path = materialiseTimerVoice(voice, environment: environment);
      expect(path, '${cache.path}/graceful-shell/sounds/timer-ding.wav');
      expect(File(path).lengthSync(), timerWavByteLength(voice));

      // And the chime's own file is a different one, even where the slugs are
      // the same string.
      expect(
        materialiseVoice(notificationVoice('bell')!, environment: environment),
        isNot(path),
      );
    });

    test('a cached file this build already wrote is not re-rendered', () {
      final cache = Directory.systemTemp.createTempSync('timer-sound-test');
      addTearDown(() => cache.deleteSync(recursive: true));
      final environment = {'XDG_CACHE_HOME': cache.path};

      final path = materialiseTimerVoice(_voice('ding'),
          environment: environment);
      final written = File(path).lastModifiedSync();
      materialiseTimerVoice(_voice('ding'), environment: environment);

      expect(File(path).lastModifiedSync(), written);
    });
  });

  group('resolveTimerSound', () {
    TimerSoundChoice resolve(
      String spelling, {
      List<String> roots = const ['/usr/share/sounds'],
      Set<String> present = const {},
      String? home,
    }) =>
        resolveTimerSound(spelling,
            soundRoots: roots, exists: present.contains, home: home);

    test('the off switches are silence, not a missing file', () {
      for (final spelling in const [
        'none',
        'off',
        'silent',
        'OFF',
        ' none ',
        ''
      ]) {
        final choice = resolve(spelling);
        expect(choice.isSilent, isTrue, reason: spelling);
        expect(choice.missing, isNull, reason: spelling);
      }
    });

    test('a shipped slug wins over anything on disk', () {
      final choice = resolve('alarm', present: const {
        '/usr/share/sounds/alarm.oga',
      });
      expect(choice.voice?.slug, 'alarm');
      expect(choice.path, isNull);
    });

    test('a path is taken as one, and a missing one says so', () {
      expect(
        resolve('/opt/sounds/mine.wav', present: const {'/opt/sounds/mine.wav'})
            .path,
        '/opt/sounds/mine.wav',
      );
      final missing = resolve('/opt/sounds/gone.wav');
      expect(missing.path, isNull);
      expect(missing.missing, '/opt/sounds/gone.wav');
    });

    test('~ is expanded against the home it is given', () {
      final choice = resolve('~/sounds/mine.oga',
          home: '/home/somebody',
          present: const {'/home/somebody/sounds/mine.oga'});
      expect(choice.path, '/home/somebody/sounds/mine.oga');
    });

    test('a bare name finds the sound theme layout', () {
      final choice = resolve('complete', present: const {
        '/usr/share/sounds/freedesktop/stereo/complete.oga',
      });
      expect(choice.path, '/usr/share/sounds/freedesktop/stereo/complete.oga');
    });

    test('a name that resolves to nothing is missing, not silent', () {
      final choice = resolve('nonesuch');
      expect(choice.isSilent, isFalse);
      expect(choice.missing, 'nonesuch');
      expect(choice.label, 'nonesuch');
    });
  });

  group('TimerSoundStore', () {
    test('a finished countdown rings the configured alarm', () {
      final played = <(String, double)>[];
      final store = _store(choice: TimerSoundChoice.shipped(_voice('gong')))
        ..configure(const TimerSoundConfig(sound: 'gong', volume: 0.4));
      store.play = (path, volume) async => played.add((path, volume));

      store.playNow();

      expect(played, [('/cache/timer-gong.wav', 0.4)]);
      expect(store.error, isNull);
    });

    test('a batch of timers finishing rings once', () {
      // Three countdowns set to the same minute finish on one tick. Unlike the
      // shutter, which is two things the user did, this is one moment.
      var plays = 0;
      var at = DateTime(2026, 8, 24, 12);
      final store = _store(choice: TimerSoundChoice.shipped(_voice('ding')));
      store.now = () => at;
      store.play = (path, volume) async => plays++;

      store.playNow();
      store.playNow();
      store.playNow();
      expect(plays, 1);

      at = at.add(kTimerSoundInterval);
      store.playNow();
      expect(plays, 2, reason: 'a later timer is a later alarm');
    });

    test('a preview is not swallowed by the rate limit', () {
      var plays = 0;
      final store = _store(choice: TimerSoundChoice.shipped(_voice('ding')));
      store.play = (path, volume) async => plays++;

      store.playNow();
      store.playNow(force: true);

      expect(plays, 2);
    });

    test('silence plays nothing and reports nothing wrong', () {
      var plays = 0;
      final store = _store()..configure(const TimerSoundConfig(sound: 'none'));
      store.play = (path, volume) async => plays++;

      store.playNow();

      expect(plays, 0);
      expect(store.error, isNull);
    });

    test('a sound that is not there is a visible failure', () {
      var plays = 0;
      final store = _store()
        ..configure(const TimerSoundConfig(sound: 'nonesuch'));
      store.play = (path, volume) async => plays++;

      store.playNow();

      expect(plays, 0);
      expect(store.error, contains('nonesuch'));
    });

    test('a player that throws is a visible failure too', () async {
      final store = _store(choice: TimerSoundChoice.shipped(_voice('ding')));
      store.play = (path, volume) async => throw StateError('no mpv here');

      store.playNow();
      await Future<void>.delayed(Duration.zero);

      expect(store.error, contains('could not be played'));
    });

    test('a successful play clears an earlier reason', () async {
      var at = DateTime(2026, 8, 24, 12);
      final store = _store(choice: TimerSoundChoice.shipped(_voice('ding')));
      store.now = () => at;
      store.play = (path, volume) async => throw StateError('no mpv here');
      store.playNow();
      await Future<void>.delayed(Duration.zero);
      expect(store.error, isNotNull);

      at = at.add(kTimerSoundInterval);
      store.play = (path, volume) async {};
      store.playNow();
      await Future<void>.delayed(Duration.zero);

      expect(store.error, isNull);
    });

    test('a lookup that throws is a visible failure, not a thrown one', () {
      // `TimersStore.tick` calls this on the path that has already retired the
      // entry and is about to notify every readout in the shell.
      final store = _store();
      store.resolve = (spelling) => throw StateError('no filesystem here');

      expect(store.playNow, returnsNormally);
      expect(store.error, contains('could not be looked up'));
    });

    test('volume is clamped rather than trusted', () {
      final played = <double>[];
      final store = _store(choice: TimerSoundChoice.shipped(_voice('ding')))
        ..configure(const TimerSoundConfig(volume: 40));
      store.play = (path, volume) async => played.add(volume);

      store.playNow();

      expect(played, [1.0]);
    });

    test('a spelling is resolved once per spelling, not once per ring', () {
      var resolves = 0;
      var at = DateTime(2026, 8, 24, 12);
      final store = _store();
      store.now = () => at;
      store.resolve = (spelling) {
        resolves++;
        return TimerSoundChoice.shipped(_voice('ding'));
      };
      store.play = (path, volume) async {};

      store.playNow();
      at = at.add(kTimerSoundInterval);
      store.playNow();
      expect(resolves, 1);

      store.configure(const TimerSoundConfig(sound: 'gong'));
      at = at.add(kTimerSoundInterval);
      store.playNow();
      expect(resolves, 2);
    });

    test('a config sweep that moved nothing is a no-op', () {
      var resolves = 0;
      final store = _store();
      store.resolve = (spelling) {
        resolves++;
        return const TimerSoundChoice.silent();
      };
      store.configure(const TimerSoundConfig());
      store.playNow();
      store.configure(const TimerSoundConfig());
      store.playNow();

      expect(resolves, 1);
    });

    test('a corrected spelling drops the reason it was typed to fix', () {
      final store = _store()
        ..configure(const TimerSoundConfig(sound: 'nonesuch'));
      store.play = (path, volume) async {};
      store.playNow();
      expect(store.error, isNotNull);

      store.configure(const TimerSoundConfig(sound: 'ding'));
      expect(store.error, isNull);
    });
  });

  group('announceFinishedTimer', () {
    // Through the singletons on purpose: this is the wiring `TimersStore`
    // actually holds, and the point of the test is that both halves happen.
    final notifications = NotificationStore.instance;
    final sound = TimerSoundStore.instance;

    tearDown(notifications.dismissAll);

    const finished = ShellTimer(
      id: 1,
      kind: ShellTimerKind.timer,
      total: Duration(minutes: 5),
      accumulated: Duration(minutes: 5),
      startedAt: null,
      finished: true,
    );

    test('a finished countdown rings and then says so', () {
      final played = <String>[];
      sound.resolve = (_) => TimerSoundChoice.shipped(_voice('ding'));
      sound.materialise = (voice) => '/cache/timer-${voice.slug}.wav';
      sound.play = (path, volume) async => played.add(path);

      announceFinishedTimer(finished);

      expect(played, ['/cache/timer-ding.wav']);
      expect(notifications.items, hasLength(1));
      expect(notifications.items.single.summary, 'Timer finished');
      expect(notifications.items.single.body, contains('05:00'));
      expect(notifications.items.single.expireTimeout, 0,
          reason: 'a fired timer stays until it is dismissed');
    });

    test('a silent alarm still notifies', () {
      var plays = 0;
      sound.resolve = (_) => const TimerSoundChoice.silent();
      sound.play = (path, volume) async => plays++;

      announceFinishedTimer(finished);

      expect(plays, 0);
      expect(notifications.items, hasLength(1));
    });

    test('the notification is posted chimeless', () {
      sound.resolve = (_) => const TimerSoundChoice.silent();
      final before = notifications.chimelessArrivals;

      announceFinishedTimer(finished);

      expect(notifications.chimelessArrivals, before + 1,
          reason: 'the alarm has already sounded for this one');
    });
  });

  group('[modules.clock]', () {
    test('the alarm keys are read off the clock table', () {
      final config = ClockConfig.fromMap(const {
        'timer_sound': 'gong',
        'timer_volume': 0.25,
      });
      expect(config.timerSound, 'gong');
      expect(config.timerVolume, 0.25);
      expect(config.timerSoundConfig,
          const TimerSoundConfig(sound: 'gong', volume: 0.25));
    });

    test('a wrongly typed value costs that key and nothing else', () {
      final config = ClockConfig.fromMap(const {
        'show_date': false,
        'timer_sound': 42,
        'timer_volume': 'loud',
      });
      expect(config.showDate, isFalse, reason: 'the good key survives');
      expect(config.timerSound, kDefaultTimerSound);
      expect(config.timerVolume, kDefaultTimerVolume);
    });

    test('volume is clamped at the reader, not just at the player', () {
      expect(ClockConfig.fromMap(const {'timer_volume': 40}).timerVolume, 1.0);
      expect(ClockConfig.fromMap(const {'timer_volume': -1}).timerVolume, 0.0);
    });

    test('an absent table is every default', () {
      const defaults = ClockConfig();
      expect(ClockConfig.fromMap(null), defaults);
      expect(defaults.timerSound, kDefaultTimerSound);
      expect(defaults.timerVolume, kDefaultTimerVolume);
    });
  });
}
