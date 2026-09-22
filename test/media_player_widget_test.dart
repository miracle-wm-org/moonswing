import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/desktop/widgets/media_player_widget.dart';
import 'package:moonswing/media/media_controls.dart';
import 'package:moonswing/media/mpris_store.dart';
import 'package:moonswing/modules/media_player.dart';
import 'package:moonswing/scopes.dart';

MprisPlayer _player({
  MprisPlaybackStatus status = MprisPlaybackStatus.playing,
  String title = 'Weightless',
  String artist = 'Marconi Union',
  String album = '',
  bool canControl = true,
  Duration? length,
}) {
  return MprisPlayer(busName: '${kMprisPrefix}vlc')
    ..status = status
    ..title = title
    ..artist = artist
    ..album = album
    ..canControl = canControl
    ..canPlay = true
    ..canPause = true
    ..canGoNext = true
    ..canGoPrevious = true
    ..length = length;
}

/// Pumps [child] in a themed box. [loose] hands it loose constraints, the way
/// a bar hands a module its own width — without it the outer `SizedBox` is
/// tight and a module that renders nothing still measures the full box.
Future<void> pumpSurface(
  WidgetTester tester,
  Widget child, {
  Size? size,
  bool loose = false,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14),
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: size?.width ?? 400,
              height: size?.height ?? 200,
              child: loose
                  ? Align(alignment: Alignment.topLeft, child: child)
                  : child,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('formatTrackTime', () {
    test('is m:ss, and h:mm:ss past the hour', () {
      expect(formatTrackTime(Duration.zero), '0:00');
      expect(formatTrackTime(const Duration(seconds: 9)), '0:09');
      expect(formatTrackTime(const Duration(minutes: 3, seconds: 7)), '3:07');
      expect(
        formatTrackTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('a negative duration reads as zero rather than as "-0:-1"', () {
      expect(formatTrackTime(const Duration(seconds: -5)), '0:00');
    });
  });

  group('TrackMarquee', () {
    testWidgets('a title that fits is one still Text', (tester) async {
      await pumpSurface(
        tester,
        const TrackMarquee(
          text: 'Short',
          maxWidth: 300,
          style: TextStyle(fontSize: 12),
        ),
      );
      expect(find.text('Short'), findsOneWidget);
      expect(find.byType(ClipRect), findsNothing);
    });

    // Two copies with the gap between them, so the loop has no visible seam.
    testWidgets('a title that does not fit scrolls, doubled', (tester) async {
      await pumpSurface(
        tester,
        const TrackMarquee(
          text: 'A really rather long track title that will not fit at all',
          maxWidth: 40,
          style: TextStyle(fontSize: 12),
        ),
      );
      expect(
        find.text('A really rather long track title that will not fit at all'),
        findsNWidgets(2),
      );

      // Repeating forever is the point; settle would time out.
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('bar module', () {
    testWidgets('takes no room at all when nothing is playing',
        (tester) async {
      final store = MprisStore.forTesting();
      addTearDown(store.dispose);

      await pumpSurface(
        tester,
        MediaPlayer(config: const MediaPlayerConfig(), store: store),
        loose: true,
      );
      expect(tester.getSize(find.byType(MediaPlayer)).width, 0);
    });

    testWidgets('shows the track and follows the store', (tester) async {
      final store = MprisStore.forTesting();
      addTearDown(store.dispose);
      final player = _player();
      store.seed([player]);

      await pumpSurface(
        tester,
        MediaPlayer(config: const MediaPlayerConfig(), store: store),
        loose: true,
      );
      // `findsWidgets`, not `findsOneWidget`: the title is a marquee, and a
      // title that does not fit is rendered twice so its loop has no seam.
      expect(find.text('Marconi Union — Weightless'), findsWidgets);
      expect(find.byType(MediaTransportButton), findsNWidgets(4));

      // A track change reaches the bar without the widget being rebuilt by
      // anything else — that is the whole point of the store.
      player.title = 'Sleepless';
      store.seed([player]);
      await tester.pump();
      expect(find.text('Marconi Union — Sleepless'), findsWidgets);
      expect(find.text('Marconi Union — Weightless'), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a player that refuses control shows no buttons',
        (tester) async {
      final store = MprisStore.forTesting();
      addTearDown(store.dispose);
      store.seed([_player(canControl: false)]);

      await pumpSurface(
        tester,
        MediaPlayer(config: const MediaPlayerConfig(), store: store),
        loose: true,
      );
      expect(find.byType(MediaTransportButton), findsNothing);
      expect(find.text('Marconi Union — Weightless'), findsWidgets);

      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('desktop widget', () {
    testWidgets('says so when nothing is playing, rather than vanishing',
        (tester) async {
      final store = MprisStore.forTesting();
      addTearDown(store.dispose);

      await pumpSurface(
        tester,
        MediaPlayerWidget(span: (columns: 2, rows: 1), store: store),
        size: const Size(200, 100),
      );
      expect(find.text('Nothing playing'), findsOneWidget);
    });

    testWidgets('the 2x1 layout is art, one line and the transport',
        (tester) async {
      final store = MprisStore.forTesting();
      addTearDown(store.dispose);
      store.seed([_player()]);

      await pumpSurface(
        tester,
        MediaPlayerWidget(span: (columns: 2, rows: 1), store: store),
        size: const Size(200, 100),
      );

      expect(find.text('Weightless'), findsWidgets);
      expect(find.text('Marconi Union'), findsOneWidget);
      expect(find.byType(AlbumArt), findsOneWidget);
      // No progress bar at this size: there is nowhere to put it.
      expect(find.byType(MediaProgressBar), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('two rows adds the album, the progress bar and the times',
        (tester) async {
      final store = MprisStore.forTesting();
      addTearDown(store.dispose);
      store.seed([
        _player(album: 'Ambient 1', length: const Duration(minutes: 4)),
      ]);

      await pumpSurface(
        tester,
        MediaPlayerWidget(span: (columns: 3, rows: 2), store: store),
        size: const Size(300, 200),
      );

      expect(find.text('Ambient 1'), findsOneWidget);
      expect(find.byType(MediaProgressBar), findsOneWidget);
      expect(find.text('4:00'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('an unknown length reads as --:--, not as 0:00',
        (tester) async {
      final store = MprisStore.forTesting();
      addTearDown(store.dispose);
      store.seed([_player()]);

      await pumpSurface(
        tester,
        MediaPlayerWidget(span: (columns: 3, rows: 2), store: store),
        size: const Size(300, 200),
      );
      expect(find.text('--:--'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
    });

    // The size a freshly-resized widget actually is on a default grid: two
    // 96px cells wide by one tall, less the frame's padding.
    testWidgets('the 2x1 minimum still fits a title, an artist and the bars',
        (tester) async {
      final store = MprisStore.forTesting();
      addTearDown(store.dispose);
      store.seed([_player()]);

      await pumpSurface(
        tester,
        MediaPlayerWidget(span: (columns: 2, rows: 1), store: store),
        size: const Size(172, 76),
      );

      expect(find.byType(PlayingBars), findsOneWidget);
      expect(find.text('Marconi Union'), findsOneWidget);
      // Skip-track is what goes when the card is this narrow; play/pause is
      // what somebody put a media player on their desktop for.
      expect(find.byType(MediaTransportButton), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a player that refuses control gets no buttons at all',
        (tester) async {
      final store = MprisStore.forTesting();
      addTearDown(store.dispose);
      store.seed([_player(canControl: false)]);

      await pumpSurface(
        tester,
        MediaPlayerWidget(span: (columns: 3, rows: 2), store: store),
        size: const Size(300, 200),
      );
      expect(find.byType(MediaTransportButton), findsNothing);
      expect(find.text('Weightless'), findsWidgets);

      await tester.pump(const Duration(milliseconds: 100));
    });

    // A cell can be configured down to 32px. Flutter reports a flex overflow
    // as a *test failure*, so pumping one at all is the assertion.
    testWidgets('a card too small for its content clips rather than overflows',
        (tester) async {
      final store = MprisStore.forTesting();
      addTearDown(store.dispose);
      store.seed([_player(album: 'Ambient 1', length: const Duration(minutes: 4))]);

      await pumpSurface(
        tester,
        MediaPlayerWidget(span: (columns: 2, rows: 1), store: store),
        size: const Size(80, 24),
      );
      expect(find.byType(MediaPlayerWidget), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
    });

    // The span asks for the expanded layout; the pixels decide whether it fits.
    testWidgets('two rows on a short grid falls back to the compact layout',
        (tester) async {
      final store = MprisStore.forTesting();
      addTearDown(store.dispose);
      store.seed([_player(length: const Duration(minutes: 4))]);

      await pumpSurface(
        tester,
        MediaPlayerWidget(span: (columns: 3, rows: 2), store: store),
        size: const Size(300, 80),
      );
      expect(find.byType(MediaProgressBar), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
    });

    // The bars and the disc are the "audio is playing" signal; a paused widget
    // settles them instead of freezing them mid-bounce.
    testWidgets('the playing animation follows the playback state',
        (tester) async {
      final store = MprisStore.forTesting();
      addTearDown(store.dispose);
      final player = _player();
      store.seed([player]);

      await pumpSurface(
        tester,
        MediaPlayerWidget(span: (columns: 2, rows: 1), store: store),
        size: const Size(200, 100),
      );

      PlayingBars bars() => tester.widget<PlayingBars>(find.byType(PlayingBars));
      expect(bars().playing, isTrue);

      player.status = MprisPlaybackStatus.paused;
      store.seed([player]);
      await tester.pump();
      expect(bars().playing, isFalse);

      // Never `pumpAndSettle` on this widget: a title that does not fit
      // scrolls forever by design, so there is no settled state to wait for.
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
