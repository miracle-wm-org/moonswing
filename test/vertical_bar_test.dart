import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/bar_button.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/media/mpris_store.dart';
import 'package:moonswing/modules/clock.dart';
import 'package:moonswing/modules/media_player.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/timers/timer_store.dart';

/// A bar's depth, the default `height`: what a side bar is wide.
const double _depth = 32;

/// Pumps [child] the way a side bar hands a module its room: the bar's depth
/// across, loosely, and the screen's height along. A [RenderFlex] that
/// overflows that width reports an error, which fails the test on its own.
Future<void> _pumpBar(
  WidgetTester tester,
  Widget child, {
  String anchor = 'left',
}) async {
  final vertical = anchor == 'left' || anchor == 'right';
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 12),
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: BarScope(
            anchor: anchor,
            thickness: _depth,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: vertical ? _depth : 800,
                height: vertical ? 800 : _depth,
                child: Align(
                  alignment:
                      vertical ? Alignment.topCenter : Alignment.centerLeft,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('BarFlex', () {
    for (final (anchor, type) in [
      ('top', Row),
      ('bottom', Row),
      ('left', Column),
      ('right', Column),
    ]) {
      testWidgets('is a $type on a $anchor bar', (tester) async {
        await _pumpBar(
          tester,
          const BarFlex(children: [SizedBox(width: 8, height: 8)]),
          anchor: anchor,
        );
        expect(
          find.descendant(of: find.byType(BarFlex), matching: find.byType(type)),
          findsOneWidget,
        );
      });
    }
  });

  group('BarRotated', () {
    test('turns text so its top faces the screen edge', () {
      expect(BarRotated.quarterTurnsFor('left'), 3);
      expect(BarRotated.quarterTurnsFor('right'), 1);
      expect(BarRotated.quarterTurnsFor('top'), 0);
      expect(BarRotated.quarterTurnsFor('bottom'), 0);
      expect(BarRotated.quarterTurnsFor(null), 0);
    });

    testWidgets('adds nothing on a top bar', (tester) async {
      await _pumpBar(
        tester,
        const BarRotated(child: Text('14:05')),
        anchor: 'top',
      );
      expect(find.byType(RotatedBox), findsNothing);
    });
  });

  group('BarText', () {
    testWidgets('is the text as styled on a top bar', (tester) async {
      await _pumpBar(
        tester,
        const BarText('100%', style: TextStyle(fontSize: 16)),
        anchor: 'top',
      );
      expect(find.byType(FittedBox), findsNothing);
      expect(tester.widget<Text>(find.text('100%')).style!.fontSize, 16);
    });

    testWidgets('fits a side bar on one line', (tester) async {
      await _pumpBar(
        tester,
        const BarText('100%', style: TextStyle(fontSize: 16)),
      );
      final text = tester.widget<Text>(find.text('100%'));
      expect(text.style!.fontSize, ShellFontSizes.secondary);
      expect(text.maxLines, 1);
      expect(tester.getSize(find.byType(BarText)).width,
          lessThanOrEqualTo(_depth));
    });

    testWidgets('a reading too wide even at the small size is scaled to fit',
        (tester) async {
      await _pumpBar(
        tester,
        const BarText('123456789', style: TextStyle(fontSize: 16)),
      );
      expect(tester.getSize(find.byType(BarText)).width,
          lessThanOrEqualTo(_depth));
    });
  });

  group('the clock on a side bar', () {
    for (final (anchor, turns) in [('left', 3), ('right', 1)]) {
      testWidgets('reads along a $anchor bar', (tester) async {
        final timers = TimersStore.forTesting();
        addTearDown(timers.dispose);
        await _pumpBar(
          tester,
          Clock(config: const ClockConfig(), timers: timers),
          anchor: anchor,
        );
        final rotated = find.ancestor(
          of: find.textContaining(':'),
          matching: find.byType(RotatedBox),
        );
        expect(rotated, findsOneWidget);
        expect(tester.widget<RotatedBox>(rotated).quarterTurns, turns);
        final size = tester.getSize(find.byType(Clock));
        expect(size.width, lessThanOrEqualTo(_depth));
        // Longer than it is wide: the date and the time run down the bar.
        expect(size.height, greaterThan(size.width));
      });
    }

    testWidgets('stays upright on a top bar', (tester) async {
      final timers = TimersStore.forTesting();
      addTearDown(timers.dispose);
      await _pumpBar(
        tester,
        Clock(config: const ClockConfig(), timers: timers),
        anchor: 'top',
      );
      expect(find.byType(RotatedBox), findsNothing);
    });

    testWidgets('puts a running timer under it, on its side', (tester) async {
      final timers = TimersStore.forTesting(
        now: () => DateTime(2026, 8, 24, 12),
      );
      addTearDown(timers.dispose);
      timers.startTimer(const Duration(hours: 1, minutes: 23, seconds: 45));
      await _pumpBar(
        tester,
        Clock(config: const ClockConfig(), timers: timers),
      );
      expect(
        find.ancestor(
          of: find.text('1:23:45'),
          matching: find.byType(RotatedBox),
        ),
        findsOneWidget,
      );
      final time = tester.getRect(find.textContaining(':').first);
      final readout = tester.getRect(find.text('1:23:45'));
      expect(readout.top, greaterThan(time.bottom));
      expect(tester.getSize(find.byType(Clock)).width,
          lessThanOrEqualTo(_depth));
    });
  });

  group('the media strip on a side bar', () {
    testWidgets('stacks the buttons and turns the title', (tester) async {
      final store = MprisStore.forTesting();
      addTearDown(store.dispose);
      store.seed([
        MprisPlayer(busName: '${kMprisPrefix}vlc')
          ..status = MprisPlaybackStatus.playing
          ..title = 'Weightless'
          ..artist = 'Marconi Union'
          ..canControl = true
          ..canPlay = true
          ..canPause = true
          ..canGoNext = true
          ..canGoPrevious = true,
      ]);
      await _pumpBar(
        tester,
        MediaPlayer(config: const MediaPlayerConfig(), store: store),
      );
      final size = tester.getSize(find.byType(MediaPlayer));
      expect(size.width, lessThanOrEqualTo(_depth));
      expect(
        find.ancestor(
          of: find.textContaining('Weightless').first,
          matching: find.byType(RotatedBox),
        ),
        findsOneWidget,
      );
    });
  });
}
