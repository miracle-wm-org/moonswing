import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/modules/notifications.dart';
import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/notification_sound.dart';

/// A voice out of the shipped catalogue, so the tests below pin what the shell
/// actually plays rather than a fixture that could drift from it.
NotificationVoice _voice(String slug) => notificationVoice(slug)!;

/// The store under test, with every injectable seam answered in memory: no
/// libmpv, no cache directory, no filesystem.
///
/// The clock advances a second per read unless one is given, so the rate limit
/// is out of the way of every test that is not about it — a fixed clock would
/// make two arrivals in one case indistinguishable from a burst.
NotificationSoundStore _store({
  NotificationSoundChoice? choice,
  DateTime Function()? clock,
}) {
  var tick = 0;
  final store = NotificationSoundStore.forTesting();
  store.now = clock ?? () => DateTime(2026, 1, 1).add(Duration(seconds: tick++));
  store.materialise = (voice) => '/cache/${voice.slug}.wav';
  store.resolve = (spelling) =>
      choice ?? resolveNotificationSound(spelling,
          soundRoots: const [], exists: (_) => false);
  return store;
}

void main() {
  final notifications = NotificationStore.instance;

  tearDown(() {
    notifications.dismissAll();
    NotificationSoundStore.instance.resetForTesting();
  });

  void arrive({String summary = 'Hello'}) {
    notifications.addOrReplace(NotificationItem(
      id: notifications.allocateId(),
      appName: 'App',
      summary: summary,
      body: '',
      actions: const [],
      expireTimeout: 0,
      arrivedAt: DateTime(2026, 1, 1),
    ));
  }

  group('the shipped sounds', () {
    test('every voice renders a playable RIFF/WAVE file', () {
      for (final voice in kNotificationVoices) {
        final bytes = renderNotificationWav(voice);
        expect(bytes.length, greaterThan(44), reason: voice.slug);

        final header = ByteData.sublistView(bytes);
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
        expect(String.fromCharCodes(bytes.sublist(12, 16)), 'fmt ');
        expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');
        // PCM, mono, 16-bit, at the rate the file says it is.
        expect(header.getUint16(20, Endian.little), 1, reason: voice.slug);
        expect(header.getUint16(22, Endian.little), 1, reason: voice.slug);
        expect(header.getUint16(34, Endian.little), 16, reason: voice.slug);
        expect(header.getUint32(24, Endian.little),
            kNotificationSoundSampleRate);
        // The two length fields agree with the buffer, or every player in the
        // world reads past the end of it.
        expect(header.getUint32(40, Endian.little), bytes.length - 44);
        expect(header.getUint32(4, Endian.little), bytes.length - 8);
      }
    });

    // The two ends are where a click comes from: a waveform that starts or
    // stops away from zero is a step, and a step is audible.
    test('every voice starts and ends at silence', () {
      for (final voice in kNotificationVoices) {
        final bytes = renderNotificationWav(voice);
        final samples = ByteData.sublistView(bytes, 44);
        expect(samples.getInt16(0, Endian.little), 0, reason: voice.slug);
        expect(
          samples.getInt16(samples.lengthInBytes - 2, Endian.little).abs(),
          lessThan(64),
          reason: voice.slug,
        );
      }
    });

    // Normalised rather than trusted: a voice is a hand-written list of gains,
    // and one that happened to sum past 1.0 would clip.
    test('every voice is normalised, and none of them clips', () {
      for (final voice in kNotificationVoices) {
        final samples = ByteData.sublistView(renderNotificationWav(voice), 44);
        var peak = 0;
        for (var i = 0; i < samples.lengthInBytes; i += 2) {
          final magnitude = samples.getInt16(i, Endian.little).abs();
          if (magnitude > peak) peak = magnitude;
        }
        expect(peak, lessThan(32768), reason: voice.slug);
        expect(peak, greaterThan(28000), reason: voice.slug);
      }
    });

    test('the default is one of them, and the slugs are unique', () {
      expect(notificationVoice(kDefaultNotificationSound), isNotNull);
      final slugs = kNotificationVoices.map((v) => v.slug).toList();
      expect(slugs.toSet(), hasLength(slugs.length));
      // The settings row's placeholder is built from the catalogue, so a voice
      // added above cannot go unmentioned where a user would look for it.
      for (final slug in slugs) {
        expect(kNotificationSoundHint, contains(slug));
      }
    });

    // The chime's hot path: `materialiseVoice` compares the file on disk
    // against this rather than against a fresh render, or every notification
    // for the life of the install would pay the synthesis again.
    test('the byte length is arithmetic, and matches what is rendered', () {
      for (final voice in kNotificationVoices) {
        expect(
          notificationWavByteLength(voice),
          renderNotificationWav(voice).length,
          reason: voice.slug,
        );
      }
    });

    test('an unknown slug is not a voice', () {
      expect(notificationVoice('tubular-bells'), isNull);
      expect(notificationVoice(''), isNull);
    });
  });

  group('resolveNotificationSound', () {
    NotificationSoundChoice resolve(
      String spelling, {
      Set<String> present = const {},
      List<String> roots = const ['/usr/share/sounds'],
    }) =>
        resolveNotificationSound(
          spelling,
          soundRoots: roots,
          exists: present.contains,
          home: '/home/somebody',
        );

    test('the off switches are silence, not a missing file', () {
      for (final spelling in [...kNotificationSoundOff, '', '   ', 'NONE']) {
        final choice = resolve(spelling);
        expect(choice.isSilent, isTrue, reason: spelling);
        expect(choice.missing, isNull, reason: spelling);
      }
    });

    test('a shipped slug wins over anything on disk', () {
      // A user who installs a sound theme with a `chime` in it must not have
      // the shell's own taken away from them by it.
      final choice = resolve(
        'chime',
        present: {'/usr/share/sounds/chime.oga'},
      );
      expect(choice.voice?.slug, 'chime');
      expect(choice.path, isNull);
    });

    test('a path is taken as one, and a missing one says so', () {
      final found = resolve(
        '/opt/sounds/mine.wav',
        present: {'/opt/sounds/mine.wav'},
      );
      expect(found.path, '/opt/sounds/mine.wav');

      // Not gone looking for elsewhere: a typo in a path is a missing file,
      // and silently resolving it to some other sound is worse than silence.
      final absent = resolve('/opt/sounds/typo.wav');
      expect(absent.path, isNull);
      expect(absent.missing, '/opt/sounds/typo.wav');
    });

    test('~ is expanded against the home it is given', () {
      final choice = resolve(
        '~/sounds/mine.oga',
        present: {'/home/somebody/sounds/mine.oga'},
      );
      expect(choice.path, '/home/somebody/sounds/mine.oga');
    });

    test('a bare name finds the sound theme layout', () {
      final choice = resolve(
        'message',
        present: {'/usr/share/sounds/freedesktop/stereo/message.oga'},
      );
      expect(choice.path, '/usr/share/sounds/freedesktop/stereo/message.oga');
    });

    test('a name spelled with its extension finds the same file', () {
      final choice = resolve(
        'message.oga',
        present: {'/usr/share/sounds/freedesktop/stereo/message.oga'},
      );
      expect(choice.path, '/usr/share/sounds/freedesktop/stereo/message.oga');
    });

    test('roots are searched in order, so the user\'s own wins', () {
      final choice = resolve(
        'message',
        roots: const ['/home/somebody/.local/share/sounds', '/usr/share/sounds'],
        present: {
          '/home/somebody/.local/share/sounds/freedesktop/stereo/message.oga',
          '/usr/share/sounds/freedesktop/stereo/message.oga',
        },
      );
      expect(
        choice.path,
        '/home/somebody/.local/share/sounds/freedesktop/stereo/message.oga',
      );
    });

    // A name nothing answers to is the user having asked for a sound and not
    // got one — which the panel's row renders. It is not silence.
    test('a name that resolves to nothing is missing, not silent', () {
      final choice = resolve('nonesuch');
      expect(choice.isSilent, isFalse);
      expect(choice.missing, 'nonesuch');
    });
  });

  group('notificationSoundRoots', () {
    test('user first, then the data dirs, then the system ones', () {
      final roots = notificationSoundRoots(environment: const {
        'HOME': '/home/somebody',
        'XDG_DATA_DIRS': '/opt/share:/var/lib/flatpak/exports/share',
      });
      expect(roots.first, '/home/somebody/.local/share/sounds');
      expect(roots, contains('/opt/share/sounds'));
      expect(roots, contains('/usr/share/sounds'));
      expect(roots.indexOf('/opt/share/sounds'),
          lessThan(roots.indexOf('/usr/share/sounds')));
    });

    test('XDG_DATA_HOME overrides the default user root', () {
      final roots = notificationSoundRoots(environment: const {
        'HOME': '/home/somebody',
        'XDG_DATA_HOME': '/home/somebody/data/',
      });
      // And the trailing slash is trimmed, or every candidate below it would
      // be spelled with a doubled separator.
      expect(roots.first, '/home/somebody/data/sounds');
    });

    test('a root is never listed twice', () {
      final roots = notificationSoundRoots(environment: const {
        'HOME': '/home/somebody',
        'XDG_DATA_DIRS': '/usr/share:/usr/share',
      });
      expect(roots.toSet(), hasLength(roots.length));
    });
  });

  group('NotificationSoundStore', () {
    test('an arrival plays the configured sound', () {
      final played = <String>[];
      final store = _store(choice: NotificationSoundChoice.shipped(
        _voice('ping'),
      ));
      store.play = (path, volume) async {
        played.add('$path@$volume');
      };
      store.configure(const NotificationSoundConfig(volume: 0.5));
      store.acquire();

      arrive();
      expect(played, ['/cache/ping.wav@0.5']);
    });

    test('nothing plays without a lease', () {
      var plays = 0;
      final store = _store(
        choice: NotificationSoundChoice.shipped(_voice('ping')),
      );
      store.play = (_, _) async => plays++;

      arrive();
      expect(plays, 0);
      expect(store.armed, isFalse);
    });

    // One player for the machine: two bars are two of these widgets, and the
    // second must not chime a frame after the first.
    test('a second lease does not double the chime', () {
      var plays = 0;
      final store = _store(
        choice: NotificationSoundChoice.shipped(_voice('ping')),
      );
      store.play = (_, _) async => plays++;
      store.acquire();
      store.acquire();
      expect(store.leaseCount, 2);

      arrive();
      expect(plays, 1);

      // And the first release does not stop it, only the last.
      store.release();
      expect(store.armed, isTrue);
      arrive();
      expect(plays, 2);

      store.release();
      expect(store.armed, isFalse);
    });

    test('a module built onto a full list does not chime for the backlog', () {
      var plays = 0;
      arrive();
      arrive();
      final store = _store(
        choice: NotificationSoundChoice.shipped(_voice('ping')),
      );
      store.play = (_, _) async => plays++;
      store.acquire();

      // Nothing yet — the two were already there when the lease was taken.
      expect(plays, 0);
      arrive();
      expect(plays, 1);
    });

    test('silenced takes the chime first', () {
      var plays = 0;
      final store = _store(
        choice: NotificationSoundChoice.shipped(_voice('ping')),
      );
      store.play = (_, _) async => plays++;
      store.acquire();

      notifications.setSilenced(true);
      addTearDown(() => notifications.setSilenced(false));
      arrive();
      expect(plays, 0);

      notifications.setSilenced(false);
      arrive();
      expect(plays, 1);
    });

    // Marking read moves the count down, which is not an arrival; the next one
    // after it is.
    test('only an arrival chimes, never a dismissal or a mark-read', () {
      var plays = 0;
      final store = _store(
        choice: NotificationSoundChoice.shipped(_voice('ping')),
      );
      store.play = (_, _) async => plays++;
      store.acquire();

      arrive();
      expect(plays, 1);
      notifications.markAllRead();
      expect(plays, 1);
      notifications.dismissAll();
      expect(plays, 1);
      arrive();
      expect(plays, 2);
    });

    test('a burst plays once, and the rate limit lifts with the clock', () {
      var plays = 0;
      var clock = DateTime(2026, 1, 1);
      final store = _store(
        choice: NotificationSoundChoice.shipped(_voice('ping')),
        clock: () => clock,
      );
      store.play = (_, _) async => plays++;
      store.acquire();

      arrive();
      arrive();
      arrive();
      expect(plays, 1);

      clock = clock.add(kNotificationSoundInterval * 2);
      arrive();
      expect(plays, 2);
    });

    // The preview button has to make a sound every time it is pressed, or the
    // button is what looks broken.
    test('a forced play ignores the rate limit', () {
      var plays = 0;
      final store = _store(
        choice: NotificationSoundChoice.shipped(_voice('ping')),
      );
      store.play = (_, _) async => plays++;

      store.playNow(force: true);
      store.playNow(force: true);
      expect(plays, 2);
    });

    test('silence plays nothing and reports nothing wrong', () {
      var plays = 0;
      final store = _store(choice: const NotificationSoundChoice.silent());
      store.play = (_, _) async => plays++;

      store.playNow(force: true);
      expect(plays, 0);
      expect(store.error, isNull);
    });

    test('a sound that is not there is a visible failure', () {
      var plays = 0;
      final store = _store(
        choice: const NotificationSoundChoice.missing('nonesuch'),
      );
      store.play = (_, _) async => plays++;

      store.playNow(force: true);
      expect(plays, 0);
      expect(store.error, contains('nonesuch'));
    });

    test('a player that throws is a visible failure too', () async {
      final store = _store(
        choice: NotificationSoundChoice.shipped(_voice('ping')),
      );
      store.play = (_, _) async => throw StateError('no audio device');

      store.playNow(force: true);
      // The failure is reported off the future rather than awaited, so that a
      // slow player never holds up the frame the notification is drawn on.
      await Future<void>.delayed(Duration.zero);
      expect(store.error, contains('no audio device'));
    });

    test('a successful play clears an earlier reason', () async {
      final store = _store(
        choice: NotificationSoundChoice.shipped(_voice('ping')),
      );
      store.play = (_, _) async => throw StateError('no audio device');
      store.playNow(force: true);
      await Future<void>.delayed(Duration.zero);
      expect(store.error, isNotNull);

      store.play = (_, _) async {};
      store.playNow(force: true);
      await Future<void>.delayed(Duration.zero);
      expect(store.error, isNull);
    });

    test('a shipped voice is materialised once per process', () {
      var materialised = 0;
      final store = _store(
        choice: NotificationSoundChoice.shipped(_voice('ping')),
      );
      store.materialise = (voice) {
        materialised++;
        return '/cache/${voice.slug}.wav';
      };
      store.play = (_, _) async {};

      store.playNow(force: true);
      store.playNow(force: true);
      store.playNow(force: true);
      // The answer cannot change under a running shell, and the alternative is
      // a stat of the cache directory on the frame a notification arrives.
      expect(materialised, 1);
    });

    // Both of this store's writers can be reached from inside a build — the
    // module configures it from `initState` and `didUpdateWidget` — and the
    // panel's sound row listens from a different FlutterView. A synchronous
    // notify from there is a markNeedsBuild on an element already building.
    test('a change moves the state now and notifies later', () async {
      final store = _store();
      var notifies = 0;
      store.addListener(() => notifies++);

      store.configure(const NotificationSoundConfig(sound: 'bell'));
      expect(store.config.sound, 'bell');
      expect(notifies, 0);

      // And a sweep of them collapses into one wake-up rather than a queue.
      store.configure(const NotificationSoundConfig(sound: 'ping'));
      store.configure(const NotificationSoundConfig(sound: 'glass'));
      await Future<void>.delayed(Duration.zero);
      expect(notifies, 1);
      expect(store.config.sound, 'glass');
    });

    test('a spelling is resolved once, and again when it moves', () {
      var resolves = 0;
      final store = NotificationSoundStore.forTesting();
      store.resolve = (spelling) {
        resolves++;
        return const NotificationSoundChoice.silent();
      };

      store.choice;
      store.choice;
      expect(resolves, 1);

      // A sweep that did not move this key costs no second walk.
      store.configure(const NotificationSoundConfig(volume: 0.2));
      store.choice;
      expect(resolves, 1);

      store.configure(const NotificationSoundConfig(sound: 'bell'));
      store.choice;
      expect(resolves, 2);
    });

    test('correcting the spelling drops the reason it was typed to fix', () {
      final store = _store(
        choice: const NotificationSoundChoice.missing('nonesuch'),
      );
      store.playNow(force: true);
      expect(store.error, isNotNull);

      store.configure(const NotificationSoundConfig(sound: 'bell'));
      expect(store.error, isNull);
    });
  });

  group('NotificationsConfig', () {
    test('an absent table is the shipped default', () {
      const config = NotificationsConfig();
      expect(NotificationsConfig.fromMap(null), config);
      expect(config.sound, kDefaultNotificationSound);
      expect(config.soundVolume, kDefaultNotificationSoundVolume);
    });

    test('a wrongly-typed value costs that key, never the table', () {
      final config = NotificationsConfig.fromMap(const {
        'sound': 42,
        'sound_volume': 0.25,
      });
      expect(config.sound, kDefaultNotificationSound);
      expect(config.soundVolume, 0.25);
    });

    test('the volume is clamped rather than trusted', () {
      expect(
        NotificationsConfig.fromMap(const {'sound_volume': 40}).soundVolume,
        1.0,
      );
      expect(
        NotificationsConfig.fromMap(const {'sound_volume': -3}).soundVolume,
        0.0,
      );
      // NaN and the infinities are absent values, not numbers to clamp.
      expect(
        NotificationsConfig.fromMap({'sound_volume': double.nan}).soundVolume,
        kDefaultNotificationSoundVolume,
      );
    });

    test('it carries value equality, which the module registry needs', () {
      expect(
        const NotificationsConfig(sound: 'bell', soundVolume: 0.5),
        const NotificationsConfig(sound: 'bell', soundVolume: 0.5),
      );
      expect(
        const NotificationsConfig(sound: 'bell'),
        isNot(const NotificationsConfig(sound: 'ping')),
      );
    });

    test('the sound layer reads the same two values off it', () {
      const config = NotificationsConfig(sound: 'glass', soundVolume: 0.4);
      expect(config.soundConfig,
          const NotificationSoundConfig(sound: 'glass', volume: 0.4));
    });
  });
}
