import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/notification_sound.dart';
import 'package:moonswing/osd/volume_sound.dart';
import 'package:moonswing/shell_sound.dart';

VolumeVoice _voice(String slug) => volumeVoice(slug)!;

/// The store under test, with every seam answered in memory: no libmpv, no
/// cache directory, no filesystem, and a clock that moves only when told.
VolumeSoundStore _store({VolumeSoundChoice? choice, DateTime? at}) {
  final store = VolumeSoundStore.forTesting();
  store.now = () => at ?? DateTime(2026, 9, 26, 12);
  store.materialise = (voice) => '/cache/volume-${voice.slug}.wav';
  store.resolve = (spelling) =>
      choice ??
      resolveVolumeSound(spelling, soundRoots: const [], exists: (_) => false);
  return store;
}

void main() {
  tearDown(VolumeSoundStore.instance.resetForTesting);

  group('the shipped sounds', () {
    test('every voice renders a playable file of the predicted size', () {
      for (final voice in kVolumeVoices) {
        final bytes = renderNotificationWav(voice);
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
        expect(bytes.length, notificationWavByteLength(voice),
            reason: voice.slug);
      }
    });

    test('every voice is short, because it plays on every key press', () {
      for (final voice in kVolumeVoices) {
        expect(voice.duration, lessThan(0.25), reason: voice.slug);
      }
    });

    test('the default is shipped, and every slug is in the hint', () {
      expect(volumeVoice(kDefaultVolumeSound), isNotNull);
      for (final voice in kVolumeVoices) {
        expect(kVolumeSoundHint, contains(voice.slug));
      }
      expect(kVolumeSoundHint, contains(kFreedesktopVolumeSound));
      expect(kVolumeSoundHint, contains('none'));
    });

    test('slugs are unique and never an off spelling', () {
      final slugs = kVolumeVoices.map((v) => v.slug).toList();
      expect(slugs.toSet(), hasLength(slugs.length));
      for (final slug in slugs) {
        expect(kShellSoundOff, isNot(contains(slug)));
      }
    });
  });

  group('resolveVolumeSound', () {
    test('off, shipped, path, theme name, missing — in that order', () {
      const root = '/usr/share/sounds';
      const themed = '$root/freedesktop/stereo/audio-volume-change.oga';
      bool exists(String path) =>
          path == themed || path == '/home/me/pop.ogg' || path == '$root/pop.oga';
      VolumeSoundChoice resolve(String s) => resolveVolumeSound(
            s,
            soundRoots: const [root],
            exists: exists,
            home: '/home/me',
          );

      expect(resolve('none').isSilent, isTrue);
      expect(resolve('  OFF ').isSilent, isTrue);
      // A theme carrying a `pop` cannot take the shipped one away.
      expect(resolve('pop').voice?.slug, 'pop');
      expect(resolve('~/pop.ogg').path, '/home/me/pop.ogg');
      expect(resolve(kFreedesktopVolumeSound).path, themed);
      expect(resolve('nonesuch').missing, 'nonesuch');
    });
  });

  group('VolumeSoundStore', () {
    test('a volume change plays the configured sound at its level', () {
      final played = <(String, double)>[];
      final store = _store()
        ..configure(const VolumeSoundConfig(sound: 'tick', volume: 0.3));
      store.play = (path, volume) async => played.add((path, volume));

      store.playNow();

      expect(played, [('/cache/volume-tick.wav', 0.3)]);
      expect(store.error, isNull);
    });

    test('a held key ticks rather than buzzing', () {
      var plays = 0;
      var at = DateTime(2026, 9, 26, 12);
      final store = _store(choice: VolumeSoundChoice.shipped(_voice('pop')));
      store.now = () => at;
      store.play = (path, volume) async => plays++;

      for (var i = 0; i < 4; i++) {
        store.playNow();
        at = at.add(const Duration(milliseconds: 30));
      }
      expect(plays, 1);

      at = at.add(kVolumeSoundInterval);
      store.playNow();
      expect(plays, 2);
    });

    test('a clock stepped backwards does not mute it', () {
      var plays = 0;
      var at = DateTime(2026, 9, 26, 12);
      final store = _store(choice: VolumeSoundChoice.shipped(_voice('pop')));
      store.now = () => at;
      store.play = (path, volume) async => plays++;

      store.playNow();
      at = at.subtract(const Duration(hours: 1));
      store.playNow();

      expect(plays, 2);
    });

    test('a preview is not swallowed by the rate limit', () {
      var plays = 0;
      final store = _store(choice: VolumeSoundChoice.shipped(_voice('pop')));
      store.play = (path, volume) async => plays++;

      store.playNow();
      store.playNow(force: true);

      expect(plays, 2);
    });

    test('silence plays nothing and reports nothing wrong', () {
      var plays = 0;
      final store = _store()..configure(const VolumeSoundConfig(sound: 'none'));
      store.play = (path, volume) async => plays++;

      store.playNow();

      expect(plays, 0);
      expect(store.error, isNull);
    });

    test('a sound that is not there is a visible failure, cleared by a fix',
        () async {
      var plays = 0;
      final store = _store()
        ..configure(const VolumeSoundConfig(sound: 'nonesuch'));
      store.play = (path, volume) async => plays++;

      store.playNow();
      expect(plays, 0);
      expect(store.error, contains('nonesuch'));

      store.configure(const VolumeSoundConfig(sound: 'blip'));
      expect(store.error, isNull);
      store.playNow();
      expect(plays, 1);
    });

    test('a player that fails says so', () async {
      final store = _store();
      store.play = (path, volume) async => throw StateError('no mpv');

      store.playNow();
      await Future<void>.delayed(Duration.zero);

      expect(store.error, contains('no mpv'));
    });

    test('an unchanged config is not a notification', () async {
      final store = _store();
      var notified = 0;
      store.addListener(() => notified++);

      store.configure(const VolumeSoundConfig());
      await Future<void>.delayed(Duration.zero);

      expect(notified, 0);
    });
  });

  group('[osd] config', () {
    test('defaults to the shipped pop', () {
      const config = OsdConfig();
      expect(config.volumeSound, kDefaultVolumeSound);
      expect(config.volumeSoundVolume, kDefaultVolumeSoundVolume);
      expect(config.volumeSoundConfig.enabled, isTrue);
    });

    test('reads the keys, and a bad one costs only itself', () {
      final config = OsdConfig.fromMap({
        'margin': 40,
        'volume_sound': 'none',
        'volume_sound_volume': 7,
      });
      expect(config.margin, 40);
      expect(config.volumeSoundConfig.enabled, isFalse);
      expect(config.volumeSoundVolume, 1.0);

      final wrong = OsdConfig.fromMap({'volume_sound': 42, 'margin': 40});
      expect(wrong.volumeSound, kDefaultVolumeSound);
      expect(wrong.margin, 40);
    });

    test('carries value equality', () {
      expect(
        OsdConfig.fromMap({'volume_sound': 'tick'}),
        OsdConfig.fromMap({'volume_sound': 'tick'}),
      );
      expect(
        OsdConfig.fromMap({'volume_sound': 'tick'}),
        isNot(OsdConfig.fromMap({'volume_sound': 'blip'})),
      );
    });
  });
}
