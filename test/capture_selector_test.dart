import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/capture/selection_controller.dart';
import 'package:graceful_shell/capture/selector_overlay.dart';
import 'package:graceful_shell/capture/window_targets.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/scopes.dart';

/// The selection surface. Every input it has is a parameter, so the whole thing
/// pumps with no compositor, no Wayland and no IPC socket — which is what makes
/// the geometry it answers with checkable at all.
///
/// The surface is the test's own 800x600, standing in for one output.
const Size _surface = Size(800, 600);

/// One output at the origin and one to its right, with a window on each. The
/// second is what pins the mapping: miracle reports one *global* space and a
/// layer-shell surface is laid out in its own output-local one, so a highlight on
/// the second monitor is only right if the origin is subtracted.
final _scene = CaptureScene(
  outputs: const [
    ScreenOutput(name: 'DP-1', rect: CaptureRect(0, 0, 800, 600)),
    ScreenOutput(name: 'HDMI-1', rect: CaptureRect(800, 0, 800, 600)),
  ],
  windows: const [
    SelectableWindow(
      id: 1,
      rect: CaptureRect(0, 0, 800, 600),
      title: 'Behind',
      appId: 'org.example.behind',
      output: 'DP-1',
    ),
    SelectableWindow(
      id: 2,
      rect: CaptureRect(100, 100, 300, 200),
      title: 'In front',
      appId: 'org.example.front',
      output: 'DP-1',
    ),
    SelectableWindow(
      id: 3,
      rect: CaptureRect(900, 100, 300, 200),
      title: 'Other screen',
      appId: 'org.example.other',
      output: 'HDMI-1',
    ),
  ],
);

Widget _overlay({
  required SelectionMode mode,
  required ValueNotifier<bool> closing,
  required void Function(CaptureTarget) onPicked,
  required VoidCallback onCancel,
  VoidCallback? onClosed,
  String connector = 'DP-1',
  CapturePoint? origin,
  CaptureKind kind = CaptureKind.screenshot,
  CaptureScene? scene,
}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: ThemeScope(
        theme: const ThemeConfig(),
        child: CaptureSelectorOverlay(
          request: SelectionRequest(kind: kind, mode: mode),
          connector: connector,
          origin: origin,
          scene: scene ?? _scene,
          closingNotifier: closing,
          onClosed: onClosed ?? () {},
          onPicked: onPicked,
          onCancel: onCancel,
        ),
      ),
    );

void main() {
  late ValueNotifier<bool> closing;
  late List<CaptureTarget> picked;
  late int cancels;

  setUp(() {
    closing = ValueNotifier(false);
    picked = [];
    cancels = 0;
  });

  tearDown(() => closing.dispose());

  Widget build(SelectionMode mode,
          {String connector = 'DP-1',
          CapturePoint? origin,
          VoidCallback? onClosed,
          CaptureScene? scene}) =>
      _overlay(
        mode: mode,
        closing: closing,
        onPicked: picked.add,
        onCancel: () => cancels++,
        onClosed: onClosed,
        connector: connector,
        origin: origin,
        scene: scene,
      );

  group('area', () {
    testWidgets('a drag answers the rectangle it swept, in surface pixels',
        (tester) async {
      await tester.pumpWidget(build(SelectionMode.area));
      await tester.pumpAndSettle();

      await tester.dragFrom(const Offset(100, 100), const Offset(200, 150));
      await tester.pump();

      expect(picked, hasLength(1));
      final target = picked.single as AreaCapture;
      expect(target.connector, 'DP-1');
      expect(target.crop, const CaptureRect(100, 100, 200, 150));
      expect(target.outputSize,
          CaptureSize(_surface.width.round(), _surface.height.round()));
      expect(cancels, 0);
    });

    testWidgets('a drag made backwards is the same rectangle', (tester) async {
      await tester.pumpWidget(build(SelectionMode.area));
      await tester.pumpAndSettle();

      await tester.dragFrom(const Offset(300, 250), const Offset(-200, -150));
      await tester.pump();

      expect((picked.single as AreaCapture).crop,
          const CaptureRect(100, 100, 200, 150));
    });

    testWidgets('a twitch of the hand is ignored, not treated as a cancel',
        (tester) async {
      // Losing a full-screen tool to a stray click while reaching for the
      // corner of a window is worse than one ignored click; Escape and the
      // right button are the ways out, and both say so on the banner.
      await tester.pumpWidget(build(SelectionMode.area));
      await tester.pumpAndSettle();

      await tester.dragFrom(const Offset(100, 100), const Offset(3, 3));
      await tester.pump();

      expect(picked, isEmpty);
      expect(cancels, 0);
    });

    testWidgets('Escape cancels', (tester) async {
      await tester.pumpWidget(build(SelectionMode.area));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(cancels, 1);
      expect(picked, isEmpty);
    });

    testWidgets('a right-click cancels', (tester) async {
      await tester.pumpWidget(build(SelectionMode.area));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(400, 300), buttons: kSecondaryButton);
      await tester.pump();

      expect(cancels, 1);
    });
  });

  group('window', () {
    testWidgets('picks the frontmost window under the pointer', (tester) async {
      await tester.pumpWidget(build(SelectionMode.window));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(200, 150));
      await tester.pump();

      final target = picked.single as WindowCapture;
      expect(target.title, 'In front');
      expect(target.appId, 'org.example.front');
      expect(target.crop, const CaptureRect(100, 100, 300, 200));
      // The identifier is joined on at the shutter, against the live
      // foreign-toplevel list — the surface cannot know it.
      expect(target.toplevelIdentifier, isNull);
    });

    testWidgets('outside the floating window the one behind it is picked',
        (tester) async {
      await tester.pumpWidget(build(SelectionMode.window));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(600, 500));
      await tester.pump();

      expect((picked.single as WindowCapture).title, 'Behind');
    });

    testWidgets('a second monitor subtracts its own global origin',
        (tester) async {
      await tester.pumpWidget(build(SelectionMode.window, connector: 'HDMI-1'));
      await tester.pumpAndSettle();

      // The window is at global (900, 100); this surface starts at x = 800, so
      // it is 100 in from the left of *this* output.
      await tester.tapAt(const Offset(150, 150));
      await tester.pump();

      final target = picked.single as WindowCapture;
      expect(target.title, 'Other screen');
      expect(target.connector, 'HDMI-1');
      expect(target.crop, const CaptureRect(100, 100, 300, 200));
    });

    testWidgets('a click on bare desktop picks nothing and cancels nothing',
        (tester) async {
      await tester.pumpWidget(build(SelectionMode.window,
          scene: const CaptureScene(outputs: [], windows: [])));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(400, 300));
      await tester.pump();

      expect(picked, isEmpty);
      expect(cancels, 0);
    });
  });

  // A compositor with no `xdg-output` manager leaves GDK with no connector at
  // all, so these surfaces are handed an empty string and the corner is the only
  // identity they carry. Without the second pass the whole feature is dead on
  // those machines.
  group('an output GDK could not name', () {
    testWidgets('resolves by its corner, so its windows are still pointable',
        (tester) async {
      await tester.pumpWidget(build(SelectionMode.window,
          connector: '', origin: const CapturePoint(800, 0)));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(150, 150));
      await tester.pump();

      final target = picked.single as WindowCapture;
      expect(target.title, 'Other screen');
      expect(target.crop, const CaptureRect(100, 100, 300, 200),
          reason: 'the mapping subtracted the resolved output origin');
    });

    testWidgets('carries its corner into every pick', (tester) async {
      await tester.pumpWidget(build(SelectionMode.output,
          connector: '', origin: const CapturePoint(800, 0)));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(400, 300));
      await tester.pump();

      final target = picked.single as OutputCapture;
      expect(target.connector, isEmpty);
      expect(target.outputOrigin, const CapturePoint(800, 0));
      expect(target.label, 'Screen', reason: 'never an empty notification');
    });

    testWidgets('an area pick carries it too', (tester) async {
      await tester.pumpWidget(build(SelectionMode.area,
          connector: '', origin: const CapturePoint(800, 0)));
      await tester.pumpAndSettle();

      await tester.dragFrom(const Offset(100, 100), const Offset(200, 150));
      await tester.pump();

      expect((picked.single as AreaCapture).outputOrigin,
          const CapturePoint(800, 0));
    });

    testWidgets('with a lone output it needs no corner at all', (tester) async {
      await tester.pumpWidget(build(
        SelectionMode.window,
        connector: '',
        scene: const CaptureScene(
          outputs: [
            ScreenOutput(name: 'DP-1', rect: CaptureRect(0, 0, 800, 600)),
          ],
          windows: [
            SelectableWindow(
              id: 1,
              rect: CaptureRect(100, 100, 300, 200),
              title: 'Only window',
              appId: 'org.example.only',
              output: 'DP-1',
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(200, 150));
      await tester.pump();

      expect((picked.single as WindowCapture).title, 'Only window');
    });
  });

  group('output', () {
    testWidgets('a click anywhere takes the whole screen', (tester) async {
      await tester.pumpWidget(build(SelectionMode.output));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pump();

      final target = picked.single as OutputCapture;
      expect(target.connector, 'DP-1');
      expect(target.crop, isNull, reason: 'a whole output is never cropped');
    });

    testWidgets('works with no scene at all, which is the IPC-down case',
        (tester) async {
      await tester.pumpWidget(build(SelectionMode.output,
          scene: const CaptureScene(outputs: [], windows: [])));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(400, 300));
      await tester.pump();

      expect((picked.single as OutputCapture).connector, 'DP-1');
    });
  });

  group('teardown', () {
    testWidgets('closing resolves on the next frame, with no animation to play',
        (tester) async {
      // The shutter fires as soon as this comes down, so there is deliberately
      // nothing to fade: a fade-out would put a half-transparent copy of this
      // very surface into the picture.
      var closed = 0;
      await tester.pumpWidget(
          build(SelectionMode.area, onClosed: () => closed++));
      await tester.pumpAndSettle();

      closing.value = true;
      expect(closed, 0, reason: 'not synchronously, mid-notification');
      await tester.pump();
      expect(closed, 1);
    });

    testWidgets('a surface that has answered ignores everything after',
        (tester) async {
      await tester.pumpWidget(build(SelectionMode.output));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(picked, hasLength(1));
      expect(cancels, 0, reason: 'the pick already answered the request');
    });
  });
}
