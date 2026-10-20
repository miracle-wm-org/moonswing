import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/screencast/cursor_pacer.dart';
import 'package:moonswing/screencast/cursor_policy.dart';

const _all = cursorModeHidden | cursorModeEmbedded | cursorModeMetadata;

void main() {
  group('resolveCursorMode', () {
    test('"app" honours a mode the backend advertised', () {
      for (final mode in [
        cursorModeHidden,
        cursorModeEmbedded,
        cursorModeMetadata,
      ]) {
        expect(
            resolveCursorMode(ScreencastCursor.app,
                requested: mode, available: _all),
            mode);
      }
    });

    test('"app" with no request is the portal default, hidden', () {
      expect(
          resolveCursorMode(ScreencastCursor.app,
              requested: null, available: _all),
          cursorModeHidden);
    });

    test('"app" treats an unadvertised or malformed request as hidden', () {
      expect(
          resolveCursorMode(ScreencastCursor.app,
              requested: cursorModeMetadata,
              available: cursorModeHidden | cursorModeEmbedded),
          cursorModeHidden);
      // Two bits is not a mode; neither is zero or one nobody defined.
      expect(
          resolveCursorMode(ScreencastCursor.app,
              requested: cursorModeEmbedded | cursorModeMetadata,
              available: _all),
          cursorModeHidden);
      expect(
          resolveCursorMode(ScreencastCursor.app,
              requested: 0, available: _all),
          cursorModeHidden);
      expect(
          resolveCursorMode(ScreencastCursor.app,
              requested: 8, available: _all),
          cursorModeHidden);
    });

    test('"always" paints the cursor in, whatever was asked', () {
      // Recordly on Linux asks for no cursor and then cannot draw its own.
      for (final mode in [null, cursorModeHidden, cursorModeMetadata]) {
        expect(
            resolveCursorMode(ScreencastCursor.always,
                requested: mode, available: _all),
            cursorModeEmbedded);
      }
    });

    test('"never" leaves it out, metadata included', () {
      for (final mode in [cursorModeEmbedded, cursorModeMetadata]) {
        expect(
            resolveCursorMode(ScreencastCursor.never,
                requested: mode, available: _all),
            cursorModeHidden);
      }
    });
  });

  group('ScreencastCursor.fromString', () {
    test('reads the three values, forgiving case and whitespace', () {
      expect(ScreencastCursor.fromString('app'), ScreencastCursor.app);
      expect(ScreencastCursor.fromString(' Always '), ScreencastCursor.always);
      expect(ScreencastCursor.fromString('NEVER'), ScreencastCursor.never);
      expect(ScreencastCursor.fromString('embedded'), isNull);
    });
  });

  group('CursorPacer', () {
    const interval = Duration(milliseconds: 16);

    // testWidgets runs timers on a fake clock; the pacer's own reading of time
    // is kept in step with it by hand.
    late Duration now;
    late WidgetTester t;
    Future<void> elapse(Duration d) async {
      now += d;
      await t.pump(d);
    }

    CursorPacer pacer(bool Function() push) =>
        CursorPacer(minInterval: interval, push: push, now: () => now);

    void start(WidgetTester tester) {
      t = tester;
      now = Duration.zero;
    }

    testWidgets('sends the first change at once', (tester) async {
      start(tester);
      var pushes = 0;
      final p = pacer(() {
        pushes++;
        return true;
      });
      p.changed();
      expect(pushes, 1);
      p.dispose();
    });

    testWidgets('folds a burst of motion into one buffer per interval, the '
        'last position included', (tester) async {
      start(tester);
      var position = 0;
      final sent = <int>[];
      final p = pacer(() {
        sent.add(position);
        return true;
      });

      // A 1000 Hz mouse for 40 ms.
      for (var i = 1; i <= 40; i++) {
        position = i;
        p.changed();
        await elapse(const Duration(milliseconds: 1));
      }
      await elapse(interval);

      expect(sent.length, lessThanOrEqualTo(4));
      expect(sent.last, 40, reason: 'where the pointer came to rest');
      p.dispose();
    });

    testWidgets('a frame carrying the cursor resets the clock', (tester) async {
      start(tester);
      var pushes = 0;
      final p = pacer(() {
        pushes++;
        return true;
      });
      p.sent();
      await elapse(const Duration(milliseconds: 4));
      p.changed();
      expect(pushes, 0, reason: 'a frame just carried it');
      await elapse(interval);
      expect(pushes, 1);
      p.dispose();
    });

    testWidgets('a buffer the consumer could not take is tried again',
        (tester) async {
      start(tester);
      var accept = false;
      var attempts = 0;
      final p = pacer(() {
        attempts++;
        return accept;
      });
      p.changed();
      expect(attempts, 1);
      await elapse(interval);
      expect(attempts, 2);
      accept = true;
      await elapse(interval);
      expect(attempts, 3);
      await elapse(interval * 4);
      expect(attempts, 3, reason: 'settled: nothing left owed');
      p.dispose();
    });

    testWidgets('dispose cancels what is owed', (tester) async {
      start(tester);
      var pushes = 0;
      final p = pacer(() {
        pushes++;
        return true;
      });
      p.changed();
      p.changed();
      p.dispose();
      await elapse(interval * 2);
      expect(pushes, 1);
    });
  });
}
