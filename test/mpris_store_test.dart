import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/media/mpris_store.dart';

MprisPlayer _player(
  String bus, {
  MprisPlaybackStatus status = MprisPlaybackStatus.stopped,
  String title = '',
  String artist = '',
  Duration? length,
  Duration position = Duration.zero,
  DateTime? positionAt,
}) {
  return MprisPlayer(busName: '$kMprisPrefix$bus')
    ..status = status
    ..title = title
    ..artist = artist
    ..length = length
    ..position = position
    ..positionAt = positionAt;
}

void main() {
  late MprisStore store;

  setUp(() {
    store = MprisStore.forTesting();
    addTearDown(store.dispose);
  });

  group('identity and label', () {
    test('strips the prefix and the instance suffix', () {
      expect(_player('firefox.instance_1_23').identity, 'firefox');
      expect(_player('spotify').identity, 'spotify');
    });

    test('falls back to the identity when there is no metadata', () {
      expect(_player('vlc').displayText, 'vlc');
      expect(_player('vlc', title: 'Track').displayText, 'Track');
      expect(_player('vlc', artist: 'Band').displayText, 'Band');
      expect(
        _player('vlc', artist: 'Band', title: 'Track').displayText,
        'Band — Track',
      );
    });
  });

  group('active player', () {
    test('prefers something playing over something paused', () {
      store.seed([
        _player('paused', status: MprisPlaybackStatus.paused),
        _player('playing', status: MprisPlaybackStatus.playing),
      ]);
      expect(store.active?.identity, 'playing');
    });

    test('falls back to paused, then to nothing', () {
      store.seed([_player('paused', status: MprisPlaybackStatus.paused)]);
      expect(store.active?.identity, 'paused');

      store.seed([_player('stopped')]);
      expect(store.active, isNull);
      expect(store.hasPlayer, isFalse);
    });

    test('does not switch away from a player that is still playing', () {
      final first = _player('first', status: MprisPlaybackStatus.playing);
      store.seed([first]);
      store.seed([first, _player('second', status: MprisPlaybackStatus.playing)]);
      expect(store.active?.identity, 'first');
    });
  });

  group('position', () {
    final at = DateTime.utc(2026, 1, 1, 12);

    test('carries a playing position forward from its reference point', () {
      store
        ..seed([
          _player(
            'p',
            status: MprisPlaybackStatus.playing,
            position: const Duration(seconds: 10),
            positionAt: at,
            length: const Duration(minutes: 3),
          ),
        ])
        ..now = () => at.add(const Duration(seconds: 5));

      expect(store.position, const Duration(seconds: 15));
      expect(store.progress, closeTo(15 / 180, 0.0001));
    });

    test('a paused player does not advance', () {
      store
        ..seed([
          _player(
            'p',
            status: MprisPlaybackStatus.paused,
            position: const Duration(seconds: 10),
            positionAt: at,
          ),
        ])
        ..now = () => at.add(const Duration(minutes: 5));

      expect(store.position, const Duration(seconds: 10));
    });

    // NTP, or a resumed laptop. A readout may stall; it may never run
    // backwards.
    test('a backwards clock step is dropped rather than subtracted', () {
      store
        ..seed([
          _player(
            'p',
            status: MprisPlaybackStatus.playing,
            position: const Duration(seconds: 10),
            positionAt: at,
          ),
        ])
        ..now = () => at.subtract(const Duration(seconds: 30));

      expect(store.position, const Duration(seconds: 10));
    });

    test('never runs past the end of the track', () {
      store
        ..seed([
          _player(
            'p',
            status: MprisPlaybackStatus.playing,
            position: const Duration(seconds: 10),
            positionAt: at,
            length: const Duration(seconds: 20),
          ),
        ])
        ..now = () => at.add(const Duration(minutes: 5));

      expect(store.position, const Duration(seconds: 20));
      expect(store.progress, 1.0);
    });

    // A bar stuck at zero would read as a track that never starts; the widget
    // renders "no length" differently on purpose.
    test('progress is null when the player publishes no length', () {
      store.seed([_player('p', status: MprisPlaybackStatus.playing)]);
      expect(store.progress, isNull);
    });

    test('with no player at all it is zero, not an error', () {
      expect(store.position, Duration.zero);
      expect(store.progress, isNull);
    });
  });

  group('leases', () {
    // The detached store never opens a bus, so this is really asserting that
    // a lease is safe to take with nothing behind it — which is what every
    // widget test of a media surface relies on.
    test('acquire and release are balanced and harmless offline', () async {
      store
        ..acquire()
        ..acquire(detailed: true)
        ..release(detailed: true)
        ..release();
      await store.playPause();
      expect(store.players, isEmpty);
    });
  });
}
