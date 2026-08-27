import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/capture/capture_source.dart';
import 'package:graceful_shell/capture/capture_targets.dart';

/// Which display a pick is finally taken from.
///
/// The one part of `resolveCaptureSource` that is not FFI, and the part that
/// decided whether the feature worked at all: it used to be a connector-string
/// comparison, so a compositor that left either end of that string empty —
/// GDK with no `xdg-output` manager to learn a connector from, `wl_output`
/// below version 4 with no `name` event to send — answered "the display is no
/// longer connected" for every capture on the machine.
void main() {
  group('a named output', () {
    test('answers its own connector', () {
      const list = [
        (connector: 'DP-1', x: 0, y: 0),
        (connector: 'HDMI-1', x: 1920, y: 0),
      ];
      expect(indexOfCaptureOutput(list, connector: 'HDMI-1'), 1);
    });

    test('beats a corner another display has since taken over', () {
      const list = [
        (connector: 'DP-1', x: 1920, y: 0),
        (connector: 'HDMI-1', x: 0, y: 0),
      ];
      expect(
        indexOfCaptureOutput(list,
            connector: 'HDMI-1', origin: const CapturePoint(1920, 0)),
        1,
      );
    });

    test('unplugged among named outputs resolves to nothing', () {
      // The failure this whole function is careful about: DP-2 is gone and
      // HDMI-1 has moved into the corner it used to occupy. Capturing HDMI-1
      // and calling it DP-2 is worse than saying the display went away.
      const list = [(connector: 'HDMI-1', x: 0, y: 0)];
      expect(
        indexOfCaptureOutput(list,
            connector: 'DP-2', origin: const CapturePoint(0, 0)),
        -1,
      );
    });
  });

  group('an output nothing could name', () {
    test('is found by its corner', () {
      const list = [
        (connector: '', x: 0, y: 0),
        (connector: '', x: 1920, y: 0),
      ];
      expect(
        indexOfCaptureOutput(list,
            connector: '', origin: const CapturePoint(1920, 0)),
        1,
      );
    });

    test('is found by its corner even where the other end has a name', () {
      // `wl_output` below version 4: GDK knows the connector, the capture
      // connection never heard one.
      const list = [
        (connector: '', x: 0, y: 0),
        (connector: '', x: 1920, y: 0),
      ];
      expect(
        indexOfCaptureOutput(list,
            connector: 'HDMI-1', origin: const CapturePoint(1920, 0)),
        1,
      );
    });

    test('is the lone display when there is only one', () {
      const list = [(connector: '', x: 0, y: 0)];
      expect(indexOfCaptureOutput(list, connector: ''), 0);
      expect(indexOfCaptureOutput(list, connector: 'DP-1'), 0);
    });

    test('with several and no corner, nothing is guessed', () {
      const list = [
        (connector: '', x: 0, y: 0),
        (connector: '', x: 1920, y: 0),
      ];
      expect(indexOfCaptureOutput(list, connector: ''), -1);
    });

    test('a corner no output has resolves to nothing', () {
      const list = [
        (connector: '', x: 0, y: 0),
        (connector: '', x: 1920, y: 0),
      ];
      expect(
        indexOfCaptureOutput(list,
            connector: '', origin: const CapturePoint(3840, 0)),
        -1,
      );
    });

    test('a named output is never the answer for one that is not', () {
      // Half-named: the compositor named DP-1 and not the other, so DP-1 has
      // already said "not me" and the unnamed one is the only candidate.
      const list = [
        (connector: 'DP-1', x: 0, y: 0),
        (connector: '', x: 1920, y: 0),
      ];
      expect(indexOfCaptureOutput(list, connector: 'HDMI-1'), 1);
    });
  });

  test('no outputs at all resolves to nothing', () {
    expect(
      indexOfCaptureOutput(const [],
          connector: 'DP-1', origin: const CapturePoint(0, 0)),
      -1,
    );
  });
}
