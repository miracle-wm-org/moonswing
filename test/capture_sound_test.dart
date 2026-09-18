import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/capture/capture_config.dart';
import 'package:graceful_shell/capture/capture_sound.dart';
import 'package:graceful_shell/shell_sound.dart';

/// A voice out of the shipped catalogue, so the tests below pin what the shell
/// actually plays rather than a fixture that could drift from it.
ShutterVoice _voice(String slug) => shutterVoice(slug)!;

/// The store under test, with every injectable seam answered in memory: no
/// libmpv, no cache directory, no filesystem.
ShutterSoundStore _store({ShutterSoundChoice? choice}) {
  final store = ShutterSoundStore.forTesting();
  store.materialise = (voice) => '/cache/shutter-${voice.slug}.wav';
  store.resolve = (spelling) =>
      choice ??
      resolveShutterSound(spelling, soundRoots: const [], exists: (_) => false);
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
  for (var i = from.clamp(0, samples.length); i < to.clamp(0, samples.length); i++) {
    final magnitude = samples[i].abs();
    if (magnitude > loudest) loudest = magnitude;
  }
  return loudest;
}

void main() {
  tearDown(ShutterSoundStore.instance.resetForTesting);

  group('the shipped shutters', () {
    test('every voice renders a playable RIFF/WAVE file', () {
      for (final voice in kShutterVoices) {
        final bytes = renderShutterWav(voice);
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
        expect(header.getUint32(40, Endian.little),
            bytes.length - kWavHeaderBytes,
            reason: '${voice.slug}: the data chunk is the rest of the file');
      }
    });

    test('every voice starts and ends at silence', () {
      // Both ends are a click otherwise, which is the one artefact a sound made
      // of clicks cannot afford: it would be heard as part of the shutter.
      for (final voice in kShutterVoices) {
        final samples = _samples(renderShutterWav(voice));
        expect(samples.first.abs(), lessThan(0.02), reason: voice.slug);
        expect(samples.last.abs(), lessThan(0.02), reason: voice.slug);
      }
    });

    test('every voice is normalised, and none of them clips', () {
      for (final voice in kShutterVoices) {
        final samples = _samples(renderShutterWav(voice));
        final peak = samples.fold<double>(
            0, (loudest, s) => s.abs() > loudest ? s.abs() : loudest);
        expect(peak, lessThanOrEqualTo(1.0), reason: voice.slug);
        expect(peak, closeTo(kShellSoundPeak, 0.01), reason: voice.slug);
      }
    });

    test('a shutter is short — none of them outlasts a third of a second', () {
      // The point of the sound is that it is over by the time the user has
      // finished the gesture that caused it. The heaviest voice here rings for
      // a quarter of a second and that is the outer bound: past this it stops
      // being a confirmation and becomes a thing the shell is playing at them.
      for (final voice in kShutterVoices) {
        expect(voice.duration, lessThan(0.33), reason: voice.slug);
      }
    });

    test('the default is two clicks, and they land where it says they do', () {
      // A reflex camera is mirror-then-curtain, and the gap is what makes it
      // read as a camera rather than as a tap. If the second click ever stops
      // landing here the sound has quietly become something else.
      final voice = _voice('shutter');
      expect(voice.clicks, hasLength(2));
      final samples = _samples(renderShutterWav(voice));

      int frame(double seconds) => (seconds * kShellSoundSampleRate).round();
      final gap = _energyBetween(
          samples, frame(0.06), frame(voice.clicks[1].at - 0.005));
      final second = _energyBetween(
          samples, frame(voice.clicks[1].at), frame(voice.clicks[1].at + 0.01));

      expect(second, greaterThan(0.2),
          reason: 'the second click has to be audible');
      expect(gap, lessThan(second / 2),
          reason: 'and there has to be a gap in front of it');
    });

    test('rendering is deterministic, noise and all', () {
      // `materialiseSound` decides the cached file is current by its length, so
      // a renderer whose samples moved between runs would leave every install
      // playing whichever noise it happened to render first.
      for (final voice in kShutterVoices) {
        expect(renderShutterWav(voice), renderShutterWav(voice),
            reason: voice.slug);
      }
    });

    test('the byte length is arithmetic, and matches what is rendered', () {
      for (final voice in kShutterVoices) {
        expect(shutterWavByteLength(voice), renderShutterWav(voice).length,
            reason: voice.slug);
      }
    });

    test('the default is one of them, and the slugs are unique', () {
      expect(shutterVoice(kDefaultShutterSound), isNotNull);
      expect(kShutterVoices.map((v) => v.slug).toSet(),
          hasLength(kShutterVoices.length));
      for (final voice in kShutterVoices) {
        expect(voice.label, isNotEmpty, reason: voice.slug);
        expect(voice.description, isNotEmpty, reason: voice.slug);
        expect(voice.clicks, isNotEmpty, reason: voice.slug);
        expect(kShutterSoundHint, contains(voice.slug),
            reason: 'the settings hint names the whole shipped set');
      }
    });

    test('an unknown slug is not a voice', () {
      expect(shutterVoice('nonesuch'), isNull);
      expect(shutterVoice(''), isNull);
      // The chime's voices are not shutters, and the shell must not quietly
      // play one in place of the other.
      expect(shutterVoice('chime'), isNull);
    });
  });

  group('resolveShutterSound', () {
    ShutterSoundChoice resolve(
      String spelling, {
      List<String> roots = const ['/usr/share/sounds'],
      Set<String> present = const {},
      String? home,
    }) =>
        resolveShutterSound(spelling,
            soundRoots: roots, exists: present.contains, home: home);

    test('the off switches are silence, not a missing file', () {
      for (final spelling in const ['none', 'off', 'silent', 'OFF', ' none ', '']) {
        final choice = resolve(spelling);
        expect(choice.isSilent, isTrue, reason: spelling);
        expect(choice.missing, isNull, reason: spelling);
      }
    });

    test('a shipped slug wins over anything on disk', () {
      final choice = resolve('shutter', present: const {
        '/usr/share/sounds/shutter.oga',
      });
      expect(choice.voice?.slug, 'shutter');
      expect(choice.path, isNull);
    });

    test('a path is taken as one, and a missing one says so', () {
      expect(
        resolve('/opt/sounds/mine.wav',
                present: const {'/opt/sounds/mine.wav'})
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
      final choice = resolve('camera-shutter', present: const {
        '/usr/share/sounds/freedesktop/stereo/camera-shutter.oga',
      });
      expect(choice.path,
          '/usr/share/sounds/freedesktop/stereo/camera-shutter.oga');
    });

    test('a name that resolves to nothing is missing, not silent', () {
      final choice = resolve('nonesuch');
      expect(choice.isSilent, isFalse);
      expect(choice.missing, 'nonesuch');
      expect(choice.label, 'nonesuch');
    });
  });

  group('ShutterSoundStore', () {
    test('a screenshot plays the configured shutter', () {
      final played = <(String, double)>[];
      final store = _store(choice: ShutterSoundChoice.shipped(_voice('snap')))
        ..configure(const ShutterSoundConfig(sound: 'snap', volume: 0.4));
      store.play = (path, volume) async => played.add((path, volume));

      store.playNow();

      expect(played, [('/cache/shutter-snap.wav', 0.4)]);
      expect(store.error, isNull);
    });

    test('two photographs are two shutters', () {
      // Deliberately unlike the chime, which swallows a burst: a burst of
      // notifications is one event arriving repeatedly, while two screenshots
      // are two things the user did.
      var plays = 0;
      final store = _store(choice: ShutterSoundChoice.shipped(_voice('tick')));
      store.play = (path, volume) async => plays++;

      store.playNow();
      store.playNow();

      expect(plays, 2);
    });

    test('silence plays nothing and reports nothing wrong', () {
      var plays = 0;
      final store = _store()..configure(const ShutterSoundConfig(sound: 'none'));
      store.play = (path, volume) async => plays++;

      store.playNow();

      expect(plays, 0);
      expect(store.error, isNull);
    });

    test('a sound that is not there is a visible failure', () {
      var plays = 0;
      final store = _store()
        ..configure(const ShutterSoundConfig(sound: 'nonesuch'));
      store.play = (path, volume) async => plays++;

      store.playNow();

      expect(plays, 0);
      expect(store.error, contains('nonesuch'));
    });

    test('a player that throws is a visible failure too', () async {
      final store = _store(choice: ShutterSoundChoice.shipped(_voice('snap')));
      store.play = (path, volume) async => throw StateError('no mpv here');

      store.playNow();
      await Future<void>.delayed(Duration.zero);

      expect(store.error, contains('could not be played'));
    });

    test('a successful play clears an earlier reason', () async {
      final store = _store(choice: ShutterSoundChoice.shipped(_voice('snap')));
      store.play = (path, volume) async => throw StateError('no mpv here');
      store.playNow();
      await Future<void>.delayed(Duration.zero);
      expect(store.error, isNotNull);

      store.play = (path, volume) async {};
      store.playNow();
      await Future<void>.delayed(Duration.zero);

      expect(store.error, isNull);
    });

    test('a lookup that throws is a visible failure, not a thrown one', () {
      // `CaptureStore` calls this after the PNG is on the disk and inside the
      // try that decides whether the screenshot failed, so a shutter that
      // cannot work out what to play must not take the photograph down with it.
      final store = _store();
      store.resolve = (spelling) => throw StateError('no filesystem here');

      expect(store.playNow, returnsNormally);
      expect(store.error, contains('could not be looked up'));
    });

    test('a cache that cannot be written is a visible failure too', () {
      final store = _store(choice: ShutterSoundChoice.shipped(_voice('snap')));
      store.materialise = (voice) => throw StateError('read-only home');

      expect(store.playNow, returnsNormally);
      expect(store.error, contains('cache directory'));
    });

    test('a shipped shutter is materialised once per process', () {
      var renders = 0;
      final store = _store(choice: ShutterSoundChoice.shipped(_voice('snap')));
      store.materialise = (voice) {
        renders++;
        return '/cache/shutter-${voice.slug}.wav';
      };
      store.play = (path, volume) async {};

      store.playNow();
      store.playNow();
      store.playNow();

      expect(renders, 1);
    });

    test('a change moves the state now and notifies later', () async {
      // `configure` is reached from the module's `fromMap`, which runs inside a
      // build, and the menu that renders `error` is in another FlutterView.
      final store = _store();
      var notifications = 0;
      store.addListener(() => notifications++);

      store.configure(const ShutterSoundConfig(sound: 'tick'));
      expect(store.config.sound, 'tick');
      expect(notifications, 0);

      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
    });

    test('a sweep that moved nothing notifies nobody', () async {
      final store = _store();
      var notifications = 0;
      store.addListener(() => notifications++);

      store.configure(const ShutterSoundConfig());
      await Future<void>.delayed(Duration.zero);

      expect(notifications, 0,
          reason: 'Module.loadAll runs on every keystroke in the settings UI');
    });

    test('a spelling is resolved once, and again when it moves', () {
      var resolutions = 0;
      final store = _store();
      store.resolve = (spelling) {
        resolutions++;
        return const ShutterSoundChoice.silent();
      };

      store.configure(const ShutterSoundConfig(sound: 'tick'));
      store.choice;
      store.choice;
      expect(resolutions, 1);

      store.configure(const ShutterSoundConfig(sound: 'clack'));
      store.choice;
      expect(resolutions, 2);
    });

    test('correcting the spelling drops the reason it was typed to fix', () {
      final store = _store()
        ..configure(const ShutterSoundConfig(sound: 'nonesuch'));
      store.play = (path, volume) async {};
      store.playNow();
      expect(store.error, isNotNull);

      store.configure(const ShutterSoundConfig(sound: 'snap'));

      expect(store.error, isNull);
    });
  });

  group('the screenshot config the shutter reads', () {
    test('a fresh config ships a shutter, not silence', () {
      const config = ScreenshotConfig();
      expect(config.shutterSound, kDefaultShutterSound);
      expect(shutterVoice(config.shutterSound), isNotNull);
      expect(config.soundConfig,
          const ShutterSoundConfig(
              sound: kDefaultShutterSound, volume: kDefaultShutterVolume));
    });

    test('the two keys are read off the table', () {
      final config = ScreenshotConfig.fromMap(const {
        'shutter_sound': 'clack',
        'shutter_volume': 0.25,
      });
      expect(config.shutterSound, 'clack');
      expect(config.shutterVolume, 0.25);
    });

    test('a wrongly-typed value costs that key, never the table', () {
      final config = ScreenshotConfig.fromMap(const {
        'shutter_sound': 42,
        'shutter_volume': 'loud',
        'copy_to_clipboard': false,
      });
      expect(config.shutterSound, const ScreenshotConfig().shutterSound);
      expect(config.shutterVolume, const ScreenshotConfig().shutterVolume);
      expect(config.copyToClipboard, isFalse);
    });

    test('the volume is clamped rather than trusted', () {
      expect(
          ScreenshotConfig.fromMap(const {'shutter_volume': 40}).shutterVolume,
          1.0);
      expect(
          ScreenshotConfig.fromMap(const {'shutter_volume': -1}).shutterVolume,
          0.0);
    });

    test('the sound keys carry value equality, which the registry needs', () {
      expect(const ScreenshotConfig(shutterSound: 'tick'),
          const ScreenshotConfig(shutterSound: 'tick'));
      expect(const ScreenshotConfig(shutterSound: 'tick'),
          isNot(const ScreenshotConfig(shutterSound: 'snap')));
      expect(const ScreenshotConfig(shutterVolume: 0.2),
          isNot(const ScreenshotConfig(shutterVolume: 0.3)));
      expect(const ScreenshotConfig(shutterSound: 'tick').hashCode,
          const ScreenshotConfig(shutterSound: 'tick').hashCode);
    });
  });
}
