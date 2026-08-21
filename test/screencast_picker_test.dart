import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/screencast/capture_session.dart';
import 'package:graceful_shell/screencast/picker_controller.dart';
import 'package:graceful_shell/screencast/picker_overlay.dart';
import 'package:graceful_shell/screencast/preview.dart';

const _request = PickRequest(
  appId: 'com.example.Meet',
  monitors: true,
  windows: true,
  multiple: false,
);

/// Feeds the preview widget a solid-colour frame out of real native memory,
/// which is the same shape the capture path delivers.
class _FakeFrames implements PreviewFrames {
  static const int width = 4;
  static const int height = 4;

  int subscriptions = 0;
  int unsubscriptions = 0;

  @override
  void Function() subscribe(void Function(CapturedFrame) onFrame) {
    subscriptions++;
    final size = width * height * 4;
    final buffer = calloc<ffi.Uint8>(size);
    scheduleMicrotask(() {
      onFrame(CapturedFrame(
        data: buffer,
        width: width,
        height: height,
        stride: width * 4,
        shmFormat: shmFormatXrgb8888,
      ));
    });
    return () {
      unsubscriptions++;
      calloc.free(buffer);
    };
  }
}

PickerSource _monitor(String connector, {PreviewFrames? frames}) =>
    PickerSource(
      key: 'monitor:$connector',
      label: connector,
      sublabel: '1920 x 1080',
      picked: PickedMonitor(connector),
      frames: frames,
    );

PickerSource _window(String id, String title) => PickerSource(
      key: 'window:$id',
      label: title,
      sublabel: 'com.example.App',
      picked: PickedWindow(id, title),
      frames: null,
    );

void main() {
  group('ScreencastPickerController', () {
    test('declines immediately when no picker UI is listening', () async {
      // Otherwise a shell whose overlay failed to mount would hang the
      // portal's Start call — or worse, share without asking.
      final controller = ScreencastPickerController.forTesting();
      expect(await controller.pick(_request), isNull);
      expect(controller.pending, isNull);
    });

    test('publishes the request and resolves on complete', () async {
      final controller = ScreencastPickerController.forTesting();
      var notifications = 0;
      controller.addListener(() => notifications++);

      final pending = controller.pick(_request);
      expect(controller.pending, same(_request));
      expect(notifications, 1);

      controller.complete(const PickResult([PickedMonitor('DP-1')]));
      final result = await pending;
      expect(result!.sources.single, isA<PickedMonitor>());
      expect(controller.pending, isNull);
      expect(notifications, 2);
    });

    test('cancel resolves with null', () async {
      final controller = ScreencastPickerController.forTesting();
      controller.addListener(() {});
      final pending = controller.pick(_request);
      controller.cancel();
      expect(await pending, isNull);
    });

    test('cancelling when nothing is pending is a no-op', () {
      final controller = ScreencastPickerController.forTesting();
      controller.addListener(() {});
      expect(controller.cancel, returnsNormally);
    });

    test('a second request supersedes the first, declining it', () async {
      final controller = ScreencastPickerController.forTesting();
      controller.addListener(() {});
      final first = controller.pick(_request);
      final second = controller.pick(_request);

      expect(await first, isNull, reason: 'the superseded pick is declined');
      controller.complete(const PickResult([PickedMonitor('DP-1')]));
      expect((await second)!.sources, hasLength(1));
    });

    test('dispose declines an outstanding pick', () async {
      // A shell tearing down still owes the portal's Start call an answer —
      // an unresolved future here is a D-Bus call that hangs forever.
      final controller = ScreencastPickerController.forTesting();
      controller.addListener(() {});
      final pending = controller.pick(_request);
      controller.dispose();
      expect(await pending, isNull);
    });
  });

  group('ScreencastPickerOverlay', () {
    late ValueNotifier<bool> closing;
    late List<List<PickedSource>> confirmed;
    late int cancelled;
    late int closed;

    setUp(() {
      closing = ValueNotifier(false);
      confirmed = [];
      cancelled = 0;
      closed = 0;
    });

    tearDown(() => closing.dispose());

    Future<void> pump(
      WidgetTester tester, {
      List<PickerSource> monitors = const [],
      List<PickerSource> windows = const [],
      PickRequest request = _request,
    }) async {
      await tester.pumpWidget(ThemeScope(
        theme: const ThemeConfig(),
        child: ScreencastPickerOverlay(
          request: request,
          monitors: monitors,
          windows: windows,
          closingNotifier: closing,
          onClosed: () => closed++,
          onConfirm: confirmed.add,
          onCancel: () => cancelled++,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('names the requesting application', (tester) async {
      await pump(tester, monitors: [_monitor('DP-1')]);
      expect(find.textContaining('com.example.Meet'), findsOneWidget);
    });

    testWidgets('an anonymous caller still gets an honest prompt',
        (tester) async {
      await pump(tester,
          monitors: [_monitor('DP-1')],
          request: const PickRequest(
              appId: '', monitors: true, windows: false, multiple: false));
      expect(find.textContaining('An application wants to share'),
          findsOneWidget);
    });

    testWidgets('lists monitors and windows under their own headings',
        (tester) async {
      await pump(
        tester,
        monitors: [_monitor('DP-1'), _monitor('HDMI-A-1')],
        windows: [_window('toplevel:1', 'Editor')],
      );
      expect(find.text('SCREENS'), findsOneWidget);
      expect(find.text('WINDOWS'), findsOneWidget);
      expect(find.text('DP-1'), findsOneWidget);
      expect(find.text('HDMI-A-1'), findsOneWidget);
      expect(find.text('Editor'), findsOneWidget);
    });

    testWidgets('a section with nothing in it is not drawn', (tester) async {
      await pump(tester, monitors: [_monitor('DP-1')]);
      expect(find.text('WINDOWS'), findsNothing);
    });

    testWidgets('says so when there is nothing to share', (tester) async {
      await pump(tester);
      expect(find.text('Nothing available to share.'), findsOneWidget);
    });

    testWidgets('Share does nothing until something is selected',
        (tester) async {
      await pump(tester, monitors: [_monitor('DP-1')]);
      await tester.tap(find.text('Share'));
      await tester.pump();
      expect(confirmed, isEmpty);
      expect(closing.value, isFalse);
    });

    testWidgets('selecting then sharing confirms that source', (tester) async {
      await pump(tester, monitors: [_monitor('DP-1'), _monitor('HDMI-A-1')]);
      await tester.tap(find.text('HDMI-A-1'));
      await tester.pump();
      await tester.tap(find.text('Share'));
      await tester.pump();

      expect(confirmed.single.single, isA<PickedMonitor>());
      expect((confirmed.single.single as PickedMonitor).connector, 'HDMI-A-1');
      expect(closing.value, isTrue, reason: 'the overlay starts fading out');
    });

    testWidgets('single-select replaces the previous choice', (tester) async {
      await pump(tester, monitors: [_monitor('DP-1'), _monitor('HDMI-A-1')]);
      await tester.tap(find.text('DP-1'));
      await tester.pump();
      await tester.tap(find.text('HDMI-A-1'));
      await tester.pump();
      await tester.tap(find.text('Share'));
      await tester.pump();

      expect(confirmed.single, hasLength(1));
      expect((confirmed.single.single as PickedMonitor).connector, 'HDMI-A-1');
    });

    testWidgets('multi-select accumulates, and tapping again deselects',
        (tester) async {
      await pump(
        tester,
        monitors: [_monitor('DP-1'), _monitor('HDMI-A-1')],
        windows: [_window('toplevel:1', 'Editor')],
        request: const PickRequest(
            appId: 'obs', monitors: true, windows: true, multiple: true),
      );
      await tester.tap(find.text('DP-1'));
      await tester.tap(find.text('HDMI-A-1'));
      await tester.tap(find.text('Editor'));
      await tester.pump();
      await tester.tap(find.text('HDMI-A-1')); // deselect
      await tester.pump();
      await tester.tap(find.text('Share'));
      await tester.pump();

      final picked = confirmed.single;
      expect(picked, hasLength(2));
      expect((picked[0] as PickedMonitor).connector, 'DP-1');
      expect((picked[1] as PickedWindow).identifier, 'toplevel:1');
    });

    testWidgets('Cancel denies the request', (tester) async {
      await pump(tester, monitors: [_monitor('DP-1')]);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(cancelled, 1);
      expect(confirmed, isEmpty);
      expect(closing.value, isTrue);
    });

    testWidgets('tapping the backdrop denies the request', (tester) async {
      // Mandatory: the surface swallows every click on the monitor, so with
      // no backdrop dismissal a mouse-only user could not refuse.
      await pump(tester, monitors: [_monitor('DP-1')]);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(cancelled, 1);
    });

    testWidgets('clicking inside the card does not deny it', (tester) async {
      await pump(tester, monitors: [_monitor('DP-1')]);
      await tester.tap(find.text('Share your screen with com.example.Meet'));
      await tester.pump();
      expect(cancelled, 0);
    });

    testWidgets('Escape denies the request', (tester) async {
      await pump(tester, monitors: [_monitor('DP-1')]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(cancelled, 1);
    });

    testWidgets('Enter confirms the current selection', (tester) async {
      await pump(tester, monitors: [_monitor('DP-1')]);
      await tester.tap(find.text('DP-1'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(confirmed, hasLength(1));
    });

    testWidgets('the request is answered exactly once', (tester) async {
      await pump(tester, monitors: [_monitor('DP-1')]);
      await tester.tap(find.text('DP-1'));
      await tester.pump();
      await tester.tap(find.text('Share'));
      await tester.pump();
      // A backdrop tap landing after the answer must not turn a granted
      // share into a denial.
      await tester.tapAt(const Offset(5, 5));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(confirmed, hasLength(1));
      expect(cancelled, 0);
    });

    testWidgets('the fade-out handshake reports back to the owner',
        (tester) async {
      await pump(tester, monitors: [_monitor('DP-1')]);
      closing.value = true;
      await tester.pumpAndSettle();
      expect(closed, 1);
    });
  });

  group('CapturePreview', () {
    testWidgets('subscribes while mounted and releases on dispose',
        (tester) async {
      final frames = _FakeFrames();
      await tester.pumpWidget(CapturePreview(
        frames: frames,
        placeholderColor: const Color(0xFF000000),
      ));
      await tester.pumpAndSettle();
      expect(frames.subscriptions, 1);
      expect(frames.unsubscriptions, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(frames.unsubscriptions, 1);
    });

    testWidgets('renders a delivered frame as an image', (tester) async {
      // runAsync: decoding goes through the real (off-frame) codec pipeline,
      // which the fake-async test clock never advances.
      await tester.pumpWidget(CapturePreview(
        frames: _FakeFrames(),
        placeholderColor: const Color(0xFF000000),
      ));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.byType(RawImage), findsOneWidget);
    });

    testWidgets('shows the placeholder until the first frame lands',
        (tester) async {
      await tester.pumpWidget(CapturePreview(
        frames: _FakeFrames(),
        placeholderColor: const Color(0xFF123456),
      ));
      // No pumpAndSettle: the frame is delivered in a microtask.
      expect(find.byType(ColoredBox), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });
}
